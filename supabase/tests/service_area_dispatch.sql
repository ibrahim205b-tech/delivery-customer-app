-- =====================================================================
-- اختبار التوزيع الجغرافي (0011): منطقة الطلب، رفض خارج المناطق، رؤية السائق، القبول، تعديل النطاق
-- يعمل داخل transaction ويتراجع في النهاية. يعطّل كل المناطق الموجودة داخلياً لعزل النتائج.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/service_area_dispatch.sql
-- =====================================================================
begin;

do $$
declare
  cust1 uuid := 'c0000001-0000-4000-8000-000000000001';
  cust2 uuid := 'c0000002-0000-4000-8000-000000000002';
  cust3 uuid := 'c0000003-0000-4000-8000-000000000003';
  cust4 uuid := 'c0000004-0000-4000-8000-000000000004';
  taxi_a uuid := 'd0000001-0000-4000-8000-000000000001';   -- سائق تكسي في منطقة A
  taxi_b uuid := 'd0000002-0000-4000-8000-000000000002';   -- سائق تكسي في منطقة B
  courier_b uuid := 'd0000003-0000-4000-8000-000000000003'; -- مندوب في منطقة B
  area_a uuid := 'a0000001-0000-4000-8000-000000000001';
  area_b uuid := 'a0000002-0000-4000-8000-000000000002';
  r1 uuid; r2 uuid; t1 uuid; n int; got uuid; msg text;
begin
  -- عزل: تعطيل المناطق الموجودة داخل هذه المعاملة فقط
  update service_areas set is_active = false;

  -- مستخدمون (auth.users يُنشئ users تلقائياً ويعطي دور زبون)
  insert into auth.users (id, email, raw_user_meta_data) values
    (cust1, 'c1@dispatch.test', '{"full_name":"زبون 1","phone":"07730000001"}'),
    (cust2, 'c2@dispatch.test', '{"full_name":"زبون 2","phone":"07730000002"}'),
    (cust3, 'c3@dispatch.test', '{"full_name":"زبون 3","phone":"07730000003"}'),
    (cust4, 'c4@dispatch.test', '{"full_name":"زبون 4","phone":"07730000004"}'),
    (taxi_a, 'ta@dispatch.test', '{"full_name":"تكسي أ","phone":"07730000011"}'),
    (taxi_b, 'tb@dispatch.test', '{"full_name":"تكسي ب","phone":"07730000012"}'),
    (courier_b, 'cb@dispatch.test', '{"full_name":"مندوب ب","phone":"07730000013"}');

  -- منطقتان: A في الكرادة (نصف قطر 3 كم)، B بعيدة (البصرة تقريباً، نصف قطر 3 كم)
  insert into service_areas (id, name, city, center_lat, center_lng, radius_km, is_active)
  values (area_a, 'منطقة اختبار A', 'بغداد', 33.3030, 44.4350, 3, true),
         (area_b, 'منطقة اختبار B', 'البصرة', 30.5085, 47.7804, 3, true);

  insert into user_roles (user_id, role) values (taxi_a, 'driver'), (taxi_b, 'driver'), (courier_b, 'driver');
  insert into drivers (id, vehicle_type, area_id, is_active, is_available) values
    (taxi_a, 'taxi', area_a, true, true),
    (taxi_b, 'taxi', area_b, true, true),
    (courier_b, 'courier', area_b, true, true);

  -- 1) طلب داخل A ياخذ منطقة A
  perform set_config('request.jwt.claim.sub', cust1::text, true);
  set local role authenticated;
  select id into r1 from request_ride('taxi', 'الكرادة', 33.3045, 44.4365, 'المنصور', 33.3150, 44.4100) as x;
  reset role;
  select area_id into got from rides where id = r1;
  if got is distinct from area_a then raise exception 'FAIL: الطلب داخل A ما أخذ منطقة A (أخذ %)', got; end if;
  raise notice 'PASS: الطلب داخل منطقة الخدمة يأخذ منطقته';

  -- 2) طلب خارج كل المناطق مرفوض
  perform set_config('request.jwt.claim.sub', cust2::text, true);
  set local role authenticated;
  begin
    perform request_ride('taxi', 'بعيد', 31.9, 45.5, 'وجهة', 31.91, 45.51);
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%outside_service_area%' then raise exception 'FAIL: الطلب خارج المناطق لازم يُرفض (رد: %)', msg; end if;
  raise notice 'PASS: الطلب خارج مناطق الخدمة مرفوض';

  -- 3) الرؤية: سائق A يشوف الطلب، وسائق B ما يشوفه
  perform set_config('request.jwt.claim.sub', taxi_a::text, true);
  set local role authenticated;
  select count(*) into n from rides where id = r1;
  reset role;
  if n <> 1 then raise exception 'FAIL: سائق المنطقة ما يشوف الطلب'; end if;

  perform set_config('request.jwt.claim.sub', taxi_b::text, true);
  set local role authenticated;
  select count(*) into n from rides where id = r1;
  reset role;
  if n <> 0 then raise exception 'FAIL: سائق خارج المنطقة يشوف الطلب'; end if;
  raise notice 'PASS: الطلب يظهر لسائق منطقته فقط';

  -- 4) القبول: سائق B ما يقدر يقبل طلب A على الخادم
  perform set_config('request.jwt.claim.sub', taxi_b::text, true);
  set local role authenticated;
  begin
    perform driver_accept_ride(r1);
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%outside_service_area%' then raise exception 'FAIL: سائق خارج المنطقة قبل الطلب (رد: %)', msg; end if;
  raise notice 'PASS: سائق خارج المنطقة ما يقدر يقبل الطلب (حتى لو استدعى الدالة مباشرة)';

  -- 5) سائق A يقبل ويصير الطلب مشغولاً
  perform set_config('request.jwt.claim.sub', taxi_a::text, true);
  set local role authenticated;
  perform driver_accept_ride(r1);
  reset role;
  select status into msg from rides where id = r1;
  if msg <> 'accepted' then raise exception 'FAIL: القبول داخل المنطقة ما نجح'; end if;
  raise notice 'PASS: سائق المنطقة يقبل الطلب';

  -- 6) تعطيل المنطقة A: الطلبات المعلّقة فيها تختفي عن سائقيها
  perform set_config('request.jwt.claim.sub', cust3::text, true);
  set local role authenticated;
  select id into r2 from request_ride('taxi', 'الكرادة 2', 33.3040, 44.4340, 'المنصور', 33.3150, 44.4100) as x;
  reset role;
  update service_areas set is_active = false where id = area_a;
  perform set_config('request.jwt.claim.sub', taxi_a::text, true);
  set local role authenticated;
  select count(*) into n from rides where id = r2;
  reset role;
  if n <> 0 then raise exception 'FAIL: منطقة معطّلة لسا تظهر طلباتها'; end if;
  raise notice 'PASS: تعطيل المنطقة يخفي طلباتها عن سائقيها';
  update service_areas set is_active = true where id = area_a;

  -- 7) تقليص نصف القطر من الإدارة: الطلب الذي يقع خارج النطاق الجديد يُرفض
  update service_areas set radius_km = 0.5 where id = area_a;
  perform set_config('request.jwt.claim.sub', cust4::text, true);
  set local role authenticated;
  begin
    perform request_ride('taxi', 'بعيد عن المركز', 33.3300, 44.4350, 'وجهة', 33.3310, 44.4360);
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%outside_service_area%' then raise exception 'FAIL: تقليص النطاق ما منع الطلب (رد: %)', msg; end if;
  raise notice 'PASS: الإدارة تقلّص النطاق فيتغيّر القبول فوراً';

  -- 8) توصيل داخل B: المندوب يشوفه، وتكسي B ما يشوفه (المهام للمندوب والتكتك فقط)
  perform set_config('request.jwt.claim.sub', cust4::text, true);
  set local role authenticated;
  select id into t1 from create_errand('courier', 'البصرة - السوق', 30.5090, 47.7810, 'البصرة - الكورنيش', 30.5150, 47.7900,
                                        'مستند', 'ظرف ورقي', '', '') as x;
  reset role;
  select area_id into got from delivery_tasks where id = t1;
  if got is distinct from area_b then raise exception 'FAIL: التوصيل ما أخذ منطقة B'; end if;

  perform set_config('request.jwt.claim.sub', courier_b::text, true);
  set local role authenticated;
  select count(*) into n from delivery_tasks where id = t1;
  reset role;
  if n <> 1 then raise exception 'FAIL: المندوب في المنطقة ما يشوف التوصيل'; end if;

  perform set_config('request.jwt.claim.sub', taxi_b::text, true);
  set local role authenticated;
  select count(*) into n from delivery_tasks where id = t1;
  reset role;
  if n <> 0 then raise exception 'FAIL: التكسي يشوف مهمة توصيل'; end if;
  raise notice 'PASS: التوصيل يظهر لمندوب منطقته فقط، والتكسي ما يشوفه';

  -- 9) سائق بلا منطقة ما يشوف شي
  update drivers set area_id = null where id = taxi_b;
  perform set_config('request.jwt.claim.sub', taxi_b::text, true);
  set local role authenticated;
  select count(*) into n from rides where id = r2;
  reset role;
  if n <> 0 then raise exception 'FAIL: سائق بلا منطقة يشوف طلبات'; end if;
  raise notice 'PASS: السائق بلا منطقة ما يشوف طلبات';

  raise notice 'ALL PASS (dispatch)';
end $$;

rollback;
\echo ✔ اختبارات التوزيع الجغرافي نجحت (وتم التراجع عن كل البيانات التجريبية)
