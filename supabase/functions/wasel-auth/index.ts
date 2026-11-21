// =====================================================================
// wasel-auth — دالة خادم واحدة لكل عمليات الدخول برمز التحقق (OTP) عبر الواتساب
//
// الإجراءات (الحقل action في جسم الطلب):
//   login_start    {phone, password}             → يتحقق من كلمة المرور ثم يرسل الرمز
//   login_verify   {phone, code}                 → يتحقق من الرمز ويرجع جلسة
//   signup_start   {full_name, phone, password}  → يرسل الرمز (الحساب لا يُنشأ قبل التحقق)
//   signup_verify  {phone, code}                 → ينشئ الحساب ويرجع جلسة
//   reset_start    {phone}                       → يرسل رمز استعادة كلمة المرور
//   reset_verify   {phone, code, new_password}   → يغيّر كلمة المرور ويرجع جلسة
//   change_password {current_password, new_password}  (يتطلب جلسة: Authorization: Bearer <jwt>)
//
// الرد دائماً JSON: {ok:true, ...} أو {ok:false, error:"<رمز>", remaining?, retry_in?}
//
// الأسرار المطلوبة (Supabase → Edge Functions → Secrets):
//   VERIFYWAY_API_KEY    مفتاح VerifyWay (لا يوضع بالتطبيق أبداً)
//   VERIFYWAY_SENDER_ID  اسم المرسل المعتمد بحسابك (مثلاً Wasel)
//   OTP_PEPPER           نص عشوائي طويل لتشفير الرموز (32 حرفاً أو أكثر)
// متوفرة تلقائياً من Supabase: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// اختياري: AUTH_EMAIL_DOMAIN (الافتراضي phone.wasel.app)، VERIFYWAY_LANG (الافتراضي ar)
// =====================================================================
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";

const VERIFYWAY_URL = "https://gateway.standingtech.com/api/v4/sms/send";
const OTP_TTL_SECONDS = 300;
const EMAIL_DOMAIN = Deno.env.get("AUTH_EMAIL_DOMAIN") ?? "phone.wasel.app";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
const fail = (error: string, extra: Record<string, unknown> = {}) => json({ ok: false, error, ...extra });

class AppError extends Error {
  constructor(public code: string, public extra: Record<string, unknown> = {}) {
    super(code);
  }
}

// ---------------------------------------------------------------------
// أدوات
// ---------------------------------------------------------------------
/** أي صيغة رقم عراقي → {local: 07XXXXXXXXX, intl: 9647XXXXXXXXX} أو null */
export function normalizeIraqiPhone(input: unknown): { local: string; intl: string } | null {
  if (typeof input !== "string") return null;
  const ar = "٠١٢٣٤٥٦٧٨٩";
  let d = input.replace(/[٠-٩]/g, (c) => String(ar.indexOf(c))).replace(/[^0-9]/g, "");
  if (d.startsWith("00964")) d = d.slice(5);
  if (d.startsWith("964")) d = d.slice(3);
  if (d.startsWith("7") && d.length === 10) d = "0" + d;
  if (!/^07[0-9]{9}$/.test(d)) return null;
  return { local: d, intl: "964" + d.slice(1) };
}

const authEmail = (intl: string) => `${intl}@${EMAIL_DOMAIN}`;

function randomCode(): string {
  const a = new Uint32Array(1);
  crypto.getRandomValues(a);
  return String(100000 + (a[0] % 900000));
}

function randomSecret(): string {
  const a = new Uint8Array(32);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function codeHash(purpose: string, intl: string, code: string): Promise<string> {
  const pepper = Deno.env.get("OTP_PEPPER");
  if (!pepper || pepper.length < 16) throw new AppError("server_misconfigured");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(pepper), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${purpose}:${intl}:${code}`));
  return Array.from(new Uint8Array(sig), (b) => b.toString(16).padStart(2, "0")).join("");
}

function validPassword(p: unknown): p is string {
  return typeof p === "string" && p.length >= 6 && p.length <= 72;
}

function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for") ?? "";
  return (fwd.split(",")[0] ?? "").trim().slice(0, 64);
}

/** يحوّل خطأ دالة قاعدة البيانات (raise exception) إلى رمز خطأ للتطبيق */
function dbError(e: { message?: string } | null): AppError {
  const msg = e?.message ?? "";
  const m = msg.match(/^otp_cooldown:(\d+)/);
  if (m) return new AppError("otp_cooldown", { retry_in: Number(m[1]) });
  for (const c of ["otp_rate_limited", "otp_ip_limited"]) if (msg.startsWith(c)) return new AppError(c);
  console.error("db error", msg);
  return new AppError("server_error");
}

// ---------------------------------------------------------------------
// VerifyWay: إرسال الرمز بالواتساب (حسب توثيق حسابك: POST /api/v4/sms/send)
// ---------------------------------------------------------------------
async function sendWhatsappOtp(intl: string, code: string): Promise<void> {
  const key = Deno.env.get("VERIFYWAY_API_KEY");
  const sender = Deno.env.get("VERIFYWAY_SENDER_ID");
  if (!key || !sender) throw new AppError("server_misconfigured");
  let res: Response;
  try {
    res = await fetch(VERIFYWAY_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ recipient: intl, sender_id: sender, type: "whatsapp", message: code, lang: Deno.env.get("VERIFYWAY_LANG") ?? "ar" }),
    });
  } catch (e) {
    console.error("verifyway network error", String(e));
    throw new AppError("otp_send_failed");
  }
  const text = await res.text();
  let body: { status?: string; error?: { code?: string; message?: string } } = {};
  try {
    body = JSON.parse(text);
  } catch { /* الرد ليس JSON */ }
  if (!res.ok || body.status === "failed") {
    // لا نسجّل الرمز؛ فقط رد المزوّد لتشخيص المشكلة
    console.error("verifyway rejected", res.status, text.slice(0, 300));
    throw new AppError("otp_send_failed", { provider_code: body.error?.code ?? String(res.status) });
  }
}

/** يصدر رمزاً بحدود الإرسال، يرسله، ويلغيه إذا فشل الإرسال */
async function issueAndSend(admin: SupabaseClient, purpose: string, intl: string, ip: string, payload: Record<string, unknown> = {}) {
  const code = randomCode();
  const { data, error } = await admin.rpc("otp_issue", {
    p_phone: intl,
    p_purpose: purpose,
    p_code_hash: await codeHash(purpose, intl, code),
    p_ip: ip,
    p_payload: payload,
    p_ttl_seconds: OTP_TTL_SECONDS,
  });
  if (error) throw dbError(error);
  try {
    await sendWhatsappOtp(intl, code);
  } catch (e) {
    await admin.rpc("otp_cancel", { p_id: (data as { id: string }).id });
    throw e;
  }
  return { ok: true, resend_in: 60, expires_in: OTP_TTL_SECONDS };
}

async function checkCode(admin: SupabaseClient, purpose: string, intl: string, code: unknown) {
  if (typeof code !== "string" || !/^[0-9]{6}$/.test(code)) throw new AppError("otp_invalid_format");
  const { data, error } = await admin.rpc("otp_check", { p_phone: intl, p_purpose: purpose, p_code_hash: await codeHash(purpose, intl, code) });
  if (error) throw dbError(error);
  const r = data as { ok: boolean; reason?: string; remaining?: number; payload?: Record<string, unknown> };
  if (!r.ok) throw new AppError(r.reason ?? "otp_invalid", r.remaining != null ? { remaining: r.remaining } : {});
  return r.payload ?? {};
}

/** جلسة حقيقية للحساب بدون كلمة مرور Supabase (رابط دخول يُستهلك فوراً داخل الخادم) */
async function issueSession(admin: SupabaseClient, anon: SupabaseClient, email: string) {
  const { data, error } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (error || !data?.properties?.hashed_token) {
    console.error("generateLink", error?.message);
    throw new AppError("server_error");
  }
  const v = await anon.auth.verifyOtp({ type: "magiclink", token_hash: data.properties.hashed_token });
  if (v.error || !v.data.session) {
    console.error("verifyOtp", v.error?.message);
    throw new AppError("server_error");
  }
  const s = v.data.session;
  return { access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in };
}

/** كلمة مرور Supabase Auth تصير عشوائية: الدخول المباشر بدون رمز التحقق يصبح مستحيلاً */
async function lockDirectLogin(admin: SupabaseClient, userId: string) {
  const { error } = await admin.auth.admin.updateUserById(userId, { password: randomSecret() });
  if (error) console.error("lockDirectLogin", error.message);
}

/**
 * يتحقق من كلمة مرور الحساب. الحسابات القديمة (قبل هذا النظام) ما عندها نسخة في auth_passwords:
 * نتحقق منها مرة واحدة عبر Supabase Auth، ننقلها لنا، ثم نقفل الدخول المباشر.
 */
async function verifyPassword(admin: SupabaseClient, anon: SupabaseClient, userId: string, intl: string, password: string): Promise<boolean> {
  const { data, error } = await admin.rpc("auth_password_check", { p_user: userId, p_password: password });
  if (error) throw dbError(error);
  if (data === true) return true;
  if (data === false) return false;
  // حساب قديم
  const legacy = await anon.auth.signInWithPassword({ email: authEmail(intl), password });
  if (legacy.error || !legacy.data.session) return false;
  await anon.auth.signOut();
  const set = await admin.rpc("auth_password_set", { p_user: userId, p_password: password });
  if (set.error) throw dbError(set.error);
  await lockDirectLogin(admin, userId);
  return true;
}

async function userIdByPhone(admin: SupabaseClient, local: string): Promise<string | null> {
  const { data, error } = await admin.rpc("auth_user_by_phone", { p_phone07: local });
  if (error) throw dbError(error);
  return (data as string | null) ?? null;
}

// ---------------------------------------------------------------------
// الخادم
// ---------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
  const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("bad_request");
  }
  const action = String(body.action ?? "");
  const ip = clientIp(req);

  try {
    switch (action) {
      // ----------------------------------------------------------- الدخول
      case "login_start": {
        const ph = normalizeIraqiPhone(body.phone);
        const password = body.password;
        if (!ph || typeof password !== "string") throw new AppError("invalid_credentials");
        const uid = await userIdByPhone(admin, ph.local);
        if (!uid || !(await verifyPassword(admin, anon, uid, ph.intl, password))) throw new AppError("invalid_credentials");
        return json(await issueAndSend(admin, "login", ph.intl, ip));
      }
      case "login_verify": {
        const ph = normalizeIraqiPhone(body.phone);
        if (!ph) throw new AppError("phone_invalid");
        await checkCode(admin, "login", ph.intl, body.code);
        return json({ ok: true, session: await issueSession(admin, anon, authEmail(ph.intl)) });
      }

      // ----------------------------------------------------------- حساب جديد
      case "signup_start": {
        const ph = normalizeIraqiPhone(body.phone);
        const name = typeof body.full_name === "string" ? body.full_name.trim().slice(0, 80) : "";
        if (!ph) throw new AppError("phone_invalid");
        if (name.length < 3) throw new AppError("name_required");
        if (!validPassword(body.password)) throw new AppError("weak_password");
        if (await userIdByPhone(admin, ph.local)) throw new AppError("phone_taken");
        const { data: hash, error } = await admin.rpc("auth_password_hash", { p_password: body.password });
        if (error) throw dbError(error);
        return json(await issueAndSend(admin, "signup", ph.intl, ip, { full_name: name, password_hash: hash }));
      }
      case "signup_verify": {
        const ph = normalizeIraqiPhone(body.phone);
        if (!ph) throw new AppError("phone_invalid");
        const payload = await checkCode(admin, "signup", ph.intl, body.code);
        if (await userIdByPhone(admin, ph.local)) throw new AppError("phone_taken");
        const created = await admin.auth.admin.createUser({
          email: authEmail(ph.intl),
          password: randomSecret(),
          email_confirm: true,
          user_metadata: { full_name: payload.full_name, phone: ph.local },
        });
        if (created.error || !created.data.user) {
          console.error("createUser", created.error?.message);
          throw new AppError(/already/i.test(created.error?.message ?? "") ? "phone_taken" : "server_error");
        }
        const set = await admin.rpc("auth_password_set_hash", { p_user: created.data.user.id, p_hash: payload.password_hash });
        if (set.error) throw dbError(set.error);
        return json({ ok: true, session: await issueSession(admin, anon, authEmail(ph.intl)) });
      }

      // ----------------------------------------------------------- نسيت كلمة المرور
      case "reset_start": {
        const ph = normalizeIraqiPhone(body.phone);
        if (!ph) throw new AppError("phone_invalid");
        const uid = await userIdByPhone(admin, ph.local);
        if (!uid) throw new AppError("phone_not_registered");
        return json(await issueAndSend(admin, "reset", ph.intl, ip));
      }
      case "reset_verify": {
        const ph = normalizeIraqiPhone(body.phone);
        if (!ph) throw new AppError("phone_invalid");
        if (!validPassword(body.new_password)) throw new AppError("weak_password");
        const uid = await userIdByPhone(admin, ph.local);
        if (!uid) throw new AppError("phone_not_registered");
        await checkCode(admin, "reset", ph.intl, body.code);
        const set = await admin.rpc("auth_password_set", { p_user: uid, p_password: body.new_password });
        if (set.error) throw dbError(set.error);
        await lockDirectLogin(admin, uid);
        return json({ ok: true, session: await issueSession(admin, anon, authEmail(ph.intl)) });
      }

      // ----------------------------------------------------------- تغيير كلمة المرور من داخل التطبيق
      case "change_password": {
        const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
        const { data: u, error } = await admin.auth.getUser(jwt);
        if (error || !u.user) throw new AppError("not_authenticated");
        if (!validPassword(body.new_password)) throw new AppError("weak_password");
        const email = u.user.email ?? "";
        const intl = email.split("@")[0];
        if (typeof body.current_password !== "string" || !(await verifyPassword(admin, anon, u.user.id, intl, body.current_password))) {
          throw new AppError("invalid_credentials");
        }
        const set = await admin.rpc("auth_password_set", { p_user: u.user.id, p_password: body.new_password });
        if (set.error) throw dbError(set.error);
        await lockDirectLogin(admin, u.user.id);
        return json({ ok: true });
      }
      default:
        return fail("bad_request");
    }
  } catch (e) {
    if (e instanceof AppError) return fail(e.code, e.extra);
    console.error("unexpected", String(e));
    return json({ ok: false, error: "server_error" }, 500);
  }
});
