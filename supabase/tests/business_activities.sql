-- =====================================================================
-- اختبار أنواع النشاط القابلة للإدارة (0016). يعمل داخل transaction ويتراجع.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/business_activities.sql
-- =====================================================================
begin;

do $$
declare
  adm uuid := 'c0000001-0000-4000-8000-000000000001';
  own uuid := 'c0000002-0000-4000-8000-000000000002';
  cus uuid := 'c0000003-0000-4000-8000-000000000003';
  mid uuid := 'c0000004-0000-4000-8000-000000000004';
  m merchants; n int; msg text; newkey text := 'act_test_gym';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (adm, 'adm@acts.test', '{"full_name":"مدير","phone":"07790000001"}'),
    (own, 'own@acts.test', '{"full_name":"صاحب","phone":"07790000002"}'),
    (cus, 'cus@acts.test', '{"full_name":"زبون","phone":"07790000003"}');
  insert into user_roles (user_id, role) values (adm, 'admin'), (own, 'merchant');
  insert into merchants (id, owner_id, category_id, name, address_text, lat, lng, phone, status, business_type, activity_chosen)
  values (mid, own, 'home_services', 'ملعب الاختبار', 'بغداد', 33.31, 44.43, '07790000002', 'approved', 'store', false);

  -- 1) البزر الأولي موجود (18 نشاطاً)
  select count(*) into n from business_activities;
  if n < 18 then raise exception 'FAIL: الأنشطة الأولية ناقصة (%)', n; end if;
  raise notice 'PASS: الأنشطة الأولية محفوظة (%)', n;

  -- 2) الزبون لا يضيف نشاطاً
  perform set_config('request.jwt.claim.sub', cus::text, true);
  set local role authenticated;
  begin insert into business_activities (key, label) values ('act_hack', 'اختراق'); msg := 'none';
  exception when others then msg := sqlerrm; end;
  reset role;
  if msg = 'none' then raise exception 'FAIL: زبون أضاف نشاطاً'; end if;
  raise notice 'PASS: غير الإدارة ما يضيف نشاطاً';

  -- 3) الإدارة تضيف نشاطاً جديداً
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  insert into business_activities (key, label, group_name) values (newkey, 'نادي رياضي', 'الحجوزات والمواعيد');
  reset role;
  raise notice 'PASS: الإدارة تضيف نشاطاً';

  -- 4) نشاط جديد مفعّل يقبل اختيار صاحب الحساب
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  m := merchant_set_business_type(mid, newkey);
  reset role;
  if m.business_type <> newkey or m.activity_chosen is not true then raise exception 'FAIL: النشاط الجديد ما انحفظ'; end if;
  raise notice 'PASS: صاحب الحساب يختار النشاط الجديد';

  -- 5) الإدارة تعطّل النشاط، فيُرفض للاختيار
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  update business_activities set is_active = false where key = newkey;
  reset role;
  perform set_config('request.jwt.claim.sub', own::text, true);
  set local role authenticated;
  begin perform merchant_set_business_type(mid, newkey); msg := 'none'; exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%business_type_unknown%' then raise exception 'FAIL: نشاط معطّل قُبل (%)', msg; end if;
  raise notice 'PASS: النشاط المعطّل مرفوض للاختيار';

  -- 6) المعطّل ما يظهر للمستهلك، والإدارة ترى الكل
  perform set_config('request.jwt.claim.sub', cus::text, true);
  set local role authenticated;
  select count(*) into n from business_activities where key = newkey;
  reset role;
  if n <> 0 then raise exception 'FAIL: نشاط معطّل يظهر للزبون'; end if;
  raise notice 'PASS: النشاط المعطّل مخفي عن الزبون';

  -- 7) قيمة نوع نشاط غير مسجّلة في الجدول مرفوضة حتى من الإدارة (مفتاح أجنبي)
  begin update merchants set business_type = 'casino' where id = mid; msg := 'none';
  exception when others then msg := sqlerrm; end;
  if msg not like '%business_type%' then raise exception 'FAIL: نوع غير مسجّل قُبل (%)', msg; end if;
  raise notice 'PASS: نوع غير مسجّل مرفوض على مستوى الجدول';

  raise notice 'ALL PASS (business activities)';
end $$;

rollback;
\echo ✔ اختبارات أنواع النشاط نجحت (وتم التراجع عن البيانات التجريبية)
