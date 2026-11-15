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
