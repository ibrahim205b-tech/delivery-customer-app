import 'package:flutter/material.dart';

/// ألوان واصل — Bold Contemporary، بوضعين نهاري وليلي.
///
/// الأدوار:
/// - ثابتة بالوضعين (هوية): [ink] للأسطح الداكنة المميِّزة وللنص فوق الليموني، [lime]، [blue]، [white] للنص فوق الداكن.
/// - تتغيّر حسب الوضع: [fg] النص الأساسي، [surface] البطاقات، [paper] الخلفية، والمحايدة والخلفيات الناعمة.
/// الليموني ما يُستخدم أبداً كنص على خلفية فاتحة — للنص الملوّن على الفاتح استخدم الأزرق.
abstract final class WColors {
  /// الوضع الحالي. يغيّره [WaselThemeController] فقط.
  static bool isDark = false;
  static Color _m(Color light, Color dark) => isDark ? dark : light;

  // ---- الهوية (ثابتة) ----
  static const ink = Color(0xFF111923); // Primary Ink — أسطح داكنة مميِّزة + نص فوق الليموني
  static const graphite = Color(0xFF303943); // Graphite
  static const lime = Color(0xFFD8F36A); // Electric Lime
  static const limeDeep = Color(0xFF9DB82C);
  static const white = Color(0xFFFFFFFF); // نص/أيقونات فوق الأسطح الداكنة
  static const inkSurface = Color(0xFF1B2531); // سطح فوق الحبر
  static const success = Color(0xFF1E8A5A);
  static const warning = Color(0xFFB57514);
  static const danger = Color(0xFFD2412F);
  static const blue = Color(0xFF4058E8); // Electric Blue — تعبئة (أزرار، علامات، بلاطات)

  // ---- تتغيّر حسب الوضع ----
  static Color get fg => _m(ink, const Color(0xFFEEF0EA)); // النص الأساسي
  static Color get link => _m(blue, const Color(0xFF8C9DFF)); // نص أزرق (روابط، أسعار) — أفتح بالليل للتباين
  static Color get paper => _m(const Color(0xFFF4F2EC), const Color(0xFF0A0F14)); // الخلفية
  static Color get surface => _m(white, const Color(0xFF151D26)); // البطاقات والحقول
  static Color get surfaceAlt => _m(const Color(0xFFEBE8DF), const Color(0xFF1F2933));
  static Color get line => _m(const Color(0xFFE3E0D7), const Color(0xFF2A3540));
  static Color get inkMuted => _m(const Color(0xFF5B6570), const Color(0xFFA3ACB5));
  static Color get inkFaint => _m(const Color(0xFF98A0A8), const Color(0xFF6E7883));
  static Color get limeSoft => _m(const Color(0xFFF0F9CF), const Color(0xFF2A3315));
  static Color get blueSoft => _m(const Color(0xFFE6E9FC), const Color(0xFF1E2550));
  static Color get successSoft => _m(const Color(0xFFDDF1E6), const Color(0xFF12301F));
  static Color get warningSoft => _m(const Color(0xFFF7EBD3), const Color(0xFF33270F));
  static Color get dangerSoft => _m(const Color(0xFFFAE3DF), const Color(0xFF3A1A15));

  /// الأسطح الداكنة المميِّزة (البطاقة الرئيسية، الشريط الجانبي): بالليل أفتح شوية من الخلفية حتى تبين
  static Color get night => _m(ink, const Color(0xFF1A2430));
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
  static List<BoxShadow> get soft => [BoxShadow(color: WColors.isDark ? const Color(0x66000000) : const Color(0x14111923), blurRadius: 16, offset: const Offset(0, 6))];
  static List<BoxShadow> get lifted => [BoxShadow(color: WColors.isDark ? const Color(0x99000000) : const Color(0x26111923), blurRadius: 30, offset: const Offset(0, 12))];
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
  static TextStyle get _base => TextStyle(
        fontFamily: kWaselFont,
        fontFamilyFallback: kWaselFallback,
        color: WColors.fg,
        height: 1.5,
        letterSpacing: 0,
      );

  /// Display — العناوين الكبيرة جداً (الترحيب، الأرقام الرئيسية)
  static TextStyle get display => _base.copyWith(fontSize: 32, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.4);

  /// Heading — عناوين الصفحات والأقسام
  static TextStyle get h1 => _base.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.2);
  static TextStyle get h2 => _base.copyWith(fontSize: 19, fontWeight: FontWeight.w600, height: 1.35);

  /// Title — أسماء المحلات والمنتجات
  static TextStyle get h3 => _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4);

  /// Body
  static TextStyle get body => _base.copyWith(fontSize: 14.5, fontWeight: FontWeight.w400);
  static TextStyle get bodyStrong => _base.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500);
  static TextStyle get small => _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: WColors.inkMuted);

  /// Caption — تفاصيل ثانوية
  static TextStyle get caption => _base.copyWith(fontSize: 12, fontWeight: FontWeight.w400, color: WColors.inkMuted, height: 1.4);

  /// Label — الأزرار والحقول والوسوم
  static TextStyle get button => _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2);
  static TextStyle get label => _base.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.2);

  /// Price — الأسعار والأرقام (أرقام متساوية العرض حتى ما تتراقص عند التحديث)
  static TextStyle get price => _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle get number => _base.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]);

  /// Overline — عناوين صغيرة فوق الأقسام
  static TextStyle get overline => _base.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: WColors.inkMuted, letterSpacing: 0.4);
}
