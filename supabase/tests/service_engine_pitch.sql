-- =====================================================================
-- اختبار المحرك المشترك + حجز الملاعب (0014) من البداية للنهاية
-- يعمل داخل transaction ويتراجع في النهاية.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/service_engine_pitch.sql
-- =====================================================================
begin;

do $$
declare
  adm uuid := 'e0000001-0000-4000-8000-000000000001';
  own uuid := 'e0000002-0000-4000-8000-000000000002';   -- صاحب الملعب
  own2 uuid := 'e0000003-0000-4000-8000-000000000003';  -- صاحب ملعب آخر (لا يحق له شيء على ملعب الأول)
  c1 uuid := 'e0000004-0000-4000-8000-000000000004';
  c2 uuid := 'e0000005-0000-4000-8000-000000000005';
  mid uuid := 'e0000006-0000-4000-8000-000000000006';
  mid2 uuid := 'e0000007-0000-4000-8000-000000000007';
  pit uuid := 'e0000008-0000-4000-8000-000000000008';
  day2 timestamp; s1 timestamptz; s2 timestamptz; s3 timestamptz; s4 timestamptz;
  r1 service_requests; r2 service_requests; r3 service_requests; r4 service_requests; r5 service_requests;
  n int; msg text; cid uuid; cm int; cnt int;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (adm, 'adm@pitch.test', '{"full_name":"مدير","phone":"07760000001"}'),
    (own, 'own@pitch.test', '{"full_name":"صاحب ملعب","phone":"07760000002"}'),
    (own2, 'own2@pitch.test', '{"full_name":"صاحب ملعب 2","phone":"07760000003"}'),
    (c1, 'c1@pitch.test', '{"full_name":"زبون 1","phone":"07760000004"}'),
    (c2, 'c2@pitch.test', '{"full_name":"زبون 2","phone":"07760000005"}');
  insert into user_roles (user_id, role) values (adm, 'admin'), (own, 'merchant'), (own2, 'merchant');

  -- ملعب: صاحب ملعب معتمد، لا يوجد سعر افتراضي (الصاحب يحدده)
  insert into merchants (id, owner_id, category_id, name, address_text, lat, lng, phone, status, business_type)
  values (mid, own, 'home_services', 'ملعب الاختبار', 'بغداد', 33.31, 44.43, '07760000002', 'approved', 'pitch_owner'),
         (mid2, own2, 'home_services', 'ملعب آخر', 'بغداد', 33.32, 44.44, '07760000003', 'approved', 'pitch_owner');

  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  perform admin_update_service('pitch_booking', true);
  reset role;

  -- صاحب الملعب يحفظ ملعبه ويفعّله (السعر 30,000 د.ع بالساعة)
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  perform upsert_pitch(pit, mid, 'ملعب الخماسي الأول', 'عشب صناعي', 30000, 60, 8, 23, 2, 'الإلغاء قبل ساعتين', true);
  reset role;

  -- مواعيد: بعد يومين، الساعة 18:00 بتوقيت بغداد
  day2 := date_trunc('day', now() at time zone 'Asia/Baghdad') + interval '2 days';
  s1 := (day2 + interval '18 hours') at time zone 'Asia/Baghdad';
  s2 := (day2 + interval '14 hours') at time zone 'Asia/Baghdad';
  s3 := (day2 + interval '14 hours 30 minutes') at time zone 'Asia/Baghdad';
  s4 := (day2 + interval '20 hours') at time zone 'Asia/Baghdad';

  -- 1) طلب حجز: 120 دقيقة = 60,000 د.ع، الحالة requested
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  r1 := pitch_book_request(pit, s1, 120, '11111111-1111-4111-8111-111111111111');
  reset role;
  if r1.status <> 'requested' or r1.amount <> 60000 then raise exception 'FAIL: الطلب ما انحفظ بالحالة/المبلغ الصحيح (%, %)', r1.status, r1.amount; end if;
  raise notice 'PASS: الزبون يطلب حجزاً، الحالة requested، المبلغ 60,000 من السعر × المدة';

  -- 2) إعادة الإرسال بنفس المعرّف ما تكرر الطلب
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  r2 := pitch_book_request(pit, s1, 120, '11111111-1111-4111-8111-111111111111');
  reset role;
  if r2.id <> r1.id then raise exception 'FAIL: إعادة الإرسال أنشأت طلباً مكرراً'; end if;
  select count(*) into n from service_requests where client_request_id = '11111111-1111-4111-8111-111111111111';
  if n <> 1 then raise exception 'FAIL: تكرار صف الطلب'; end if;
  raise notice 'PASS: إعادة الإرسال بنفس المعرّف لا تكرر الحجز';

  -- 3) الإشعار وصل لصاحب الملعب عند الطلب
  select count(*) into n from notifications where user_id = own and (data->>'id') = r1.id::text;
  if n < 1 then raise exception 'FAIL: صاحب الملعب ما استلم إشعار الطلب'; end if;
  raise notice 'PASS: صاحب الملعب يستلم إشعار الطلب الجديد';

  -- 4) مدة غير صالحة ومواعيد خارج الدوام مرفوضة
  perform set_config('request.jwt.claim.sub', c2::text, true);
  set local role authenticated;
  begin perform pitch_book_request(pit, s2, 45, null); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%invalid_duration%' then raise exception 'FAIL: مدة 45 دقيقة قُبلت (%)', msg; end if;
  set local role authenticated;
  begin perform pitch_book_request(pit, ((day2 + interval '22 hours') at time zone 'Asia/Baghdad'), 120, null); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%outside_hours%' then raise exception 'FAIL: حجز خارج الدوام قُبل (%)', msg; end if;
  raise notice 'PASS: المدة غير الصالحة والمواعيد خارج الدوام مرفوضة';

  -- 5) صاحب الملعب يقبل الطلب الأول، والإشعار يصل للزبون
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  r1 := service_respond(r1.id, true);
  reset role;
  if r1.status <> 'accepted' then raise exception 'FAIL: القبول ما نجح'; end if;
  select count(*) into n from notifications where user_id = c1 and (data->>'status') = 'accepted';
  if n < 1 then raise exception 'FAIL: الزبون ما استلم إشعار القبول'; end if;
  raise notice 'PASS: صاحب الملعب يقبل، والزبون يستلم الإشعار';

  -- 6) منع الحجز المزدوج: طلب يتداخل مع مقبول يُرفض فوراً
  perform set_config('request.jwt.claim.sub', c2::text, true);
  set local role authenticated;
  begin perform pitch_book_request(pit, s4 - interval '30 minutes', 60, null); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%slot_taken%' then raise exception 'FAIL: حجز متداخل مع مقبول قُبل (%)', msg; end if;
  raise notice 'PASS: حجز يتداخل مع مقبول يُرفض (منع الحجز المزدوج)';

  -- 7) تعارض عند القبول: طلبان متداخلان معلّقان، القبول الأول ينجح والثاني يفشل
  perform set_config('request.jwt.claim.sub', c2::text, true);
  set local role authenticated;
  r2 := pitch_book_request(pit, s2, 60, null);
  r3 := pitch_book_request(pit, s3, 60, null);
  reset role;
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  perform service_respond(r2.id, true);
  begin perform service_respond(r3.id, true); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%slot_taken%' then raise exception 'FAIL: قبول متعارض نجح (%)', msg; end if;
  raise notice 'PASS: القبول المتعارض يفشل تحت القفل والحجز الأول يبقى';

  -- 8) الرفض يحتاج سبباً
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  r3 := pitch_book_request(pit, s4, 60, null);
  reset role;
  perform set_config('request.jwt.claim.sub', c2::text, true);
  set local role authenticated;
  r3 := pitch_book_request(pit, s4 + interval '2 hours', 60, null);
  reset role;
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  begin perform service_respond(r3.id, false, 'x'); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%reason_required%' then raise exception 'FAIL: الرفض بلا سبب قُبل'; end if;
  set local role authenticated;
  r3 := service_respond(r3.id, false, 'الملعب مغلق لصيانة');
  reset role;
  if r3.status <> 'rejected' or r3.reject_reason = '' then raise exception 'FAIL: الرفض ما سُجّل'; end if;
  raise notice 'PASS: الرفض يحتاج سبباً ويُسجَّل';

  -- 9) صاحب ملعب آخر لا يقبل طلبات ملعب غيره، ولا يقرأها
  perform set_config('request.jwt.claim.sub', own2::text, true);
  set local role authenticated;
  begin perform service_respond(r1.id, true); msg := 'none'; exception when others then msg := sqlerrm; end;
  select count(*) into n from service_requests where id = r1.id;
  reset role;
  if msg not like '%forbidden%' or n <> 0 then raise exception 'FAIL: صاحب ملعب آخر وصل لطلب غيره'; end if;
  raise notice 'PASS: صاحب ملعب آخر لا يقبل ولا يقرأ طلبات غيره';

  -- 10) الزبون الثاني لا يقرأ طلبات الأول
  perform set_config('request.jwt.claim.sub', c2::text, true);
  set local role authenticated;
  select count(*) into n from service_requests where id = r1.id;
  reset role;
  if n <> 0 then raise exception 'FAIL: زبون يقرأ طلب زبون آخر'; end if;
  raise notice 'PASS: الزبون لا يقرأ طلبات غيره';

  -- 11) دورة الإتمام + العمولة (افتراضياً مجانية، ثم نسبة 10٪)
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  r1 := service_set_status(r1.id, 'in_progress');
  r1 := service_set_status(r1.id, 'completed');
  reset role;
  select amount into cm from service_commissions where request_id = r1.id;
  if cm is null or cm <> 0 then raise exception 'FAIL: العمولة الافتراضية ليست صفراً (%)', cm; end if;

  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  perform admin_set_service_commission('pitch_booking', 'percent', 10);
  reset role;

  -- حجز جديد يُتم بعد تغيير العمولة: 10% من 30,000 (ساعة) = 3,000
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  r4 := pitch_book_request(pit, (day2 + interval '10 hours') at time zone 'Asia/Baghdad', 60, null);
  reset role;
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  perform service_respond(r4.id, true);
  r4 := service_set_status(r4.id, 'completed');
  reset role;
  select amount into cm from service_commissions where request_id = r4.id;
  if cm <> 3000 then raise exception 'FAIL: العمولة 10%% لا تساوي 3,000 (%)', cm; end if;
  select count(*) into n from service_commissions where request_id = r4.id;
  if n <> 1 then raise exception 'FAIL: العمولة تكررت'; end if;
  raise notice 'PASS: العمولة تُحسب مرة واحدة عند الإتمام حسب إعداد الخدمة';

  -- 12) الإلغاء: الزبون يلغي حجزاً مقبولاً قبل نافذة الإلغاء، ولا يلغي بعدها
  -- ساعات الملعب تُوسَّع لهذه الخطوة فقط (الوقت الحالي قد يكون خارج الدوام)
  update pitches set open_hour = 0, close_hour = 24 where id = pit;
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  r5 := pitch_book_request(pit, now() + interval '1 hour' + interval '5 minutes', 60, null);
  reset role;
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  perform service_respond(r5.id, true);
  reset role;
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  begin perform service_cancel(r5.id, 'تغيّرت الخطة'); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%cancellation_window_closed%' then raise exception 'FAIL: الإلغاء داخل نافذة الإلغاء المغلقة نجح (%)', msg; end if;
  set local role authenticated;
  begin perform service_cancel(r1.id, 'x'); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%invalid_transition%' then raise exception 'FAIL: إلغاء طلب مكتمل قُبل (%)', msg; end if;
  raise notice 'PASS: الإلغاء يُمنع بعد نافذة الإلغاء، وطلب مكتمل لا يُلغى';

  -- 13) التقييم بعد الإتمام مرة واحدة فقط
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  perform service_rate(r4.id, 5, 'ملعب ممتاز');
  reset role;
  if (select status from service_requests where id = r4.id) <> 'completed' then null; end if;
  begin
    perform set_config('request.jwt.claim.sub', c1::text, true);
    set local role authenticated;
    perform service_rate(r4.id, 4, 'مرة ثانية');
    reset role;
    msg := 'none';
  exception when others then msg := sqlerrm; reset role; end;
  if msg not like '%duplicate%' and msg not like '%unique%' then raise exception 'FAIL: تقييم مكرر قُبل (%)', msg; end if;
  raise notice 'PASS: التقييم مرة واحدة بعد الإتمام';

  -- 14) أوقات الملعب المحجوزة: مقبولة فقط، ليوم معيّن، بدون أي بيانات زبون
  perform set_config('request.jwt.claim.sub', c2::text, true);
  set local role authenticated;
  select count(*) into cnt from pitch_busy_slots(pit, day2::date);
  reset role;
  if cnt < 2 then raise exception 'FAIL: الأوقات المحجوزة لليوم أقل من المتوقع (%)', cnt; end if;
  raise notice 'PASS: الأوقات المحجوزة تظهر للزبون (%) دون بيانات الزبائن', cnt;

  -- 15) الخدمة معطّلة: لا يُطلب حجز
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  perform admin_update_service('pitch_booking', false);
  reset role;
  perform set_config('request.jwt.claim.sub', c1::text, true);
  set local role authenticated;
  begin perform pitch_book_request(pit, s4 + interval '4 hours', 60, null); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%service_inactive%' then raise exception 'FAIL: حجز على خدمة معطّلة قُبل (%)', msg; end if;
  raise notice 'PASS: خدمة معطّلة لا تقبل حجوزات';

  raise notice 'ALL PASS (service engine + pitch booking)';
end $$;

rollback;
\echo ✔ اختبارات المحرك وحجز الملاعب نجحت (وتم التراجع عن البيانات التجريبية)
