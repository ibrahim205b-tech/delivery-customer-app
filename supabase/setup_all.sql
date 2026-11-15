-- ملف واحد يجمع كل ملفات supabase/migrations بالترتيب. الصقه كاملاً في SQL Editor واضغط Run (مرة وحدة فقط على قاعدة جديدة).

-- ===== migrations/0001_schema.sql =====
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

-- ===== migrations/0002_functions.sql =====
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

-- ===== migrations/0003_security.sql =====
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

-- ===== migrations/0004_storage.sql =====
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

-- ===== migrations/0005_seed.sql =====
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

-- ===== migrations/0006_admin_reports.sql =====
-- =====================================================================
-- WASEL | تقارير الإدارة (بيانات حقيقية للرسوم البيانية)
-- =====================================================================
-- يشغَّل بعد 0001..0005. آمن للتشغيل أكثر من مرة (create or replace).

create or replace function admin_reports(p_days int default 14)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  days int := least(greatest(coalesce(p_days, 14), 1), 90);
  start_day date := ((now() at time zone 'Asia/Baghdad')::date - (days - 1));
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'days', days,
    -- لكل يوم: كل الطلبات، المسلّمة، الملغاة، ومبيعات المسلّمة (بدون التوصيل)
    'daily', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'day', d::date,
               'orders', coalesce(x.orders, 0),
               'delivered', coalesce(x.delivered, 0),
               'cancelled', coalesce(x.cancelled, 0),
               'sales', coalesce(x.sales, 0),
               'rides', coalesce(r.rides, 0)) order by d), '[]'::jsonb)
      from generate_series(start_day, start_day + (days - 1), interval '1 day') d
      left join (
        select (created_at at time zone 'Asia/Baghdad')::date as day,
               count(*) as orders,
               count(*) filter (where status = 'delivered') as delivered,
               count(*) filter (where status = 'cancelled') as cancelled,
               sum(subtotal) filter (where status = 'delivered') as sales
        from orders
        where created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by 1
      ) x on x.day = d::date
      left join (
        select (created_at at time zone 'Asia/Baghdad')::date as day, count(*) as rides
        from rides
        where created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by 1
      ) r on r.day = d::date
    ),
    -- توزيع حالات الطلبات بالفترة
    'by_status', (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (
        select status::text, count(*) n from orders
        where created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by status
      ) s
    ),
    -- الطلبات حسب القسم
    'by_category', (
      select coalesce(jsonb_agg(jsonb_build_object('category', c.name, 'orders', t.n) order by t.n desc), '[]'::jsonb) from (
        select m.category_id, count(*) n from orders o join merchants m on m.id = o.merchant_id
        where o.created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by m.category_id
      ) t join merchant_categories c on c.id = t.category_id
    ),
    -- أفضل المحلات بالطلبات المسلّمة
    'top_merchants', (
      select coalesce(jsonb_agg(jsonb_build_object('name', name, 'delivered', n, 'sales', sales) order by n desc), '[]'::jsonb) from (
        select m.name, count(*) n, sum(o.subtotal) sales from orders o join merchants m on m.id = o.merchant_id
        where o.status = 'delivered' and o.created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by m.name order by n desc limit 5
      ) t
    )
  );
end $$;

revoke execute on function admin_reports(int) from public, anon;
grant execute on function admin_reports(int) to authenticated, service_role;

-- خريطة العمليات: مواقع السائقين المتاحين وآخر ظهور (للإدارة فقط عبر RLS على drivers)
-- لا تحتاج دالة: الإدارة تقرأ drivers + users مباشرة.

-- تحديث ذاكرة PostgREST حتى تظهر الدالة فوراً للتطبيقات
notify pgrst, 'reload schema';

-- ===== migrations/0007_support.sql =====
-- =====================================================================
-- WASEL | واصل — مراسلة الدعم داخل التطبيق
-- محادثة وحدة لكل مستخدم بكل تطبيق (مستهلك / تاجر / سائق) مع إدارة واصل.
-- الكتابة عبر دوال بالخادم فقط؛ القراءة بـ RLS (صاحب المحادثة أو الإدارة).
-- =====================================================================

create table if not exists support_threads (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references users (id) on delete cascade,
  app              text not null check (app in ('customer', 'merchant', 'driver')),
  status           text not null default 'open' check (status in ('open', 'closed')),
  last_message     text not null default '',
  last_message_at  timestamptz not null default now(),
  unread_for_admin int not null default 0,
  unread_for_user  int not null default 0,
  created_at       timestamptz not null default now(),
  unique (user_id, app)
);
create index if not exists support_threads_recent_idx on support_threads (last_message_at desc);

create table if not exists support_messages (
  id          bigint generated always as identity primary key,
  thread_id   uuid not null references support_threads (id) on delete cascade,
  sender_id   uuid references users (id) on delete set null,
  from_admin  boolean not null default false,
  body        text not null check (char_length(btrim(body)) between 1 and 2000),
  order_code  text,
  created_at  timestamptz not null default now()
);
create index if not exists support_messages_thread_idx on support_messages (thread_id, id);

alter table support_threads  enable row level security;
alter table support_messages enable row level security;

drop policy if exists support_threads_read on support_threads;
create policy support_threads_read on support_threads for select to authenticated
  using (user_id = auth.uid() or is_admin());

drop policy if exists support_messages_read on support_messages;
create policy support_messages_read on support_messages for select to authenticated
  using (exists (select 1 from support_threads t where t.id = thread_id and (t.user_id = auth.uid() or is_admin())));

grant select on support_threads, support_messages to authenticated;
grant all on support_threads, support_messages to service_role;

-- إرسال رسالة من المستخدم (ينشئ المحادثة إذا ما موجودة، ويعيد فتحها إذا مسكّرة)
create or replace function support_send(p_app text, p_body text, p_order_code text default null)
returns support_messages language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  th support_threads;
  msg support_messages;
  b text := btrim(coalesce(p_body, ''));
begin
  if p_app not in ('customer', 'merchant', 'driver') then raise exception 'invalid_app'; end if;
  if char_length(b) = 0 then raise exception 'empty_message'; end if;
  if char_length(b) > 2000 then raise exception 'message_too_long'; end if;
  insert into support_threads (user_id, app) values (uid, p_app)
    on conflict (user_id, app) do nothing;
  select * into th from support_threads where user_id = uid and app = p_app;
  insert into support_messages (thread_id, sender_id, from_admin, body, order_code)
    values (th.id, uid, false, b, nullif(btrim(coalesce(p_order_code, '')), ''))
    returning * into msg;
  update support_threads set status = 'open', last_message = left(b, 140), last_message_at = msg.created_at,
         unread_for_admin = unread_for_admin + 1
   where id = th.id;
  return msg;
end $$;

-- رد الإدارة (يوصل للمستخدم كإشعار أيضاً)
create or replace function support_reply(p_thread uuid, p_body text)
returns support_messages language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  th support_threads;
  msg support_messages;
  b text := btrim(coalesce(p_body, ''));
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if char_length(b) = 0 then raise exception 'empty_message'; end if;
  if char_length(b) > 2000 then raise exception 'message_too_long'; end if;
  select * into th from support_threads where id = p_thread;
  if not found then raise exception 'not_found'; end if;
  insert into support_messages (thread_id, sender_id, from_admin, body)
    values (th.id, uid, true, b) returning * into msg;
  update support_threads set last_message = left(b, 140), last_message_at = msg.created_at,
         unread_for_user = unread_for_user + 1
   where id = th.id;
  perform notify_user(th.user_id, 'رد من دعم واصل', left(b, 140), jsonb_build_object('type', 'support', 'app', th.app));
  return msg;
end $$;

-- تعليم المحادثة كمقروءة (المستخدم لمحادثته، والإدارة لأي محادثة)
create or replace function support_mark_read(p_thread uuid)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user();
begin
  if is_admin() then
    update support_threads set unread_for_admin = 0 where id = p_thread;
  end if;
  update support_threads set unread_for_user = 0 where id = p_thread and user_id = uid;
end $$;

-- الإدارة تسكّر أو تفتح محادثة
create or replace function support_set_status(p_thread uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform require_user();
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_status not in ('open', 'closed') then raise exception 'invalid_status'; end if;
  update support_threads set status = p_status where id = p_thread;
end $$;

revoke execute on function support_send(text, text, text), support_reply(uuid, text), support_mark_read(uuid), support_set_status(uuid, text) from public, anon;
grant execute on function support_send(text, text, text), support_reply(uuid, text), support_mark_read(uuid), support_set_status(uuid, text) to authenticated, service_role;

-- رقم واتساب الدعم (إعداد قابل للتعديل من تطبيق الإدارة)
insert into app_settings (key, value) values ('support', '{"phone": "", "whatsapp": ""}')
on conflict (key) do update set value = app_settings.value || jsonb_build_object('whatsapp', coalesce(app_settings.value->>'whatsapp', ''));

-- التحديثات اللحظية
do $$ begin
  alter publication supabase_realtime add table support_threads, support_messages;
exception when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';

-- ===== migrations/0008_commission.sql =====
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


-- ===== migrations/0009_captain_ledger.sql =====
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

-- ===== migrations/0010_driver_realtime.sql =====
-- =====================================================================
-- WASEL MAPS | المرحلة 1: تحديث مواقع السائقين لحظياً + وقت آخر موقع معروف
--
-- 1) جدول drivers يُنشر على Realtime. سياسة drivers_read تسمح للسائق بقراءة صفه
--    والإدارة بقراءة الكل فقط، فالزبون ما يستقبل أي موقع سائق مباشرة.
-- 2) كل طلب/رحلة/مهمة يحمل driver_located_at = وقت آخر موقع أرسله السائق.
--    الزبون يحتاجه لعرض "آخر تحديث" وتمييز الموقع القديم بوضوح.
-- التأثير: إضافة أعمدة nullable وتعديل دالة واحدة فقط (driver_update_location)، بدون حذف أو تغيير بيانات.
-- =====================================================================

alter table orders          add column if not exists driver_located_at timestamptz;
alter table delivery_tasks  add column if not exists driver_located_at timestamptz;
alter table rides           add column if not exists driver_located_at timestamptz;

-- نشر جدول السائقين على Realtime (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'drivers'
  ) then
    alter publication supabase_realtime add table drivers;
  end if;
end $$;

-- نفس منطق 0002 + تسجيل وقت الموقع على الطلب/الرحلة/المهمة الجارية
create or replace function driver_update_location(p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); now_ts timestamptz := now();
begin
  update drivers set last_lat = p_lat, last_lng = p_lng, last_seen_at = now_ts where id = d.id;
  update delivery_tasks set driver_lat = p_lat, driver_lng = p_lng, driver_located_at = now_ts
   where driver_id = d.id and status in ('assigned', 'picked_up', 'on_the_way');
  update orders set driver_lat = p_lat, driver_lng = p_lng, driver_located_at = now_ts
   where driver_id = d.id and status in ('ready', 'picked_up', 'on_the_way');
  update rides set driver_lat = p_lat, driver_lng = p_lng, driver_located_at = now_ts
   where driver_id = d.id and status in ('accepted', 'arrived', 'in_progress');
end $$;

notify pgrst, 'reload schema';

-- ===== migrations/0011_service_area_dispatch.sql =====
-- =====================================================================
-- WASEL MAPS | المرحلة 3: التوزيع الجغرافي حسب مناطق الخدمة المعتمدة
--
-- القواعد:
-- 1) كل طلب (رحلة/توصيل/طلب محل) يأخذ منطقته من نقطة الاستلام: أقرب منطقة مفعّلة
--    يقع ضمن نصف قطرها. إذا ما في منطقة مفعّلة = الطلب مرفوض برسالة outside_service_area.
-- 2) السائق يرى الطلبات المعلّقة لمنطقته فقط (drivers.area_id) وهي مفعّلة، ومن نوع مركبته.
-- 3) قبول الطلب يتحقق من المنطقة على الخادم (ما يكفي إخفاؤه من الواجهة).
-- 4) الإدارة تضبط نصف القطر والتفعيل من شاشة المناطق الموجودة (لا قيمة ثابتة 5 كم في الكود).
-- 5) الطلبات المعلّقة القديمة تأخذ منطقتها بالحساب نفسه؛ ما يُحذف شي.
-- ملاحظة: لا تُضاف منطقة المعامل هنا لأن إحداثياتها غير مؤكدة. تُنشأ من لوحة الإدارة بالإحداثيات التي تتحقق منها.
-- =====================================================================

-- ---------------------------------------------------------------------
-- الدوال المساعدة
-- ---------------------------------------------------------------------
create or replace function area_for_point(p_lat double precision, p_lng double precision)
returns uuid language sql stable security definer set search_path = public as $$
  select a.id from service_areas a
   where a.is_active and distance_km(a.center_lat, a.center_lng, p_lat, p_lng) <= a.radius_km
   order by distance_km(a.center_lat, a.center_lng, p_lat, p_lng) asc
   limit 1;
$$;

-- منطقة السائق الحالي، فقط إذا كان فعّالاً والمنطقة مفعّلة
create or replace function my_driver_area()
returns uuid language sql stable security definer set search_path = public as $$
  select d.area_id from drivers d
    join service_areas a on a.id = d.area_id
   where d.id = auth.uid() and d.is_active and a.is_active and has_role('driver');
$$;

-- ---------------------------------------------------------------------
-- الطلبات الجديدة: تأخذ المنطقة، ومرفوضة خارج المناطق
-- ---------------------------------------------------------------------
create or replace function request_ride(
  p_vehicle vehicle_type,
  p_pickup_text text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_dropoff_text text, p_dropoff_lat double precision, p_dropoff_lng double precision
) returns rides language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); u users; r rides; km double precision; aid uuid;
begin
  if p_vehicle not in ('taxi', 'tuktuk') then raise exception 'invalid_vehicle'; end if;
  if exists (select 1 from rides where customer_id = uid and status in ('requested', 'accepted', 'arrived', 'in_progress')) then
    raise exception 'ride_already_active';
  end if;
  aid := area_for_point(p_pickup_lat, p_pickup_lng);
  if aid is null then raise exception 'outside_service_area'; end if;
  km := distance_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng);
  if km < 0.1 then raise exception 'same_location'; end if;
  select * into u from users where id = uid;
  insert into rides (customer_id, vehicle, area_id, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng,
                     distance_km, fare, customer_name, customer_phone)
  values (uid, p_vehicle, aid, coalesce(p_pickup_text, ''), p_pickup_lat, p_pickup_lng,
          coalesce(p_dropoff_text, ''), p_dropoff_lat, p_dropoff_lng, round(km::numeric, 2),
          compute_fare(setting('ride_pricing') -> p_vehicle::text, km), u.full_name, coalesce(u.phone, ''))
  returning * into r;
  return r;
end $$;

create or replace function create_errand(
  p_kind task_kind,
  p_pickup_text text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_dropoff_text text, p_dropoff_lat double precision, p_dropoff_lng double precision,
  p_item_type text, p_description text, p_recipient_phone text, p_notes text
) returns delivery_tasks language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); u users; t delivery_tasks; km double precision; aid uuid;
begin
  if p_kind not in ('courier', 'parcel') then raise exception 'invalid_kind'; end if;
  if coalesce(trim(p_description), '') = '' then raise exception 'description_required'; end if;
  aid := area_for_point(p_pickup_lat, p_pickup_lng);
  if aid is null then raise exception 'outside_service_area'; end if;
  km := distance_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng);
  if km > coalesce((setting('errand_pricing')->>'max_km')::numeric, 30) then raise exception 'too_far'; end if;
  select * into u from users where id = uid;
  insert into delivery_tasks (kind, customer_id, area_id, pickup_text, pickup_lat, pickup_lng,
                              dropoff_text, dropoff_lat, dropoff_lng, item_type, description,
                              recipient_phone, notes, customer_name, customer_phone, distance_km, fee)
  values (p_kind, uid, aid, coalesce(p_pickup_text, ''), p_pickup_lat, p_pickup_lng,
          coalesce(p_dropoff_text, ''), p_dropoff_lat, p_dropoff_lng,
          coalesce(left(p_item_type, 100), ''), left(p_description, 1000),
          coalesce(left(p_recipient_phone, 20), ''), coalesce(left(p_notes, 500), ''),
          u.full_name, coalesce(u.phone, ''), round(km::numeric, 2),
          compute_fare(setting('errand_pricing'), km))
  returning * into t;
  return t;
end $$;

-- ---------------------------------------------------------------------
-- القبول: تحقق من المنطقة على الخادم
-- ---------------------------------------------------------------------
create or replace function driver_accept_ride(p_ride_id uuid)
returns rides language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); u users; r rides;
begin
  if driver_has_active_job(d.id) then raise exception 'already_on_job'; end if;
  if not exists (select 1 from rides where id = p_ride_id and area_id is not null and area_id = my_driver_area()) then
    raise exception 'outside_service_area';
  end if;
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

create or replace function driver_accept_task(p_task_id uuid)
returns delivery_tasks language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); u users; t delivery_tasks;
begin
  if d.vehicle_type not in ('courier', 'tuktuk') then raise exception 'vehicle_not_allowed'; end if;
  if driver_has_active_job(d.id) then raise exception 'already_on_job'; end if;
  if not exists (select 1 from delivery_tasks where id = p_task_id and area_id is not null and area_id = my_driver_area()) then
    raise exception 'outside_service_area';
  end if;
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

-- ---------------------------------------------------------------------
-- صلاحيات القراءة: الطلب المعلّق يظهر لسائق منطقته فقط
-- ---------------------------------------------------------------------
drop policy if exists tasks_read on delivery_tasks;
create policy tasks_read on delivery_tasks for select to authenticated
  using (
    customer_id = auth.uid()
    or driver_id = auth.uid()
    or is_admin()
    or (order_id is not null and can_see_order(order_id))
    -- المهام المتاحة: ضمن منطقة السائق فقط، والمندوب يشوف الكل، التكتك يشوف توصيل الأغراض فقط
    or (status = 'requested' and area_id is not null and area_id = my_driver_area()
        and (my_driver_vehicle() = 'courier' or (my_driver_vehicle() = 'tuktuk' and kind = 'parcel')))
  );

drop policy if exists rides_read on rides;
create policy rides_read on rides for select to authenticated
  using (customer_id = auth.uid() or driver_id = auth.uid() or is_admin()
         or (status = 'requested' and vehicle = my_driver_vehicle()
             and area_id is not null and area_id = my_driver_area()));

-- ---------------------------------------------------------------------
-- تعيين المناطق للطلبات المعلّقة القديمة (لا حذف، فقط تعبئة الحقل الفارغ)
-- ---------------------------------------------------------------------
update rides set area_id = area_for_point(pickup_lat, pickup_lng)
 where area_id is null and status = 'requested';
update delivery_tasks set area_id = area_for_point(pickup_lat, pickup_lng)
 where area_id is null and status = 'requested' and kind in ('courier', 'parcel');

grant execute on function area_for_point(double precision, double precision) to authenticated;
grant execute on function my_driver_area() to authenticated;

notify pgrst, 'reload schema';

-- ===== migrations/0012_map_places.sql =====
-- =====================================================================
-- WASEL MAPS | المرحلة 4: نقاط الاستدلال والملاحظات الجغرافية (map_places)
--
-- الحالات: draft (مسودة/اقتراح) · approved (معتمد) · rejected (مرفوض)
-- القواعد:
-- 1) أي مستخدم يقترح نقطة (suggest_map_place) → تدخل كـ draft دائماً. لا اعتماد تلقائي.
-- 2) الاعتماد/الرفض للإدارة فقط (admin_review_map_place) ويُسجَّل من راجع ووقته.
-- 3) الرفض يحتاج سبباً مكتوباً.
-- 4) الزبون والسائق يقرؤون النقاط المعتمدة فقط. مسوداتهم يشوفونها هم فقط.
-- 5) لا كتابة مباشرة على الجدول من أي دور تطبيقي؛ كل الكتابة عبر دوال محددة.
-- 6) الإحداثيات يجب أن تقع ضمن حدود العراق التقريبية (تمنع الخطأ الواضح).
-- لا تُضاف أي نقطة تلقائياً من هذا الملف: الجدول فارغ، والإدارة تضيف ما تتحقق منه.
-- التأثير: جدول جديد وإضافات دوال، لا يغيّر أي جدول قائم.
-- =====================================================================

create table if not exists map_places (
  id            uuid primary key default gen_random_uuid(),
  name_ar       text not null check (char_length(btrim(name_ar)) between 2 and 120),
  kind          text not null check (kind in ('landmark', 'district', 'street', 'store', 'service_point', 'hard_access', 'driver_note')),
  description   text not null default '' check (char_length(description) <= 500),
  lat           double precision not null check (lat between 29 and 38),
  lng           double precision not null check (lng between 38 and 49),
  area_id       uuid references service_areas (id) on delete set null,
  status        text not null default 'draft' check (status in ('draft', 'approved', 'rejected')),
  rejection_reason text not null default '',
  created_by    uuid references users (id) on delete set null,
  reviewed_by   uuid references users (id) on delete set null,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (status <> 'approved' or (reviewed_by is not null and reviewed_at is not null)),
  check (status <> 'rejected' or char_length(btrim(rejection_reason)) >= 5)
);
create index if not exists map_places_status_idx on map_places (status);
create index if not exists map_places_area_idx on map_places (area_id);

alter table map_places enable row level security;

drop policy if exists map_places_read on map_places;
create policy map_places_read on map_places for select to authenticated
  using (status = 'approved' or created_by = auth.uid() or is_admin());

-- الكتابة المباشرة ممنوعة لكل الأدوار التطبيقية
revoke all on map_places from authenticated, anon;
grant select on map_places to authenticated;
grant all on map_places to service_role;

-- ---------------------------------------------------------------------
-- اقتراح نقطة: تدخل كمسودة دائماً
-- ---------------------------------------------------------------------
create or replace function suggest_map_place(
  p_name text, p_kind text, p_lat double precision, p_lng double precision, p_description text default ''
) returns map_places language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r map_places; aid uuid;
begin
  if p_kind not in ('landmark', 'district', 'street', 'store', 'service_point', 'hard_access', 'driver_note') then raise exception 'invalid_kind'; end if;
  aid := area_for_point(p_lat, p_lng);
  insert into map_places (name_ar, kind, description, lat, lng, area_id, status, created_by)
  values (btrim(coalesce(p_name, '')), p_kind, left(btrim(coalesce(p_description, '')), 500), p_lat, p_lng, aid, 'draft', uid)
  returning * into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- الإدارة: إضافة/تعديل مسودة أو نقطة، ثم المراجعة
-- ---------------------------------------------------------------------
create or replace function admin_save_map_place(
  p_id uuid, p_name text, p_kind text, p_lat double precision, p_lng double precision, p_description text default ''
) returns map_places language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r map_places; aid uuid;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_kind not in ('landmark', 'district', 'street', 'store', 'service_point', 'hard_access', 'driver_note') then raise exception 'invalid_kind'; end if;
  aid := area_for_point(p_lat, p_lng);
  if p_id is null then
    insert into map_places (name_ar, kind, description, lat, lng, area_id, status, created_by)
    values (btrim(coalesce(p_name, '')), p_kind, left(btrim(coalesce(p_description, '')), 500), p_lat, p_lng, aid, 'draft', uid)
    returning * into r;
  else
    -- التعديل يعيد النقطة لمسودة حتى تُراجَع من جديد (ما نعتمد تغييراً لم نراجعه)
    update map_places set name_ar = btrim(coalesce(p_name, '')), kind = p_kind,
           description = left(btrim(coalesce(p_description, '')), 500), lat = p_lat, lng = p_lng, area_id = aid,
           status = 'draft', reviewed_by = null, reviewed_at = null, rejection_reason = '', updated_at = now()
     where id = p_id returning * into r;
    if not found then raise exception 'place_not_found'; end if;
  end if;
  return r;
end $$;

create or replace function admin_review_map_place(p_id uuid, p_status text, p_reason text default '')
returns map_places language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r map_places;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_status not in ('approved', 'rejected') then raise exception 'invalid_status'; end if;
  if p_status = 'rejected' and char_length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'reason_required'; end if;
  update map_places set status = p_status,
         reviewed_by = uid, reviewed_at = now(),
         rejection_reason = case when p_status = 'rejected' then btrim(p_reason) else '' end,
         updated_at = now()
   where id = p_id returning * into r;
  if not found then raise exception 'place_not_found'; end if;
  return r;
end $$;

create or replace function admin_delete_map_place(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  -- نحذف المسودات والمرفوضة فقط. المعتمدة تُرفض أولاً حتى يبقى أثر المراجعة.
  delete from map_places where id = p_id and status <> 'approved';
  if not found then raise exception 'cannot_delete_approved_or_missing'; end if;
end $$;

grant execute on function suggest_map_place(text, text, double precision, double precision, text) to authenticated;
grant execute on function admin_save_map_place(uuid, text, text, double precision, double precision, text) to authenticated;
grant execute on function admin_review_map_place(uuid, text, text) to authenticated;
grant execute on function admin_delete_map_place(uuid) to authenticated;

notify pgrst, 'reload schema';

-- ===== migrations/0013_super_app_foundation.sql =====
-- =====================================================================
-- WASEL SUPER APP | المرحلة 1: الأساس (تصنيفات الخدمات، الكتالوج، نوع النشاط، البحث)
--
-- 1) service_groups: تصنيفات «اكتشف خدمات واصل» (10 تصنيفات).
-- 2) services: كتالوج الخدمات. كل خدمة لها "محرك" (engine) يحدد كيف تُنفَّذ:
--    order = طلب متجر، task = مهمة مندوب، ride = رحلة، booking = حجز/خدمة، none = بانتظار التنفيذ.
--    الخدمة لا تظهر للزبون إلا إذا فعّلتها الإدارة (is_active)، وهكذا لا تظهر واجهة بلا تنفيذ.
-- 3) merchants.business_type: نوع النشاط (متجر، مزود خدمة، ملعب، مصور...). الحالي يبقى كما هو.
-- 4) إعدادات العمولة لكل خدمة في app_settings (service_commissions) وقابلة للتعديل من الإدارة.
--    القيم الافتراضية بدون نسب مخترعة: كل خدمة بنموذج "بدون عمولة" حتى تحدد الإدارة النموذج والقيمة.
-- التأثير: إضافة جداول وأعمدة وتعبئة نوع النشاط للمحلات القائمة. لا حذف لأي بيانات أو وظائف.
-- =====================================================================

-- ---------------------------------------------------------------------
-- التصنيفات
-- ---------------------------------------------------------------------
create table if not exists service_groups (
  id          text primary key,
  name_ar     text not null,
  sort_order  int not null default 0,
  is_active   boolean not null default true
);

insert into service_groups (id, name_ar, sort_order) values
  ('bookings',  'الحجوزات والمواعيد', 1),
  ('jobs',      'الوظائف وفرص العمل', 2),
  ('transport', 'النقل والتوصيل', 3),
  ('shopping',  'التسوق والمتاجر', 4),
  ('home',      'الخدمات المنزلية والصيانة', 5),
  ('office',    'الخدمات المكتبية والمعاملات', 6),
  ('education', 'التعليم والمعاهد', 7),
  ('events',    'التصوير والمناسبات', 8),
  ('travel',    'السفر والسياحة', 9),
  ('finance',   'الخدمات المالية والتسليم النقدي', 10)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- الكتالوج
-- ---------------------------------------------------------------------
create table if not exists services (
  id                 text primary key,
  group_id           text not null references service_groups (id) on delete restrict,
  name_ar            text not null check (char_length(btrim(name_ar)) between 2 and 80),
  description        text not null default '' check (char_length(description) <= 300),
  keywords           text not null default '' check (char_length(keywords) <= 300),
  engine             text not null default 'none' check (engine in ('none', 'order', 'task', 'ride', 'booking')),
  requires_approval  boolean not null default true,
  is_active          boolean not null default false,
  sort_order         int not null default 0,
  updated_at         timestamptz not null default now()
);
create index if not exists services_group_idx on services (group_id, sort_order);

-- الخدمات الأولية: كلها معطّلة حتى تُنفَّذ. الخدمات التي تعمل حالياً مرتبطة بمحركاتها الفعلية.
insert into services (id, group_id, name_ar, description, keywords, engine, is_active, sort_order) values
  -- تعمل حالياً على المحركات القائمة
  ('parcel_delivery', 'transport', 'توصيل الأمانات', 'توصيل غرض بين شخصين: استلام وتسليم وصورة وعنوان', 'توصيل امانات غرض طرد', 'task', true, 1),
  ('courier_errand',  'transport', 'مندوب يشتري لك', 'مندوب يذهب يشتري أو يستلم لك شي', 'مندوب مشتريات شراء', 'task', true, 2),
  ('home_services',   'home',      'الصيانة المنزلية والحرف', 'فنيون للكهرباء والسباكة والنجارة وغيرها', 'صيانة سباكة كهرباء نجارة فني', 'booking', true, 1),
  ('restaurants',     'shopping',  'المطاعم', 'طلب طعام من المطاعم القريبة', 'طعام مطعم اكل', 'order', true, 1),
  ('stores',          'shopping',  'المحلات والسوبرماركت', 'مشتريات من المحلات والسوبرماركت', 'محل سوبرماركت بقالة', 'order', true, 2),
  -- مخطط لها: معطّلة حتى تُبنى وتُختبر
  ('pitch_booking',   'bookings',  'حجز ملاعب الخماسي', 'حجز ملعب بالساعة مع تأكيد صاحب الملعب', 'ملعب خماسي كرة حجز', 'none', false, 1),
  ('doctor_booking',  'bookings',  'حجز الأطباء والمضمدين', 'حجز إلكتروني أو حجز دور حضورياً', 'طبيب دكتور حجز عيادة مضمد', 'none', false, 2),
  ('restaurant_booking', 'bookings', 'حجز المطاعم والصالات', 'حجز صالة وتجهيز طلب مسبق', 'حجز مطعم صالة عزيمة', 'none', false, 3),
  ('institute_seats', 'education', 'المعاهد وحجز المقاعد', 'دليل المعاهد وحجز المقاعد في الدورات', 'معهد دورة مقعد تعليم', 'none', false, 1),
  ('photographers',   'events',    'المصورون', 'حجز مصور للمباريات والأعراس والمنتجات', 'مصور تصوير فيديو عرس', 'none', false, 1),
  ('documents',       'office',    'معاملاتك علينا', 'استنساخ وطباعة وتوصيل المستمسكات', 'معاملة مستمسكات استنساخ طباعة', 'none', false, 1),
  ('print_custom',    'shopping',  'الطباعة حسب الطلب', 'طباعة ملابس وتصاميم شخصية', 'طباعة تصميم ملابس تيشيرت', 'none', false, 4),
  ('clothing_store',  'shopping',  'سوق الملابس', 'متجر ملابس متعدد التجار', 'ملابس احذية حقائب', 'order', false, 5),
  ('device_installments', 'shopping', 'الأجهزة بالتقسيط', 'موبايلات وحاسبات وأجهزة بالتقسيط من التجار', 'موبايل حاسبة تقسيط جهاز', 'order', false, 6),
  ('school_lines',    'transport', 'خطوط المدارس', 'اشتراكات نقل دورية للمدارس', 'مدرسة خط نقل طالب', 'ride', false, 4),
  ('staff_lines',     'transport', 'خطوط الموظفين', 'اشتراكات نقل دورية للموظفين', 'موظف خط نقل دوام', 'ride', false, 5),
  ('heavy_transport', 'transport', 'كيا الحمل والستوت', 'نقل الأثاث والحمولات الكبيرة', 'كيا حمل ستوت نقل اثاث', 'ride', false, 6),
  ('package_delivery_big', 'transport', 'الأغراض الكبيرة', 'توصيل طرود متوسطة وكبيرة', 'طرد كبير شحن', 'task', false, 7),
  ('phone_repair',    'home',      'صيانة الموبايلات من المنزل', 'استلام الجهاز وتشخيصه وإعادته', 'موبايل تصليح صيانة شاشة', 'task', false, 2),
  ('carpet_cleaning', 'home',      'غسل الفرشات والسجاد', 'تنظيف الفرشات والسجاد والكنب والستائر', 'غسل فرشة سجاد تنظيف كنب', 'booking', false, 3),
  ('ps_rental',       'events',    'تأجير أجهزة البلايستيشن', 'تأجير من المراكز المتعاقدة مع تأمين مسترد', 'بلايستيشن ألعاب تأجير', 'booking', false, 2),
  ('digital_topup',   'finance',   'الرصيد والبطاقات الإلكترونية', 'تعبئة رصيد وبطاقات رقمية', 'رصيد تعبئة كارت بطاقة', 'order', false, 1),
  ('salary_delivery', 'finance',   'راتبك لباب بيتك', 'استلام المبلغ المستحق من المكتبة وتسليمه للبيت', 'راتب مبلغ تسليم', 'task', false, 2),
  ('jobs',            'jobs',      'وظائف واصل', 'منصة توظيف محلية: إعلانات وطلبات تقديم', 'وظيفة توظيف عمل شغل', 'none', false, 1),
  ('travel_campaigns','travel',    'السفر والسياحة', 'حملات سياحية موثّقة', 'سفر سياحة رحلة حملة', 'booking', false, 1)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- نوع النشاط للتاجر/مقدم الخدمة
-- ---------------------------------------------------------------------
alter table merchants add column if not exists business_type text not null default 'store'
  check (business_type in ('store', 'restaurant', 'provider', 'pitch_owner', 'venue', 'library', 'institute',
                           'photographer', 'technician', 'employer', 'maintenance_center', 'rental_center', 'travel_agency'));

-- المحلات القائمة مرتبطة بتصنيفها الحالي: مزودو الخدمات المنزلية نوع provider، والباقي store
update merchants set business_type = 'provider' where category_id = 'home_services' and business_type = 'store';
update merchants set business_type = 'restaurant' where category_id = 'restaurants' and business_type = 'store';

-- ---------------------------------------------------------------------
-- الصلاحيات
-- ---------------------------------------------------------------------
alter table service_groups enable row level security;
alter table services enable row level security;

drop policy if exists service_groups_read on service_groups;
create policy service_groups_read on service_groups for select to authenticated using (true);
drop policy if exists service_groups_admin on service_groups;
create policy service_groups_admin on service_groups for all to authenticated using (is_admin()) with check (is_admin());

-- الزبون والمستخدمون يقرؤون الخدمات المفعّلة فقط. الإدارة ترى الكل.
drop policy if exists services_read on services;
create policy services_read on services for select to authenticated using (is_active or is_admin());
drop policy if exists services_admin on services;
create policy services_admin on services for all to authenticated using (is_admin()) with check (is_admin());

grant select on service_groups, services to authenticated;
grant all on service_groups, services to service_role;

-- ---------------------------------------------------------------------
-- الإدارة: تشغيل/إيقاف وتعديل الخدمة (بدون أي تغيير آخر)
-- ---------------------------------------------------------------------
create or replace function admin_update_service(
  p_id text, p_is_active boolean, p_name_ar text default null, p_description text default null
) returns services language plpgsql security definer set search_path = public as $$
declare r services;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_is_active and not exists (select 1 from services where id = p_id and engine <> 'none') then
    -- لا نفعّل خدمة بلا محرك تنفيذ: هذا يخفي وعداً لا نقدر على الوفاء به
    raise exception 'service_not_implemented';
  end if;
  update services set is_active = p_is_active,
         name_ar = coalesce(nullif(btrim(p_name_ar), ''), name_ar),
         description = coalesce(p_description, description),
         updated_at = now()
   where id = p_id returning * into r;
  if not found then raise exception 'service_not_found'; end if;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- البحث الموحد: خدمات مفعّلة + محلات/مقدمو خدمات معتمدون بالاسم أو الوصف
-- ---------------------------------------------------------------------
create or replace function search_services(p_query text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q text := '%' || btrim(coalesce(p_query, '')) || '%';
begin
  if char_length(btrim(coalesce(p_query, ''))) < 2 then return jsonb_build_object('services', '[]'::jsonb, 'merchants', '[]'::jsonb); end if;
  return jsonb_build_object(
    'services', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name_ar, 'group', s.group_id, 'engine', s.engine, 'description', s.description) order by s.sort_order), '[]'::jsonb)
                   from services s
                  where s.is_active and (s.name_ar ilike q or s.keywords ilike q or s.description ilike q)),
    'merchants', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'business_type', m.business_type, 'category_id', m.category_id) order by m.name), '[]'::jsonb)
                    from (select * from merchants where status = 'approved' and name ilike q limit 20) m)
  );
end $$;

-- ---------------------------------------------------------------------
-- إعدادات العمولة لكل خدمة (قابلة للتعديل من الإدارة، بدون نسب افتراضية مخترعة)
--   model: free (مجانية) | percent (نسبة من المبلغ) | fixed (مبلغ ثابت لكل عملية)
-- ---------------------------------------------------------------------
insert into app_settings (key, value)
select 'service_commissions', jsonb_object_agg(id, jsonb_build_object('model', 'free', 'value', 0)) from services
on conflict (key) do nothing;

create or replace function admin_set_service_commission(p_service_id text, p_model text, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur jsonb;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_model not in ('free', 'percent', 'fixed') then raise exception 'invalid_model'; end if;
  if p_value is null or p_value < 0 then raise exception 'invalid_value'; end if;
  if p_model = 'percent' and p_value > 50 then raise exception 'invalid_percent'; end if;
  if not exists (select 1 from services where id = p_service_id) then raise exception 'service_not_found'; end if;
  select value into cur from app_settings where key = 'service_commissions';
  cur := coalesce(cur, '{}'::jsonb) || jsonb_build_object(p_service_id, jsonb_build_object('model', p_model, 'value', p_value));
  insert into app_settings (key, value, updated_at) values ('service_commissions', cur, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return cur -> p_service_id;
end $$;

grant execute on function admin_update_service(text, boolean, text, text) to authenticated;
grant execute on function search_services(text) to authenticated;
grant execute on function admin_set_service_commission(text, text, numeric) to authenticated;

notify pgrst, 'reload schema';

-- ===== migrations/0014_service_engine.sql =====
-- =====================================================================
-- WASEL SUPER APP | المرحلة 2: المحرك المشترك للخدمات + حجز الملاعب
--
-- المحرك المشترك (service_requests):
--   كل خدمة من نوع "حجز/طلب من مقدم خدمة" تمر بنفس الدورة:
--   requested → accepted | rejected | cancelled
--   accepted  → in_progress | completed | cancelled
--   in_progress → completed | cancelled
--   كل تغيير يُسجَّل في service_request_events (سجل تدقيق) ويُرسل إشعاراً للطرف الآخر.
--   العمولة تُحسب عند completed فقط، من إعداد الخدمة في app_settings.
--
-- حجز الملاعب (pitches): الملعب يتبع مقدم خدمة من نوع pitch_owner. صاحب الملعب يحدد السعر
-- والساعات والحد الأدنى وسياسة الإلغاء بنفسه. لا توجد أرقام افتراضية وهمية.
-- منع الحجز المزدوج: التحقق عند القبول تحت قفل لكل ملعب، ولا يُقبل حجز يتداخل مع حجز مقبول.
-- التأثير: جداول وأعمدة جديدة ودوال. لا تغيير على الجداول القائمة إلا إضافة أعمدة اختيارية.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) الطلبات الموحدة
-- ---------------------------------------------------------------------
create table if not exists service_requests (
  id                uuid primary key default gen_random_uuid(),
  service_id        text not null references services (id) on delete restrict,
  customer_id       uuid not null references users (id) on delete restrict,
  provider_id       uuid not null references merchants (id) on delete restrict,
  area_id           uuid references service_areas (id) on delete set null,
  status            text not null default 'requested'
                    check (status in ('requested', 'accepted', 'rejected', 'in_progress', 'completed', 'cancelled')),
  payload           jsonb not null default '{}'::jsonb,
  amount            int not null default 0 check (amount >= 0),
  client_request_id uuid unique,
  reject_reason     text not null default '' check (char_length(reject_reason) <= 300),
  cancel_reason     text not null default '' check (char_length(cancel_reason) <= 300),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  responded_at      timestamptz,
  completed_at      timestamptz
);
create index if not exists service_requests_customer_idx on service_requests (customer_id, created_at desc);
create index if not exists service_requests_provider_idx on service_requests (provider_id, status, created_at desc);
create index if not exists service_requests_service_idx on service_requests (service_id, status);

create table if not exists service_request_events (
  id          bigint generated always as identity primary key,
  request_id  uuid not null references service_requests (id) on delete cascade,
  actor_id    uuid references users (id) on delete set null,
  from_status text,
  to_status   text not null,
  note        text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists service_request_events_req_idx on service_request_events (request_id, created_at);

create table if not exists service_commissions (
  id          bigint generated always as identity primary key,
  request_id  uuid not null unique references service_requests (id) on delete cascade,
  service_id  text not null references services (id),
  provider_id uuid not null references merchants (id) on delete restrict,
  base_amount int not null check (base_amount >= 0),
  model       text not null check (model in ('free', 'percent', 'fixed')),
  value       numeric(10,2) not null default 0,
  amount      int not null default 0 check (amount >= 0),
  created_at  timestamptz not null default now()
);

create table if not exists service_reviews (
  id          bigint generated always as identity primary key,
  request_id  uuid not null unique references service_requests (id) on delete cascade,
  customer_id uuid not null references users (id) on delete cascade,
  provider_id uuid not null references merchants (id) on delete cascade,
  rating      int not null check (rating between 1 and 5),
  comment     text not null default '' check (char_length(comment) <= 500),
  created_at  timestamptz not null default now()
);

alter table service_requests       enable row level security;
alter table service_request_events enable row level security;
alter table service_commissions    enable row level security;
alter table service_reviews        enable row level security;

-- القراءة: الزبون يرى طلباته، ومقدم الخدمة يرى طلبات محله، والإدارة ترى الكل
drop policy if exists service_requests_read on service_requests;
create policy service_requests_read on service_requests for select to authenticated
  using (customer_id = auth.uid() or owns_merchant(provider_id) or is_admin());
drop policy if exists service_events_read on service_request_events;
create policy service_events_read on service_request_events for select to authenticated
  using (exists (select 1 from service_requests r where r.id = request_id
                 and (r.customer_id = auth.uid() or owns_merchant(r.provider_id) or is_admin())));
drop policy if exists service_commissions_read on service_commissions;
create policy service_commissions_read on service_commissions for select to authenticated
  using (is_admin() or owns_merchant(provider_id));
drop policy if exists service_reviews_read on service_reviews;
create policy service_reviews_read on service_reviews for select to authenticated
  using (customer_id = auth.uid() or owns_merchant(provider_id) or is_admin());

-- الكتابة المباشرة ممنوعة: كل شيء عبر الدوال
revoke all on service_requests, service_request_events, service_commissions, service_reviews from authenticated, anon;
grant select on service_requests, service_request_events, service_commissions, service_reviews to authenticated;
grant all on service_requests, service_request_events, service_commissions, service_reviews to service_role;

-- ---------------------------------------------------------------------
-- 2) دورة الحالة: الانتقالات المسموحة وقواعدها
-- ---------------------------------------------------------------------
create or replace function _svc_transition_allowed(p_from text, p_to text)
returns boolean language sql immutable as $$
  select (p_from, p_to) in (
    ('requested', 'accepted'), ('requested', 'rejected'), ('requested', 'cancelled'),
    ('accepted', 'in_progress'), ('accepted', 'completed'), ('accepted', 'cancelled'),
    ('in_progress', 'completed'), ('in_progress', 'cancelled')
  );
$$;

-- يحوّل الحالة ويسجّل الحدث ويرسل الإشعار ويحسب العمولة عند الإتمام
create or replace function _svc_move(p_req uuid, p_to text, p_actor uuid, p_note text default '')
returns service_requests language plpgsql security definer set search_path = public as $$
declare r service_requests; m merchants; cfg jsonb; model text; val numeric; amt int; who_notify uuid; title text;
begin
  select * into r from service_requests where id = p_req for update;
  if not found then raise exception 'request_not_found'; end if;
  if not _svc_transition_allowed(r.status, p_to) then raise exception 'invalid_transition:%->%', r.status, p_to; end if;

  update service_requests set status = p_to, updated_at = now(),
         responded_at = case when p_to in ('accepted', 'rejected') then now() else responded_at end,
         completed_at = case when p_to = 'completed' then now() else completed_at end
   where id = r.id returning * into r;

  insert into service_request_events (request_id, actor_id, from_status, to_status, note)
  values (r.id, p_actor, null, p_to, coalesce(p_note, ''));

  -- العمولة: مرة واحدة عند الإتمام (unique على request_id)
  if p_to = 'completed' then
    select * into m from merchants where id = r.provider_id;
    cfg := coalesce((select value -> r.service_id from app_settings where key = 'service_commissions'), '{}'::jsonb);
    model := coalesce(cfg ->> 'model', 'free');
    val := coalesce((cfg ->> 'value')::numeric, 0);
    amt := case model
             when 'percent' then round(r.amount * least(greatest(val, 0), 50) / 100.0)::int
             when 'fixed' then least(greatest(val, 0), 2147483647)::int
             else 0 end;
    insert into service_commissions (request_id, service_id, provider_id, base_amount, model, value, amount)
    values (r.id, r.service_id, r.provider_id, r.amount, model, val, amt)
    on conflict (request_id) do nothing;
  end if;

  -- الإشعار للطرف الآخر
  if p_actor = r.customer_id then
    who_notify := (select owner_id from merchants where id = r.provider_id);
  else
    who_notify := r.customer_id;
  end if;
  title := case p_to
    when 'accepted' then 'تم قبول الحجز'
    when 'rejected' then 'تم رفض الطلب'
    when 'in_progress' then 'بدأت الخدمة'
    when 'completed' then 'انتهت الخدمة'
    when 'cancelled' then 'تم إلغاء الطلب'
    else 'تحديث على طلبك' end;
  perform notify_user(who_notify, title, '', jsonb_build_object('type', 'service_request', 'id', r.id, 'status', p_to));
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 3) الملاعب
-- ---------------------------------------------------------------------
create table if not exists pitches (
  id                  uuid primary key default gen_random_uuid(),
  merchant_id         uuid not null references merchants (id) on delete cascade,
  name_ar             text not null check (char_length(btrim(name_ar)) between 2 and 120),
  description         text not null default '' check (char_length(description) <= 500),
  price_per_hour      int not null default 0 check (price_per_hour >= 0),
  min_minutes         int not null default 60 check (min_minutes between 30 and 480),
  open_hour           int not null default 8 check (open_hour between 0 and 23),
  close_hour          int not null default 23 check (close_hour between 1 and 24),
  cancel_before_hours int not null default 2 check (cancel_before_hours between 0 and 168),
  cancellation_policy text not null default '' check (char_length(cancellation_policy) <= 500),
  is_active           boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (open_hour < close_hour),
  check (not is_active or price_per_hour > 0)
);
create index if not exists pitches_merchant_idx on pitches (merchant_id);

alter table pitches enable row level security;
drop policy if exists pitches_read on pitches;
create policy pitches_read on pitches for select to authenticated
  using ((is_active and exists (select 1 from merchants m where m.id = merchant_id and m.status = 'approved'))
         or owns_merchant(merchant_id) or is_admin());
revoke all on pitches from authenticated, anon;
grant select on pitches to authenticated;
grant all on pitches to service_role;

-- صاحب الملعب (أو الإدارة) يحفظ بيانات الملعب. الإيقاف والتفعيل من نفس الدالة.
create or replace function upsert_pitch(
  p_id uuid, p_merchant_id uuid, p_name text, p_description text, p_price_per_hour int,
  p_min_minutes int, p_open_hour int, p_close_hour int, p_cancel_before_hours int,
  p_cancellation_policy text, p_is_active boolean
) returns pitches language plpgsql security definer set search_path = public as $$
declare r pitches; m merchants;
begin
  select * into m from merchants where id = p_merchant_id;
  if not found then raise exception 'merchant_not_found'; end if;
  if not (owns_merchant(p_merchant_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if m.business_type <> 'pitch_owner' then raise exception 'not_pitch_owner'; end if;
  if m.status <> 'approved' and coalesce(p_is_active, false) then raise exception 'merchant_not_approved'; end if;
  if p_id is null then
    insert into pitches (merchant_id, name_ar, description, price_per_hour, min_minutes, open_hour, close_hour,
                         cancel_before_hours, cancellation_policy, is_active)
    values (p_merchant_id, btrim(p_name), coalesce(p_description, ''), p_price_per_hour, p_min_minutes, p_open_hour,
            p_close_hour, p_cancel_before_hours, coalesce(p_cancellation_policy, ''), coalesce(p_is_active, false))
    returning * into r;
  else
    -- إنشاء بمعرّف محدد أو تحديث ملعب موجود لنفس الصاحب فقط
    insert into pitches (id, merchant_id, name_ar, description, price_per_hour, min_minutes, open_hour, close_hour,
                         cancel_before_hours, cancellation_policy, is_active)
    values (p_id, p_merchant_id, btrim(p_name), coalesce(p_description, ''), p_price_per_hour, p_min_minutes, p_open_hour,
            p_close_hour, p_cancel_before_hours, coalesce(p_cancellation_policy, ''), coalesce(p_is_active, false))
    on conflict (id) do update set name_ar = excluded.name_ar, description = excluded.description,
           price_per_hour = excluded.price_per_hour, min_minutes = excluded.min_minutes, open_hour = excluded.open_hour,
           close_hour = excluded.close_hour, cancel_before_hours = excluded.cancel_before_hours,
           cancellation_policy = excluded.cancellation_policy, is_active = excluded.is_active, updated_at = now()
     where pitches.merchant_id = p_merchant_id
    returning * into r;
    if r.id is null then raise exception 'pitch_not_found'; end if;
  end if;
  return r;
end $$;

-- الساعات المحجوزة (مقبولة فقط) ليوم معيّن، بتوقيت بغداد. لا تكشف أي بيانات للزبون.
create or replace function pitch_busy_slots(p_pitch_id uuid, p_day date)
returns table (starts_at timestamptz, ends_at timestamptz) language sql stable security definer set search_path = public as $$
  select (r.payload->>'starts_at')::timestamptz, (r.payload->>'ends_at')::timestamptz
    from service_requests r
   where r.service_id = 'pitch_booking' and r.status in ('accepted', 'in_progress', 'completed')
     and (r.payload->>'pitch_id')::uuid = p_pitch_id
     and (r.payload->>'starts_at')::timestamptz >= (p_day::timestamp at time zone 'Asia/Baghdad')
     and (r.payload->>'starts_at')::timestamptz < ((p_day + 1)::timestamp at time zone 'Asia/Baghdad')
   order by 1;
$$;

-- الزبون يطلب حجزاً. لا يُحجز شيء هنا: الحجز يتأكد عند قبول صاحب الملعب.
create or replace function pitch_book_request(
  p_pitch_id uuid, p_starts_at timestamptz, p_minutes int, p_client_request_id uuid
) returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); p pitches; r service_requests; ends timestamptz; hr_start int; hr_end numeric; amt int;
begin
  if not exists (select 1 from services where id = 'pitch_booking' and is_active) then raise exception 'service_inactive'; end if;
  -- إعادة الإرسال بنفس المعرّف ترجّع الطلب الأصلي
  if p_client_request_id is not null then
    select * into r from service_requests where client_request_id = p_client_request_id and customer_id = uid;
    if found then return r; end if;
  end if;
  select * into p from pitches where id = p_pitch_id;
  if not found or not p.is_active then raise exception 'pitch_unavailable'; end if;
  if p_starts_at <= now() then raise exception 'start_in_past'; end if;
  if p_minutes is null or p_minutes < p.min_minutes or p_minutes > 480 or p_minutes % 30 <> 0 then raise exception 'invalid_duration'; end if;
  ends := p_starts_at + make_interval(mins => p_minutes);
  hr_start := extract(hour from (p_starts_at at time zone 'Asia/Baghdad'))::int;
  hr_end := extract(hour from (ends at time zone 'Asia/Baghdad')) + extract(minute from (ends at time zone 'Asia/Baghdad')) / 60.0;
  -- الحجز داخل يوم واحد بتوقيت بغداد؛ انتهاؤه عند منتصف الليل (00:00 اليوم التالي) مسموح فقط إذا الإغلاق 24
  if (ends at time zone 'Asia/Baghdad')::date <> (p_starts_at at time zone 'Asia/Baghdad')::date then
    if not (p.close_hour = 24 and (ends at time zone 'Asia/Baghdad')::time = time '00:00') then raise exception 'outside_hours'; end if;
    hr_end := 24;
  end if;
  if hr_start < p.open_hour or hr_end > p.close_hour then raise exception 'outside_hours'; end if;
  amt := round(p.price_per_hour * p_minutes / 60.0)::int;
  -- الوقت المتاح الآن لا يُحجز مسبقاً: نتحقق من التعارض مع المقبول فقط
  if exists (select 1 from service_requests r2 where r2.service_id = 'pitch_booking'
              and r2.status in ('accepted', 'in_progress', 'completed')
              and (r2.payload->>'pitch_id')::uuid = p_pitch_id
              and (r2.payload->>'starts_at')::timestamptz < ends
              and (r2.payload->>'ends_at')::timestamptz > p_starts_at) then
    raise exception 'slot_taken';
  end if;
  insert into service_requests (service_id, customer_id, provider_id, payload, amount, client_request_id)
  values ('pitch_booking', uid, p.merchant_id,
          jsonb_build_object('pitch_id', p.id, 'pitch_name', p.name_ar, 'starts_at', p_starts_at, 'ends_at', ends, 'minutes', p_minutes),
          amt, p_client_request_id)
  returning * into r;
  insert into service_request_events (request_id, actor_id, from_status, to_status) values (r.id, uid, null, 'requested');
  perform notify_user((select owner_id from merchants where id = p.merchant_id), 'طلب حجز ملعب جديد', p.name_ar,
                      jsonb_build_object('type', 'service_request', 'id', r.id, 'status', 'requested'));
  return r;
end $$;

-- صاحب الملعب يقبل أو يرفض. القبول يتحقق من التعارض تحت قفل الملعب.
create or replace function service_respond(p_request_id uuid, p_accept boolean, p_reason text default '')
returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests; pid uuid;
begin
  select * into r from service_requests where id = p_request_id;
  if not found then raise exception 'request_not_found'; end if;
  if not (owns_merchant(r.provider_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if r.status <> 'requested' then raise exception 'invalid_transition:%', r.status; end if;
  if p_accept then
    if r.service_id = 'pitch_booking' then
      pid := (r.payload->>'pitch_id')::uuid;
      perform pg_advisory_xact_lock(hashtext(pid::text));
      if exists (select 1 from service_requests r2 where r2.service_id = 'pitch_booking' and r2.id <> r.id
                  and r2.status in ('accepted', 'in_progress', 'completed')
                  and (r2.payload->>'pitch_id')::uuid = pid
                  and (r2.payload->>'starts_at')::timestamptz < (r.payload->>'ends_at')::timestamptz
                  and (r2.payload->>'ends_at')::timestamptz > (r.payload->>'starts_at')::timestamptz) then
        raise exception 'slot_taken';
      end if;
    end if;
    return _svc_move(r.id, 'accepted', uid, '');
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'reason_required'; end if;
  update service_requests set reject_reason = btrim(p_reason) where id = r.id;
  return _svc_move(r.id, 'rejected', uid, btrim(p_reason));
end $$;

-- تغيير الحالة بعد القبول (بدء/إتمام) من مقدم الخدمة أو الإدارة
create or replace function service_set_status(p_request_id uuid, p_to text)
returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests;
begin
  select * into r from service_requests where id = p_request_id;
  if not found then raise exception 'request_not_found'; end if;
  if not (owns_merchant(r.provider_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_to not in ('in_progress', 'completed') then raise exception 'invalid_status'; end if;
  return _svc_move(p_request_id, p_to, uid, '');
end $$;

-- إلغاء: الزبون يلغي قبل الموعد بالمدة التي يحددها صاحب الملعب، ومقدم الخدمة يلغي بسبب
create or replace function service_cancel(p_request_id uuid, p_reason text default '')
returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests; p pitches; lead_h int;
begin
  select * into r from service_requests where id = p_request_id;
  if not found then raise exception 'request_not_found'; end if;
  if r.customer_id = uid then
    if r.service_id = 'pitch_booking' then
      select * into p from pitches where id = (r.payload->>'pitch_id')::uuid;
      lead_h := coalesce(p.cancel_before_hours, 0);
      if r.status in ('accepted') and now() > (r.payload->>'starts_at')::timestamptz - make_interval(hours => lead_h) then
        raise exception 'cancellation_window_closed';
      end if;
    end if;
  elsif not (owns_merchant(r.provider_id) or is_admin()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update service_requests set cancel_reason = btrim(coalesce(p_reason, '')) where id = r.id;
  return _svc_move(r.id, 'cancelled', uid, btrim(coalesce(p_reason, '')));
end $$;

-- تقييم بعد الإتمام (مرة واحدة)
create or replace function service_rate(p_request_id uuid, p_rating int, p_comment text default '')
returns service_reviews language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests; v service_reviews;
begin
  select * into r from service_requests where id = p_request_id and customer_id = uid;
  if not found or r.status <> 'completed' then raise exception 'cannot_rate'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'invalid_rating'; end if;
  insert into service_reviews (request_id, customer_id, provider_id, rating, comment)
  values (r.id, uid, r.provider_id, p_rating, left(coalesce(p_comment, ''), 500))
  returning * into v;
  return v;
end $$;

grant execute on function pitch_book_request(uuid, timestamptz, int, uuid) to authenticated;
grant execute on function service_respond(uuid, boolean, text) to authenticated;
grant execute on function service_set_status(uuid, text) to authenticated;
grant execute on function service_cancel(uuid, text) to authenticated;
grant execute on function service_rate(uuid, int, text) to authenticated;
grant execute on function upsert_pitch(uuid, uuid, text, text, int, int, int, int, int, text, boolean) to authenticated;
grant execute on function pitch_busy_slots(uuid, date) to authenticated;
revoke execute on function _svc_move(uuid, text, uuid, text) from public, anon, authenticated;
revoke execute on function _svc_transition_allowed(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) تفعيل خدمة الملاعب بمحركها الآن (التفعيل الفعلي من الإدارة)
-- ---------------------------------------------------------------------
update services set engine = 'booking', updated_at = now() where id = 'pitch_booking';

notify pgrst, 'reload schema';
