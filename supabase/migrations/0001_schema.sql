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
