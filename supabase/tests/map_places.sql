-- =====================================================================
-- اختبار نقاط الاستدلال (0012): لا اعتماد تلقائي، الرفض يحتاج سبباً، عزل المسودات، لا كتابة مباشرة
-- يعمل داخل transaction ويتراجع في النهاية.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/map_places.sql
-- =====================================================================
begin;

do $$
declare
  adm uuid := 'f0000001-0000-4000-8000-000000000001';
  u1 uuid := 'f0000002-0000-4000-8000-000000000002';
  u2 uuid := 'f0000003-0000-4000-8000-000000000003';
  p1 map_places; p2 map_places; n int; msg text; st text;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (adm, 'adm@places.test', '{"full_name":"مدير","phone":"07740000001"}'),
    (u1, 'u1@places.test', '{"full_name":"مستخدم 1","phone":"07740000002"}'),
    (u2, 'u2@places.test', '{"full_name":"مستخدم 2","phone":"07740000003"}');
  insert into user_roles (user_id, role) values (adm, 'admin');

  -- 1) الاقتراح يدخل كمسودة دائماً (حتى لو المستخدم أرسل status)
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  select * into p1 from suggest_map_place('جسر الكرادة الجديد', 'landmark', 33.3050, 44.4300, 'معلم قريب من المحطة');
  reset role;
  if p1.status <> 'draft' then raise exception 'FAIL: الاقتراح ما دخل كمسودة'; end if;
  raise notice 'PASS: الاقتراح يدخل كمسودة ولا يُعتمد تلقائياً';

  -- 2) المستخدم يشوف مسودته، والآخر ما يشوفها
  perform set_config('request.jwt.claim.sub', u2::text, true);
  set local role authenticated;
  select count(*) into n from map_places where id = p1.id;
  reset role;
  if n <> 0 then raise exception 'FAIL: مستخدم آخر يشوف مسودة غيره'; end if;
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  select count(*) into n from map_places where id = p1.id;
  reset role;
  if n <> 1 then raise exception 'FAIL: صاحب المسودة ما يشوفها'; end if;
  raise notice 'PASS: المسودة مرئية لصاحبها فقط';

  -- 3) الكتابة المباشرة ممنوعة
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  begin
    insert into map_places (name_ar, kind, lat, lng, status) values ('تزوير', 'landmark', 33.3, 44.4, 'approved');
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%permission denied%' then raise exception 'FAIL: الكتابة المباشرة مسموحة (رد: %)', msg; end if;
  raise notice 'PASS: لا كتابة مباشرة على الجدول';

  -- 4) المستخدم العادي ما يقدر يعتمد
  perform set_config('request.jwt.claim.sub', u1::text, true);
  set local role authenticated;
  begin
    perform admin_review_map_place(p1.id, 'approved', '');
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%forbidden%' then raise exception 'FAIL: مستخدم عادي اعتمد نقطة (رد: %)', msg; end if;
  raise notice 'PASS: المستخدم العادي ما يعتمد';

  -- 5) الرفض يحتاج سبباً
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  begin
    perform admin_review_map_place(p1.id, 'rejected', 'x');
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%reason_required%' then raise exception 'FAIL: الرفض بلا سبب مقبول (رد: %)', msg; end if;
  raise notice 'PASS: الرفض يحتاج سبباً مكتوباً';

  -- 6) الإدارة تراجع: اعتماد يسجّل المراجع والوقت
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  select * into p1 from admin_review_map_place(p1.id, 'approved', '');
  reset role;
  if p1.status <> 'approved' or p1.reviewed_by <> adm or p1.reviewed_at is null then raise exception 'FAIL: الاعتماد ما سجّل المراجع'; end if;
  raise notice 'PASS: الإدارة تعتمد وتسجّل المراجع والوقت';

  -- 7) المعتمدة مرئية للجميع
  perform set_config('request.jwt.claim.sub', u2::text, true);
  set local role authenticated;
  select count(*) into n from map_places where id = p1.id;
  reset role;
  if n <> 1 then raise exception 'FAIL: النقطة المعتمدة ما تظهر لمستخدم آخر'; end if;
  raise notice 'PASS: النقطة المعتمدة تظهر للمستخدمين';

  -- 8) تعديل نقطة معتمدة يعيدها لمسودة (لا نعتمد تغييراً لم نراجعه)
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  select * into p2 from admin_save_map_place(p1.id, 'جسر الكرادة (مُعدّل)', 'landmark', 33.3055, 44.4305, 'تعديل');
  reset role;
  if p2.status <> 'draft' or p2.reviewed_by is not null then raise exception 'FAIL: التعديل ما أعاد النقطة لمسودة'; end if;
  raise notice 'PASS: التعديل يعيد النقطة لمسودة حتى تُراجع';

  -- 9) الإحداثيات خارج العراق مرفوضة
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  begin
    perform admin_save_map_place(null, 'خارج', 'landmark', 51.5, -0.12, '');
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg = 'none' then raise exception 'FAIL: إحداثيات خارج العراق قُبلت'; end if;
  raise notice 'PASS: الإحداثيات خارج حدود العراق مرفوضة';

  -- 10) حذف: المعتمدة ما تنحذف، والمسودة تنحذف
  perform set_config('request.jwt.claim.sub', adm::text, true);
  set local role authenticated;
  perform admin_review_map_place(p1.id, 'approved', '');
  begin
    perform admin_delete_map_place(p1.id);
    msg := 'none';
  exception when others then msg := sqlerrm;
  end;
  reset role;
  if msg not like '%cannot_delete_approved_or_missing%' then raise exception 'FAIL: حذف نقطة معتمدة مسموح (رد: %)', msg; end if;
  raise notice 'PASS: النقطة المعتمدة ما تنحذف بصمت';

  raise notice 'ALL PASS (map_places)';
end $$;

rollback;
\echo ✔ اختبارات نقاط الاستدلال نجحت (وتم التراجع عن كل البيانات التجريبية)
