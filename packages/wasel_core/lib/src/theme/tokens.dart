import 'package:flutter/material.dart';

/// لوحة ألوان كاملة لتطبيق واحد. كل تطبيق يختار لوحته عند التشغيل ([WColors.palette]).
///
/// الأدوار (نفسها بكل اللوحات حتى ما تتغيّر الشاشات):
/// - [ink]: أغمق لون؛ نص فوق [lime] ونص أساسي بالنهاري.
/// - [lime]: لون التمييز (تعبئة الأزرار الرئيسية والشارات) ونصه دائماً [ink].
/// - [blue]: لون التفاعل (روابط، أسعار، تعبئة نصها أبيض).
/// - [night]: الأسطح المميِّزة الداكنة/الملوّنة ونصها أبيض.
class WPalette {
  const WPalette({
    required this.name,
    required this.ink,
    required this.lime,
    required this.blue,
    required this.graphite,
    required this.inkSurface,
    required this.limeDeep,
    required this.night,
    required this.nightDark,
    required this.fgDark,
    required this.linkDark,
    required this.paper,
    required this.paperDark,
    required this.surfaceDark,
    required this.surfaceAlt,
    required this.surfaceAltDark,
    required this.line,
    required this.lineDark,
    required this.inkMuted,
    required this.inkMutedDark,
    required this.inkFaint,
    required this.inkFaintDark,
    required this.limeSoft,
    required this.limeSoftDark,
    required this.blueSoft,
    required this.blueSoftDark,
    this.coral = const Color(0xFFFF6A4D),
    this.mint = const Color(0xFF14B88F),
  });
  final String name;
  final Color ink, lime, blue, graphite, inkSurface, limeDeep, night, nightDark, fgDark, linkDark;
  final Color paper, paperDark, surfaceDark, surfaceAlt, surfaceAltDark, line, lineDark;
  final Color inkMuted, inkMutedDark, inkFaint, inkFaintDark, limeSoft, limeSoftDark, blueSoft, blueSoftDark;
  final Color coral, mint;

  /// هوية واصل الأصلية (حبر + ليموني + أزرق) — تطبيقا التاجر/السائق والإدارة
  static const classic = WPalette(
    name: 'classic',
    ink: Color(0xFF17191B),
    lime: Color(0xFFC7F464),
    blue: Color(0xFF3979E8),
    graphite: Color(0xFF2E3135),
    inkSurface: Color(0xFF232629),
    limeDeep: Color(0xFF8FB02B),
    night: Color(0xFF17191B),
    nightDark: Color(0xFF1F2124),
    fgDark: Color(0xFFEFEDE6),
    linkDark: Color(0xFF86AEF5),
    paper: Color(0xFFF3F0E8),
    paperDark: Color(0xFF0D0E0F),
    surfaceDark: Color(0xFF17191B),
    surfaceAlt: Color(0xFFE9E5DA),
    surfaceAltDark: Color(0xFF222427),
    line: Color(0xFFE2DED3),
    lineDark: Color(0xFF2D3034),
    inkMuted: Color(0xFF5E6368),
    inkMutedDark: Color(0xFFA5A9AE),
    inkFaint: Color(0xFF9A9EA3),
    inkFaintDark: Color(0xFF6F7378),
    limeSoft: Color(0xFFEDF8CB),
    limeSoftDark: Color(0xFF283214),
    blueSoft: Color(0xFFE2ECFC),
    blueSoftDark: Color(0xFF16264A),
  );

  /// هوية تطبيق الزبون الجديدة: نيلي واصل + أصفر التكسي، على خلفية سحابية هادئة.
  /// النيلي = الثقة والحركة (الأسطح المميِّزة والروابط)، الأصفر = الفعل والطاقة (الأزرار والتكسي).
  static const customer = WPalette(
    name: 'customer',
    ink: Color(0xFF15142B), // نيلي شبه أسود
    lime: Color(0xFFFFC83A), // أصفر التكسي — تعبئة نصها نيلي داكن
    blue: Color(0xFF4433E0), // نيلي واصل — الروابط والتعبئات بنص أبيض
    graphite: Color(0xFF34325A),
    inkSurface: Color(0xFF5546EA), // سطح فوق النيلي
    limeDeep: Color(0xFFC79000),
    night: Color(0xFF4433E0), // الأسطح المميِّزة = نيلي واصل
    nightDark: Color(0xFF2E2694),
    fgDark: Color(0xFFF1F0FA),
    linkDark: Color(0xFFA79FFF),
    paper: Color(0xFFF5F4FA), // خلفية سحابية
    paperDark: Color(0xFF0E0D1C),
    surfaceDark: Color(0xFF1A1930),
    surfaceAlt: Color(0xFFECEAF6),
    surfaceAltDark: Color(0xFF24223D),
    line: Color(0xFFE4E2F0),
    lineDark: Color(0xFF302E4D),
    inkMuted: Color(0xFF68668A),
    inkMutedDark: Color(0xFFB0AECB),
    inkFaint: Color(0xFFA2A0BC),
    inkFaintDark: Color(0xFF75738F),
    limeSoft: Color(0xFFFFF3D1),
    limeSoftDark: Color(0xFF3A2F0E),
    blueSoft: Color(0xFFE9E7FD),
    blueSoftDark: Color(0xFF231F57),
  );
}

/// ألوان واصل، بوضعين نهاري وليلي، حسب لوحة التطبيق الحالية.
/// الليموني ([lime]) ما يُستخدم أبداً كنص على خلفية فاتحة — للنص الملوّن على الفاتح استخدم [link].
abstract final class WColors {
  /// لوحة التطبيق. يضبطها التطبيق قبل التشغيل (الافتراضي: الهوية الأصلية).
  static WPalette palette = WPalette.classic;

  /// الوضع الحالي. يغيّره [WaselThemeController] فقط.
  static bool isDark = false;
  static Color _m(Color light, Color dark) => isDark ? dark : light;

  // ---- الهوية ----
  static Color get ink => palette.ink;
  static Color get graphite => palette.graphite;
  static Color get lime => palette.lime;
  static Color get limeDeep => palette.limeDeep;
  static Color get inkSurface => palette.inkSurface;
  static Color get blue => palette.blue;
  static Color get coral => palette.coral;
  static Color get mint => palette.mint;
  static const white = Color(0xFFFFFFFF); // نص/أيقونات فوق الأسطح الداكنة
  static const success = Color(0xFF1E8A5A);
  static const warning = Color(0xFFB57514);
  static const danger = Color(0xFFD2412F);

  // ---- تتغيّر حسب الوضع ----
  static Color get fg => _m(palette.ink, palette.fgDark); // النص الأساسي
  static Color get link => _m(palette.blue, palette.linkDark);
  static Color get paper => _m(palette.paper, palette.paperDark);
  static Color get surface => _m(white, palette.surfaceDark);
  static Color get surfaceAlt => _m(palette.surfaceAlt, palette.surfaceAltDark);
  static Color get line => _m(palette.line, palette.lineDark);
  static Color get inkMuted => _m(palette.inkMuted, palette.inkMutedDark);
  static Color get inkFaint => _m(palette.inkFaint, palette.inkFaintDark);
  static Color get limeSoft => _m(palette.limeSoft, palette.limeSoftDark);
  static Color get blueSoft => _m(palette.blueSoft, palette.blueSoftDark);
  static Color get successSoft => _m(const Color(0xFFDDF1E6), const Color(0xFF12301F));
  static Color get warningSoft => _m(const Color(0xFFF7EBD3), const Color(0xFF33270F));
  static Color get dangerSoft => _m(const Color(0xFFFAE3DF), const Color(0xFF3A1A15));

  /// الأسطح المميِّزة (البطاقة الرئيسية، الشريط الجانبي)
  static Color get night => _m(palette.night, palette.nightDark);
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
  static List<BoxShadow> get soft => [BoxShadow(color: WColors.isDark ? const Color(0x66000000) : WColors.ink.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))];
  static List<BoxShadow> get lifted => [BoxShadow(color: WColors.isDark ? const Color(0x99000000) : WColors.ink.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 12))];
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
