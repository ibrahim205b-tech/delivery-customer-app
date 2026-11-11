-- ملف واحد يجمع كل ملفات supabase/migrations بالترتيب. الصقه كاملاً في SQL Editor واضغط Run (مرة وحدة فقط).

-- ===== supabase/migrations/0001_schema.sql =====
-- =====================================================================
-- WASEL | واصل — المخطط الأساسي لقاعدة البيانات (Supabase / PostgreSQL)
-- =====================================================================
-- كل الجداول بالمخطط public. الحماية بـ Row Level Security (ملف 0003).
-- العمليات الحساسة (إنشاء طلب، تغيير حالة، تسعير) تمر عبر دوال بالخادم (ملف 0002)
-- حتى ما يگدر التطبيق يغيّر سعر أو حالة بشكل مباشر.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- الأنواع
-- ---------------------------------------------------------------------
create type app_role as enum ('customer', 'merchant', 'driver', 'admin');
create type category_kind as enum ('store', 'home_service', 'ride', 'courier', 'parcel');
create type merchant_status as enum ('pending', 'approved', 'suspended');
create type order_status as enum (
  'placed',      -- تم إرسال الطلب
  'accepted',    -- المحل وافق
  'preparing',   -- قيد التحضير
  'ready',       -- جاهز للاستلام
  'picked_up',   -- المندوب استلم
  'on_the_way',  -- في الطريق
  'delivered',   -- تم التسليم
  'cancelled'    -- ملغي
);
create type vehicle_type as enum ('taxi', 'tuktuk', 'courier');
create type task_kind as enum ('order', 'courier', 'parcel');
create type task_status as enum ('requested', 'assigned', 'picked_up', 'on_the_way', 'delivered', 'cancelled');
create type ride_status as enum ('requested', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled');
create type booking_status as enum ('requested', 'accepted', 'rejected', 'in_progress', 'completed', 'cancelled');

-- ---------------------------------------------------------------------
-- المستخدمون والأدوار
-- ---------------------------------------------------------------------
create table users (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '',
  phone       text unique,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table user_roles (
  user_id    uuid not null references users (id) on delete cascade,
  role       app_role not null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

-- ---------------------------------------------------------------------
-- المناطق والإعدادات
-- ---------------------------------------------------------------------
create table service_areas (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  city       text not null,
  center_lat double precision not null check (center_lat between -90 and 90),
  center_lng double precision not null check (center_lng between -180 and 180),
  radius_km  numeric(6,2) not null default 5 check (radius_km > 0),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create table app_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- الأقسام والمحلات
-- ---------------------------------------------------------------------
create table merchant_categories (
  id        text primary key,            -- مثال: restaurants
  name      text not null,
  kind      category_kind not null default 'store',
  icon      text not null,               -- اسم الأيقونة داخل التطبيق
  sort      int not null default 0,
  is_active boolean not null default true
);

create table merchants (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid references users (id) on delete set null,
  category_id         text not null references merchant_categories (id),
  area_id             uuid references service_areas (id) on delete set null,
  name                text not null check (length(trim(name)) > 1),
  description         text not null default '',
  address_text        text not null default '',
  lat                 double precision not null check (lat between -90 and 90),
  lng                 double precision not null check (lng between -180 and 180),
  phone               text not null default '',
  cover_url           text,
  logo_url            text,
  delivery_fee        int not null default 0 check (delivery_fee >= 0),
  min_order           int not null default 0 check (min_order >= 0),
  prep_minutes        int not null default 20 check (prep_minutes between 0 and 300),
  delivery_radius_km  numeric(6,2) not null default 5 check (delivery_radius_km > 0),
  -- {"0":{"open":"09:00","close":"23:00","closed":false}, ... } (0 = الأحد)
  working_hours       jsonb not null default '{}'::jsonb,
  status              merchant_status not null default 'pending',
  is_accepting_orders boolean not null default true,
  rating_avg          numeric(3,2) not null default 0,
  rating_count        int not null default 0,
  order_count         int not null default 0,
  created_at          timestamptz not null default now()
);
create index merchants_category_idx on merchants (category_id) where status = 'approved';
create index merchants_owner_idx on merchants (owner_id);
create index merchants_area_idx on merchants (area_id);

create table product_categories (
  id          uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  sort        int not null default 0,
  unique (merchant_id, name)
);

create table products (
  id           uuid primary key default gen_random_uuid(),
  merchant_id  uuid not null references merchants (id) on delete cascade,
  category_id  uuid references product_categories (id) on delete set null,
  name         text not null check (length(trim(name)) > 0),
  description  text not null default '',
  price        int not null check (price > 0),           -- دينار عراقي
  is_available boolean not null default true,
  stock        int check (stock is null or stock >= 0),  -- null = بدون حد
  sort         int not null default 0,
  created_at   timestamptz not null default now()
);
create index products_merchant_idx on products (merchant_id);

create table product_images (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references products (id) on delete cascade,
  url        text not null,
  sort       int not null default 0
);
create index product_images_product_idx on product_images (product_id);

-- ---------------------------------------------------------------------
-- العناوين
-- ---------------------------------------------------------------------
create table addresses (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users (id) on delete cascade,
  label      text not null default 'البيت',
  details    text not null default '',
  landmark   text not null default '',
  lat        double precision not null check (lat between -90 and 90),
  lng        double precision not null check (lng between -180 and 180),
  area_id    uuid references service_areas (id) on delete set null,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index addresses_user_idx on addresses (user_id);

-- ---------------------------------------------------------------------
-- السائقون والمركبات
-- ---------------------------------------------------------------------
create table drivers (
  id            uuid primary key references users (id) on delete cascade,
  vehicle_type  vehicle_type not null,
  area_id       uuid references service_areas (id) on delete set null,
  is_active     boolean not null default true,     -- الإدارة تفعّل/توقف
  is_available  boolean not null default false,    -- السائق يختار
  last_lat      double precision,
  last_lng      double precision,
  last_seen_at  timestamptz,
  rating_avg    numeric(3,2) not null default 0,
  created_at    timestamptz not null default now()
);

create table vehicles (
  id         uuid primary key default gen_random_uuid(),
  driver_id  uuid not null unique references drivers (id) on delete cascade,
  type       vehicle_type not null,
  plate      text not null default '',
  model      text not null default '',
  color      text not null default '',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- الطلبات
-- ---------------------------------------------------------------------
create sequence order_code_seq start 1001;

create table orders (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique default ('W' || nextval('order_code_seq')),
  client_ref      uuid not null,                     -- يمنع تكرار الطلب لو انضغط الزر مرتين
  customer_id     uuid not null references users (id),
  merchant_id     uuid not null references merchants (id),
  driver_id       uuid references drivers (id),
  area_id         uuid references service_areas (id),
  status          order_status not null default 'placed',
  -- نسخة من البيانات وقت الطلب (snapshot)
  customer_name   text not null default '',
  customer_phone  text not null default '',
  address_text    text not null default '',
  address_lat     double precision not null,
  address_lng     double precision not null,
  driver_name     text,
  driver_phone    text,
  driver_vehicle  text,
  driver_lat      double precision,
  driver_lng      double precision,
  subtotal        int not null check (subtotal >= 0),
  delivery_fee    int not null check (delivery_fee >= 0),
  total           int not null check (total >= 0),
  payment_method  text not null default 'cash' check (payment_method = 'cash'),
  customer_note   text not null default '',
  cancel_reason   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (customer_id, client_ref)
);
create index orders_customer_idx on orders (customer_id, created_at desc);
create index orders_merchant_idx on orders (merchant_id, created_at desc);
create index orders_driver_idx on orders (driver_id) where driver_id is not null;
create index orders_status_idx on orders (status);

create table order_items (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references orders (id) on delete cascade,
  product_id uuid references products (id) on delete set null,
  name       text not null,
  unit_price int not null check (unit_price >= 0),
  qty        int not null check (qty between 1 and 99),
  note       text not null default ''
);
create index order_items_order_idx on order_items (order_id);

create table order_status_history (
  id         bigint generated always as identity primary key,
  order_id   uuid not null references orders (id) on delete cascade,
  status     order_status not null,
  actor_id   uuid,
  note       text,
  created_at timestamptz not null default now()
);
create index order_status_history_order_idx on order_status_history (order_id, created_at);

-- ---------------------------------------------------------------------
-- مهام التوصيل (توصيل طلبات المحلات + المندوب + توصيل الأغراض)
-- ---------------------------------------------------------------------
create table delivery_tasks (
  id              uuid primary key default gen_random_uuid(),
  kind            task_kind not null,
  order_id        uuid unique references orders (id) on delete cascade,
  customer_id     uuid not null references users (id),
  driver_id       uuid references drivers (id),
  area_id         uuid references service_areas (id),
  status          task_status not null default 'requested',
  pickup_text     text not null default '',
  pickup_lat      double precision not null,
  pickup_lng      double precision not null,
  dropoff_text    text not null default '',
  dropoff_lat     double precision not null,
  dropoff_lng     double precision not null,
  item_type       text not null default '',
  description     text not null default '',
  recipient_phone text not null default '',
  notes           text not null default '',
  customer_name   text not null default '',
  customer_phone  text not null default '',
  driver_name     text,
  driver_phone    text,
  driver_lat      double precision,
  driver_lng      double precision,
  distance_km     numeric(7,2),
  fee             int not null check (fee >= 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check ((kind = 'order') = (order_id is not null))
);
create index delivery_tasks_status_idx on delivery_tasks (status) where status = 'requested';
create index delivery_tasks_driver_idx on delivery_tasks (driver_id);
create index delivery_tasks_customer_idx on delivery_tasks (customer_id, created_at desc);

-- ---------------------------------------------------------------------
-- الرحلات (تكسي / تكتك)
-- ---------------------------------------------------------------------
create table rides (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references users (id),
  driver_id      uuid references drivers (id),
  area_id        uuid references service_areas (id),
  vehicle        vehicle_type not null check (vehicle in ('taxi', 'tuktuk')),
  status         ride_status not null default 'requested',
  pickup_text    text not null default '',
  pickup_lat     double precision not null,
  pickup_lng     double precision not null,
  dropoff_text   text not null default '',
  dropoff_lat    double precision not null,
  dropoff_lng    double precision not null,
  distance_km    numeric(7,2) not null,
  fare           int not null check (fare >= 0),
  customer_name  text not null default '',
  customer_phone text not null default '',
  driver_name    text,
  driver_phone   text,
  driver_vehicle text,
  driver_lat     double precision,
  driver_lng     double precision,
  created_at     timestamptz not null default now(),
  accepted_at    timestamptz,
  completed_at   timestamptz,
  updated_at     timestamptz not null default now()
);
create index rides_status_idx on rides (vehicle, status) where status = 'requested';
create index rides_customer_idx on rides (customer_id, created_at desc);
create index rides_driver_idx on rides (driver_id);

-- ---------------------------------------------------------------------
-- الخدمات المنزلية
-- ---------------------------------------------------------------------
create table home_services (
  id        uuid primary key default gen_random_uuid(),
  name      text not null unique,
  icon      text not null default 'handyman',
  sort      int not null default 0,
  is_active boolean not null default true
);

-- أي مقدّم خدمة (محل من قسم home_services) يقدّم أي خدمة
create table merchant_services (
  merchant_id uuid not null references merchants (id) on delete cascade,
  service_id  uuid not null references home_services (id) on delete cascade,
  primary key (merchant_id, service_id)
);

create table service_bookings (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references users (id),
  service_id     uuid not null references home_services (id),
  provider_id    uuid not null references merchants (id),
  status         booking_status not null default 'requested',
  address_text   text not null default '',
  lat            double precision not null,
  lng            double precision not null,
  description    text not null check (length(trim(description)) > 0),
  photo_urls     text[] not null default '{}',
  preferred_time timestamptz not null,
  customer_name  text not null default '',
  customer_phone text not null default '',
  provider_note  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index service_bookings_customer_idx on service_bookings (customer_id, created_at desc);
create index service_bookings_provider_idx on service_bookings (provider_id, created_at desc);

-- ---------------------------------------------------------------------
-- التقييمات والمفضلة والعروض والإشعارات
-- ---------------------------------------------------------------------
create table reviews (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null unique references orders (id) on delete cascade,
  customer_id uuid not null references users (id),
  merchant_id uuid not null references merchants (id) on delete cascade,
  rating      int not null check (rating between 1 and 5),
  comment     text not null default '',
  created_at  timestamptz not null default now()
);

create table favorites (
  user_id     uuid not null references users (id) on delete cascade,
  merchant_id uuid not null references merchants (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, merchant_id)
);

create table promotions (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text not null default '',
  image_url   text,
  merchant_id uuid references merchants (id) on delete cascade,
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references users (id) on delete cascade,
  title      text not null,
  body       text not null default '',
  data       jsonb not null default '{}'::jsonb,
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on notifications (user_id, created_at desc);

-- ===== supabase/migrations/0002_functions.sql =====
-- =====================================================================
-- WASEL | دوال الخادم: الصلاحيات، التسعير، دورة حياة الطلبات والرحلات
-- =====================================================================
-- كل دالة "security definer" تتحقق بنفسها من هوية المستدعي auth.uid()
-- لأنها تتجاوز RLS. لا توجد كتابة مباشرة على orders/rides/tasks من التطبيقات.

-- ---------------------------------------------------------------------
-- أدوات مساعدة
-- ---------------------------------------------------------------------
create or replace function has_role(r app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_roles ur join users u on u.id = ur.user_id
    where ur.user_id = auth.uid() and ur.role = r and u.is_active
  );
$$;

create or replace function is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select has_role('admin');
$$;

create or replace function owns_merchant(m uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from merchants where id = m and owner_id = auth.uid());
$$;

create or replace function require_user()
returns uuid language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from users where id = uid and is_active) then
    raise exception 'account_disabled' using errcode = '42501';
  end if;
  return uid;
end $$;

-- المسافة بالكيلومتر (Haversine) — بدون خدمة خرائط خارجية
create or replace function distance_km(lat1 double precision, lng1 double precision,
                                       lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

create or replace function setting(k text)
returns jsonb language sql stable security definer set search_path = public as $$
  select value from app_settings where key = k;
$$;

-- يحسب الأجرة من إعدادات الإدارة: {"mode":"distance"|"fixed","base":..,"per_km":..,"fixed":..,"min":..}
create or replace function compute_fare(cfg jsonb, km double precision)
returns int language plpgsql immutable as $$
declare fare numeric;
begin
  if cfg is null then raise exception 'pricing_not_configured'; end if;
  if coalesce(cfg->>'mode', 'distance') = 'fixed' then
    fare := (cfg->>'fixed')::numeric;
  else
    fare := coalesce((cfg->>'base')::numeric, 0) + coalesce((cfg->>'per_km')::numeric, 0) * km;
  end if;
  fare := greatest(fare, coalesce((cfg->>'min')::numeric, 0));
  return (ceil(fare / 250.0) * 250)::int;   -- تقريب لأقرب 250 دينار
end $$;

-- المحل مفتوح الآن؟ (حسب توقيت بغداد وأوقات العمل وزر الإيقاف المؤقت)
create or replace function merchant_is_open(m merchants)
returns boolean language plpgsql stable as $$
declare
  now_bg timestamp := (now() at time zone 'Asia/Baghdad');
  d jsonb := m.working_hours -> (extract(dow from now_bg)::int)::text;
  t time := now_bg::time;
  o time; c time;
begin
  if m.status <> 'approved' or not m.is_accepting_orders then return false; end if;
  if d is null then return true; end if;                 -- ما محدد = مفتوح دائماً
  if coalesce((d->>'closed')::boolean, false) then return false; end if;
  o := (d->>'open')::time; c := (d->>'close')::time;
  if o is null or c is null then return true; end if;
  if c > o then return t >= o and t < c; end if;
  return t >= o or t < c;                                -- يعبر منتصف الليل
end $$;

-- ---------------------------------------------------------------------
-- إنشاء ملف المستخدم تلقائياً عند التسجيل
-- ---------------------------------------------------------------------
create or replace function handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into users (id, full_name, phone)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name', ''),
          nullif(new.raw_user_meta_data->>'phone', ''))
  on conflict (id) do nothing;
  insert into user_roles (user_id, role) values (new.id, 'customer') on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();

-- ---------------------------------------------------------------------
-- الإشعارات (تُكتب من الخادم فقط)
-- ---------------------------------------------------------------------
create or replace function notify_user(uid uuid, t text, b text, d jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public as $$
  insert into notifications (user_id, title, body, data)
  select uid, t, b, d where uid is not null;
$$;

create or replace function order_status_label(s order_status)
returns text language sql immutable as $$
  select case s
    when 'placed' then 'تم إرسال طلبك'
    when 'accepted' then 'المحل وافق على طلبك'
    when 'preparing' then 'طلبك قيد التحضير'
    when 'ready' then 'طلبك جاهز للاستلام'
    when 'picked_up' then 'المندوب استلم طلبك'
    when 'on_the_way' then 'طلبك في الطريق إليك'
    when 'delivered' then 'تم تسليم طلبك'
    when 'cancelled' then 'انلغى طلبك'
  end;
$$;

-- سجل الحالات + إشعار الزبون عند كل تغيير
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger orders_touch_trg
  before update on orders
  for each row execute function touch_updated_at();

create or replace function on_order_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into order_status_history (order_id, status, actor_id, note)
    values (new.id, new.status, auth.uid(), new.cancel_reason);
    if tg_op = 'UPDATE' then
      perform notify_user(new.customer_id, order_status_label(new.status),
        'طلب ' || new.code, jsonb_build_object('type', 'order', 'id', new.id));
    end if;
  end if;
  return null;
end $$;

create trigger orders_status_trg
  after insert or update of status on orders
  for each row execute function on_order_status_change();

-- ---------------------------------------------------------------------
-- إنشاء طلب من محل (الأسعار تُحسب هنا فقط)
-- p_items: [{"product_id": "...", "qty": 2, "note": ""}]
-- ---------------------------------------------------------------------
create or replace function place_order(
  p_merchant_id uuid, p_address_id uuid, p_items jsonb, p_note text, p_client_ref uuid
) returns orders language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  m merchants; a addresses; u users; o orders;
  item jsonb; p products;
  v_subtotal int := 0; v_qty int; v_fee int;
  allow_out boolean := coalesce((setting('allow_out_of_area')->>'enabled')::boolean, false);
  v_min int;
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

  select * into u from users where id = uid;
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

  update orders set subtotal = v_subtotal, total = v_subtotal + v_fee where id = o.id returning * into o;

  perform notify_user(m.owner_id, 'طلب جديد ' || o.code,
    'المبلغ ' || o.total || ' د.ع', jsonb_build_object('type', 'merchant_order', 'id', o.id));
  return o;
end $$;

-- ---------------------------------------------------------------------
-- الزبون يلغي (فقط قبل موافقة المحل)
-- ---------------------------------------------------------------------
create or replace function customer_cancel_order(p_order_id uuid)
returns orders language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); o orders; it record;
begin
  select * into o from orders where id = p_order_id and customer_id = uid for update;
  if not found then raise exception 'order_not_found'; end if;
  if o.status <> 'placed' then raise exception 'cannot_cancel_now'; end if;
  for it in select product_id, qty from order_items where order_id = o.id loop
    update products set stock = stock + it.qty, is_available = true
     where id = it.product_id and stock is not null;
  end loop;
  update orders set status = 'cancelled', cancel_reason = 'ألغاه الزبون' where id = o.id returning * into o;
  return o;
end $$;

-- ---------------------------------------------------------------------
-- التاجر يغيّر حالة الطلب
-- placed -> accepted | cancelled(رفض مع سبب) ; accepted -> preparing ; preparing -> ready
-- عند "جاهز" تنشأ مهمة توصيل للمندوبين المتاحين
-- ---------------------------------------------------------------------
create or replace function merchant_set_order_status(p_order_id uuid, p_status order_status, p_reason text default null)
returns orders language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); o orders; m merchants; it record;
begin
  select * into o from orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;
  select * into m from merchants where id = o.merchant_id;
  if m.owner_id is distinct from uid and not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;

  if not (
       (o.status = 'placed'    and p_status in ('accepted', 'cancelled'))
    or (o.status = 'accepted'  and p_status in ('preparing', 'cancelled'))
    or (o.status = 'preparing' and p_status = 'ready')
  ) then
    raise exception 'invalid_transition:%->%', o.status, p_status;
  end if;

  if p_status = 'cancelled' then
    if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
    for it in select product_id, qty from order_items where order_id = o.id loop
      update products set stock = stock + it.qty, is_available = true
       where id = it.product_id and stock is not null;
    end loop;
    update orders set status = 'cancelled', cancel_reason = left(p_reason, 300) where id = o.id returning * into o;
    return o;
  end if;

  update orders set status = p_status where id = o.id returning * into o;

  if p_status = 'ready' then
    insert into delivery_tasks (kind, order_id, customer_id, area_id, pickup_text, pickup_lat, pickup_lng,
                                dropoff_text, dropoff_lat, dropoff_lng, item_type, description,
                                customer_name, customer_phone, distance_km, fee)
    values ('order', o.id, o.customer_id, o.area_id, m.name || ' - ' || m.address_text, m.lat, m.lng,
            o.address_text, o.address_lat, o.address_lng, 'طلب ' || o.code,
            (select string_agg(qty || '× ' || name, '، ') from order_items where order_id = o.id),
            o.customer_name, o.customer_phone,
            round(distance_km(m.lat, m.lng, o.address_lat, o.address_lng)::numeric, 2), o.delivery_fee)
    on conflict (order_id) do nothing;
  end if;
  return o;
end $$;

-- التاجر يعدّل معلومات محله المسموح بيها (الإدارة تتحكم بالباقي)
create or replace function merchant_update_profile(
  p_merchant_id uuid, p_description text, p_phone text, p_working_hours jsonb,
  p_is_accepting boolean, p_prep_minutes int, p_logo_url text, p_cover_url text
) returns merchants language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); m merchants;
begin
  if not owns_merchant(p_merchant_id) and not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  update merchants set
    description = coalesce(p_description, description),
    phone = coalesce(p_phone, phone),
    working_hours = coalesce(p_working_hours, working_hours),
    is_accepting_orders = coalesce(p_is_accepting, is_accepting_orders),
    prep_minutes = coalesce(p_prep_minutes, prep_minutes),
    logo_url = coalesce(p_logo_url, logo_url),
    cover_url = coalesce(p_cover_url, cover_url)
  where id = p_merchant_id returning * into m;
  return m;
end $$;

-- إحصائيات التاجر اليومية (توقيت بغداد)
create or replace function merchant_stats(p_merchant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Baghdad') at time zone 'Asia/Baghdad';
begin
  if not owns_merchant(p_merchant_id) and not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return (
    select jsonb_build_object(
      'today_orders', count(*) filter (where created_at >= day_start),
      'today_delivered', count(*) filter (where created_at >= day_start and status = 'delivered'),
      'today_cancelled', count(*) filter (where created_at >= day_start and status = 'cancelled'),
      'today_sales', coalesce(sum(subtotal) filter (where created_at >= day_start and status = 'delivered'), 0),
      'week_sales', coalesce(sum(subtotal) filter (where created_at >= day_start - interval '6 days' and status = 'delivered'), 0),
      'active', count(*) filter (where status in ('placed', 'accepted', 'preparing', 'ready', 'picked_up', 'on_the_way'))
    ) from orders where merchant_id = p_merchant_id
  );
end $$;

-- ---------------------------------------------------------------------
-- السائقون
-- ---------------------------------------------------------------------
create or replace function current_driver()
returns drivers language plpgsql stable security definer set search_path = public as $$
declare d drivers;
begin
  perform require_user();
  if not has_role('driver') then raise exception 'not_a_driver' using errcode = '42501'; end if;
  select * into d from drivers where id = auth.uid();
  if not found or not d.is_active then raise exception 'driver_inactive' using errcode = '42501'; end if;
  return d;
end $$;

create or replace function driver_has_active_job(did uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from delivery_tasks where driver_id = did and status in ('assigned', 'picked_up', 'on_the_way'))
      or exists (select 1 from rides where driver_id = did and status in ('accepted', 'arrived', 'in_progress'));
$$;

create or replace function driver_set_available(p_available boolean, p_lat double precision, p_lng double precision)
returns drivers language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver();
begin
  update drivers set is_available = p_available,
                     last_lat = coalesce(p_lat, last_lat), last_lng = coalesce(p_lng, last_lng),
                     last_seen_at = now()
   where id = d.id returning * into d;
  return d;
end $$;

-- السائق يرسل موقعه، وينعكس على الطلب/الرحلة الشغّالة حتى يشوفه الزبون لحظياً
create or replace function driver_update_location(p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver();
begin
  update drivers set last_lat = p_lat, last_lng = p_lng, last_seen_at = now() where id = d.id;
  update delivery_tasks set driver_lat = p_lat, driver_lng = p_lng
   where driver_id = d.id and status in ('assigned', 'picked_up', 'on_the_way');
  update orders set driver_lat = p_lat, driver_lng = p_lng
   where driver_id = d.id and status in ('ready', 'picked_up', 'on_the_way');
  update rides set driver_lat = p_lat, driver_lng = p_lng
   where driver_id = d.id and status in ('accepted', 'arrived', 'in_progress');
end $$;

create or replace function vehicle_label(did uuid)
returns text language sql stable security definer set search_path = public as $$
  select trim(concat_ws(' · ', nullif(v.model, ''), nullif(v.color, ''), nullif(v.plate, '')))
  from vehicles v where v.driver_id = did;
$$;

-- قبول مهمة توصيل (أول سائق يقبل يأخذها)
create or replace function driver_accept_task(p_task_id uuid)
returns delivery_tasks language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); u users; t delivery_tasks;
begin
  if d.vehicle_type not in ('courier', 'tuktuk') then raise exception 'vehicle_not_allowed'; end if;
  if driver_has_active_job(d.id) then raise exception 'already_on_job'; end if;
  select * into u from users where id = d.id;
  update delivery_tasks set driver_id = d.id, status = 'assigned', driver_name = u.full_name,
                            driver_phone = u.phone, driver_lat = d.last_lat, driver_lng = d.last_lng,
                            updated_at = now()
   where id = p_task_id and status = 'requested' and driver_id is null
     and (kind <> 'order' or d.vehicle_type = 'courier')
  returning * into t;
  if not found then raise exception 'task_taken'; end if;

  if t.kind = 'order' then
    update orders set driver_id = d.id, driver_name = u.full_name, driver_phone = u.phone,
                      driver_vehicle = vehicle_label(d.id), driver_lat = d.last_lat, driver_lng = d.last_lng
     where id = t.order_id;
  end if;
  perform notify_user(t.customer_id, 'تم تعيين مندوب', coalesce(u.full_name, '') || ' بالطريق',
                      jsonb_build_object('type', 'task', 'id', t.id));
  return t;
end $$;

-- تحديث مهمة: assigned -> picked_up -> on_the_way -> delivered (وتنعكس على الطلب)
create or replace function driver_update_task(p_task_id uuid, p_status task_status)
returns delivery_tasks language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); t delivery_tasks;
begin
  select * into t from delivery_tasks where id = p_task_id and driver_id = d.id for update;
  if not found then raise exception 'task_not_found'; end if;
  if not (
       (t.status = 'assigned'   and p_status = 'picked_up')
    or (t.status = 'picked_up'  and p_status = 'on_the_way')
    or (t.status = 'on_the_way' and p_status = 'delivered')
  ) then raise exception 'invalid_transition:%->%', t.status, p_status; end if;

  update delivery_tasks set status = p_status, updated_at = now() where id = t.id returning * into t;

  if t.kind = 'order' then
    update orders set status = p_status::text::order_status where id = t.order_id;
    if p_status = 'delivered' then
      update merchants set order_count = order_count + 1
       where id = (select merchant_id from orders where id = t.order_id);
    end if;
  else
    perform notify_user(t.customer_id,
      case p_status when 'picked_up' then 'المندوب استلم الغرض'
                    when 'on_the_way' then 'الغرض في الطريق'
                    else 'تم التسليم' end,
      t.item_type, jsonb_build_object('type', 'task', 'id', t.id));
  end if;
  return t;
end $$;

-- السائق يتخلى عن مهمة قبل الاستلام (ترجع متاحة لغيره)
create or replace function driver_release_task(p_task_id uuid)
returns delivery_tasks language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); t delivery_tasks;
begin
  update delivery_tasks set driver_id = null, status = 'requested', driver_name = null,
                            driver_phone = null, driver_lat = null, driver_lng = null, updated_at = now()
   where id = p_task_id and driver_id = d.id and status = 'assigned'
  returning * into t;
  if not found then raise exception 'cannot_release'; end if;
  if t.kind = 'order' then
    update orders set driver_id = null, driver_name = null, driver_phone = null, driver_vehicle = null,
                      driver_lat = null, driver_lng = null
     where id = t.order_id;
  end if;
  return t;
end $$;

-- ---------------------------------------------------------------------
-- المندوب / توصيل الأغراض (يطلبه الزبون)
-- ---------------------------------------------------------------------
create or replace function create_errand(
  p_kind task_kind,
  p_pickup_text text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_dropoff_text text, p_dropoff_lat double precision, p_dropoff_lng double precision,
  p_item_type text, p_description text, p_recipient_phone text, p_notes text
) returns delivery_tasks language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); u users; t delivery_tasks; km double precision;
begin
  if p_kind not in ('courier', 'parcel') then raise exception 'invalid_kind'; end if;
  if coalesce(trim(p_description), '') = '' then raise exception 'description_required'; end if;
  km := distance_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng);
  if km > coalesce((setting('errand_pricing')->>'max_km')::numeric, 30) then raise exception 'too_far'; end if;
  select * into u from users where id = uid;
  insert into delivery_tasks (kind, customer_id, pickup_text, pickup_lat, pickup_lng,
                              dropoff_text, dropoff_lat, dropoff_lng, item_type, description,
                              recipient_phone, notes, customer_name, customer_phone, distance_km, fee)
  values (p_kind, uid, coalesce(p_pickup_text, ''), p_pickup_lat, p_pickup_lng,
          coalesce(p_dropoff_text, ''), p_dropoff_lat, p_dropoff_lng,
          coalesce(left(p_item_type, 100), ''), left(p_description, 1000),
          coalesce(left(p_recipient_phone, 20), ''), coalesce(left(p_notes, 500), ''),
          u.full_name, coalesce(u.phone, ''), round(km::numeric, 2),
          compute_fare(setting('errand_pricing'), km))
  returning * into t;
  return t;
end $$;

create or replace function customer_cancel_errand(p_task_id uuid)
returns delivery_tasks language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); t delivery_tasks;
begin
  update delivery_tasks set status = 'cancelled', updated_at = now()
   where id = p_task_id and customer_id = uid and kind <> 'order' and status in ('requested', 'assigned')
  returning * into t;
  if not found then raise exception 'cannot_cancel_now'; end if;
  return t;
end $$;

-- تقدير أجرة قبل الإرسال (للعرض فقط؛ السعر النهائي يُحسب عند الإنشاء)
create or replace function estimate_fare(p_service text, p_from_lat double precision, p_from_lng double precision,
                                         p_to_lat double precision, p_to_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare km double precision := distance_km(p_from_lat, p_from_lng, p_to_lat, p_to_lng); cfg jsonb;
begin
  cfg := case p_service
           when 'taxi' then setting('ride_pricing')->'taxi'
           when 'tuktuk' then setting('ride_pricing')->'tuktuk'
           else setting('errand_pricing') end;
  return jsonb_build_object('distance_km', round(km::numeric, 2), 'fare', compute_fare(cfg, km));
end $$;

-- ---------------------------------------------------------------------
-- الرحلات: تكسي / تكتك
-- ---------------------------------------------------------------------
create or replace function request_ride(
  p_vehicle vehicle_type,
  p_pickup_text text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_dropoff_text text, p_dropoff_lat double precision, p_dropoff_lng double precision
) returns rides language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); u users; r rides; km double precision;
begin
  if p_vehicle not in ('taxi', 'tuktuk') then raise exception 'invalid_vehicle'; end if;
  if exists (select 1 from rides where customer_id = uid and status in ('requested', 'accepted', 'arrived', 'in_progress')) then
    raise exception 'ride_already_active';
  end if;
  km := distance_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng);
  if km < 0.1 then raise exception 'same_location'; end if;
  select * into u from users where id = uid;
  insert into rides (customer_id, vehicle, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng,
                     distance_km, fare, customer_name, customer_phone)
  values (uid, p_vehicle, coalesce(p_pickup_text, ''), p_pickup_lat, p_pickup_lng,
          coalesce(p_dropoff_text, ''), p_dropoff_lat, p_dropoff_lng, round(km::numeric, 2),
          compute_fare(setting('ride_pricing') -> p_vehicle::text, km), u.full_name, coalesce(u.phone, ''))
  returning * into r;
  return r;
end $$;

create or replace function customer_cancel_ride(p_ride_id uuid)
returns rides language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r rides;
begin
  update rides set status = 'cancelled', updated_at = now()
   where id = p_ride_id and customer_id = uid and status in ('requested', 'accepted', 'arrived')
  returning * into r;
  if not found then raise exception 'cannot_cancel_now'; end if;
  if r.driver_id is not null then
    perform notify_user(r.driver_id, 'الزبون ألغى الرحلة', r.pickup_text, jsonb_build_object('type', 'ride', 'id', r.id));
  end if;
  return r;
end $$;

create or replace function driver_accept_ride(p_ride_id uuid)
returns rides language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); u users; r rides;
begin
  if driver_has_active_job(d.id) then raise exception 'already_on_job'; end if;
  select * into u from users where id = d.id;
  update rides set driver_id = d.id, status = 'accepted', accepted_at = now(), updated_at = now(),
                   driver_name = u.full_name, driver_phone = u.phone, driver_vehicle = vehicle_label(d.id),
                   driver_lat = d.last_lat, driver_lng = d.last_lng
   where id = p_ride_id and status = 'requested' and driver_id is null and vehicle = d.vehicle_type
  returning * into r;
  if not found then raise exception 'ride_taken'; end if;
  perform notify_user(r.customer_id, 'السائق قبل رحلتك', coalesce(u.full_name, '') || ' جاي إليك',
                      jsonb_build_object('type', 'ride', 'id', r.id));
  return r;
end $$;

create or replace function driver_update_ride(p_ride_id uuid, p_status ride_status)
returns rides language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); r rides;
begin
  select * into r from rides where id = p_ride_id and driver_id = d.id for update;
  if not found then raise exception 'ride_not_found'; end if;
  if not (
       (r.status = 'accepted'    and p_status = 'arrived')
    or (r.status = 'arrived'     and p_status = 'in_progress')
    or (r.status = 'in_progress' and p_status = 'completed')
    or (r.status in ('accepted', 'arrived') and p_status = 'cancelled')
  ) then raise exception 'invalid_transition:%->%', r.status, p_status; end if;
  update rides set status = p_status, updated_at = now(),
                   completed_at = case when p_status = 'completed' then now() else completed_at end
   where id = r.id returning * into r;
  perform notify_user(r.customer_id,
    case p_status when 'arrived' then 'السائق وصل لمكانك'
                  when 'in_progress' then 'بدأت الرحلة'
                  when 'completed' then 'وصلت بالسلامة · الأجرة ' || r.fare || ' د.ع'
                  else 'السائق ألغى الرحلة' end,
    '', jsonb_build_object('type', 'ride', 'id', r.id));
  return r;
end $$;

-- ---------------------------------------------------------------------
-- الخدمات المنزلية
-- ---------------------------------------------------------------------
create or replace function book_service(
  p_service_id uuid, p_provider_id uuid, p_address_text text, p_lat double precision, p_lng double precision,
  p_description text, p_photo_urls text[], p_preferred_time timestamptz
) returns service_bookings language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); u users; b service_bookings; m merchants;
begin
  select * into m from merchants where id = p_provider_id and status = 'approved';
  if not found then raise exception 'provider_unavailable'; end if;
  if not exists (select 1 from merchant_services where merchant_id = m.id and service_id = p_service_id) then
    raise exception 'provider_does_not_offer_service';
  end if;
  if p_preferred_time < now() - interval '10 minutes' then raise exception 'time_in_past'; end if;
  if coalesce(array_length(p_photo_urls, 1), 0) > 5 then raise exception 'too_many_photos'; end if;
  select * into u from users where id = uid;
  insert into service_bookings (customer_id, service_id, provider_id, address_text, lat, lng, description,
                                photo_urls, preferred_time, customer_name, customer_phone)
  values (uid, p_service_id, m.id, coalesce(p_address_text, ''), p_lat, p_lng, left(p_description, 1000),
          coalesce(p_photo_urls, '{}'), p_preferred_time, u.full_name, coalesce(u.phone, ''))
  returning * into b;
  perform notify_user(m.owner_id, 'طلب خدمة جديد', left(p_description, 80),
                      jsonb_build_object('type', 'booking', 'id', b.id));
  return b;
end $$;

create or replace function provider_update_booking(p_booking_id uuid, p_status booking_status, p_note text default null)
returns service_bookings language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); b service_bookings;
begin
  select * into b from service_bookings where id = p_booking_id for update;
  if not found then raise exception 'booking_not_found'; end if;
  if not owns_merchant(b.provider_id) and not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if not (
       (b.status = 'requested'   and p_status in ('accepted', 'rejected'))
    or (b.status = 'accepted'    and p_status in ('in_progress', 'cancelled'))
    or (b.status = 'in_progress' and p_status = 'completed')
  ) then raise exception 'invalid_transition:%->%', b.status, p_status; end if;
  update service_bookings set status = p_status, provider_note = coalesce(left(p_note, 300), provider_note), updated_at = now()
   where id = b.id returning * into b;
  perform notify_user(b.customer_id,
    case p_status when 'accepted' then 'تم قبول طلب الخدمة'
                  when 'rejected' then 'تعذّر قبول طلب الخدمة'
                  when 'in_progress' then 'بدأ العمل على طلبك'
                  when 'completed' then 'اكتملت الخدمة'
                  else 'انلغى موعد الخدمة' end,
    coalesce(p_note, ''), jsonb_build_object('type', 'booking', 'id', b.id));
  return b;
end $$;

create or replace function customer_cancel_booking(p_booking_id uuid)
returns service_bookings language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); b service_bookings;
begin
  update service_bookings set status = 'cancelled', updated_at = now()
   where id = p_booking_id and customer_id = uid and status in ('requested', 'accepted')
  returning * into b;
  if not found then raise exception 'cannot_cancel_now'; end if;
  return b;
end $$;

-- ---------------------------------------------------------------------
-- التقييم بعد التسليم
-- ---------------------------------------------------------------------
create or replace function rate_order(p_order_id uuid, p_rating int, p_comment text)
returns reviews language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); o orders; r reviews;
begin
  select * into o from orders where id = p_order_id and customer_id = uid;
  if not found or o.status <> 'delivered' then raise exception 'cannot_rate'; end if;
  insert into reviews (order_id, customer_id, merchant_id, rating, comment)
  values (o.id, uid, o.merchant_id, p_rating, coalesce(left(p_comment, 500), ''))
  on conflict (order_id) do update set rating = excluded.rating, comment = excluded.comment
  returning * into r;
  update merchants set
    rating_avg = (select round(avg(rating)::numeric, 2) from reviews where merchant_id = o.merchant_id),
    rating_count = (select count(*) from reviews where merchant_id = o.merchant_id)
   where id = o.merchant_id;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- الإدارة
-- ---------------------------------------------------------------------
create or replace function admin_set_role(p_user_id uuid, p_role app_role, p_grant boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_grant then
    insert into user_roles (user_id, role) values (p_user_id, p_role) on conflict do nothing;
  else
    if p_user_id = auth.uid() and p_role = 'admin' then raise exception 'cannot_remove_own_admin'; end if;
    delete from user_roles where user_id = p_user_id and role = p_role;
  end if;
end $$;

-- تحويل حساب موجود إلى سائق مع مركبته
create or replace function admin_upsert_driver(
  p_user_id uuid, p_vehicle vehicle_type, p_area_id uuid, p_plate text, p_model text, p_color text, p_active boolean
) returns drivers language plpgsql security definer set search_path = public as $$
declare d drivers;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  insert into user_roles (user_id, role) values (p_user_id, 'driver') on conflict do nothing;
  insert into drivers (id, vehicle_type, area_id, is_active)
  values (p_user_id, p_vehicle, p_area_id, coalesce(p_active, true))
  on conflict (id) do update set vehicle_type = excluded.vehicle_type, area_id = excluded.area_id,
                                 is_active = excluded.is_active,
                                 is_available = drivers.is_available and excluded.is_active
  returning * into d;
  insert into vehicles (driver_id, type, plate, model, color)
  values (p_user_id, p_vehicle, coalesce(p_plate, ''), coalesce(p_model, ''), coalesce(p_color, ''))
  on conflict (driver_id) do update set type = excluded.type, plate = excluded.plate,
                                        model = excluded.model, color = excluded.color;
  return d;
end $$;

-- ربط حساب تاجر بمحل (ويمنحه دور التاجر)
create or replace function admin_link_merchant_owner(p_merchant_id uuid, p_user_id uuid)
returns merchants language plpgsql security definer set search_path = public as $$
declare m merchants;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_user_id is not null then
    insert into user_roles (user_id, role) values (p_user_id, 'merchant') on conflict do nothing;
  end if;
  update merchants set owner_id = p_user_id where id = p_merchant_id returning * into m;
  return m;
end $$;

create or replace function admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'users', (select count(*) from users),
    'merchants', (select count(*) from merchants),
    'merchants_pending', (select count(*) from merchants where status = 'pending'),
    'orders', (select count(*) from orders),
    'orders_active', (select count(*) from orders where status not in ('delivered', 'cancelled')),
    'orders_delivered', (select count(*) from orders where status = 'delivered'),
    'orders_cancelled', (select count(*) from orders where status = 'cancelled'),
    'drivers', (select count(*) from drivers),
    'drivers_available', (select count(*) from drivers where is_available and is_active),
    'rides_active', (select count(*) from rides where status not in ('completed', 'cancelled')),
    'tasks_active', (select count(*) from delivery_tasks where kind <> 'order' and status not in ('delivered', 'cancelled')),
    'bookings', (select count(*) from service_bookings),
    'bookings_open', (select count(*) from service_bookings where status in ('requested', 'accepted', 'in_progress')),
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object('name', a.name,
               'merchants', (select count(*) from merchants m where m.area_id = a.id),
               'orders', (select count(*) from orders o where o.area_id = a.id)) order by a.name)
      from service_areas a), '[]'::jsonb)
  );
end $$;

-- الإدارة تلغي أي طلب عالق
create or replace function admin_cancel_order(p_order_id uuid, p_reason text)
returns orders language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  update orders set status = 'cancelled', cancel_reason = coalesce(p_reason, 'ألغته الإدارة')
   where id = p_order_id and status not in ('delivered', 'cancelled') returning * into o;
  if not found then raise exception 'cannot_cancel_now'; end if;
  update delivery_tasks set status = 'cancelled', updated_at = now() where order_id = o.id and status <> 'delivered';
  return o;
end $$;

-- ===== supabase/migrations/0003_security.sql =====
-- =====================================================================
-- WASEL | الحماية: Row Level Security + الصلاحيات + Realtime
-- =====================================================================
-- القاعدة: كل مستخدم يشوف بياناته فقط. التاجر يشوف محله وطلباته.
-- السائق يشوف المهام المتاحة لنوع مركبته ومهامه هو. الإدارة تشوف كلشي.
-- الكتابة على الطلبات والرحلات والمهام تتم فقط عبر دوال 0002.

create or replace function my_driver_vehicle()
returns vehicle_type language sql stable security definer set search_path = public as $$
  select d.vehicle_type from drivers d join users u on u.id = d.id
  where d.id = auth.uid() and d.is_active and u.is_active and has_role('driver');
$$;

create or replace function can_see_order(oid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from orders o
    where o.id = oid and (o.customer_id = auth.uid() or o.driver_id = auth.uid()
                          or owns_merchant(o.merchant_id) or is_admin())
  );
$$;

-- تفعيل RLS على كل الجداول
alter table users                enable row level security;
alter table user_roles           enable row level security;
alter table service_areas        enable row level security;
alter table app_settings         enable row level security;
alter table merchant_categories  enable row level security;
alter table merchants            enable row level security;
alter table product_categories   enable row level security;
alter table products             enable row level security;
alter table product_images       enable row level security;
alter table addresses            enable row level security;
alter table drivers              enable row level security;
alter table vehicles             enable row level security;
alter table orders               enable row level security;
alter table order_items          enable row level security;
alter table order_status_history enable row level security;
alter table delivery_tasks       enable row level security;
alter table rides                enable row level security;
alter table home_services        enable row level security;
alter table merchant_services    enable row level security;
alter table service_bookings     enable row level security;
alter table reviews              enable row level security;
alter table favorites            enable row level security;
alter table promotions           enable row level security;
alter table notifications        enable row level security;

-- ---------------- المستخدمون ----------------
create policy users_select on users for select to authenticated
  using (id = auth.uid() or is_admin());
create policy users_update_self on users for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid() and is_active);
create policy users_admin_update on users for update to authenticated
  using (is_admin()) with check (is_admin());

-- المستخدم ما يگدر يغيّر is_active لنفسه: نمنعه بتريگر
create or replace function guard_user_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() and (new.is_active is distinct from old.is_active or new.id <> old.id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger users_guard_trg before update on users for each row execute function guard_user_update();

create policy roles_select on user_roles for select to authenticated
  using (user_id = auth.uid() or is_admin());
-- تعديل الأدوار فقط عبر admin_set_role

-- ---------------- بيانات عامة للقراءة ----------------
create policy areas_read on service_areas for select to authenticated using (is_active or is_admin());
create policy areas_admin on service_areas for all to authenticated using (is_admin()) with check (is_admin());

create policy settings_read on app_settings for select to authenticated using (true);
create policy settings_admin on app_settings for all to authenticated using (is_admin()) with check (is_admin());

create policy categories_read on merchant_categories for select to authenticated using (is_active or is_admin());
create policy categories_admin on merchant_categories for all to authenticated using (is_admin()) with check (is_admin());

create policy home_services_read on home_services for select to authenticated using (is_active or is_admin());
create policy home_services_admin on home_services for all to authenticated using (is_admin()) with check (is_admin());

create policy promotions_read on promotions for select to authenticated
  using ((is_active and now() between starts_at and ends_at) or is_admin());
create policy promotions_admin on promotions for all to authenticated using (is_admin()) with check (is_admin());

-- ---------------- المحلات ----------------
-- المستهلك يشوف المعتمد فقط. التاجر يشوف محله. الإدارة كلشي.
create policy merchants_read on merchants for select to authenticated
  using (status = 'approved' or owner_id = auth.uid() or is_admin());
create policy merchants_admin on merchants for all to authenticated using (is_admin()) with check (is_admin());
-- التاجر يعدّل عبر merchant_update_profile فقط

create policy merchant_services_read on merchant_services for select to authenticated using (true);
create policy merchant_services_admin on merchant_services for all to authenticated using (is_admin()) with check (is_admin());

-- ---------------- المنتجات ----------------
create policy product_categories_read on product_categories for select to authenticated
  using (exists (select 1 from merchants m where m.id = merchant_id and m.status = 'approved')
         or owns_merchant(merchant_id) or is_admin());
create policy product_categories_write on product_categories for all to authenticated
  using (owns_merchant(merchant_id) or is_admin()) with check (owns_merchant(merchant_id) or is_admin());

create policy products_read on products for select to authenticated
  using (exists (select 1 from merchants m where m.id = merchant_id and m.status = 'approved')
         or owns_merchant(merchant_id) or is_admin());
create policy products_write on products for all to authenticated
  using (owns_merchant(merchant_id) or is_admin()) with check (owns_merchant(merchant_id) or is_admin());

create policy product_images_read on product_images for select to authenticated using (true);
create policy product_images_write on product_images for all to authenticated
  using (exists (select 1 from products p where p.id = product_id and (owns_merchant(p.merchant_id) or is_admin())))
  with check (exists (select 1 from products p where p.id = product_id and (owns_merchant(p.merchant_id) or is_admin())));

-- ---------------- العناوين والمفضلة والإشعارات ----------------
create policy addresses_own on addresses for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy favorites_own on favorites for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy notifications_own_read on notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_own_update on notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------- السائقون ----------------
create policy drivers_read on drivers for select to authenticated using (id = auth.uid() or is_admin());
create policy drivers_admin on drivers for all to authenticated using (is_admin()) with check (is_admin());
create policy vehicles_read on vehicles for select to authenticated using (driver_id = auth.uid() or is_admin());
create policy vehicles_admin on vehicles for all to authenticated using (is_admin()) with check (is_admin());

-- ---------------- الطلبات ----------------
create policy orders_read on orders for select to authenticated
  using (customer_id = auth.uid() or driver_id = auth.uid() or owns_merchant(merchant_id) or is_admin());
create policy order_items_read on order_items for select to authenticated using (can_see_order(order_id));
create policy order_history_read on order_status_history for select to authenticated using (can_see_order(order_id));

-- ---------------- مهام التوصيل ----------------
create policy tasks_read on delivery_tasks for select to authenticated
  using (
    customer_id = auth.uid()
    or driver_id = auth.uid()
    or is_admin()
    or (order_id is not null and can_see_order(order_id))
    -- المهام المتاحة: المندوب يشوف الكل، التكتك يشوف توصيل الأغراض فقط
    or (status = 'requested' and (my_driver_vehicle() = 'courier'
                                  or (my_driver_vehicle() = 'tuktuk' and kind = 'parcel')))
  );

-- ---------------- الرحلات ----------------
create policy rides_read on rides for select to authenticated
  using (customer_id = auth.uid() or driver_id = auth.uid() or is_admin()
         or (status = 'requested' and my_driver_vehicle() = vehicle));

-- ---------------- الخدمات المنزلية ----------------
create policy bookings_read on service_bookings for select to authenticated
  using (customer_id = auth.uid() or owns_merchant(provider_id) or is_admin());

-- ---------------- التقييمات ----------------
create policy reviews_read on reviews for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- الصلاحيات على مستوى الجداول (RLS تحدد الصفوف)
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon, public;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
-- مفتاح الخدمة (للسكربتات الإدارية فقط، لا يوضع بالتطبيقات)
grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- دوال داخلية ما تنستدعى مباشرة من التطبيق
revoke execute on function notify_user(uuid, text, text, jsonb) from authenticated;
revoke execute on function handle_new_auth_user() from authenticated;

-- ---------------------------------------------------------------------
-- Realtime: التحديثات اللحظية (تحترم RLS)
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
alter publication supabase_realtime add table
  orders, delivery_tasks, rides, service_bookings, notifications, merchants, products;

-- ===== supabase/migrations/0004_storage.sql =====
-- =====================================================================
-- WASEL | تخزين الصور (Supabase Storage)
-- =====================================================================
-- حاوية عامة للقراءة "media". الرفع مقيّد بالمسار:
--   merchants/<merchant_id>/...  ← صاحب المحل أو الإدارة
--   promotions/...               ← الإدارة
--   bookings/<user_id>/...       ← المستخدم نفسه (صور طلب الخدمة)

insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

create or replace function public.can_upload_media(object_name text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare parts text[] := string_to_array(object_name, '/');
begin
  if auth.uid() is null then return false; end if;
  if is_admin() then return true; end if;
  if parts[1] = 'merchants' and array_length(parts, 1) >= 3 then
    begin
      return owns_merchant(parts[2]::uuid);
    exception when invalid_text_representation then
      return false;
    end;
  end if;
  if parts[1] = 'bookings' and array_length(parts, 1) >= 3 then
    return parts[2] = auth.uid()::text;
  end if;
  return false;
end $$;

create policy media_read on storage.objects for select
  using (bucket_id = 'media');
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.can_upload_media(name));
create policy media_update on storage.objects for update to authenticated
  using (bucket_id = 'media' and public.can_upload_media(name))
  with check (bucket_id = 'media' and public.can_upload_media(name));
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.can_upload_media(name));

-- ===== supabase/migrations/0005_seed.sql =====
-- =====================================================================
-- WASEL | بيانات الإعداد الأساسية (ليست بيانات وهمية)
-- =====================================================================
-- الأقسام، أنواع الخدمات المنزلية، والإعدادات الافتراضية.
-- المحلات والمناطق والسائقون تضيفهم الإدارة من تطبيق WASEL ADMIN.

insert into merchant_categories (id, name, kind, icon, sort) values
  ('restaurants',  'المطاعم',           'store',        'restaurant', 1),
  ('supermarket',  'السوبر ماركت',      'store',        'supermarket', 2),
  ('home_services','الأعمال المنزلية',   'home_service', 'home_repair', 3),
  ('sweets',       'الحلويات',          'store',        'sweets', 4),
  ('mobiles',      'الموبايلات',        'store',        'mobile', 5),
  ('bakery',       'المخابز والأفران',   'store',        'bakery', 6),
  ('produce',      'الخضار والفواكه',    'store',        'produce', 7),
  ('taxi',         'التكسي',            'ride',         'taxi', 8),
  ('tuktuk',       'التكتك',            'ride',         'tuktuk', 9),
  ('courier',      'الدلفري والمندوب',   'courier',      'courier', 10),
  ('parcel',       'توصيل الأغراض',      'parcel',       'parcel', 11)
on conflict (id) do nothing;

insert into home_services (name, icon, sort) values
  ('سباكة', 'plumbing', 1),
  ('كهرباء', 'electric', 2),
  ('صيانة منزلية', 'handyman', 3),
  ('تنظيف', 'cleaning', 4)
on conflict (name) do nothing;

insert into app_settings (key, value) values
  -- أجور الرحلات: mode = distance (حسب المسافة) أو fixed (ثابتة)
  ('ride_pricing', '{
     "taxi":   {"mode": "distance", "base": 2000, "per_km": 750, "fixed": 5000, "min": 3000},
     "tuktuk": {"mode": "distance", "base": 1000, "per_km": 500, "fixed": 3000, "min": 1500}
   }'),
  -- المندوب وتوصيل الأغراض
  ('errand_pricing', '{"mode": "distance", "base": 2000, "per_km": 500, "fixed": 3000, "min": 2000, "max_km": 30}'),
  -- الحد الأدنى العام للطلب (يُضاف لحد المحل إن كان أكبر)
  ('min_order', '{"amount": 0}'),
  -- السماح بالطلب خارج نطاق توصيل المحل
  ('allow_out_of_area', '{"enabled": false}'),
  -- العمولات: معطلة افتراضياً ولا تُحتسب حالياً
  ('commission', '{"enabled": false, "percent": 0}'),
  -- أوقات تشغيل المنصة (للعرض والتنبيه)
  ('operating_hours', '{"open": "08:00", "close": "02:00"}'),
  ('support', '{"phone": ""}')
on conflict (key) do nothing;
