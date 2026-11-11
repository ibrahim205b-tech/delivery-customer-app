import 'package:flutter/material.dart';

/// ألوان واصل. كل لون له غرض محدد؛ لا تستخدم ألوان خارج هذه القائمة.
abstract final class WColors {
  // الهوية
  static const navy = Color(0xFF172E3B);
  static const navySoft = Color(0xFF2B4757);
  static const coral = Color(0xFFF0785B);
  static const coralDeep = Color(0xFFD9603F); // للنص على خلفية فاتحة (تباين أعلى)
  static const coralSoft = Color(0xFFFCE6DF);
  static const ivory = Color(0xFFF5F1E8);
  static const mint = Color(0xFFA9C8B9);
  static const mintDeep = Color(0xFF3F7A63);
  static const mintSoft = Color(0xFFE4EFEA);
  static const white = Color(0xFFFFFFFF);

  // المحايدة
  static const ink = navy;
  static const inkMuted = Color(0xFF5E6E77);
  static const inkFaint = Color(0xFF94A1A8);
  static const line = Color(0xFFE6E0D3);
  static const surfaceAlt = Color(0xFFEDE8DC);

  // الحالات
  static const success = mintDeep;
  static const successSoft = mintSoft;
  static const warning = Color(0xFFB7791F);
  static const warningSoft = Color(0xFFF8ECD6);
  static const danger = Color(0xFFC2412D);
  static const dangerSoft = Color(0xFFF9E1DC);
  static const info = Color(0xFF2F6A8A);
  static const infoSoft = Color(0xFFDDEBF2);
}

/// المسافات على شبكة 4.
abstract final class WSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const page = 20.0; // هامش الصفحة الجانبي
}

abstract final class WRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// الظلال: ظل واحد ناعم للعناصر المرفوعة فقط.
abstract final class WShadow {
  static const soft = [
    BoxShadow(color: Color(0x14172E3B), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const lifted = [
    BoxShadow(color: Color(0x22172E3B), blurRadius: 28, offset: Offset(0, 10)),
  ];
}

abstract final class WDurations {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 380);
}

const kWaselFont = 'packages/wasel_core/ReadexPro';

/// الخطوط: مقاسات مقروءة للعربي (أكبر شوية من الإنگليزي) مع ارتفاع سطر مريح.
abstract final class WText {
  static const _base = TextStyle(fontFamily: kWaselFont, color: WColors.ink, height: 1.45);

  static final display = _base.copyWith(fontSize: 30, fontWeight: FontWeight.w700, height: 1.25);
  static final h1 = _base.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3);
  static final h2 = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w600, height: 1.35);
  static final h3 = _base.copyWith(fontSize: 17, fontWeight: FontWeight.w600);
  static final body = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w400);
  static final bodyStrong = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w500);
  static final small = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: WColors.inkMuted);
  static final caption = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: WColors.inkMuted);
  static final button = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2);
  static final price = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700);
}
