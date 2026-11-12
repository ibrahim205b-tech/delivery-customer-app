-- =====================================================================
-- WASEL | واصل — العمولة الفعلية + حذف المحلات بأمان
--
-- العمولة:
-- - نسبة عامة من إعدادات المنصة (commission: enabled/percent)، ونسبة خاصة لكل محل (اختيارية) تتقدّم عليها.
-- - تُحسب على مبلغ المنتجات فقط (subtotal) — أجرة التوصيل ما تدخل، والزبون ما يدفع أي شي إضافي.
-- - النسبة تُثبَّت على الطلب وقت إنشائه (تغيير النسبة لاحقاً ما يغيّر الطلبات القديمة).
-- - المبلغ يُستحق فقط عند "تم التسليم"، ويصير صفر إذا انلغى الطلب.
-- - محفوظة بجدول منفصل حتى الزبون ما يشوف عمولة المحل.
-- - الدفع نقدي: المحل يسلّم عمولة واصل للإدارة، والإدارة تسجّل الدفعات (settlements)؛ المتبقي = المستحق − المدفوع.
-- =====================================================================

alter table merchants add column if not exists commission_percent numeric(5,2)
  check (commission_percent is null or (commission_percent >= 0 and commission_percent <= 50));
comment on column merchants.commission_percent is 'نسبة عمولة خاصة بالمحل. فارغة = تُستخدم النسبة العامة.';

create table if not exists order_commissions (
  order_id    uuid primary key references orders (id) on delete cascade,
  merchant_id uuid not null references merchants (id) on delete cascade,
  percent     numeric(5,2) not null default 0,
  amount      int not null default 0 check (amount >= 0),
  earned_at   timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists order_commissions_merchant_idx on order_commissions (merchant_id, earned_at);

create table if not exists merchant_settlements (
  id          bigint generated always as identity primary key,
  merchant_id uuid not null references merchants (id) on delete cascade,
  amount      int not null check (amount > 0),
  note        text not null default '',
  created_by  uuid references users (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists merchant_settlements_merchant_idx on merchant_settlements (merchant_id, created_at desc);

alter table order_commissions    enable row level security;
alter table merchant_settlements enable row level security;

drop policy if exists order_commissions_read on order_commissions;
create policy order_commissions_read on order_commissions for select to authenticated
  using (is_admin() or owns_merchant(merchant_id));
drop policy if exists merchant_settlements_read on merchant_settlements;
create policy merchant_settlements_read on merchant_settlements for select to authenticated
  using (is_admin() or owns_merchant(merchant_id));

grant select on order_commissions, merchant_settlements to authenticated;
grant all on order_commissions, merchant_settlements to service_role;

-- النسبة الفعلية للمحل الآن
create or replace function effective_commission_percent(p_merchant uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(
    (select commission_percent from merchants where id = p_merchant),
    (select case when coalesce((value->>'enabled')::boolean, false)
                 then least(greatest(coalesce((value->>'percent')::numeric, 0), 0), 50) else 0 end
       from app_settings where key = 'commission'),
    0);
$$;

-- عند إنشاء الطلب: تثبيت النسبة
create or replace function _order_commission_on_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into order_commissions (order_id, merchant_id, percent)
  values (new.id, new.merchant_id, effective_commission_percent(new.merchant_id))
  on conflict (order_id) do nothing;
  return new;
end $$;

-- عند التسليم: احتساب المبلغ. عند الإلغاء: صفر.
create or replace function _order_commission_on_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = old.status then return new; end if;
  if new.status = 'delivered' then
    update order_commissions set amount = round(new.subtotal * percent / 100.0)::int, earned_at = now() where order_id = new.id;
  elsif new.status = 'cancelled' then
    update order_commissions set amount = 0, earned_at = null where order_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists order_commission_insert on orders;
create trigger order_commission_insert after insert on orders
  for each row execute function _order_commission_on_insert();
drop trigger if exists order_commission_status on orders;
create trigger order_commission_status after update of status on orders
  for each row execute function _order_commission_on_status();

-- الطلبات القديمة: سجل بنسبة صفر (العمولة ما كانت مفعّلة)
insert into order_commissions (order_id, merchant_id, percent, amount)
select id, merchant_id, 0, 0 from orders
on conflict (order_id) do nothing;

-- ملخص عمولة محل واحد (للتاجر نفسه أو الإدارة)
create or replace function merchant_commission_summary(p_merchant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  month_start timestamptz := date_trunc('month', now() at time zone 'Asia/Baghdad') at time zone 'Asia/Baghdad';
  earned bigint; settled bigint;
begin
  if not owns_merchant(p_merchant_id) and not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select coalesce(sum(amount), 0) into earned from order_commissions where merchant_id = p_merchant_id;
  select coalesce(sum(amount), 0) into settled from merchant_settlements where merchant_id = p_merchant_id;
  return jsonb_build_object(
    'percent', effective_commission_percent(p_merchant_id),
    'custom', (select commission_percent is not null from merchants where id = p_merchant_id),
    'earned_total', earned,
    'settled_total', settled,
    'due', earned - settled,
    'month_commission', (select coalesce(sum(amount), 0) from order_commissions where merchant_id = p_merchant_id and earned_at >= month_start),
    'month_sales', (select coalesce(sum(o.subtotal), 0) from order_commissions c join orders o on o.id = c.order_id where c.merchant_id = p_merchant_id and c.earned_at >= month_start),
    'settlements', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'amount', s.amount, 'note', s.note, 'created_at', s.created_at) order by s.created_at desc)
                             from (select * from merchant_settlements where merchant_id = p_merchant_id order by created_at desc limit 20) s), '[]'::jsonb)
  );
end $$;

-- ملخص كل المحلات للإدارة
create or replace function admin_commission_summary(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare since timestamptz := now() - make_interval(days => greatest(1, least(p_days, 365)));
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'days', p_days,
    'global', (select value from app_settings where key = 'commission'),
    'period_commission', (select coalesce(sum(amount), 0) from order_commissions where earned_at >= since),
    'period_sales', (select coalesce(sum(o.subtotal), 0) from order_commissions c join orders o on o.id = c.order_id where c.earned_at >= since),
    'due_total', (select coalesce(sum(amount), 0) from order_commissions) - (select coalesce(sum(amount), 0) from merchant_settlements),
    'merchants', coalesce((
      select jsonb_agg(row_to_json(x) order by x.due desc, x.name)
      from (
        select m.id, m.name, m.commission_percent as custom_percent, effective_commission_percent(m.id) as percent,
               coalesce(e.period_orders, 0) as period_orders, coalesce(e.period_sales, 0) as period_sales,
               coalesce(e.period_commission, 0) as period_commission,
               coalesce(t.earned, 0) as earned_total, coalesce(s.settled, 0) as settled_total,
               coalesce(t.earned, 0) - coalesce(s.settled, 0) as due
        from merchants m
        left join (select c.merchant_id, count(*) as period_orders, sum(o.subtotal) as period_sales, sum(c.amount) as period_commission
                   from order_commissions c join orders o on o.id = c.order_id
                   where c.earned_at >= since group by c.merchant_id) e on e.merchant_id = m.id
        left join (select merchant_id, sum(amount) as earned from order_commissions group by merchant_id) t on t.merchant_id = m.id
        left join (select merchant_id, sum(amount) as settled from merchant_settlements group by merchant_id) s on s.merchant_id = m.id
        where m.category_id <> 'home_services'
      ) x), '[]'::jsonb)
  );
end $$;

-- تسجيل دفعة عمولة استلمتها الإدارة من المحل
create or replace function admin_add_settlement(p_merchant_id uuid, p_amount int, p_note text default '')
returns merchant_settlements language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r merchant_settlements;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if not exists (select 1 from merchants where id = p_merchant_id) then raise exception 'merchant_unavailable'; end if;
  insert into merchant_settlements (merchant_id, amount, note, created_by)
  values (p_merchant_id, p_amount, btrim(coalesce(p_note, '')), uid) returning * into r;
  return r;
end $$;

-- حذف محل: مسموح فقط إذا ما عنده أي طلبات أو حجوزات (حتى ما تضيع السجلات والحسابات).
-- إذا عنده سجل يرجّع merchant_has_history، والتطبيق يقترح "إيقاف" بدل الحذف.
create or replace function admin_delete_merchant(p_merchant_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform require_user();
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if exists (select 1 from orders where merchant_id = p_merchant_id)
     or exists (select 1 from service_bookings where provider_id = p_merchant_id) then
    raise exception 'merchant_has_history';
  end if;
  delete from merchants where id = p_merchant_id;
end $$;

revoke execute on function effective_commission_percent(uuid), merchant_commission_summary(uuid), admin_commission_summary(int),
  admin_add_settlement(uuid, int, text), admin_delete_merchant(uuid) from public, anon;
grant execute on function effective_commission_percent(uuid), merchant_commission_summary(uuid), admin_commission_summary(int),
  admin_add_settlement(uuid, int, text), admin_delete_merchant(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
