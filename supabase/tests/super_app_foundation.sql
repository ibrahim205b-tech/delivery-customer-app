-- =====================================================================
-- اختبار أساس WASEL Super App (0013): الكتالوج، الرؤية، التفعيل، البحث، العمولات، نوع النشاط
-- يعمل داخل transaction ويتراجع في النهاية.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/super_app_foundation.sql
-- =====================================================================
begin;

do $$
declare
  adm uuid := 'b0000001-0000-4000-8000-000000000001';
  cust uuid := 'b0000002-0000-4000-8000-000000000002';
  n int; msg text; j jsonb;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (adm, 'adm@superapp.test', '{"full_name":"مدير","phone":"07750000001"}'),
    (cust, 'cust@superapp.test', '{"full_name":"زبون","phone":"07750000002"}');
  insert into user_roles (user_id, role) values (adm, 'admin');

  -- 1) الزبون يرى الخدمات المفعّلة فقط
  perform set_config('request.jwt.claim.sub', cust::text, true);
  set local role authenticated;
  select count(*) into n from services;
  reset role;
  if n <> (select count(*) from services where is_active) then raise exception 'FAIL: الزبون يرى خدمات معطّلة (%)', n; end if;
  raise notice 'PASS: الزبون يرى الخدمات المفعّلة فقط (%)', n;

  -- 2) الإدارة ترى الكل
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  select count(*) into n from services;
  reset role;
  if n <> (select count(*) from services) then raise exception 'FAIL: الإدارة ما ترى كل الخدمات'; end if;
  raise notice 'PASS: الإدارة ترى كل الخدمات';

  -- 3) خدمة بلا محرك تنفيذ ما تُفعَّل (لا وعد بلا تنفيذ)
  set local role authenticated;
  begin
    perform admin_update_service('jobs', true);
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%service_not_implemented%' then raise exception 'FAIL: خدمة بلا محرك فُعّلت (رد: %)', msg; end if;
  raise notice 'PASS: خدمة بلا محرك تنفيذ ما تُفعَّل';

  -- 4) تفعيل وإيقاف خدمة لها محرك ينعكس على الزبون
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  perform admin_update_service('stores', false);
  reset role;
  perform set_config('request.jwt.claim.sub', cust::text, true);
  set local role authenticated;
  select count(*) into n from services where id = 'stores';
  reset role;
  if n <> 0 then raise exception 'FAIL: خدمة موقفة لسا تظهر للزبون'; end if;
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  perform admin_update_service('stores', true);
  reset role;
  raise notice 'PASS: إيقاف الخدمة يخفيها عن الزبون، والتفعيل يعيدها';

  -- 5) غير الإدارة ما يقدر يعدّل الكتالوج
  perform set_config('request.jwt.claim.sub', cust::text, true);
  set local role authenticated;
  begin
    perform admin_update_service('stores', false);
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%forbidden%' then raise exception 'FAIL: زبون عدّل الكتالوج (رد: %)', msg; end if;
  raise notice 'PASS: الزبون ما يعدّل الكتالوج';

  -- 6) البحث الموحد: يرجّع المفعّل فقط
  perform set_config('request.jwt.claim.sub', cust::text, true);
  set local role authenticated;
  j := search_services('توصيل');
  reset role;
  if not exists (select 1 from jsonb_array_elements(j->'services') s where s->>'id' = 'parcel_delivery') then
    raise exception 'FAIL: البحث ما يرجّع توصيل الأمانات';
  end if;
  set local role authenticated;
  j := search_services('وظيفة');
  reset role;
  if jsonb_array_length(j->'services') <> 0 then raise exception 'FAIL: البحث يرجّع خدمة معطّلة (وظيفة)'; end if;
  raise notice 'PASS: البحث يرجّع الخدمات المفعّلة فقط';

  -- 7) نوع النشاط: قيمة غير معروفة مرفوضة، والمحلات القائمة مصنّفة
  insert into merchants (id, owner_id, category_id, name, address_text, lat, lng, phone, status, business_type, activity_chosen)
  values ('b0000009-0000-4000-8000-000000000009', adm, 'home_services', 'محل الاختبار', 'بغداد', 33.31, 44.43, '07750000009', 'approved', 'provider', true);
  begin
    update merchants set business_type = 'casino' where id = 'b0000009-0000-4000-8000-000000000009';
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  if msg not like '%business_type%' then raise exception 'FAIL: نوع نشاط غير معروف قُبل (رد: %)', msg; end if;
  if (select count(*) from merchants where business_type = 'provider' and category_id <> 'home_services') > 0 then
    raise exception 'FAIL: مزود خدمة خارج تصنيف الخدمات المنزلية';
  end if;
  raise notice 'PASS: نوع النشاط محكوم بقائمة معروفة، والمحلات القائمة مصنّفة';

  -- 8) العمولة لكل خدمة: قابلة للتعديل من الإدارة، والنسبة محدودة، وغير الإدارة مرفوض
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  j := admin_set_service_commission('clothing_store', 'percent', 12);
  reset role;
  if (j->>'model') <> 'percent' or (j->>'value')::numeric <> 12 then raise exception 'FAIL: حفظ العمولة ما نجح'; end if;

  set local role authenticated;
  begin perform admin_set_service_commission('clothing_store', 'percent', 80); msg := 'none';
  exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%invalid_percent%' then raise exception 'FAIL: نسبة فوق 50 قُبلت'; end if;

  perform set_config('request.jwt.claim.sub', cust::text, true);
  set local role authenticated;
  begin perform admin_set_service_commission('clothing_store', 'free', 0); msg := 'none';
  exception when others then msg := sqlerrm; end;
  reset role;
  if msg not like '%forbidden%' then raise exception 'FAIL: زبون غيّر العمولة (رد: %)', msg; end if;
  raise notice 'PASS: العمولة لكل خدمة قابلة للتعديل من الإدارة ومحدودة';

  raise notice 'ALL PASS (super app foundation)';
end $$;

rollback;
\echo ✔ اختبارات أساس Super App نجحت (وتم التراجع عن البيانات التجريبية)
