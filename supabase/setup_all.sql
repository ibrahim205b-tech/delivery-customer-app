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

-- ===== migrations/0009_growth.sql =====
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
