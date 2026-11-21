import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'config.dart';

/// يحوّل أي صيغة رقم عراقي إلى الشكل المحلي 07XXXXXXXXX، أو null إذا غير صالح.
String? normalizeIraqiPhone(String input) {
  var d = input.replaceAll(RegExp(r'[^0-9٠-٩]'), '');
  const ar = '٠١٢٣٤٥٦٧٨٩';
  d = d.split('').map((c) => ar.contains(c) ? '${ar.indexOf(c)}' : c).join();
  if (d.startsWith('00964')) d = d.substring(5);
  if (d.startsWith('964')) d = d.substring(3);
  if (d.startsWith('7') && d.length == 10) d = '0$d';
  if (RegExp(r'^07[0-9]{9}$').hasMatch(d)) return d;
  return null;
}

/// الحساب يعتمد رقم الهاتف + كلمة مرور + رمز تحقق بالواتساب. داخلياً يتحوّل الرقم
/// لبريد ثابت تستخدمه دالة الخادم wasel-auth لإصدار الجلسة.
String phoneToAuthEmail(String phone07) => '964${phone07.substring(1)}@${WaselConfig.authEmailDomain}';

/// خطأ من دالة الخادم wasel-auth (رمز الخطأ + معلومات إضافية للواجهة)
class AuthFlowException implements Exception {
  const AuthFlowException(this.code, {this.remaining, this.retryIn});
  final String code;
  final int? remaining;
  final int? retryIn;

  /// الصيغة code:arg تفهمها friendlyError
  @override
  String toString() => retryIn != null ? '$code:$retryIn' : remaining != null ? '$code:$remaining' : code;
}

/// حالة الجلسة والملف والأدوار. التطبيقات تستمع لها لتبديل الشاشات.
class AuthController extends ChangeNotifier {
  AuthController() {
    _sub = db.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) {
        _profile = null;
        _roles = {};
        notifyListeners();
      } else if (s.session != null && (_profile == null || s.event == AuthChangeEvent.signedIn)) {
        refresh();
      }
    });
    if (db.auth.currentSession != null) refresh();
  }

  late final StreamSubscription<AuthState> _sub;
  AppUser? _profile;
  Set<AppRole> _roles = {};
  bool _loading = false;
  String? _loadError;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool get isSignedIn => db.auth.currentSession != null;
  bool get loading => _loading;
  String? get loadError => _loadError;
  AppUser? get profile => _profile;
  Set<AppRole> get roles => _roles;
  String? get userId => db.auth.currentUser?.id;
  bool hasRole(AppRole r) => _roles.contains(r);

  Future<void> refresh() async {
    final uid = userId;
    if (uid == null) return;
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final p = await db.from('users').select().eq('id', uid).maybeSingle();
      final r = await db.from('user_roles').select('role').eq('user_id', uid);
      _profile = p == null ? null : AppUser.fromJson(p);
      _roles = r.map((e) => AppRole.values.byName(e['role'] as String)).toSet();
    } catch (e) {
      _loadError = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------
  // الدخول برمز التحقق (OTP) عبر الواتساب — كل العمليات تمر بدالة الخادم wasel-auth.
  // التطبيق لا يحمل مفتاح المزوّد، ولا يفتح جلسة إلا بعد تحقق الخادم من الرمز.
  // -------------------------------------------------------------------

  /// يرسل رمز الدخول بعد التحقق من كلمة المرور. يرجع ثواني الانتظار قبل إعادة الإرسال.
  Future<int> startLogin({required String phone, required String password}) async {
    final r = await _call('login_start', {'phone': _phone(phone), 'password': password});
    return (r['resend_in'] as num?)?.toInt() ?? 60;
  }

  Future<void> verifyLogin({required String phone, required String code}) async =>
      _applySession(await _call('login_verify', {'phone': _phone(phone), 'code': code}));

  /// يرسل رمز التسجيل. الحساب لا يُنشأ إلا بعد التحقق.
  Future<int> startSignUp({required String fullName, required String phone, required String password}) async {
    final r = await _call('signup_start', {'full_name': fullName.trim(), 'phone': _phone(phone), 'password': password});
    return (r['resend_in'] as num?)?.toInt() ?? 60;
  }

  Future<void> verifySignUp({required String phone, required String code}) async =>
      _applySession(await _call('signup_verify', {'phone': _phone(phone), 'code': code}));

  /// يرسل رمز استعادة كلمة المرور.
  Future<int> startReset({required String phone}) async {
    final r = await _call('reset_start', {'phone': _phone(phone)});
    return (r['resend_in'] as num?)?.toInt() ?? 60;
  }

  Future<void> verifyReset({required String phone, required String code, required String newPassword}) async =>
      _applySession(await _call('reset_verify', {'phone': _phone(phone), 'code': code, 'new_password': newPassword}));

  String _phone(String input) {
    final p = normalizeIraqiPhone(input);
    if (p == null) throw const AuthFlowException('phone_invalid');
    return p;
  }

  Future<Map<String, dynamic>> _call(String action, Map<String, dynamic> body) async {
    dynamic data;
    try {
      final res = await db.functions.invoke('wasel-auth', body: {'action': action, ...body});
      data = res.data;
    } on FunctionException catch (e) {
      data = e.details;
    }
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    if (data is! Map) throw const AuthFlowException('server_error');
    final m = Map<String, dynamic>.from(data);
    if (m['ok'] != true) {
      throw AuthFlowException(
        (m['error'] as String?) ?? 'server_error',
        remaining: (m['remaining'] as num?)?.toInt(),
        retryIn: (m['retry_in'] as num?)?.toInt(),
      );
    }
    return m;
  }

  Future<void> _applySession(Map<String, dynamic> r) async {
    final s = r['session'];
    if (s is! Map || s['refresh_token'] is! String) throw const AuthFlowException('server_error');
    await db.auth.setSession(s['refresh_token'] as String);
    await refresh();
  }

  Future<void> updateName(String name) async {
    await db.from('users').update({'full_name': name.trim()}).eq('id', userId!);
    await refresh();
  }

  /// تغيير كلمة المرور من داخل التطبيق (يتطلب كلمة المرور الحالية)
  Future<void> changePassword({required String current, required String next}) async {
    await _call('change_password', {'current_password': current, 'new_password': next});
  }

  Future<void> signOut() => db.auth.signOut();

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    super.dispose();
  }
}
