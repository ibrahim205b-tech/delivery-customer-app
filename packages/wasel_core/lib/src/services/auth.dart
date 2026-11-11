import 'dart:async';

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

/// الحساب يعتمد رقم الهاتف + كلمة مرور. داخلياً يتحوّل الرقم لبريد ثابت
/// (بدون إرسال رسائل) حتى نستغني عن مزوّد SMS مدفوع بالنسخة التجريبية.
String phoneToAuthEmail(String phone07) => '964${phone07.substring(1)}@${WaselConfig.authEmailDomain}';

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

  Future<void> signUp({required String fullName, required String phone, required String password}) async {
    final p = normalizeIraqiPhone(phone);
    if (p == null) throw const AuthException('invalid phone');
    await db.auth.signUp(
      email: phoneToAuthEmail(p),
      password: password,
      data: {'full_name': fullName.trim(), 'phone': p},
    );
    await refresh();
  }

  Future<void> signIn({required String phone, required String password}) async {
    final p = normalizeIraqiPhone(phone);
    if (p == null) throw const AuthException('Invalid login credentials');
    await db.auth.signInWithPassword(email: phoneToAuthEmail(p), password: password);
    await refresh();
  }

  Future<void> updateName(String name) async {
    await db.from('users').update({'full_name': name.trim()}).eq('id', userId!);
    await refresh();
  }

  Future<void> changePassword(String password) => db.auth.updateUser(UserAttributes(password: password));

  Future<void> signOut() => db.auth.signOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
