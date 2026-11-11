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
