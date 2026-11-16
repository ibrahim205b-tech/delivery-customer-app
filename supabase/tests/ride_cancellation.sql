-- =====================================================================
-- اختبار إلغاء الرحلات ومنع الإساءة (0017). يعمل داخل transaction ويتراجع في النهاية.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/ride_cancellation.sql
-- التسلسل: كل سيناريو له زبون/سائق خاص به حتى لا تتداخل العدادات.
-- =====================================================================
begin;

do $$
declare
  adm uuid := 'e0000001-0000-4000-8000-000000000001';
  c1 uuid := 'e0000011-0000-4000-8000-000000000011';   -- إلغاء واحد
  c2 uuid := 'e0000012-0000-4000-8000-000000000012';   -- 9 ثم العاشر + الإيقاف
  c3 uuid := 'e0000013-0000-4000-8000-000000000013';   -- مكرر
  c4 uuid := 'e0000014-0000-4000-8000-000000000014';   -- إلغاء الإدارة
  c5 uuid := 'e0000015-0000-4000-8000-000000000015';   -- طلبات منتهية
  c6 uuid := 'e0000016-0000-4000-8000-000000000016';   -- يوم بغداد
  c7 uuid := 'e0000017-0000-4000-8000-000000000017';   -- أسباب خاطئة
  d1 uuid := 'e0000021-0000-4000-8000-000000000021';   -- سائق: إلغاء واحد
  d2 uuid := 'e0000022-0000-4000-8000-000000000022';   -- سائق: 9 ثم العاشر + الإيقاف + رفع
  d5 uuid := 'e0000025-0000-4000-8000-000000000025';   -- سائق: انتهاء الإيقاف
  d6 uuid := 'e0000026-0000-4000-8000-000000000026';   -- سائق: يوم بغداد
  area_a uuid := 'f0000001-0000-4000-8000-000000000001';
  rid uuid; rid2 uuid; n int; j int; msg text; rs user_restrictions; rr rides; span interval; cnt int;
  pickup_lat double precision := 33.3045; pickup_lng double precision := 44.4365;
begin
  update service_areas set is_active = false;
  insert into auth.users (id, email, raw_user_meta_data) values
    (adm, 'adm@cancel.test', '{"full_name":"مدير","phone":"07710000000"}'),
    (c1, 'c1@cancel.test', '{"full_name":"زبون 1","phone":"07710000011"}'),
    (c2, 'c2@cancel.test', '{"full_name":"زبون 2","phone":"07710000012"}'),
    (c3, 'c3@cancel.test', '{"full_name":"زبون 3","phone":"07710000013"}'),
    (c4, 'c4@cancel.test', '{"full_name":"زبون 4","phone":"07710000014"}'),
    (c5, 'c5@cancel.test', '{"full_name":"زبون 5","phone":"07710000015"}'),
    (c6, 'c6@cancel.test', '{"full_name":"زبون 6","phone":"07710000016"}'),
    (c7, 'c7@cancel.test', '{"full_name":"زبون 7","phone":"07710000017"}'),
    (d1, 'd1@cancel.test', '{"full_name":"سائق 1","phone":"07720000021"}'),
    (d2, 'd2@cancel.test', '{"full_name":"سائق 2","phone":"07720000022"}'),
    (d5, 'd5@cancel.test', '{"full_name":"سائق 5","phone":"07720000025"}'),
    (d6, 'd6@cancel.test', '{"full_name":"سائق 6","phone":"07720000026"}');
  insert into user_roles (user_id, role) values (adm, 'admin'), (d1, 'driver'), (d2, 'driver'), (d5, 'driver'), (d6, 'driver');
  insert into service_areas (id, name, city, center_lat, center_lng, radius_km, is_active)
  values (area_a, 'منطقة الإلغاء', 'بغداد', 33.3030, 44.4350, 3, true);
  insert into drivers (id, vehicle_type, area_id, is_active, is_available) values
    (d1, 'taxi', area_a, true, true), (d2, 'taxi', area_a, true, true),
    (d5, 'taxi', area_a, true, true), (d6, 'taxi', area_a, true, true);

  -- مساعد: طلب بحالة requested لزبون
  -- (يُنفَّذ كـ superuser لإنشاء البيانات، ثم الإلغاء يمر عبر دالة الخادم بدور authenticated)

  -- 0) توقيت بغداد: حدود اليوم
  if baghdad_day_start('2026-11-15 21:30:00+00') <> '2026-11-15 21:00:00+00' then raise exception 'FAIL: بداية يوم بغداد (بعد منتصف الليل)'; end if;
  if baghdad_day_start('2026-11-15 20:59:00+00') <> '2026-11-14 21:00:00+00' then raise exception 'FAIL: بداية يوم بغداد (قبل منتصف الليل)'; end if;
  raise notice 'PASS: يوم بغداد يبدأ 00:00 بتوقيت بغداد (21:00 UTC)';

  -- 1) زبون يلغي رحلة واحدة
  insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
  values (c1, 'taxi', area_a, 'requested', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 1', '07710000011') returning id into rid;
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  perform cancel_ride(rid, 'changed_mind', '');
  reset role;
  if cancellations_today(c1, 'customer') <> 1 then raise exception 'FAIL: عدّ الإلغاء الأول'; end if;
  if exists (select 1 from user_restrictions where user_id = c1) then raise exception 'FAIL: إيقاف بعد إلغاء واحد'; end if;
  raise notice 'PASS: زبون يلغي رحلة واحدة: عدّ 1 بلا إيقاف';

  -- 2) و 3) زبون يلغي 9 ثم العاشر: إيقاف 24 ساعة
  for j in 1..10 loop
    insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
    values (c2, 'taxi', area_a, 'requested', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 2', '07710000012') returning id into rid;
    perform set_config('request.jwt.claim.sub', c2::text, true);
    set local role authenticated;
    perform cancel_ride(rid, 'changed_mind', '');
    reset role;
    if j = 9 and exists (select 1 from user_restrictions where user_id = c2) then raise exception 'FAIL: إيقاف عند الإلغاء التاسع'; end if;
  end loop;
  select * into rs from user_restrictions where user_id = c2 and kind = 'customer_rides';
  if not found then raise exception 'FAIL: لا يوجد إيقاف بعد الإلغاء العاشر'; end if;
  span := rs.ends_at - rs.starts_at;
  if span <> interval '24 hours' then raise exception 'FAIL: مدة إيقاف الزبون (%)', span; end if;
  if not exists (select 1 from notifications where user_id = c2 and title = 'تم إيقاف طلب الرحلات مؤقتاً' and body like '%10 حالات إلغاء%') then
    raise exception 'FAIL: لا يوجد إشعار إيقاف للزبون';
  end if;
  raise notice 'PASS: الإلغاء 1..9 بلا إيقاف، والعاشر يوقف الزبون 24 ساعة مع إشعار عربي';

  -- 4) الزبون الموقوف لا يطلب رحلة
  perform set_config('request.jwt.claim.sub', c2::text, true);
  set local role authenticated;
  begin perform request_ride('taxi', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41); msg := 'none';
  exception when others then msg := sqlerrm; end;
  reset role;
  if msg <> 'customer_restricted' then raise exception 'FAIL: الزبون الموقوف طلب رحلة (%)', msg; end if;
  raise notice 'PASS: الزبون الموقوف لا يستطيع طلب رحلة (customer_restricted)';

  -- 5) بعد انتهاء المدة (وقت الخادم) يطلب رحلة
  update user_restrictions set ends_at = now() - interval '1 minute' where id = rs.id;
  perform set_config('request.jwt.claim.sub', c2::text, true);
  set local role authenticated;
  rr := request_ride('taxi', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41);
  reset role;
  if rr.customer_id <> c2 then raise exception 'FAIL: الطلب بعد الانتهاء ما نجح'; end if;
  raise notice 'PASS: بعد انتهاء الإيقاف يطلب الزبون رحلة';

  -- 6) سائق يلغي رحلة مقبولة واحدة
  insert into rides (customer_id, driver_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone, accepted_at)
  values (c5, d1, 'taxi', area_a, 'accepted', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 5', '07710000015', now()) returning id into rid;
  perform set_config('request.jwt.claim.sub', d1::text, true);
  set local role authenticated;
  perform cancel_ride(rid, 'no_answer', '');
  reset role;
  if cancellations_today(d1, 'driver') <> 1 then raise exception 'FAIL: عدّ إلغاء السائق الأول'; end if;
  if exists (select 1 from user_restrictions where user_id = d1) then raise exception 'FAIL: إيقاف سائق بعد إلغاء واحد'; end if;
  raise notice 'PASS: سائق يلغي رحلة مقبولة واحدة: عدّ 1 بلا إيقاف';

  -- 7) و 8) سائق يلغي 9 ثم العاشر: إيقاف 25 دقيقة، والحساب يبقى فعالاً
  for j in 1..10 loop
    insert into rides (customer_id, driver_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone, accepted_at)
    values (c5, d2, 'taxi', area_a, 'accepted', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 5', '07710000015', now()) returning id into rid;
    perform set_config('request.jwt.claim.sub', d2::text, true);
    set local role authenticated;
    perform cancel_ride(rid, 'no_answer', '');
    reset role;
    if j = 9 and exists (select 1 from user_restrictions where user_id = d2) then raise exception 'FAIL: إيقاف سائق عند الإلغاء التاسع'; end if;
  end loop;
  select * into rs from user_restrictions where user_id = d2 and kind = 'driver_dispatch';
  if not found then raise exception 'FAIL: لا يوجد إيقاف للسائق بعد الإلغاء العاشر'; end if;
  if rs.ends_at - rs.starts_at <> interval '25 minutes' then raise exception 'FAIL: مدة إيقاف السائق (%)', rs.ends_at - rs.starts_at; end if;
  if not exists (select 1 from users where id = d2 and is_active) then raise exception 'FAIL: السائق تعطّل حسابه نهائياً'; end if;
  if not exists (select 1 from notifications where user_id = d2 and body like '%25 دقيقة%') then raise exception 'FAIL: لا يوجد إشعار إيقاف للسائق'; end if;
  raise notice 'PASS: السائق يلغي 1..9 بلا إيقاف، والعاشر يوقفه 25 دقيقة بلا تعطيل الحساب';

  -- 9) السائق الموقوف لا يقبل رحلة جديدة
  insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
  values (c3, 'taxi', area_a, 'requested', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 3', '07710000013') returning id into rid2;
  perform set_config('request.jwt.claim.sub', d2::text, true);
  set local role authenticated;
  begin perform driver_accept_ride(rid2); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg <> 'driver_restricted' then raise exception 'FAIL: السائق الموقوف قبل رحلة (%)', msg; end if;
  raise notice 'PASS: السائق الموقوف لا يستقبل رحلات جديدة (driver_restricted)';

  -- 10) بعد انتهاء المدة يعود يستقبل الطلبات تلقائياً
  update user_restrictions set ends_at = now() - interval '1 second' where id = rs.id;
  perform set_config('request.jwt.claim.sub', d2::text, true);
  set local role authenticated;
  rr := driver_accept_ride(rid2);
  reset role;
  if rr.status <> 'accepted' or rr.driver_id <> d2 then raise exception 'FAIL: السائق ما رجع يستقبل بعد الانتهاء'; end if;
  raise notice 'PASS: السائق يستقبل الطلبات تلقائياً بعد انتهاء الإيقاف';

  -- 11) طلب مكرر لا يزيد العدّ
  insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
  values (c3, 'taxi', area_a, 'requested', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 3', '07710000013') returning id into rid;
  perform set_config('request.jwt.claim.sub', c3::text, true);
  set local role authenticated;
  perform cancel_ride(rid, 'changed_mind', '');
  begin perform cancel_ride(rid, 'changed_mind', ''); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg <> 'ride_already_cancelled' then raise exception 'FAIL: الإلغاء المكرر ما انرفض (%)', msg; end if;
  if cancellations_today(c3, 'customer') <> 1 then raise exception 'FAIL: الإلغاء المكرر زاد العدّ'; end if;
  raise notice 'PASS: الإلغاء المكرر يُرفض ولا يزيد العدّ';

  -- 12) إلغاء الإدارة لا يُعدّ على أحد (10 مرات)
  for j in 1..10 loop
    insert into rides (customer_id, driver_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone, accepted_at)
    values (c4, d6, 'taxi', area_a, 'accepted', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 4', '07710000014', now()) returning id into rid;
    perform set_config('request.jwt.claim.sub', adm::text, true);
    set local role authenticated;
    perform admin_cancel_ride(rid, 'تحقيق في بلاغ');
    reset role;
  end loop;
  if cancellations_today(c4, 'customer') <> 0 or cancellations_today(d6, 'driver') <> 0 then raise exception 'FAIL: إلغاء الإدارة عُدّ على أحد'; end if;
  if exists (select 1 from user_restrictions where user_id in (c4, d6)) then raise exception 'FAIL: إلغاء الإدارة أوقف حساباً'; end if;
  if (select count(*) from admin_audit_log where action = 'ride.cancel' and actor_id = adm) < 10 then raise exception 'FAIL: سجل التدقيق ما سجّل إلغاءات الإدارة'; end if;
  raise notice 'PASS: إلغاء الإدارة (10 مرات) لا يُعد على زبون أو سائق، ويُسجَّل في التدقيق';

  -- 13) الطلبات المنتهية لا تُعد على السائق
  insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone, created_at)
  values (c6, 'taxi', area_a, 'requested', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 6', '07710000016', now() - interval '30 minutes') returning id into rid;
  insert into rides (customer_id, driver_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone, accepted_at, created_at)
  values (c6, d5, 'taxi', area_a, 'accepted', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 6', '07710000016', now(), now() - interval '30 minutes') returning id into rid2;
  n := expire_stale_ride_requests();
  if not exists (select 1 from rides where id = rid and status = 'cancelled')
     or not exists (select 1 from ride_cancellations where ride_id = rid and party = 'system') then
    raise exception 'FAIL: الطلب المنتهي ما انتهى';
  end if;
  if (select status from rides where id = rid2) <> 'accepted' then raise exception 'FAIL: انتهى طلب مقبول بالخطأ'; end if;
  if cancellations_today(c6, 'customer') <> 0 then raise exception 'FAIL: الطلب المنتهي عُدّ على الزبون'; end if;
  -- السائق لا يلغي رحلة غير معيّنة له
  perform set_config('request.jwt.claim.sub', d5::text, true);
  set local role authenticated;
  begin perform cancel_ride((select id from rides where customer_id = c6 and status = 'requested' limit 1), 'no_answer', ''); msg := 'none';
  exception when others then msg := sqlerrm; end;
  reset role;
  if msg = 'none' then raise exception 'FAIL: السائق ألغى رحلة غير معيّنة له'; end if;
  if cancellations_today(d5, 'driver') <> 0 then raise exception 'FAIL: السائق عُدّ بلا تعيين'; end if;
  raise notice 'PASS: الطلب المنتهي لا يُعد على أحد، والسائق لا يلغي رحلة غير معيّنة';

  -- 14) يوم بغداد: إلغاءات الأمس لا تُحسب اليوم
  for j in 1..9 loop
    insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
    values (c7, 'taxi', area_a, 'cancelled', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 7', '07710000017') returning id into rid;
    insert into ride_cancellations (ride_id, party, responsible_id, reason_code, reason_label, ride_status_before, cancelled_at)
    values (rid, 'customer', c7, 'changed_mind', 'غيرت رأيي.', 'requested', baghdad_day_start() - interval '1 minute');
  end loop;
  if cancellations_today(c7, 'customer') <> 0 then raise exception 'FAIL: إلغاءات الأمس حُسبت اليوم'; end if;
  for j in 1..9 loop
    insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
    values (c7, 'taxi', area_a, 'requested', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 7', '07710000017') returning id into rid;
    perform set_config('request.jwt.claim.sub', c7::text, true);
    set local role authenticated;
    perform cancel_ride(rid, 'changed_mind', '');
    reset role;
  end loop;
  if cancellations_today(c7, 'customer') <> 9 then raise exception 'FAIL: عدّ اليوم بعد 9 إلغاءات (%)', cancellations_today(c7, 'customer'); end if;
  if exists (select 1 from user_restrictions where user_id = c7) then raise exception 'FAIL: 9 إلغاءات اليوم + إلغاءات الأمس أوقفت الزبون'; end if;
  raise notice 'PASS: إلغاءات الأمس لا تُحسب اليوم (9 اليوم بلا إيقاف رغم 18 إجمالاً)';

  -- 14b) نفس الشيء للسائق: 9 اليوم + الأمس لا يوقف
  for j in 1..9 loop
    insert into rides (customer_id, driver_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone, accepted_at)
    values (c7, d6, 'taxi', area_a, 'cancelled', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 7', '07710000017', now()) returning id into rid;
    insert into ride_cancellations (ride_id, party, responsible_id, reason_code, reason_label, ride_status_before, cancelled_at)
    values (rid, 'driver', d6, 'no_answer', 'الزبون لا يرد على الاتصال.', 'accepted', baghdad_day_start() - interval '5 minutes');
  end loop;
  for j in 1..9 loop
    insert into rides (customer_id, driver_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone, accepted_at)
    values (c7, d6, 'taxi', area_a, 'accepted', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 7', '07710000017', now()) returning id into rid;
    perform set_config('request.jwt.claim.sub', d6::text, true);
    set local role authenticated;
    perform cancel_ride(rid, 'no_answer', '');
    reset role;
  end loop;
  if exists (select 1 from user_restrictions where user_id = d6) then raise exception 'FAIL: إلغاءات أمس السائق أوقفته اليوم'; end if;
  raise notice 'PASS: إلغاءات سائق الأمس لا تُحسب اليوم';

  -- 15) أسباب خاطئة أو ملاحظة ناقصة مرفوضة، والإلغاء القديم بلا سبب مرفوض
  insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
  values (c7, 'taxi', area_a, 'requested', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 7', '07710000017') returning id into rid;
  perform set_config('request.jwt.claim.sub', c7::text, true);
  set local role authenticated;
  begin perform cancel_ride(rid, 'no_answer', ''); msg := 'none'; exception when others then msg := sqlerrm; end;
  if msg <> 'invalid_cancel_reason' then raise exception 'FAIL: سبب سائق قُبل من الزبون (%)', msg; end if;
  begin perform cancel_ride(rid, 'other', ''); msg := 'none'; exception when others then msg := sqlerrm; end;
  if msg <> 'note_required' then raise exception 'FAIL: سبب آخر بلا ملاحظة قُبل (%)', msg; end if;
  begin perform customer_cancel_ride(rid); msg := 'none'; exception when others then msg := sqlerrm; end;
  if msg <> 'cancel_reason_required' then raise exception 'FAIL: الإلغاء القديم بلا سبب قُبل (%)', msg; end if;
  perform cancel_ride(rid, 'other', 'تغيّر موعدي فجأة');
  reset role;
  raise notice 'PASS: السبب الخاطئ والملاحظة الناقصة والإلغاء القديم مرفوضة، و"سبب آخر" مع ملاحظة يُقبل';

  -- 16) الإدارة ترفع الإيقاف (مع سبب) ويُسجَّل في التدقيق
  -- إيقاف نشط جديد لسائق 5 (زُرع مباشرة لأن إيقاف d2 انتهى في الخطوة 10)
  insert into user_restrictions (user_id, kind, trigger_count, day_start, starts_at, ends_at, reason)
  values (d5, 'driver_dispatch', 10, baghdad_day_start(), now(), now() + interval '25 minutes', 'اختبار الرفع');
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  begin perform admin_lift_restriction((select id from user_restrictions where user_id = d5 and lifted_at is null), 'ok'); msg := 'none';
  exception when others then msg := sqlerrm; end;
  reset role;
  if msg <> 'reason_required' then raise exception 'FAIL: رفع الإيقاف قُبل بدون سبب كافٍ (%)', msg; end if;
  -- إيقاف منتهٍ يُرفض
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  begin perform admin_lift_restriction((select id from user_restrictions where user_id = d2 and kind = 'driver_dispatch' order by starts_at desc limit 1), 'تم التحقق من السائق'); msg := 'none';
  exception when others then msg := sqlerrm; end;
  reset role;
  if msg <> 'restriction_not_active' then raise exception 'FAIL: رفع إيقاف منتهٍ قُبل (%)', msg; end if;
  -- إيقاف نشط يُرفع، ثم يقبل السائق رحلة فوراً
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  perform admin_lift_restriction((select id from user_restrictions where user_id = d5 and lifted_at is null), 'تم التحقق من السائق');
  reset role;
  if not exists (select 1 from admin_audit_log where action = 'restriction.lift' and actor_id = adm) then raise exception 'FAIL: الرفع ما سُجّل في التدقيق'; end if;
  if not exists (select 1 from notifications where user_id = d5 and title = 'تم رفع الإيقاف عن حسابك') then raise exception 'FAIL: لا إشعار برفع الإيقاف'; end if;
  insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
  values (c6, 'taxi', area_a, 'requested', 'a', pickup_lat, pickup_lng, 'b', 33.315, 44.41, 3, 5000, 'زبون 6', '07710000016') returning id into rid2;
  update rides set status = 'completed' where driver_id = d5 and status = 'accepted';
  perform set_config('request.jwt.claim.sub', d5::text, true);
  set local role authenticated;
  rr := driver_accept_ride(rid2);
  reset role;
  if rr.driver_id <> d5 then raise exception 'FAIL: السائق بعد الرفع ما قبل الرحلة'; end if;
  raise notice 'PASS: رفع الإيقاف يحتاج سبباً، والمنتهي يُرفض، والنشط يُرفع ويعود السائق للعمل فوراً';

  -- 17) غير الإدارة ما يرفع إيقافاً ولا يلغي بالإدارة
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  begin perform admin_cancel_ride(rid, 'محاولة'); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%forbidden%' then raise exception 'FAIL: زبون ألغى بصلاحية الإدارة (%)', msg; end if;
  raise notice 'PASS: غير الإدارة لا يلغي بصلاحية الإدارة';

  raise notice 'ALL PASS (ride cancellation: customer, driver, admin, expiry, timezone)';
end $$;

rollback;
\echo ✔ اختبارات إلغاء الرحلات نجحت (وتم التراجع عن البيانات التجريبية)
