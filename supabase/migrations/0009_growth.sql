-- =====================================================================
-- WASEL | واصل — النمو: رئيسية تتحكم بيها الإدارة، أكواد خصم، دعوات، محفظة ونقاط، تقييم الرحلات
--
-- القواعد المالية (الدفع يبقى نقدي):
-- - الخصم (كود) ورصيد المحفظة ينطبقان على مبلغ المنتجات فقط. أجرة التوصيل ما تنقص أبداً.
-- - واصل هي اللي تتحمل الخصم والرصيد، مو المحل: المبلغ يتسجّل للمحل كـ"رصيد على واصل"
--   (order_commissions.platform_credit) وينطرح من العمولة المستحقة عليه. إذا صار السالب، واصل مدينة للمحل.
-- - كل المبالغ المخصومة تتقرّب لأقرب 250 د.ع نزولاً حتى يبقى المبلغ النقدي سهل الدفع.
-- - النقاط تُمنح عند "تم التسليم" / "اكتملت الرحلة" فقط، ومكافأة الدعوة عند أول طلب مُسلَّم للمدعو.
-- - الإلغاء يرجّع رصيد المحفظة ويحرّر استخدام الكود.
-- - ما اكو كتابة مباشرة من التطبيقات على المحفظة أو النقاط أو الاستخدامات: كلها عبر دوال الخادم.
--
-- الملف آمن للتشغيل أكثر من مرة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) الصفحة الرئيسية: أقسام مرتّبة من الإدارة
-- ---------------------------------------------------------------------
create table if not exists home_sections (
  id         uuid primary key default gen_random_uuid(),
  -- أقسام جاهزة بالتطبيق: categories, promotions, destinations, nearby, popular, reorder
  -- أقسام محتواها من home_items: slider, banner, cards
  type       text not null check (type in ('categories', 'promotions', 'destinations', 'nearby', 'popular', 'reorder', 'slider', 'banner', 'cards')),
  title      text not null default '',
  sort       int not null default 0,
  is_active  boolean not null default true,
  starts_at  timestamptz,
  ends_at    timestamptz,
  created_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index if not exists home_sections_sort_idx on home_sections (sort);

create table if not exists home_items (
  id         uuid primary key default gen_random_uuid(),
  section_id uuid not null references home_sections (id) on delete cascade,
  title      text not null default '',
  subtitle   text not null default '',
  image_url  text,
  badge      text not null default '',
  tone       text not null default 'plain' check (tone in ('plain', 'lime', 'ink', 'blue')),
  -- الوجهة: wasel://category/<id> | wasel://merchant/<uuid> | wasel://ride/taxi | wasel://ride/tuktuk
  --         wasel://rewards | wasel://invite | wasel://search | https://...
  link       text not null default '',
  sort       int not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists home_items_section_idx on home_items (section_id, sort);

alter table home_sections enable row level security;
alter table home_items    enable row level security;

drop policy if exists home_sections_read on home_sections;
create policy home_sections_read on home_sections for select to authenticated
  using ((is_active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now())) or is_admin());
drop policy if exists home_sections_admin on home_sections;
create policy home_sections_admin on home_sections for all to authenticated using (is_admin()) with check (is_admin());
drop policy if exists home_items_read on home_items;
create policy home_items_read on home_items for select to authenticated using (is_active or is_admin());
drop policy if exists home_items_admin on home_items;
create policy home_items_admin on home_items for all to authenticated using (is_admin()) with check (is_admin());

grant select, insert, update, delete on home_sections, home_items to authenticated;
grant all on home_sections, home_items to service_role;

-- الرئيسية كاملة بطلب واحد (تحترم RLS: الزبون يشوف المفعّل فقط)
create or replace function home_layout()
returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'type', s.type, 'title', s.title,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'title', i.title, 'subtitle', i.subtitle, 'image_url', i.image_url,
        'badge', i.badge, 'tone', i.tone, 'link', i.link) order by i.sort, i.created_at)
      from home_items i where i.section_id = s.id and i.is_active), '[]'::jsonb)
  ) order by s.sort, s.created_at), '[]'::jsonb)
  from home_sections s
  where s.is_active and (s.starts_at is null or s.starts_at <= now()) and (s.ends_at is null or s.ends_at > now());
$$;

-- الترتيب الافتراضي (فقط إذا الجدول فارغ)
do $$
declare sid uuid;
begin
  if not exists (select 1 from home_sections) then
    insert into home_sections (type, title, sort) values
      ('destinations', 'وين رايح؟', 10),
      ('categories', 'الأقسام', 20),
      ('promotions', '', 30),
      ('nearby', '', 50),
      ('popular', 'الأكثر طلباً', 60),
      ('reorder', 'اطلب مرة ثانية', 70);
    insert into home_sections (type, title, sort) values ('cards', 'واصل إلك', 40) returning id into sid;
    insert into home_items (section_id, title, subtitle, tone, link, sort) values
      (sid, 'نقاطك ورصيدك', 'كل طلب يجمعلك نقاط تتحول لرصيد', 'ink', 'wasel://rewards', 1),
      (sid, 'ادعُ صديق', 'إنت وصديقك تاخذون رصيد', 'lime', 'wasel://invite', 2);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2) الرحلات: تقييم السائق + الوجهات المتكررة
-- ---------------------------------------------------------------------
alter table rides add column if not exists rating int check (rating is null or rating between 1 and 5);
alter table rides add column if not exists rating_comment text not null default '';
alter table drivers add column if not exists rating_count int not null default 0;

create or replace function rate_ride(p_ride_id uuid, p_rating int, p_comment text default '')
returns rides language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r rides;
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'invalid_rating'; end if;
  select * into r from rides where id = p_ride_id and customer_id = uid for update;
  if not found or r.status <> 'completed' or r.driver_id is null then raise exception 'cannot_rate'; end if;
  update rides set rating = p_rating, rating_comment = coalesce(left(btrim(p_comment), 500), '') where id = r.id returning * into r;
  update drivers set
    rating_avg = (select round(avg(rating)::numeric, 2) from rides where driver_id = r.driver_id and rating is not null),
    rating_count = (select count(*) from rides where driver_id = r.driver_id and rating is not null)
   where id = r.driver_id;
  return r;
end $$;

-- أكثر وجهات الزبون تكراراً (من الرحلات المكتملة) لاقتراحها بضغطة وحدة
create or replace function my_ride_destinations(p_limit int default 4)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('text', x.dropoff_text, 'lat', x.lat, 'lng', x.lng, 'vehicle', x.vehicle, 'count', x.n)
                            order by x.n desc, x.last_at desc), '[]'::jsonb)
  from (
    select (array_agg(dropoff_text order by created_at desc))[1] as dropoff_text,
           (array_agg(dropoff_lat order by created_at desc))[1] as lat,
           (array_agg(dropoff_lng order by created_at desc))[1] as lng,
           (array_agg(vehicle order by created_at desc))[1] as vehicle,
           count(*) as n, max(created_at) as last_at
    from rides
    where customer_id = auth.uid() and status = 'completed'
    group by round(dropoff_lat::numeric, 3), round(dropoff_lng::numeric, 3)
    order by count(*) desc, max(created_at) desc
    limit greatest(1, least(coalesce(p_limit, 4), 10))
  ) x;
$$;

-- ---------------------------------------------------------------------
-- 3) المحفظة والنقاط والدعوات: الجداول
-- ---------------------------------------------------------------------
insert into app_settings (key, value) values
  -- points_per_1000: نقاط لكل 1000 د.ع | redeem_points نقطة = redeem_value د.ع رصيد
  -- wallet_max_percent: أقصى نسبة من مبلغ المنتجات تندفع من الرصيد
  -- points_max_order / points_max_ride: سقف النقاط للطلب أو الرحلة الوحدة (0 = بدون سقف).
  --   السقف يحد من تجميع النقاط بطلبات أو رحلات وهمية كبيرة، لأن الدفع نقدي وما يمر بالمنصة.
  ('rewards', '{"enabled": true, "points_per_1000": 1, "redeem_points": 100, "redeem_value": 1000,
                "referral_inviter": 2000, "referral_invitee": 2000, "wallet_max_percent": 50,
                "points_max_order": 30, "points_max_ride": 15}')
on conflict (key) do nothing;

create table if not exists wallet_ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references users (id) on delete cascade,
  amount     int not null check (amount <> 0),          -- موجب = إضافة، سالب = صرف
  kind       text not null check (kind in ('referral', 'points', 'admin', 'order', 'refund')),
  order_id   uuid references orders (id) on delete set null,
  note       text not null default '',
  created_by uuid references users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists wallet_ledger_user_idx on wallet_ledger (user_id, created_at desc);
create unique index if not exists wallet_ledger_refund_uq on wallet_ledger (order_id) where kind = 'refund';

create table if not exists points_ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references users (id) on delete cascade,
  points     int not null check (points <> 0),
  kind       text not null check (kind in ('order', 'ride', 'redeem', 'admin')),
  ref_id     uuid,
  note       text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists points_ledger_user_idx on points_ledger (user_id, created_at desc);
-- كل طلب/رحلة يعطي نقاط مرة وحدة فقط
create unique index if not exists points_ledger_ref_uq on points_ledger (kind, ref_id) where kind in ('order', 'ride');

create table if not exists referral_codes (
  user_id    uuid primary key references users (id) on delete cascade,
  code       text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists referrals (
  invitee_id  uuid primary key references users (id) on delete cascade,
  inviter_id  uuid not null references users (id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'rewarded')),
  created_at  timestamptz not null default now(),
  rewarded_at timestamptz,
  check (invitee_id <> inviter_id)
);
create index if not exists referrals_inviter_idx on referrals (inviter_id);

create table if not exists promo_codes (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique check (code = upper(btrim(code)) and length(code) between 3 and 24),
  description      text not null default '',
  kind             text not null check (kind in ('percent', 'fixed')),
  value            int not null check (value > 0),
  max_discount     int check (max_discount is null or max_discount > 0),   -- سقف الخصم للنسبة
  min_subtotal     int not null default 0 check (min_subtotal >= 0),
  merchant_id      uuid references merchants (id) on delete cascade,       -- فارغ = كل المحلات
  usage_limit      int check (usage_limit is null or usage_limit > 0),     -- مجموع الاستخدامات
  per_user_limit   int not null default 1 check (per_user_limit > 0),
  first_order_only boolean not null default false,
  starts_at        timestamptz not null default now(),
  ends_at          timestamptz,
  is_active        boolean not null default true,
  used_count       int not null default 0,
  created_at       timestamptz not null default now(),
  check (kind <> 'percent' or value <= 100)
);

create table if not exists promo_redemptions (
  id         bigint generated always as identity primary key,
  promo_id   uuid not null references promo_codes (id) on delete cascade,
  user_id    uuid not null references users (id) on delete cascade,
  order_id   uuid not null unique references orders (id) on delete cascade,
  amount     int not null check (amount >= 0),
  created_at timestamptz not null default now()
);
create index if not exists promo_redemptions_user_idx on promo_redemptions (promo_id, user_id);

alter table orders add column if not exists discount    int not null default 0 check (discount >= 0);
alter table orders add column if not exists wallet_used int not null default 0 check (wallet_used >= 0);
alter table orders add column if not exists promo_code  text;
alter table order_commissions add column if not exists platform_credit int not null default 0 check (platform_credit >= 0);

alter table wallet_ledger     enable row level security;
alter table points_ledger     enable row level security;
alter table referral_codes    enable row level security;
alter table referrals         enable row level security;
alter table promo_codes       enable row level security;
alter table promo_redemptions enable row level security;

-- قراءة فقط: صاحب السجل أو الإدارة. الكتابة عبر الدوال.
drop policy if exists wallet_ledger_read on wallet_ledger;
create policy wallet_ledger_read on wallet_ledger for select to authenticated using (user_id = auth.uid() or is_admin());
drop policy if exists points_ledger_read on points_ledger;
create policy points_ledger_read on points_ledger for select to authenticated using (user_id = auth.uid() or is_admin());
drop policy if exists referral_codes_read on referral_codes;
create policy referral_codes_read on referral_codes for select to authenticated using (user_id = auth.uid() or is_admin());
drop policy if exists referrals_read on referrals;
create policy referrals_read on referrals for select to authenticated
  using (invitee_id = auth.uid() or inviter_id = auth.uid() or is_admin());
drop policy if exists promo_redemptions_read on promo_redemptions;
create policy promo_redemptions_read on promo_redemptions for select to authenticated using (user_id = auth.uid() or is_admin());
-- الأكواد: الإدارة فقط (الزبون يتحقق من الكود عبر checkout_quote حتى ما تنكشف قائمة الأكواد)
drop policy if exists promo_codes_admin on promo_codes;
create policy promo_codes_admin on promo_codes for all to authenticated using (is_admin()) with check (is_admin());

grant select on wallet_ledger, points_ledger, referral_codes, referrals, promo_redemptions to authenticated;
grant select, insert, update, delete on promo_codes to authenticated;
grant all on wallet_ledger, points_ledger, referral_codes, referrals, promo_codes, promo_redemptions to service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;

-- الإدارة ما تغيّر عدّاد الاستخدام يدوياً، والكود يتخزن بحروف كبيرة
create or replace function _promo_code_guard()
returns trigger language plpgsql as $$
begin
  new.code := upper(btrim(new.code));
  if tg_op = 'INSERT' then new.used_count := 0;
  elsif auth.uid() is not null and current_user = 'authenticated' then new.used_count := old.used_count;
  end if;
  return new;
end $$;
drop trigger if exists promo_code_guard on promo_codes;
create trigger promo_code_guard before insert or update on promo_codes
  for each row execute function _promo_code_guard();

-- ---------------------------------------------------------------------
-- 4) دوال داخلية
-- ---------------------------------------------------------------------
create or replace function _rewards_cfg()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select value from app_settings where key = 'rewards'), '{"enabled": false}'::jsonb);
$$;

create or replace function _wallet_balance(p_uid uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount), 0)::int from wallet_ledger where user_id = p_uid;
$$;

create or replace function _points_balance(p_uid uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(points), 0)::int from points_ledger where user_id = p_uid;
$$;

-- تقريب نزولاً لأقرب 250 د.ع
create or replace function _floor250(n numeric)
returns int language sql immutable as $$ select (floor(greatest(n, 0) / 250) * 250)::int $$;

-- يتحقق من الكود ويرجّع (المعرّف، مبلغ الخصم). يرمي خطأ مفهوم إذا ما ينطبق.
create or replace function _promo_check(p_uid uuid, p_code text, p_merchant_id uuid, p_subtotal int, p_lock boolean,
                                        out promo_id uuid, out discount int)
language plpgsql security definer set search_path = public as $$
declare pc promo_codes; v_code text := upper(btrim(coalesce(p_code, ''))); d numeric;
begin
  if v_code = '' then raise exception 'promo_invalid'; end if;
  if p_lock then select * into pc from promo_codes where code = v_code for update;
  else select * into pc from promo_codes where code = v_code; end if;
  if not found or not pc.is_active or pc.starts_at > now() then raise exception 'promo_invalid'; end if;
  if pc.ends_at is not null and pc.ends_at <= now() then raise exception 'promo_expired'; end if;
  if pc.merchant_id is not null and pc.merchant_id <> p_merchant_id then raise exception 'promo_other_merchant'; end if;
  if pc.usage_limit is not null and pc.used_count >= pc.usage_limit then raise exception 'promo_exhausted'; end if;
  if (select count(*) from promo_redemptions r where r.promo_id = pc.id and r.user_id = p_uid) >= pc.per_user_limit then
    raise exception 'promo_used';
  end if;
  if pc.first_order_only and exists (select 1 from orders where customer_id = p_uid and status <> 'cancelled') then
    raise exception 'promo_first_order';
  end if;
  if p_subtotal < pc.min_subtotal then raise exception 'promo_min:%', pc.min_subtotal; end if;
  d := case pc.kind when 'percent' then p_subtotal * pc.value / 100.0 else pc.value end;
  if pc.max_discount is not null then d := least(d, pc.max_discount); end if;
  promo_id := pc.id;
  discount := least(_floor250(d), p_subtotal);
end $$;

-- كم يندفع من الرصيد لطلب معيّن
create or replace function _wallet_usable(p_uid uuid, p_base int)
returns int language sql stable security definer set search_path = public as $$
  select case when coalesce((_rewards_cfg()->>'enabled')::boolean, false)
    then _floor250(least(_wallet_balance(p_uid),
                         p_base * least(greatest(coalesce((_rewards_cfg()->>'wallet_max_percent')::numeric, 0), 0), 100) / 100.0))
    else 0 end;
$$;

create or replace function _ensure_referral_code(p_uid uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v text;
begin
  select code into v from referral_codes where user_id = p_uid;
  if found then return v; end if;
  loop
    -- حروف وأرقام واضحة (بدون 0/O/1/I)
    select 'W' || string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
      into v from generate_series(1, 6);
    begin
      insert into referral_codes (user_id, code) values (p_uid, v);
      return v;
    exception when unique_violation then
      select code into v from referral_codes where user_id = p_uid;
      if found then return v; end if;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5) الطلب: عرض السعر قبل التأكيد + إنشاء الطلب مع الخصم والرصيد
-- ---------------------------------------------------------------------
-- للعرض فقط (السلة). السعر النهائي يُحسب داخل place_order.
create or replace function checkout_quote(p_merchant_id uuid, p_items jsonb, p_promo_code text default null, p_use_wallet boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := require_user(); m merchants;
  v_subtotal int := 0; v_discount int := 0; v_wallet int := 0; v_err text; v_pid uuid;
begin
  select * into m from merchants where id = p_merchant_id;
  if not found or m.status <> 'approved' then raise exception 'merchant_unavailable'; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'empty_cart'; end if;
  select coalesce(sum(p.price * least(greatest((i->>'qty')::int, 0), 99)), 0)::int into v_subtotal
    from jsonb_array_elements(p_items) i join products p on p.id = (i->>'product_id')::uuid and p.merchant_id = m.id;
  if btrim(coalesce(p_promo_code, '')) <> '' then
    begin
      select c.promo_id, c.discount into v_pid, v_discount from _promo_check(uid, p_promo_code, m.id, v_subtotal, false) c;
    exception when raise_exception then
      v_err := sqlerrm; v_discount := 0;
    end;
  end if;
  if p_use_wallet then v_wallet := _wallet_usable(uid, v_subtotal - v_discount); end if;
  return jsonb_build_object(
    'subtotal', v_subtotal, 'delivery_fee', m.delivery_fee, 'discount', v_discount, 'wallet_used', v_wallet,
    'total', v_subtotal + m.delivery_fee - v_discount - v_wallet,
    'promo_error', v_err, 'wallet_balance', _wallet_balance(uid),
    'wallet_available', _wallet_usable(uid, v_subtotal - v_discount));
end $$;

-- التوقيع القديم (5 معاملات) ينحذف حتى ما يتعارض مع الجديد. التطبيقات القديمة تبقى تشتغل
-- لأن المعاملين الجديدين إلهما قيم افتراضية.
drop function if exists place_order(uuid, uuid, jsonb, text, uuid);

create or replace function place_order(
  p_merchant_id uuid, p_address_id uuid, p_items jsonb, p_note text, p_client_ref uuid,
  p_promo_code text default null, p_use_wallet boolean default false
) returns orders language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  m merchants; a addresses; u users; o orders;
  item jsonb; p products;
  v_subtotal int := 0; v_qty int; v_fee int;
  allow_out boolean := coalesce((setting('allow_out_of_area')->>'enabled')::boolean, false);
  v_min int; v_promo uuid; v_discount int := 0; v_wallet int := 0; v_code text;
begin
  -- نفس الطلب انرسل قبل؟ نرجّعه بدل ما نكرره
  select * into o from orders where customer_id = uid and client_ref = p_client_ref;
  if found then return o; end if;

  select * into m from merchants where id = p_merchant_id;
  if not found or m.status <> 'approved' then raise exception 'merchant_unavailable'; end if;
  if not merchant_is_open(m) then raise exception 'merchant_closed'; end if;
  if (select kind from merchant_categories where id = m.category_id) <> 'store' then
    raise exception 'merchant_not_orderable';
  end if;

  select * into a from addresses where id = p_address_id and user_id = uid;
  if not found then raise exception 'address_not_found'; end if;

  if not allow_out and distance_km(m.lat, m.lng, a.lat, a.lng) > m.delivery_radius_km then
    raise exception 'out_of_delivery_area';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'empty_cart';
  end if;

  -- قفل صف المستخدم: طلبين بنفس اللحظة ما يصرفون نفس الرصيد أو نفس الكود
  select * into u from users where id = uid for update;
  v_fee := m.delivery_fee;

  insert into orders (client_ref, customer_id, merchant_id, area_id, customer_name, customer_phone,
                      address_text, address_lat, address_lng, subtotal, delivery_fee, total, customer_note)
  values (p_client_ref, uid, m.id, m.area_id, u.full_name, coalesce(u.phone, ''),
          trim(a.label || ' - ' || a.details || case
            when a.landmark = '' then ''
            when a.landmark ~ '^(قرب|مقابل|جنب|خلف|بجانب|يم) ' then ' (' || a.landmark || ')'
            else ' (قرب ' || a.landmark || ')' end),
          a.lat, a.lng, 0, v_fee, 0, coalesce(left(p_note, 500), ''))
  returning * into o;

  for item in select * from jsonb_array_elements(p_items) loop
    v_qty := (item->>'qty')::int;
    if v_qty is null or v_qty < 1 or v_qty > 99 then raise exception 'invalid_quantity'; end if;
    select * into p from products where id = (item->>'product_id')::uuid and merchant_id = m.id for update;
    if not found or not p.is_available then raise exception 'product_unavailable:%', coalesce(p.name, ''); end if;
    if p.stock is not null then
      if p.stock < v_qty then raise exception 'out_of_stock:%', p.name; end if;
      update products set stock = stock - v_qty,
                          is_available = (stock - v_qty) > 0
       where id = p.id;
    end if;
    insert into order_items (order_id, product_id, name, unit_price, qty, note)
    values (o.id, p.id, p.name, p.price, v_qty, coalesce(left(item->>'note', 200), ''));
    v_subtotal := v_subtotal + p.price * v_qty;
  end loop;

  v_min := greatest(m.min_order, coalesce((setting('min_order')->>'amount')::int, 0));
  if v_subtotal < v_min then raise exception 'below_min_order:%', v_min; end if;

  -- كود الخصم (على المنتجات فقط)
  if btrim(coalesce(p_promo_code, '')) <> '' then
    select c.promo_id, c.discount into v_promo, v_discount from _promo_check(uid, p_promo_code, m.id, v_subtotal, true) c;
    v_code := upper(btrim(p_promo_code));
    insert into promo_redemptions (promo_id, user_id, order_id, amount) values (v_promo, uid, o.id, v_discount);
    update promo_codes set used_count = used_count + 1 where id = v_promo;
  end if;

  -- رصيد المحفظة
  if p_use_wallet then
    v_wallet := _wallet_usable(uid, v_subtotal - v_discount);
    if v_wallet > 0 then
      insert into wallet_ledger (user_id, amount, kind, order_id, note) values (uid, -v_wallet, 'order', o.id, 'طلب ' || o.code);
    end if;
  end if;

  update orders set subtotal = v_subtotal, discount = v_discount, wallet_used = v_wallet, promo_code = v_code,
                    total = v_subtotal + v_fee - v_discount - v_wallet
   where id = o.id returning * into o;

  perform notify_user(m.owner_id, 'طلب جديد ' || o.code,
    'المبلغ ' || o.total || ' د.ع', jsonb_build_object('type', 'merchant_order', 'id', o.id));
  return o;
end $$;

-- ---------------------------------------------------------------------
-- 6) عند تغيّر حالة الطلب / الرحلة: نقاط، مكافأة الدعوة، استرجاع، رصيد المحل
-- ---------------------------------------------------------------------
create or replace function _order_growth_on_status()
returns trigger language plpgsql security definer set search_path = public as $$
declare cfg jsonb := _rewards_cfg(); on_ boolean := coalesce((cfg->>'enabled')::boolean, false);
        pts int; ref referrals; v_inviter int; v_invitee int;
begin
  if new.status = old.status then return new; end if;

  if new.status = 'cancelled' then
    if new.wallet_used > 0 then
      insert into wallet_ledger (user_id, amount, kind, order_id, note)
      values (new.customer_id, new.wallet_used, 'refund', new.id, 'استرجاع طلب ' || new.code)
      on conflict do nothing;
    end if;
    update promo_codes set used_count = greatest(used_count - 1, 0)
     where id in (select promo_id from promo_redemptions where order_id = new.id);
    delete from promo_redemptions where order_id = new.id;
    update order_commissions set platform_credit = 0 where order_id = new.id;

  elsif new.status = 'delivered' then
    -- واصل تتحمل الخصم والرصيد: ينحسب للمحل
    update order_commissions set platform_credit = new.discount + new.wallet_used where order_id = new.id;

    if on_ then
      pts := (floor((new.subtotal - new.discount) / 1000.0) * greatest(coalesce((cfg->>'points_per_1000')::int, 0), 0))::int;
      if coalesce((cfg->>'points_max_order')::int, 0) > 0 then pts := least(pts, (cfg->>'points_max_order')::int); end if;
      if pts > 0 then
        insert into points_ledger (user_id, points, kind, ref_id, note)
        values (new.customer_id, pts, 'order', new.id, 'طلب ' || new.code)
        on conflict do nothing;
      end if;

      -- أول طلب مُسلَّم للمدعو: الاثنين ياخذون رصيد
      select * into ref from referrals where invitee_id = new.customer_id and status = 'pending' for update;
      if found then
        v_inviter := greatest(coalesce((cfg->>'referral_inviter')::int, 0), 0);
        v_invitee := greatest(coalesce((cfg->>'referral_invitee')::int, 0), 0);
        update referrals set status = 'rewarded', rewarded_at = now() where invitee_id = ref.invitee_id;
        if v_invitee > 0 then
          insert into wallet_ledger (user_id, amount, kind, note) values (ref.invitee_id, v_invitee, 'referral', 'هدية الانضمام بدعوة');
          perform notify_user(ref.invitee_id, 'وصلك رصيد ' || v_invitee || ' د.ع', 'هدية أول طلب بدعوة صديق', jsonb_build_object('type', 'rewards'));
        end if;
        if v_inviter > 0 then
          insert into wallet_ledger (user_id, amount, kind, note) values (ref.inviter_id, v_inviter, 'referral', 'مكافأة دعوة صديق');
          perform notify_user(ref.inviter_id, 'وصلك رصيد ' || v_inviter || ' د.ع', 'صديقك كمّل أول طلب', jsonb_build_object('type', 'rewards'));
        end if;
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists order_growth_status on orders;
create trigger order_growth_status after update of status on orders
  for each row execute function _order_growth_on_status();

create or replace function _ride_growth_on_status()
returns trigger language plpgsql security definer set search_path = public as $$
declare cfg jsonb := _rewards_cfg(); pts int;
begin
  if new.status = old.status or new.status <> 'completed' then return new; end if;
  if not coalesce((cfg->>'enabled')::boolean, false) then return new; end if;
  pts := (floor(new.fare / 1000.0) * greatest(coalesce((cfg->>'points_per_1000')::int, 0), 0))::int;
  if coalesce((cfg->>'points_max_ride')::int, 0) > 0 then pts := least(pts, (cfg->>'points_max_ride')::int); end if;
  if pts > 0 then
    insert into points_ledger (user_id, points, kind, ref_id, note)
    values (new.customer_id, pts, 'ride', new.id, 'رحلة ' || case new.vehicle when 'tuktuk' then 'تكتك' else 'تكسي' end)
    on conflict do nothing;
  end if;
  return new;
end $$;

-- المندوب يشوف المبلغ المطلوب من الزبون (بعد الخصم والرصيد) ضمن ملاحظات مهمة التوصيل
create or replace function _task_collect_note()
returns trigger language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  if new.kind <> 'order' or new.order_id is null then return new; end if;
  select * into o from orders where id = new.order_id;
  if not found then return new; end if;
  new.notes := btrim('المطلوب من الزبون: ' || o.total || ' د.ع'
    || case when o.discount + o.wallet_used > 0 then ' (بعد خصم ' || (o.discount + o.wallet_used) || ' تتحمله واصل)' else '' end
    || case when new.notes <> '' then E'\n' || new.notes else '' end);
  return new;
end $$;

drop trigger if exists task_collect_note on delivery_tasks;
create trigger task_collect_note before insert on delivery_tasks
  for each row execute function _task_collect_note();

drop trigger if exists ride_growth_status on rides;
create trigger ride_growth_status after update of status on rides
  for each row execute function _ride_growth_on_status();

-- ---------------------------------------------------------------------
-- 7) دوال الزبون: ملخص المكافآت، تحويل النقاط، إدخال كود دعوة
-- ---------------------------------------------------------------------
create or replace function my_rewards()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); cfg jsonb := _rewards_cfg();
begin
  return jsonb_build_object(
    'enabled', coalesce((cfg->>'enabled')::boolean, false),
    'wallet', _wallet_balance(uid),
    'points', _points_balance(uid),
    'points_per_1000', coalesce((cfg->>'points_per_1000')::int, 0),
    'redeem_points', coalesce((cfg->>'redeem_points')::int, 0),
    'redeem_value', coalesce((cfg->>'redeem_value')::int, 0),
    'referral_inviter', coalesce((cfg->>'referral_inviter')::int, 0),
    'referral_invitee', coalesce((cfg->>'referral_invitee')::int, 0),
    'wallet_max_percent', coalesce((cfg->>'wallet_max_percent')::int, 0),
    'referral_code', _ensure_referral_code(uid),
    'referred', exists (select 1 from referrals where invitee_id = uid),
    'can_enter_code', not exists (select 1 from referrals where invitee_id = uid)
                      and not exists (select 1 from orders where customer_id = uid and status = 'delivered'),
    'invited', (select count(*) from referrals where inviter_id = uid),
    'invited_rewarded', (select count(*) from referrals where inviter_id = uid and status = 'rewarded'),
    'wallet_history', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'amount', w.amount, 'kind', w.kind, 'note', w.note, 'created_at', w.created_at) order by w.id desc)
                                from (select * from wallet_ledger where user_id = uid order by id desc limit 30) w), '[]'::jsonb),
    'points_history', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'points', p.points, 'kind', p.kind, 'note', p.note, 'created_at', p.created_at) order by p.id desc)
                                from (select * from points_ledger where user_id = uid order by id desc limit 30) p), '[]'::jsonb)
  );
end $$;

-- يحوّل كل النقاط الممكنة إلى رصيد (بمضاعفات redeem_points)
create or replace function redeem_points()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); cfg jsonb := _rewards_cfg();
        rp int := coalesce((cfg->>'redeem_points')::int, 0); rv int := coalesce((cfg->>'redeem_value')::int, 0);
        bal int; units int;
begin
  if not coalesce((cfg->>'enabled')::boolean, false) or rp <= 0 or rv <= 0 then raise exception 'rewards_disabled'; end if;
  perform 1 from users where id = uid for update;
  bal := _points_balance(uid);
  units := bal / rp;
  if units < 1 then raise exception 'points_not_enough:%', rp; end if;
  insert into points_ledger (user_id, points, kind, note) values (uid, -units * rp, 'redeem', 'تحويل إلى رصيد');
  insert into wallet_ledger (user_id, amount, kind, note) values (uid, units * rv, 'points', 'تحويل ' || units * rp || ' نقطة');
  return my_rewards();
end $$;

-- الزبون الجديد يدخل كود صديقه (قبل أول طلب مُسلَّم، مرة وحدة)
create or replace function apply_referral_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); v_inviter uuid;
begin
  if not coalesce((_rewards_cfg()->>'enabled')::boolean, false) then raise exception 'rewards_disabled'; end if;
  if exists (select 1 from referrals where invitee_id = uid) then raise exception 'referral_already_used'; end if;
  if exists (select 1 from orders where customer_id = uid and status = 'delivered') then raise exception 'referral_not_new'; end if;
  select user_id into v_inviter from referral_codes where code = upper(btrim(coalesce(p_code, '')));
  if not found then raise exception 'referral_invalid'; end if;
  if v_inviter = uid then raise exception 'referral_self'; end if;
  -- ما يصير اثنين يدعون بعض
  if exists (select 1 from referrals where invitee_id = v_inviter and inviter_id = uid) then raise exception 'referral_invalid'; end if;
  insert into referrals (invitee_id, inviter_id) values (uid, v_inviter);
  return my_rewards();
end $$;

-- ---------------------------------------------------------------------
-- 8) الإدارة: إضافة/خصم رصيد يدوياً + ملخص
-- ---------------------------------------------------------------------
create or replace function admin_wallet_adjust(p_user_id uuid, p_amount int, p_note text default '')
returns int language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); bal int;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'invalid_amount'; end if;
  perform 1 from users where id = p_user_id for update;
  if not found then raise exception 'user_not_found'; end if;
  bal := _wallet_balance(p_user_id);
  if bal + p_amount < 0 then raise exception 'wallet_insufficient'; end if;
  insert into wallet_ledger (user_id, amount, kind, note, created_by)
  values (p_user_id, p_amount, 'admin', btrim(coalesce(p_note, '')), uid);
  if p_amount > 0 then
    perform notify_user(p_user_id, 'وصلك رصيد ' || p_amount || ' د.ع', btrim(coalesce(p_note, '')), jsonb_build_object('type', 'rewards'));
  end if;
  return bal + p_amount;
end $$;

create or replace function admin_growth_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'wallet_outstanding', (select coalesce(sum(amount), 0) from wallet_ledger),
    'points_outstanding', (select coalesce(sum(points), 0) from points_ledger),
    'referrals', (select count(*) from referrals),
    'referrals_rewarded', (select count(*) from referrals where status = 'rewarded'),
    'promo_discounts', (select coalesce(sum(discount), 0) from orders where status = 'delivered'),
    'wallet_spent', (select coalesce(sum(wallet_used), 0) from orders where status = 'delivered'),
    'merchant_credit', (select coalesce(sum(platform_credit), 0) from order_commissions)
  );
end $$;

-- ملخصات العمولة: المستحق = العمولة − المدفوع − رصيد المحل على واصل (خصومات تحملتها واصل)
create or replace function merchant_commission_summary(p_merchant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  month_start timestamptz := date_trunc('month', now() at time zone 'Asia/Baghdad') at time zone 'Asia/Baghdad';
  earned bigint; settled bigint; credit bigint;
begin
  if not owns_merchant(p_merchant_id) and not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select coalesce(sum(amount), 0), coalesce(sum(platform_credit), 0) into earned, credit from order_commissions where merchant_id = p_merchant_id;
  select coalesce(sum(amount), 0) into settled from merchant_settlements where merchant_id = p_merchant_id;
  return jsonb_build_object(
    'percent', effective_commission_percent(p_merchant_id),
    'custom', (select commission_percent is not null from merchants where id = p_merchant_id),
    'earned_total', earned,
    'settled_total', settled,
    'credit_total', credit,
    'due', earned - settled - credit,
    'month_commission', (select coalesce(sum(amount), 0) from order_commissions where merchant_id = p_merchant_id and earned_at >= month_start),
    'month_sales', (select coalesce(sum(o.subtotal), 0) from order_commissions c join orders o on o.id = c.order_id where c.merchant_id = p_merchant_id and c.earned_at >= month_start),
    'settlements', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'amount', s.amount, 'note', s.note, 'created_at', s.created_at) order by s.created_at desc)
                             from (select * from merchant_settlements where merchant_id = p_merchant_id order by created_at desc limit 20) s), '[]'::jsonb)
  );
end $$;

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
    'credit_total', (select coalesce(sum(platform_credit), 0) from order_commissions),
    'due_total', (select coalesce(sum(amount - platform_credit), 0) from order_commissions) - (select coalesce(sum(amount), 0) from merchant_settlements),
    'merchants', coalesce((
      select jsonb_agg(row_to_json(x) order by x.due desc, x.name)
      from (
        select m.id, m.name, m.commission_percent as custom_percent, effective_commission_percent(m.id) as percent,
               coalesce(e.period_orders, 0) as period_orders, coalesce(e.period_sales, 0) as period_sales,
               coalesce(e.period_commission, 0) as period_commission,
               coalesce(t.earned, 0) as earned_total, coalesce(s.settled, 0) as settled_total,
               coalesce(t.credit, 0) as credit_total,
               coalesce(t.earned, 0) - coalesce(s.settled, 0) - coalesce(t.credit, 0) as due
        from merchants m
        left join (select c.merchant_id, count(*) as period_orders, sum(o.subtotal) as period_sales, sum(c.amount) as period_commission
                   from order_commissions c join orders o on o.id = c.order_id
                   where c.earned_at >= since group by c.merchant_id) e on e.merchant_id = m.id
        left join (select merchant_id, sum(amount) as earned, sum(platform_credit) as credit from order_commissions group by merchant_id) t on t.merchant_id = m.id
        left join (select merchant_id, sum(amount) as settled from merchant_settlements group by merchant_id) s on s.merchant_id = m.id
        where m.category_id <> 'home_services'
      ) x), '[]'::jsonb)
  );
end $$;

-- ---------------------------------------------------------------------
-- 9) صلاحيات التنفيذ
-- ---------------------------------------------------------------------
-- الدوال الداخلية: ما تنستدعى من التطبيقات أبداً
revoke execute on function _rewards_cfg(), _wallet_balance(uuid), _points_balance(uuid), _floor250(numeric),
  _promo_check(uuid, text, uuid, int, boolean), _wallet_usable(uuid, int), _ensure_referral_code(uuid),
  _order_growth_on_status(), _ride_growth_on_status(), _promo_code_guard(), _task_collect_note()
  from public, anon, authenticated;

revoke execute on function home_layout(), rate_ride(uuid, int, text), my_ride_destinations(int),
  checkout_quote(uuid, jsonb, text, boolean), place_order(uuid, uuid, jsonb, text, uuid, text, boolean),
  my_rewards(), redeem_points(), apply_referral_code(text), admin_wallet_adjust(uuid, int, text), admin_growth_stats()
  from public, anon;
grant execute on function home_layout(), rate_ride(uuid, int, text), my_ride_destinations(int),
  checkout_quote(uuid, jsonb, text, boolean), place_order(uuid, uuid, jsonb, text, uuid, text, boolean),
  my_rewards(), redeem_points(), apply_referral_code(text), admin_wallet_adjust(uuid, int, text), admin_growth_stats()
  to authenticated, service_role;

notify pgrst, 'reload schema';
