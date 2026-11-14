-- =====================================================================
-- WASEL | واصل للأعمال — دفتر حسابات الكابتن (عمولة + مستحقات + تسديدات)
--
-- المبدأ: الزبون يدفع الأجرة نقداً للكابتن. عند إكمال الرحلة/التوصيل يُسجَّل تلقائياً
-- صف "عمولة" يمثل المبلغ المستحق لواصل. المستحق الفعلي = مجموع العمولات + التصحيحات − المدفوع.
-- - كل حركة صف مستقل. لا يوجد تعديل ولا حذف لصفوف قديمة؛ التصحيح يكون صف تصحيح جديد بسبب.
-- - عمولة الرحلة/المهمة تُسجَّل مرة واحدة فقط (unique على ride_id / task_id).
-- - النسبة تُثبَّت على الصف وقت الإكمال؛ تغيير النسبة لاحقاً ما يغيّر الصفوف القديمة.
-- - العمولة لا تُعتبر مال محصّل قبل تسجيل التسديد من الإدارة.
-- - طلبات المحلات (kind = order) عمولتها على المحل (0008)، فما تدخل هنا.
-- =====================================================================

-- الإعداد الافتراضي: معطّل حتى تفعّله الإدارة (نسبة قابلة للتعديل من لوحة الإدارة)
insert into app_settings (key, value)
values ('driver_commission', '{"enabled": false, "percent": 10}')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- جدول العمولات (صف لكل رحلة مكتملة أو توصيل مكتمل)
-- ---------------------------------------------------------------------
create table if not exists driver_commissions (
  id          bigint generated always as identity primary key,
  driver_id   uuid not null references drivers (id) on delete cascade,
  ride_id     uuid unique references rides (id) on delete cascade,
  task_id     uuid unique references delivery_tasks (id) on delete cascade,
  fare        int not null check (fare >= 0),
  percent     numeric(5,2) not null check (percent >= 0 and percent <= 50),
  amount      int not null check (amount >= 0),
  earned_at   timestamptz not null default now(),
  check ((ride_id is null) <> (task_id is null))
);
create index if not exists driver_commissions_driver_idx on driver_commissions (driver_id, earned_at desc);

-- ---------------------------------------------------------------------
-- دفتر التسديدات والتصحيحات
--   payment    : الكابتن سدّد لواصل (delta سالب دائماً)
--   adjustment : تصحيح بسبب مكتوب (delta موجب أو سالب، لكن ليس صفر)
-- ---------------------------------------------------------------------
create table if not exists driver_ledger_entries (
  id          bigint generated always as identity primary key,
  driver_id   uuid not null references drivers (id) on delete cascade,
  kind        text not null check (kind in ('payment', 'adjustment')),
  delta       int not null check (delta <> 0),
  note        text not null default '',
  request_id  uuid unique,                 -- يمنع تكرار نفس التسديد عند إعادة الضغط
  created_by  uuid references users (id) on delete set null,
  created_at  timestamptz not null default now(),
  check (kind <> 'payment' or delta < 0),
  check (kind <> 'adjustment' or length(btrim(note)) >= 5)
);
create index if not exists driver_ledger_driver_idx on driver_ledger_entries (driver_id, created_at desc);

alter table driver_commissions    enable row level security;
alter table driver_ledger_entries enable row level security;

drop policy if exists driver_commissions_read on driver_commissions;
create policy driver_commissions_read on driver_commissions for select to authenticated
  using (is_admin() or driver_id = auth.uid());
drop policy if exists driver_ledger_read on driver_ledger_entries;
create policy driver_ledger_read on driver_ledger_entries for select to authenticated
  using (is_admin() or driver_id = auth.uid());

-- الكتابة فقط عبر الدوال (security definer) — لا insert/update/delete مباشر من أي دور تطبيقي
revoke all on driver_commissions, driver_ledger_entries from authenticated, anon;
grant select on driver_commissions, driver_ledger_entries to authenticated;
grant all on driver_commissions, driver_ledger_entries to service_role;

-- ---------------------------------------------------------------------
-- احتساب العمولة تلقائياً عند الإكمال
-- ---------------------------------------------------------------------
create or replace function _driver_commission_percent()
returns numeric language sql stable security definer set search_path = public as $$
  select case when coalesce((value->>'enabled')::boolean, false)
              then least(greatest(coalesce((value->>'percent')::numeric, 0), 0), 50) else 0 end
    from app_settings where key = 'driver_commission';
$$;

create or replace function _ride_commission_on_complete()
returns trigger language plpgsql security definer set search_path = public as $$
declare pct numeric := coalesce(_driver_commission_percent(), 0);
begin
  if new.status = 'completed' and old.status is distinct from 'completed' and new.driver_id is not null then
    insert into driver_commissions (driver_id, ride_id, fare, percent, amount, earned_at)
    values (new.driver_id, new.id, new.fare, pct, round(new.fare * pct / 100.0)::int, coalesce(new.completed_at, now()))
    on conflict (ride_id) do nothing;
  end if;
  return new;
end $$;

drop trigger if exists ride_commission_on_complete on rides;
create trigger ride_commission_on_complete after update of status on rides
  for each row execute function _ride_commission_on_complete();

create or replace function _task_commission_on_deliver()
returns trigger language plpgsql security definer set search_path = public as $$
declare pct numeric := coalesce(_driver_commission_percent(), 0);
begin
  -- التوصيل والمندوب فقط (طلبات المحلات عمولتها على المحل)
  if new.status = 'delivered' and old.status is distinct from 'delivered'
     and new.driver_id is not null and new.kind in ('courier', 'parcel') then
    insert into driver_commissions (driver_id, task_id, fare, percent, amount, earned_at)
    values (new.driver_id, new.id, new.fee, pct, round(new.fee * pct / 100.0)::int, now())
    on conflict (task_id) do nothing;
  end if;
  return new;
end $$;

drop trigger if exists task_commission_on_deliver on delivery_tasks;
create trigger task_commission_on_deliver after update of status on delivery_tasks
  for each row execute function _task_commission_on_deliver();

-- ---------------------------------------------------------------------
-- حساب الكابتن: ملخص مالي + أداء (كلها من بيانات حقيقية)
-- ---------------------------------------------------------------------
create or replace function _driver_account_json(p_driver uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with tz as (
    select (date_trunc('day', now() at time zone 'Asia/Baghdad')) at time zone 'Asia/Baghdad' as day_start,
           (date_trunc('week', now() at time zone 'Asia/Baghdad')) at time zone 'Asia/Baghdad' as week_start,
           (date_trunc('month', now() at time zone 'Asia/Baghdad')) at time zone 'Asia/Baghdad' as month_start
  ),
  c as (
    select * from driver_commissions where driver_id = p_driver
  ),
  l as (
    select
      coalesce(sum(delta) filter (where kind = 'payment'), 0) as paid,
      coalesce(sum(delta) filter (where kind = 'adjustment'), 0) as adjust
    from driver_ledger_entries where driver_id = p_driver
  ),
  trips as (
    select
      (select count(*) from rides where driver_id = p_driver and status = 'completed')
        + (select count(*) from delivery_tasks where driver_id = p_driver and status = 'delivered') as done,
      (select count(*) from rides where driver_id = p_driver and status = 'cancelled')
        + (select count(*) from delivery_tasks where driver_id = p_driver and status = 'cancelled') as cancelled,
      (select count(*) from c, tz where earned_at >= tz.day_start) as done_today
  ),
  days as (
    select d::date as day,
           coalesce((select count(*) from c where (earned_at at time zone 'Asia/Baghdad')::date = d::date), 0) as trips,
           coalesce((select sum(fare) from c where (earned_at at time zone 'Asia/Baghdad')::date = d::date), 0) as fares
    from generate_series(((now() at time zone 'Asia/Baghdad')::date - 6), (now() at time zone 'Asia/Baghdad')::date, interval '1 day') d
  )
  select jsonb_build_object(
    'owed', (select coalesce(sum(amount), 0) from c) + l.adjust - (-l.paid),
    'commission_total', (select coalesce(sum(amount), 0) from c),
    'commission_today', (select coalesce(sum(amount), 0) from c, tz where earned_at >= tz.day_start),
    'commission_week', (select coalesce(sum(amount), 0) from c, tz where earned_at >= tz.week_start),
    'commission_month', (select coalesce(sum(amount), 0) from c, tz where earned_at >= tz.month_start),
    'paid_total', -l.paid,
    'adjust_total', l.adjust,
    'fares_today', (select coalesce(sum(fare), 0) from c, tz where earned_at >= tz.day_start),
    'fares_week', (select coalesce(sum(fare), 0) from c, tz where earned_at >= tz.week_start),
    'fares_month', (select coalesce(sum(fare), 0) from c, tz where earned_at >= tz.month_start),
    'trips_done', trips.done,
    'trips_done_today', trips.done_today,
    'trips_cancelled', trips.cancelled,
    'cancel_rate', case when trips.done + trips.cancelled = 0 then null
                        else round(trips.cancelled::numeric * 100 / (trips.done + trips.cancelled), 1) end,
    'rating_avg', (select rating_avg from drivers where id = p_driver),
    'last_7_days', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'trips', trips, 'fares', fares) order by day), '[]'::jsonb) from days)
  )
  from l, trips;
$$;

-- قائمة الحركات: عمولات + تسديدات + تصحيحات (الأحدث أولاً)
create or replace function _driver_ledger_json(p_driver uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_json order by at_ts desc), '[]'::jsonb) from (
    select c.earned_at as at_ts, jsonb_build_object(
             'type', 'commission', 'at', c.earned_at, 'amount', c.amount, 'fare', c.fare, 'percent', c.percent,
             'ref', case when c.ride_id is not null then 'ride' else 'task' end,
             'ref_id', coalesce(c.ride_id, c.task_id), 'note', '') as row_json
      from driver_commissions c
     where c.driver_id = p_driver
       and (p_from is null or c.earned_at >= p_from) and (p_to is null or c.earned_at < p_to)
    union all
    select e.created_at as at_ts, jsonb_build_object(
             'type', e.kind, 'at', e.created_at, 'amount', e.delta, 'fare', null, 'percent', null,
             'ref', null, 'ref_id', null, 'note', e.note)
      from driver_ledger_entries e
     where e.driver_id = p_driver
       and (p_from is null or e.created_at >= p_from) and (p_to is null or e.created_at < p_to)
    order by at_ts desc
    limit 500
  ) x;
$$;

-- الكابتن يشوف حسابه فقط
create or replace function driver_account()
returns jsonb language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver();
begin
  return jsonb_build_object('summary', _driver_account_json(d.id), 'ledger', _driver_ledger_json(d.id, null, null));
end $$;

-- الإدارة: قائمة الكباتن مع المستحق
create or replace function admin_driver_accounts()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'driver_id', d.id, 'name', coalesce(u.full_name, ''), 'phone', coalesce(u.phone, ''),
             'vehicle_type', d.vehicle_type, 'is_active', d.is_active,
             'owed', (_driver_account_json(d.id) ->> 'owed')::int,
             'trips_done', (_driver_account_json(d.id) ->> 'trips_done')::int
           ) order by (_driver_account_json(d.id) ->> 'owed')::int desc), '[]'::jsonb)
      from drivers d left join users u on u.id = d.id
  );
end $$;

-- الإدارة: تفاصيل كابتن
create or replace function admin_driver_account(p_driver_id uuid, p_from timestamptz default null, p_to timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if not exists (select 1 from drivers where id = p_driver_id) then raise exception 'driver_unavailable'; end if;
  return jsonb_build_object('summary', _driver_account_json(p_driver_id), 'ledger', _driver_ledger_json(p_driver_id, p_from, p_to));
end $$;

-- الإدارة: تسجيل تسديد نقدي استلمته فعلاً. لا يسمح بأكثر من المستحق.
create or replace function admin_add_driver_payment(p_driver_id uuid, p_amount int, p_note text default '', p_request_id uuid default null)
returns driver_ledger_entries language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); owed int; r driver_ledger_entries;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if not exists (select 1 from drivers where id = p_driver_id) then raise exception 'driver_unavailable'; end if;
  if p_request_id is not null then
    select * into r from driver_ledger_entries where request_id = p_request_id;
    if found then return r; end if;
  end if;
  -- قفل صف الكابتن لمنع تسديدين متزامنين يتجاوزان المستحق
  perform 1 from drivers where id = p_driver_id for update;
  owed := (_driver_account_json(p_driver_id) ->> 'owed')::int;
  if p_amount > owed then raise exception 'amount_exceeds_owed:%', owed; end if;
  insert into driver_ledger_entries (driver_id, kind, delta, note, request_id, created_by)
  values (p_driver_id, 'payment', -p_amount, btrim(coalesce(p_note, '')), p_request_id, uid)
  returning * into r;
  return r;
end $$;

-- الإدارة: تصحيح بسبب مكتوب، كصف مستقل (لا تعديل لصفوف قديمة)
create or replace function admin_add_driver_adjustment(p_driver_id uuid, p_delta int, p_reason text, p_request_id uuid default null)
returns driver_ledger_entries language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r driver_ledger_entries;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_delta is null or p_delta = 0 then raise exception 'invalid_amount'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'reason_required'; end if;
  if not exists (select 1 from drivers where id = p_driver_id) then raise exception 'driver_unavailable'; end if;
  if p_request_id is not null then
    select * into r from driver_ledger_entries where request_id = p_request_id;
    if found then return r; end if;
  end if;
  insert into driver_ledger_entries (driver_id, kind, delta, note, request_id, created_by)
  values (p_driver_id, 'adjustment', p_delta, btrim(p_reason), p_request_id, uid)
  returning * into r;
  return r;
end $$;

-- الإدارة: نسبة عمولة الكباتن (تُطبَّق على الإكمالات الجديدة فقط)
create or replace function admin_set_driver_commission(p_enabled boolean, p_percent numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_percent is null or p_percent < 0 or p_percent > 50 then raise exception 'invalid_percent'; end if;
  insert into app_settings (key, value, updated_at)
  values ('driver_commission', jsonb_build_object('enabled', coalesce(p_enabled, false), 'percent', p_percent), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return (select value from app_settings where key = 'driver_commission');
end $$;

grant execute on function driver_account() to authenticated;
grant execute on function admin_driver_accounts() to authenticated;
grant execute on function admin_driver_account(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function admin_add_driver_payment(uuid, int, text, uuid) to authenticated;
grant execute on function admin_add_driver_adjustment(uuid, int, text, uuid) to authenticated;
grant execute on function admin_set_driver_commission(boolean, numeric) to authenticated;
-- الدوال الداخلية ما تُستدعى من التطبيق
revoke execute on function _driver_account_json(uuid) from public, anon, authenticated;
revoke execute on function _driver_ledger_json(uuid, timestamptz, timestamptz) from public, anon, authenticated;

-- Make PostgREST pick up new functions right away (Supabase does this on DDL; harmless elsewhere)
notify pgrst, 'reload schema';
