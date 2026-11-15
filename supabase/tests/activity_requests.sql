-- =====================================================================
-- اختبار اختيار النشاط + الطلب العام (0015). يعمل داخل transaction ويتراجع.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/activity_requests.sql
-- =====================================================================
begin;

do $$
declare
  adm uuid := 'a1000001-0000-4000-8000-000000000001';
  own uuid := 'a1000002-0000-4000-8000-000000000002';
  oth uuid := 'a1000003-0000-4000-8000-000000000003';
  cus uuid := 'a1000004-0000-4000-8000-000000000004';
  mid uuid := 'a1000005-0000-4000-8000-000000000005';
  r service_requests; m merchants; n int; msg text;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (adm, 'adm@activity.test', '{"full_name":"مدير","phone":"07780000001"}'),
    (own, 'own@activity.test', '{"full_name":"صاحب خدمة","phone":"07780000002"}'),
    (oth, 'oth@activity.test', '{"full_name":"غريب","phone":"07780000003"}'),
    (cus, 'cus@activity.test', '{"full_name":"زبون","phone":"07780000004"}');
  insert into user_roles (user_id, role) values (adm, 'admin'), (own, 'merchant'), (oth, 'merchant');

  -- صاحب خدمة جديد لم يختر نشاطه بعد
  insert into merchants (id, owner_id, category_id, name, address_text, lat, lng, phone, status, business_type, activity_chosen)
  values (mid, own, 'home_services', 'مصور الاختبار', 'بغداد', 33.31, 44.43, '07780000002', 'approved', 'store', false);

  -- 1) صاحب الحساب يختار نشاطه بنفسه
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  m := merchant_set_business_type(mid, 'photographer');
  reset role;
  if m.business_type <> 'photographer' or m.activity_chosen is not true then raise exception 'FAIL: اختيار النشاط ما انحفظ'; end if;
  raise notice 'PASS: صاحب الحساب يختار نشاطه ويُحفظ';

  -- 2) حساب غريب ما يغيّر النشاط
  perform set_config('request.jwt.claim.sub', oth::text, true);
  set local role authenticated;
  begin perform merchant_set_business_type(mid, 'store'); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%forbidden%' then raise exception 'FAIL: غريب غيّر النشاط (%)', msg; end if;
  raise notice 'PASS: حساب غير مالك لا يغيّر النشاط';

  -- 3) نوع نشاط غير معروف مرفوض
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  begin perform merchant_set_business_type(mid, 'casino'); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg = 'none' then raise exception 'FAIL: نوع نشاط غير معروف قُبل'; end if;
  raise notice 'PASS: نوع النشاط المجهول مرفوض';

  -- 4) تفعيل خدمة التصوير (محركها الطلب العام)
  update services set engine = 'booking' where id = 'photographers';
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  perform admin_update_service('photographers', true);
  reset role;

  -- 5) الزبون يطلب تصويراً مع تفاصيل (مصور بنفس النشاط)
  perform set_config('request.jwt.claim.sub', cus::text, true);
  set local role authenticated;
  r := svc_create_request('photographers', mid, '{"type":"عرس","date":"2026-12-01"}'::jsonb, '22222222-2222-4222-8222-222222222222');
  reset role;
  if r.status <> 'requested' or r.provider_id <> mid then raise exception 'FAIL: الطلب العام ما انحفظ'; end if;
  raise notice 'PASS: الزبون يطلب خدمة من مقدم بالنشاط المناسب';

  -- 6) مقدم بنشاط غير مناسب مرفوض
  reset role;
  update merchants set business_type = 'clinic' where id = mid;
  perform set_config('request.jwt.claim.sub', cus::text, true);
  set local role authenticated;
  begin perform svc_create_request('photographers', mid, '{"type":"x"}'::jsonb, null); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  update merchants set business_type = 'photographer' where id = mid;
  if msg not like '%provider_not_for_service%' then raise exception 'FAIL: مقدم بنشاط غير مناسب قُبل (%)', msg; end if;
  raise notice 'PASS: مقدم بنشاط غير مناسب يُرفض';

  -- 7) طلب بلا تفاصيل مرفوض
  perform set_config('request.jwt.claim.sub', cus::text, true);
  set local role authenticated;
  begin perform svc_create_request('photographers', mid, '{}'::jsonb, null); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%payload_required%' then raise exception 'FAIL: طلب فارغ قُبل'; end if;
  raise notice 'PASS: الطلب بلا تفاصيل مرفوض';

  -- 8) مقدم الخدمة يحدد السعر ثم يقبل
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  r := service_set_amount(r.id, 75000);
  r := service_respond(r.id, true);
  reset role;
  if r.amount <> 75000 or r.status <> 'accepted' then raise exception 'FAIL: السعر أو القبول ما نجح'; end if;
  raise notice 'PASS: مقدم الخدمة يحدد السعر ويقبل';

  -- 9) لا يتغير النشاط والطلب مفتوح (مقبول)
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  begin perform merchant_set_business_type(mid, 'store'); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%open_requests%' then raise exception 'FAIL: تغيّر النشاط مع طلب مفتوح (%)', msg; end if;
  raise notice 'PASS: لا يتغير النشاط والطلب مفتوح';

  -- 10) الزبون يرى المقدمين المناسبين للخدمة فقط
  perform set_config('request.jwt.claim.sub', cus::text, true);
  set local role authenticated;
  select count(*) into n from providers_for_service('photographers');
  reset role;
  if n < 1 then raise exception 'FAIL: لا يظهر المصور للزبون'; end if;
  raise notice 'PASS: الزبون يرى المقدمين المناسبين للخدمة';

  raise notice 'ALL PASS (activity + generic requests)';
end $$;

rollback;
\echo ✔ اختبارات اختيار النشاط والطلب العام نجحت (وتم التراجع عن البيانات التجريبية)
