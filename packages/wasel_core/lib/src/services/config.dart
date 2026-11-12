import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/mode.dart';
import 'notifier.dart';

/// إعدادات الاتصال. تُمرَّر وقت البناء ولا تُحفظ بالمستودع:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// المفتاح العام (publishable) آمن داخل التطبيق لأن الحماية الفعلية عبر RLS، لكن نبقيه خارج الكود.
/// مفتاح anon القديم (SUPABASE_ANON_KEY) ما زال مدعوماً إذا ما انحط المفتاح الجديد.
abstract final class WaselConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _publishable = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _legacyAnon = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const supabaseAnonKey = _publishable != '' ? _publishable : _legacyAnon;

  /// نطاق البريد الداخلي المستخدم لتحويل رقم الهاتف إلى حساب (لا تُرسل له رسائل).
  static const authEmailDomain = 'phone.wasel.app';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

SupabaseClient? _clientOverride;

/// عميل Supabase الحالي. الاختبارات تگدر تبدله بعميل مستقل لكل مستخدم.
SupabaseClient get db => _clientOverride ?? Supabase.instance.client;

@visibleForTesting
void useClientForTesting(SupabaseClient? client) => _clientOverride = client;

/// تهيئة مشتركة لكل التطبيقات. ترجع false إذا الإعدادات ناقصة.
Future<bool> bootstrapWasel() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await WaselThemeController.instance.load();
  if (!WaselConfig.isConfigured) return false;
  await Supabase.initialize(
    url: WaselConfig.supabaseUrl,
    publishableKey: WaselConfig.supabaseAnonKey,
    debug: kDebugMode,
  );
  await WaselNotifier.instance.init();
  return true;
}
