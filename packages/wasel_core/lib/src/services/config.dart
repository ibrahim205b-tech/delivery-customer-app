import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// إعدادات الاتصال. تُمرَّر وقت البناء ولا تُحفظ بالمستودع:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// مفتاح anon عام بطبيعته (الحماية الفعلية عبر RLS)، لكن نبقيه خارج الكود.
abstract final class WaselConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// نطاق البريد الداخلي المستخدم لتحويل رقم الهاتف إلى حساب (لا تُرسل له رسائل).
  static const authEmailDomain = 'phone.wasel.app';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

SupabaseClient get db => Supabase.instance.client;

/// تهيئة مشتركة لكل التطبيقات. ترجع false إذا الإعدادات ناقصة.
Future<bool> bootstrapWasel() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  if (!WaselConfig.isConfigured) return false;
  await Supabase.initialize(
    url: WaselConfig.supabaseUrl,
    anonKey: WaselConfig.supabaseAnonKey,
    debug: kDebugMode,
  );
  return true;
}
