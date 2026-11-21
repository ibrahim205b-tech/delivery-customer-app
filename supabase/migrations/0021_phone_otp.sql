-- =====================================================================
-- WASEL | التحقق برقم الهاتف عبر رمز OTP يُرسل بالواتساب (0021)
--
-- الإرسال الفعلي يتم من دالة الخادم wasel-auth (Supabase Edge Function) التي تحمل
-- مفتاح VerifyWay كسرّ. هذا الملف يضيف فقط ما تحتاجه الدالة داخل قاعدة البيانات:
--
-- 1) otp_codes: رموز التحقق. يُخزَّن هاش الرمز فقط (HMAC بمفتاح سري لدى الخادم)، لا الرمز نفسه.
--    صلاحية الرمز 5 دقائق، 5 محاولات خاطئة كحد أقصى ثم يُلغى.
--    حدود الإرسال: رمز كل 60 ثانية لكل رقم وغرض، 3 رموز كل 15 دقيقة، 10 باليوم لكل رقم،
--    و20 بالساعة لكل عنوان IP.
-- 2) auth_passwords: كلمات مرور الحسابات (bcrypt). الدخول يمر عبر الخادم فقط:
--    كلمة مرور Supabase Auth لكل حساب تُستبدل بقيمة عشوائية لا يعرفها أحد، فلا يمكن
--    تجاوز رمز التحقق بالدخول المباشر.
--
-- كل الدوال هنا لا يستدعيها إلا الخادم (service_role). التطبيقات لا تصل لهذه الجداول.
-- التأثير: إضافة جدولين ودوال. لا يحذف ولا يغيّر أي بيانات موجودة.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- رموز التحقق
-- ---------------------------------------------------------------------
create table if not exists otp_codes (
  id          uuid primary key default gen_random_uuid(),
  phone       text not null check (phone ~ '^9647[0-9]{9}$'),     -- الصيغة الدولية بدون +
  purpose     text not null check (purpose in ('signup', 'login', 'reset')),
  code_hash   text not null,
  payload     jsonb not null default '{}'::jsonb,                 -- بيانات التسجيل (الاسم وهاش كلمة المرور)
  ip          text not null default '',
  attempts    int  not null default 0,
  expires_at  timestamptz not null,
  consumed_at timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists otp_codes_phone_idx on otp_codes (phone, purpose, created_at desc);
create index if not exists otp_codes_ip_idx on otp_codes (ip, created_at desc);
alter table otp_codes enable row level security;          -- بدون سياسات: لا وصول إلا للخادم
revoke all on otp_codes from anon, authenticated;
grant all on otp_codes to service_role;

-- ---------------------------------------------------------------------
-- كلمات المرور (bcrypt)
-- ---------------------------------------------------------------------
create table if not exists auth_passwords (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  hash       text not null,
  updated_at timestamptz not null default now()
);
alter table auth_passwords enable row level security;
revoke all on auth_passwords from anon, authenticated;
grant all on auth_passwords to service_role;

-- ---------------------------------------------------------------------
-- إصدار رمز جديد مع حدود الإرسال
-- يرجع {id, expires_at, resend_in} أو خطأ:
--   otp_cooldown:<ثواني>  ،  otp_rate_limited  ،  otp_ip_limited
-- ---------------------------------------------------------------------
create or replace function otp_issue(p_phone text, p_purpose text, p_code_hash text, p_ip text default '',
                                     p_payload jsonb default '{}'::jsonb, p_ttl_seconds int default 300)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare last_at timestamptz; n15 int; nday int; nip int; r otp_codes; wait int;
begin
  -- قفل على الرقم: طلبان متزامنان لا يتجاوزان الحدود معاً
  perform pg_advisory_xact_lock(hashtext('otp:' || p_phone));

  select max(created_at) into last_at from otp_codes where phone = p_phone and purpose = p_purpose;
  if last_at is not null and last_at > now() - interval '60 seconds' then
    wait := ceil(extract(epoch from (last_at + interval '60 seconds' - now())))::int;
    raise exception 'otp_cooldown:%', greatest(wait, 1);
  end if;
  select count(*) into n15 from otp_codes where phone = p_phone and created_at > now() - interval '15 minutes';
  select count(*) into nday from otp_codes where phone = p_phone and created_at > now() - interval '1 day';
  if n15 >= 3 or nday >= 10 then raise exception 'otp_rate_limited'; end if;
  if coalesce(p_ip, '') <> '' then
    select count(*) into nip from otp_codes where ip = p_ip and created_at > now() - interval '1 hour';
    if nip >= 20 then raise exception 'otp_ip_limited'; end if;
  end if;

  -- أي رمز سابق لنفس الرقم والغرض يبطل
  update otp_codes set consumed_at = now()
   where phone = p_phone and purpose = p_purpose and consumed_at is null;

  insert into otp_codes (phone, purpose, code_hash, payload, ip, expires_at)
  values (p_phone, p_purpose, p_code_hash, coalesce(p_payload, '{}'::jsonb), coalesce(p_ip, ''),
          now() + make_interval(secs => p_ttl_seconds))
  returning * into r;
  return jsonb_build_object('id', r.id, 'expires_at', r.expires_at, 'resend_in', 60);
end $$;

-- الإرسال فشل عند المزوّد: نحذف الرمز حتى لا يُحسب على المستخدم ولا يُستعمل
create or replace function otp_cancel(p_id uuid)
returns void language sql security definer set search_path = public as $$
  delete from otp_codes where id = p_id;
$$;

-- ---------------------------------------------------------------------
-- التحقق من الرمز
-- يرجع {ok:true, payload} أو {ok:false, reason: otp_missing|otp_expired|otp_locked|otp_invalid, remaining}
-- (لا يرمي خطأ عند الرمز الخاطئ حتى لا يضيع عدّاد المحاولات بالتراجع)
-- ---------------------------------------------------------------------
create or replace function otp_check(p_phone text, p_purpose text, p_code_hash text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r otp_codes; max_attempts constant int := 5;
begin
  select * into r from otp_codes
   where phone = p_phone and purpose = p_purpose and consumed_at is null
   order by created_at desc limit 1
   for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'otp_missing'); end if;
  if r.expires_at <= now() then
    update otp_codes set consumed_at = now() where id = r.id;
    return jsonb_build_object('ok', false, 'reason', 'otp_expired');
  end if;
  if r.attempts >= max_attempts then
    update otp_codes set consumed_at = now() where id = r.id;
    return jsonb_build_object('ok', false, 'reason', 'otp_locked');
  end if;
  if r.code_hash <> p_code_hash then
    update otp_codes set attempts = attempts + 1,
                         consumed_at = case when attempts + 1 >= max_attempts then now() end
     where id = r.id;
    if r.attempts + 1 >= max_attempts then
      return jsonb_build_object('ok', false, 'reason', 'otp_locked');
    end if;
    return jsonb_build_object('ok', false, 'reason', 'otp_invalid', 'remaining', max_attempts - (r.attempts + 1));
  end if;
  update otp_codes set consumed_at = now() where id = r.id;
  return jsonb_build_object('ok', true, 'payload', r.payload);
end $$;

-- ---------------------------------------------------------------------
-- كلمات المرور
-- ---------------------------------------------------------------------
create or replace function auth_password_hash(p_password text)
returns text language sql volatile security definer set search_path = public, extensions as $$
  select crypt(p_password, gen_salt('bf', 10));
$$;

create or replace function auth_password_set_hash(p_user uuid, p_hash text)
returns void language sql security definer set search_path = public as $$
  insert into auth_passwords (user_id, hash, updated_at) values (p_user, p_hash, now())
  on conflict (user_id) do update set hash = excluded.hash, updated_at = now();
$$;

create or replace function auth_password_set(p_user uuid, p_password text)
returns void language sql security definer set search_path = public, extensions as $$
  select auth_password_set_hash(p_user, crypt(p_password, gen_salt('bf', 10)));
$$;

-- true/false، أو null إذا الحساب ما زال على كلمة مرور Supabase القديمة (يُنقل عند أول دخول)
create or replace function auth_password_check(p_user uuid, p_password text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select hash = crypt(p_password, hash) from auth_passwords where user_id = p_user;
$$;

-- الحساب حسب الرقم المحلي 07XXXXXXXXX
create or replace function auth_user_by_phone(p_phone07 text)
returns uuid language sql stable security definer set search_path = public as $$
  select id from users where phone = p_phone07 limit 1;
$$;

-- الصلاحيات: الخادم فقط
revoke all on function otp_issue(text, text, text, text, jsonb, int) from public, anon, authenticated;
revoke all on function otp_cancel(uuid) from public, anon, authenticated;
revoke all on function otp_check(text, text, text) from public, anon, authenticated;
revoke all on function auth_password_hash(text) from public, anon, authenticated;
revoke all on function auth_password_set_hash(uuid, text) from public, anon, authenticated;
revoke all on function auth_password_set(uuid, text) from public, anon, authenticated;
revoke all on function auth_password_check(uuid, text) from public, anon, authenticated;
revoke all on function auth_user_by_phone(text) from public, anon, authenticated;
grant execute on function otp_issue(text, text, text, text, jsonb, int) to service_role;
grant execute on function otp_cancel(uuid) to service_role;
grant execute on function otp_check(text, text, text) to service_role;
grant execute on function auth_password_hash(text) to service_role;
grant execute on function auth_password_set_hash(uuid, text) to service_role;
grant execute on function auth_password_set(uuid, text) to service_role;
grant execute on function auth_password_check(uuid, text) to service_role;
grant execute on function auth_user_by_phone(text) to service_role;

notify pgrst, 'reload schema';
