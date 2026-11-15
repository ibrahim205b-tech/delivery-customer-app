-- =====================================================================
-- اختبار WASEL MAPS المرحلة 1 (0010): النشر الفوري، وقت الموقع، عزل بيانات السائق
-- يعمل داخل transaction وينتهي بـ rollback، فلا يترك أي بيانات في القاعدة.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/driver_realtime.sql
-- يحتاج سائقاً موجوداً في drivers. إذا لم يوجد زبون غير السائق يستعمل السائق نفسه للاختبار (قراءة الزبون).
-- =====================================================================
begin;

do $$
declare
  drv uuid; cust uuid; rid uuid; before_loc timestamptz; after_loc timestamptz; n int; lat double precision;
begin
  select id into drv from drivers order by created_at limit 1;
  if drv is null then raise exception 'FAIL: لا يوجد سائق للاختبار'; end if;
  select id into cust from users where id <> drv order by created_at limit 1;

  -- 1) drivers منشور على Realtime
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'drivers') then
    raise exception 'FAIL: drivers ليس منشوراً على Realtime';
  end if;
  raise notice 'PASS: drivers منشور على Realtime';

  -- 2) عزل القراءة: زبون لا يقرأ صفوف السائقين، والسائق يقرأ صفه فقط
  if cust is not null then
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', cust::text, true);
    select count(*) into n from drivers;
    reset role;
    if n <> 0 then raise exception 'FAIL: الزبون يقرأ % صف سائق', n; end if;
    raise notice 'PASS: الزبون لا يقرأ مواقع السائقين';
  end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', drv::text, true);
  select count(*) into n from drivers;
  reset role;
  if n <> 1 then raise exception 'FAIL: السائق يقرأ % صف بدل صفه فقط', n; end if;
  raise notice 'PASS: السائق يقرأ صفه فقط';

  -- 3) تحديث الموقع يكتب driver_located_at على الرحلة الجارية
  if cust is null then cust := drv; end if;
  insert into rides (customer_id, vehicle, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone, status, driver_id)
  values (cust, 'taxi', 33.31, 44.43, 33.32, 44.44, 2.0, 5000, 'اختبار', '', 'accepted', drv)
  returning id into rid;
  select driver_located_at into before_loc from rides where id = rid;
  if before_loc is not null then raise exception 'FAIL: وقت الموقع ليس فارغاً قبل أول تحديث'; end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', drv::text, true);
  perform driver_update_location(33.3055, 44.4340);
  reset role;

  select driver_located_at, driver_lat into after_loc, lat from rides where id = rid;
  if after_loc is null or after_loc < now() - interval '1 minute' then raise exception 'FAIL: وقت الموقع لم يتحدّث'; end if;
  if lat <> 33.3055 then raise exception 'FAIL: إحداثيات الرحلة لم تتحدّث'; end if;
  raise notice 'PASS: تحديث الموقع يكتب إحداثيات ووقتها على الرحلة الجارية';
end $$;

rollback;
\echo ✔ اختبارات تحديث المواقع نجحت (وتم التراجع عن كل البيانات التجريبية)
