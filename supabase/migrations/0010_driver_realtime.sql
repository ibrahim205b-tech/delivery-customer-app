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
