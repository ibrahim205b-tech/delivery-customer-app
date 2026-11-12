import 'package:flutter/material.dart';

/// ألوان واصل — Bold Contemporary.
///
/// القاعدة: الحبر (ink) للأساس والنص، الليموني (lime) للفعل الرئيسي ولحظات التميّز فقط،
/// الأزرق للتفاعل والمعلومة والمسارات، والورقي (paper) خلفية هادئة.
/// الليموني ما يُستخدم أبداً كنص على خلفية فاتحة (تباينه ضعيف) — للنص الملوّن على الفاتح استخدم الأزرق.
abstract final class WColors {
  // ---- الهوية ----
  static const ink = Color(0xFF111923); // Primary Ink
  static const graphite = Color(0xFF303943); // Graphite
  static const lime = Color(0xFFD8F36A); // Electric Lime
  static const limeSoft = Color(0xFFF0F9CF);
  static const limeDeep = Color(0xFF9DB82C); // لليموني على الفاتح عند الضرورة (حدود، أيقونات كبيرة)
  static const blue = Color(0xFF4058E8); // Electric Blue
  static const blueSoft = Color(0xFFE6E9FC);
  static const paper = Color(0xFFF4F2EC); // Warm Paper
  static const white = Color(0xFFFFFFFF);

  // ---- محايدة ----
  static const inkMuted = Color(0xFF5B6570);
  static const inkFaint = Color(0xFF98A0A8);
  static const line = Color(0xFFE3E0D7);
  static const surfaceAlt = Color(0xFFEBE8DF);
  static const inkSurface = Color(0xFF1B2531); // سطح فوق الحبر (بطاقات داخل الأقسام الداكنة)

  // ---- حالات (وظيفية فقط) ----
  static const success = Color(0xFF1E8A5A);
  static const successSoft = Color(0xFFDDF1E6);
  static const warning = Color(0xFFB57514);
  static const warningSoft = Color(0xFFF7EBD3);
  static const danger = Color(0xFFD2412F);
  static const dangerSoft = Color(0xFFFAE3DF);
}

/// المسافات على شبكة 4
abstract final class WSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const page = 20.0;
}

/// الزوايا: مدروسة لا دائرية بالكامل. الأزرار 14، البطاقات 20، الأقسام الكبيرة 28.
abstract final class WRadius {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// ظل واحد خفيف للعناصر الطافية فقط (شريط السلة، الأوراق السفلية)
abstract final class WShadow {
  static const soft = [BoxShadow(color: Color(0x14111923), blurRadius: 16, offset: Offset(0, 6))];
  static const lifted = [BoxShadow(color: Color(0x26111923), blurRadius: 30, offset: Offset(0, 12))];
}

abstract final class WDurations {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 360);
  static const curve = Curves.easeOutCubic;
}

const kWaselFont = 'packages/wasel_core/Alexandria';
const kWaselFallback = ['packages/wasel_core/NotoSansArabic'];

/// نظام الخطوط (Alexandria). الأوزان: 400 للنص، 500 للعناوين الصغيرة، 600 للتأكيد، 700 للعناوين والأسعار.
abstract final class WText {
  static const _base = TextStyle(
    fontFamily: kWaselFont,
    fontFamilyFallback: kWaselFallback,
    color: WColors.ink,
    height: 1.5,
    letterSpacing: 0,
  );

  /// Display — العناوين الكبيرة جداً (الترحيب، الأرقام الرئيسية)
  static final display = _base.copyWith(fontSize: 32, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.4);

  /// Heading — عناوين الصفحات والأقسام
  static final h1 = _base.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.2);
  static final h2 = _base.copyWith(fontSize: 19, fontWeight: FontWeight.w600, height: 1.35);

  /// Title — أسماء المحلات والمنتجات
  static final h3 = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4);

  /// Body
  static final body = _base.copyWith(fontSize: 14.5, fontWeight: FontWeight.w400);
  static final bodyStrong = _base.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500);
  static final small = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: WColors.inkMuted);

  /// Caption — تفاصيل ثانوية
  static final caption = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w400, color: WColors.inkMuted, height: 1.4);

  /// Label — الأزرار والحقول والوسوم
  static final button = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2);
  static final label = _base.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.2);

  /// Price — الأسعار والأرقام (أرقام متساوية العرض حتى ما تتراقص عند التحديث)
  static final price = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]);
  static final number = _base.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]);

  /// Overline — عناوين صغيرة فوق الأقسام
  static final overline = _base.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: WColors.inkMuted, letterSpacing: 0.4);
}
