import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// يحوّل أخطاء الخادم والشبكة إلى رسائل عربية مفهومة.
String friendlyError(Object e) {
  if (e is SocketException || e is TimeoutException) return 'ما اكو اتصال بالإنترنت. تأكد من الشبكة وحاول مرة ثانية.';
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
    if (m.contains('already registered') || m.contains('already exists')) return 'هذا الرقم مسجّل مسبقاً. سجّل دخولك.';
    if (m.contains('password')) return 'كلمة المرور لازم تكون 6 أحرف على الأقل.';
    if (m.contains('email not confirmed')) return 'الحساب بانتظار التفعيل. راجع إعدادات المشروع (تعطيل تأكيد البريد).';
    return 'تعذّر تسجيل الدخول: ${e.message}';
  }
  final msg = switch (e) {
    PostgrestException(:final message) => message,
    StorageException(:final message) => message,
    _ => e.toString(),
  };
  final code = msg.split(':').first.trim();
  final arg = msg.contains(':') ? msg.substring(msg.indexOf(':') + 1).trim() : '';
  return switch (code) {
    'not_authenticated' => 'لازم تسجّل دخولك أولاً.',
    'account_disabled' => 'حسابك موقوف. تواصل مع الدعم بالواتساب أو الاتصال.',
    'forbidden' => 'ما عندك صلاحية لهذه العملية.',
    'merchant_unavailable' => 'المحل غير متاح حالياً.',
    'merchant_closed' => 'المحل مسكّر هسه أو موقف الطلبات.',
    'merchant_not_orderable' => 'هذا القسم ما يدعم الطلب المباشر.',
    'address_not_found' => 'اختار عنوان توصيل صحيح.',
    'out_of_delivery_area' => 'عنوانك خارج منطقة توصيل هذا المحل.',
    'empty_cart' => 'السلة فارغة.',
    'invalid_quantity' => 'الكمية غير صحيحة.',
    'product_unavailable' => 'المنتج "$arg" ما متوفر هسه.',
    'out_of_stock' => 'الكمية المطلوبة من "$arg" غير متوفرة.',
    'below_min_order' => 'الحد الأدنى للطلب $arg د.ع.',
    'cannot_cancel_now' => 'ما يصير الإلغاء بهذه المرحلة.',
    'order_not_found' || 'task_not_found' || 'ride_not_found' || 'booking_not_found' => 'الطلب غير موجود.',
    'invalid_transition' => 'ما يصير الانتقال لهذه الحالة الآن.',
    'reason_required' => 'اكتب السبب أولاً.',
    'not_a_driver' || 'driver_inactive' => 'حساب السائق غير مفعّل. تواصل مع الإدارة.',
    'already_on_job' => 'عندك مهمة شغّالة. كمّلها أولاً.',
    'outside_service_area' => 'هذا الموقع خارج مناطق خدمة واصل حالياً.',
    'service_not_implemented' => 'هذه الخدمة لسا ما لها تنفيذ، ما تنفعّل قبل ما تنبنى.',
    'invalid_percent' => 'النسبة لازم تكون بين 0 و50٪.',
    'invalid_model' => 'نوع العمولة غير معروف.',
    'invalid_value' => 'القيمة لازم تكون صفر أو أكثر.',
    'service_not_found' => 'الخدمة غير موجودة.',
    'open_requests' => 'عندك طلبات مفتوحة. أنهها أو ألغها قبل تغيير النشاط.',
    'provider_not_for_service' => 'هذا المقدم ما يقدم هذه الخدمة.',
    'payload_required' => 'اكتب تفاصيل الطلب.',
    'service_inactive' => 'هذه الخدمة غير مفعّلة حالياً.',
    'task_taken' || 'ride_taken' => 'سائق ثاني سبقك وقبلها.',
    'vehicle_not_allowed' => 'نوع مركبتك ما يناسب هذه المهمة.',
    'cannot_release' => 'ما يصير تتخلى عن المهمة بعد الاستلام.',
    'ride_already_active' => 'عندك رحلة شغّالة.',
    'customer_restricted' => 'طلب الرحلات موقوف مؤقتاً بسبب تكرار الإلغاء. راجع مدة الإيقاف في الشاشة الرئيسية.',
    'driver_restricted' => 'استقبال الطلبات موقوف مؤقتاً بسبب تكرار الإلغاء. يعود تلقائياً بعد انتهاء المدة.',
    'cancel_reason_required' => 'اختار سبب الإلغاء. حدّث التطبيق إذا ما ظهرت الخيارات.',
    'invalid_cancel_reason' => 'سبب الإلغاء غير صحيح لهذا الحساب.',
    'note_required' => 'اكتب توضيحاً قصيراً (5 أحرف على الأقل).',
    'ride_already_cancelled' => 'الرحلة ملغاة من قبل.',
    'restriction_not_active' => 'هذا الإيقاف منتهٍ أو مرفوع.',
    'restriction_not_found' => 'الإيقاف غير موجود.',
    'same_location' => 'الانطلاق والوجهة نفس المكان.',
    'invalid_vehicle' || 'invalid_kind' => 'نوع الخدمة غير صحيح.',
    'description_required' => 'اكتب وصف للطلب.',
    'empty_message' => 'اكتب رسالتك أولاً.',
    'merchant_has_history' => 'المحل عنده طلبات سابقة، فما ينحذف حتى تبقى السجلات والحسابات. تگدر توقفه بدل الحذف.',
    'invalid_amount' => 'اكتب مبلغ صحيح.',
    'message_too_long' => 'الرسالة طويلة، الحد 2000 حرف.',
    'too_far' => 'المسافة أبعد من المسموح.',
    'pricing_not_configured' => 'التسعير غير مضبوط من الإدارة.',
    'provider_unavailable' => 'مقدّم الخدمة غير متاح.',
    'provider_does_not_offer_service' => 'مقدّم الخدمة ما يقدّم هذه الخدمة.',
    'time_in_past' => 'اختار وقت قادم.',
    'too_many_photos' => 'الحد الأقصى 5 صور.',
    'cannot_rate' => 'التقييم متاح بعد التسليم فقط.',
    'cannot_remove_own_admin' => 'ما تگدر تشيل صلاحية الإدارة عن نفسك.',
    // الدخول برمز التحقق (wasel-auth)
    'invalid_credentials' => 'رقم الهاتف أو كلمة المرور غير صحيحة.',
    'phone_invalid' => 'اكتب رقم عراقي صحيح يبدأ بـ 07.',
    'phone_taken' => 'هذا الرقم مسجّل مسبقاً. سجّل دخولك.',
    'phone_not_registered' => 'ما اكو حساب بهذا الرقم.',
    'name_required' => 'اكتب اسمك الكامل.',
    'weak_password' => 'كلمة المرور لازم تكون 6 أحرف على الأقل.',
    'otp_invalid' => arg.isEmpty ? 'الرمز غير صحيح.' : 'الرمز غير صحيح. باقي لك $arg محاولات.',
    'otp_invalid_format' => 'الرمز يتكون من 6 أرقام.',
    'otp_expired' => 'انتهت صلاحية الرمز. اطلب رمزاً جديداً.',
    'otp_locked' => 'تجاوزت عدد المحاولات. اطلب رمزاً جديداً.',
    'otp_missing' => 'ما اكو رمز فعّال. اطلب رمزاً جديداً.',
    'otp_cooldown' => 'انتظر $arg ثانية قبل طلب رمز جديد.',
    'otp_rate_limited' => 'طلبت رموزاً كثيرة. حاول بعد ربع ساعة.',
    'otp_ip_limited' => 'طلبات كثيرة من هذه الشبكة. حاول بعد ساعة.',
    'otp_send_failed' => 'تعذّر إرسال الرمز على الواتساب. تأكد أن الرقم عليه واتساب وحاول مرة ثانية.',
    'server_misconfigured' || 'server_error' || 'bad_request' => 'خدمة التحقق غير متاحة حالياً. حاول بعد قليل.',
    _ when msg.contains('duplicate key') => 'هذا العنصر موجود مسبقاً.',
    _ when msg.contains('row-level security') => 'ما عندك صلاحية لهذه العملية.',
    _ when msg.contains('Failed host lookup') || msg.contains('SocketException') || msg.contains('ClientException') => 'ما اكو اتصال بالإنترنت. تأكد من الشبكة وحاول مرة ثانية.',
    _ => 'صار خطأ غير متوقع. حاول مرة ثانية.',
  };
}
