-- =====================================================================
-- اختبار رموز التحقق وكلمات المرور (0021). يعمل داخل transaction ويتراجع.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/phone_otp.sql
-- =====================================================================
begin;

do $$
declare
  ph text := '9647801234567';
  uid uuid := 'b1000001-0000-4000-8000-000000000001';
  r jsonb; msg text; n int; h text;
begin
  -- 1) إصدار رمز
  r := otp_issue(ph, 'login', 'hash-1', '1.1.1.1');
  if (r->>'resend_in')::int <> 60 or (r->>'expires_at')::timestamptz <= now() + interval '4 minutes' then
    raise exception 'FAIL issue: %', r; end if;
  raise notice 'PASS: إصدار رمز بصلاحية 5 دقائق';

  -- 2) مهلة 60 ثانية بين رمزين
  begin
    perform otp_issue(ph, 'login', 'hash-2', '1.1.1.1');
    raise exception 'FAIL: cooldown not enforced';
  exception when others then
    msg := sqlerrm;
    if msg not like 'otp_cooldown:%' then raise exception 'FAIL cooldown: %', msg; end if;
  end;
  raise notice 'PASS: مهلة إعادة الإرسال (%)', msg;

  -- 3) رمز خاطئ: يقل عدد المحاولات، ثم القفل بعد 5
  r := otp_check(ph, 'login', 'wrong');
  if r->>'reason' <> 'otp_invalid' or (r->>'remaining')::int <> 4 then raise exception 'FAIL wrong1: %', r; end if;
  for i in 2..4 loop r := otp_check(ph, 'login', 'wrong'); end loop;
  if (r->>'remaining')::int <> 1 then raise exception 'FAIL wrong4: %', r; end if;
  r := otp_check(ph, 'login', 'wrong');
  if r->>'reason' <> 'otp_locked' then raise exception 'FAIL lock: %', r; end if;
  -- حتى الرمز الصحيح لا يعمل بعد القفل
  r := otp_check(ph, 'login', 'hash-1');
  if r->>'reason' <> 'otp_missing' then raise exception 'FAIL after lock: %', r; end if;
  raise notice 'PASS: 5 محاولات ثم قفل الرمز';

  -- 4) رمز صحيح يُستعمل مرة واحدة فقط
  update otp_codes set created_at = now() - interval '61 seconds' where phone = ph;
  perform otp_issue(ph, 'login', 'hash-3', '1.1.1.1');
  r := otp_check(ph, 'login', 'hash-3');
  if (r->>'ok')::boolean is not true then raise exception 'FAIL ok: %', r; end if;
  r := otp_check(ph, 'login', 'hash-3');
  if r->>'reason' <> 'otp_missing' then raise exception 'FAIL reuse: %', r; end if;
  raise notice 'PASS: الرمز الصحيح يُقبل مرة واحدة';

  -- 5) انتهاء الصلاحية
  update otp_codes set created_at = now() - interval '61 seconds' where phone = ph;
  perform otp_issue(ph, 'reset', 'hash-4', '1.1.1.1', '{}', 300);
  update otp_codes set expires_at = now() - interval '1 second' where phone = ph and purpose = 'reset' and consumed_at is null;
  r := otp_check(ph, 'reset', 'hash-4');
  if r->>'reason' <> 'otp_expired' then raise exception 'FAIL expiry: %', r; end if;
  raise notice 'PASS: الرمز المنتهي يُرفض';

  -- 6) الغرض منفصل: رمز الدخول لا يصلح للاستعادة
  -- (3 رموز صدرت خلال ربع ساعة: نرجّعها للوراء حتى لا يتدخل حد الـ 15 دقيقة)
  update otp_codes set created_at = now() - interval '16 minutes' where phone = ph;
  perform otp_issue(ph, 'signup', 'hash-5', '1.1.1.1', '{"full_name":"x"}');
  r := otp_check(ph, 'login', 'hash-5');
  if r->>'reason' <> 'otp_missing' then raise exception 'FAIL purpose: %', r; end if;
  r := otp_check(ph, 'signup', 'hash-5');
  if r->'payload'->>'full_name' <> 'x' then raise exception 'FAIL payload: %', r; end if;
  raise notice 'PASS: الرمز مربوط بغرضه ويرجع بيانات التسجيل';

  -- 7) حد 3 رموز كل 15 دقيقة لكل رقم (رمز التسجيل + رمزان آخران = 3، فالرابع يُرفض)
  update otp_codes set created_at = now() - interval '61 seconds' where phone = ph and purpose = 'signup';
  insert into otp_codes (phone, purpose, code_hash, expires_at, consumed_at, created_at)
    select ph, 'reset', 'x', now(), now(), now() - interval '5 minutes' from generate_series(1, 2);
  begin
    perform otp_issue(ph, 'login', 'hash-6', '1.1.1.1');
    raise exception 'FAIL: 15min limit not enforced';
  exception when others then
    if sqlerrm <> 'otp_rate_limited' then raise exception 'FAIL rate: %', sqlerrm; end if;
  end;
  raise notice 'PASS: حد 3 رموز كل 15 دقيقة';

  -- 8) حد 10 باليوم (6 سابقة + 4 = 10، فالحادي عشر يُرفض)
  update otp_codes set created_at = now() - interval '2 hours' where phone = ph;
  select count(*) into n from otp_codes where phone = ph;
  if n <> 6 then raise exception 'FAIL setup daily: %', n; end if;
  insert into otp_codes (phone, purpose, code_hash, expires_at, created_at)
    select ph, 'login', 'x', now(), now() - interval '3 hours' from generate_series(1, 4);
  begin
    perform otp_issue(ph, 'login', 'hash-7', '');
    raise exception 'FAIL: daily limit not enforced';
  exception when others then
    if sqlerrm <> 'otp_rate_limited' then raise exception 'FAIL daily: %', sqlerrm; end if;
  end;
  raise notice 'PASS: حد 10 رموز باليوم';

  -- 9) حد 20 بالساعة لكل IP (أرقام مختلفة)
  insert into otp_codes (phone, purpose, code_hash, ip, expires_at)
    select '96478' || lpad(g::text, 8, '0'), 'login', 'x', '9.9.9.9', now() from generate_series(1, 20) g;
  begin
    perform otp_issue('9647700000099', 'login', 'hash-8', '9.9.9.9');
    raise exception 'FAIL: ip limit not enforced';
  exception when others then
    if sqlerrm <> 'otp_ip_limited' then raise exception 'FAIL ip: %', sqlerrm; end if;
  end;
  raise notice 'PASS: حد 20 طلب بالساعة لكل IP';

  -- 10) إلغاء الرمز عند فشل الإرسال لا يُحسب على المستخدم
  r := otp_issue('9647700000088', 'login', 'hash-9', '');
  perform otp_cancel((r->>'id')::uuid);
  select count(*) into n from otp_codes where phone = '9647700000088';
  if n <> 0 then raise exception 'FAIL cancel'; end if;
  perform otp_issue('9647700000088', 'login', 'hash-9', '');  -- بلا مهلة لأن السابق حُذف
  raise notice 'PASS: فشل الإرسال يلغي الرمز';

  -- 11) صيغة الرقم
  begin
    perform otp_issue('07801234567', 'login', 'h', '');
    raise exception 'FAIL: bad phone accepted';
  exception when check_violation then null;
  end;
  raise notice 'PASS: يرفض رقماً بغير الصيغة الدولية';

  -- 12) كلمات المرور bcrypt
  insert into auth.users (id, email, raw_user_meta_data) values
    (uid, '9647801234567@phone.wasel.app', '{"full_name":"زبون OTP","phone":"07801234567"}');
  if auth_user_by_phone('07801234567') is distinct from uid then raise exception 'FAIL by_phone'; end if;
  if auth_password_check(uid, 'secret123') is not null then raise exception 'FAIL legacy should be null'; end if;
  perform auth_password_set(uid, 'secret123');
  if auth_password_check(uid, 'secret123') is not true then raise exception 'FAIL pw ok'; end if;
  if auth_password_check(uid, 'wrong') is not false then raise exception 'FAIL pw wrong'; end if;
  select hash into h from auth_passwords where user_id = uid;
  if h not like '$2a$10$%' then raise exception 'FAIL not bcrypt: %', left(h, 7); end if;
  perform auth_password_set_hash(uid, auth_password_hash('newpass1'));
  if auth_password_check(uid, 'newpass1') is not true or auth_password_check(uid, 'secret123') then raise exception 'FAIL set_hash'; end if;
  raise notice 'PASS: كلمات المرور bcrypt (تعيين، تحقق، نقل الحسابات القديمة)';
end $$;

-- 13) التطبيقات لا تصل للجداول ولا للدوال
do $$
declare ok boolean;
begin
  foreach ok in array array[
    has_table_privilege('anon', 'otp_codes', 'select'),
    has_table_privilege('authenticated', 'otp_codes', 'select'),
    has_table_privilege('authenticated', 'auth_passwords', 'select'),
    has_function_privilege('anon', 'otp_issue(text,text,text,text,jsonb,int)', 'execute'),
    has_function_privilege('authenticated', 'otp_check(text,text,text)', 'execute'),
    has_function_privilege('authenticated', 'auth_password_check(uuid,text)', 'execute'),
    has_function_privilege('anon', 'auth_user_by_phone(text)', 'execute')
  ] loop
    if ok then raise exception 'FAIL: client role has access'; end if;
  end loop;
  if not has_function_privilege('service_role', 'otp_check(text,text,text)', 'execute') then
    raise exception 'FAIL: service_role lacks access'; end if;
  raise notice 'PASS: لا وصول للتطبيقات، الخادم فقط';
end $$;

rollback;
