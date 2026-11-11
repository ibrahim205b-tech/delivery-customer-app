import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// الثيم الموحد لتطبيقات واصل الثلاثة.
/// [accent] يميّز كل تطبيق (المستهلك: مرجاني، التاجر: كحلي، الإدارة: كحلي).
ThemeData buildWaselTheme({Color accent = WColors.coral, Color onAccent = WColors.white}) {
  final scheme = ColorScheme(
    brightness: Brightness.light,
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: WColors.coralSoft,
    onPrimaryContainer: WColors.navy,
    secondary: WColors.navy,
    onSecondary: WColors.white,
    secondaryContainer: WColors.mintSoft,
    onSecondaryContainer: WColors.navy,
    tertiary: WColors.mintDeep,
    onTertiary: WColors.white,
    error: WColors.danger,
    onError: WColors.white,
    surface: WColors.white,
    onSurface: WColors.ink,
    onSurfaceVariant: WColors.inkMuted,
    outline: WColors.line,
    outlineVariant: WColors.line,
    surfaceContainerLowest: WColors.white,
    surfaceContainerLow: WColors.white,
    surfaceContainer: WColors.ivory,
    surfaceContainerHigh: WColors.surfaceAlt,
    surfaceContainerHighest: WColors.surfaceAlt,
    surfaceTint: Colors.transparent,
    shadow: const Color(0x33172E3B),
  );

  final textTheme = TextTheme(
    displaySmall: WText.display,
    headlineMedium: WText.h1,
    headlineSmall: WText.h2,
    titleLarge: WText.h2,
    titleMedium: WText.h3,
    titleSmall: WText.bodyStrong,
    bodyLarge: WText.body,
    bodyMedium: WText.body,
    bodySmall: WText.small,
    labelLarge: WText.button,
    labelMedium: WText.caption,
    labelSmall: WText.caption.copyWith(fontSize: 11),
  );

  final buttonShape = RoundedRectangleBorder(borderRadius: WRadius.all(WRadius.md));
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kWaselFont,
    textTheme: textTheme,
    scaffoldBackgroundColor: WColors.ivory,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: WColors.ivory,
      foregroundColor: WColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: WText.h2,
      systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        disabledBackgroundColor: WColors.line,
        disabledForegroundColor: WColors.inkFaint,
        textStyle: WText.button,
        shape: buttonShape,
        padding: buttonPadding,
        minimumSize: const Size(64, 52),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WColors.ink,
        side: const BorderSide(color: WColors.line, width: 1.5),
        textStyle: WText.button,
        shape: buttonShape,
        padding: buttonPadding,
        minimumSize: const Size(64, 52),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent == WColors.coral ? WColors.coralDeep : accent,
        textStyle: WText.button,
        shape: buttonShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: WText.body.copyWith(color: WColors.inkFaint),
      labelStyle: WText.body.copyWith(color: WColors.inkMuted),
      floatingLabelStyle: WText.caption.copyWith(color: WColors.navy),
      prefixIconColor: WColors.inkMuted,
      border: OutlineInputBorder(borderRadius: WRadius.all(WRadius.md), borderSide: const BorderSide(color: WColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: WRadius.all(WRadius.md), borderSide: const BorderSide(color: WColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: WRadius.all(WRadius.md), borderSide: const BorderSide(color: WColors.navy, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: WRadius.all(WRadius.md), borderSide: const BorderSide(color: WColors.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: WRadius.all(WRadius.md), borderSide: const BorderSide(color: WColors.danger, width: 1.5)),
      errorStyle: WText.caption.copyWith(color: WColors.danger),
    ),
    cardTheme: CardThemeData(
      color: WColors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: WRadius.all(WRadius.lg), side: const BorderSide(color: WColors.line)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: WColors.white,
      selectedColor: WColors.navy,
      labelStyle: WText.caption.copyWith(color: WColors.ink),
      secondaryLabelStyle: WText.caption.copyWith(color: WColors.white),
      side: const BorderSide(color: WColors.line),
      shape: RoundedRectangleBorder(borderRadius: WRadius.all(WRadius.pill)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      showCheckmark: false,
    ),
    dividerTheme: const DividerThemeData(color: WColors.line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: WColors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: WColors.line,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(WRadius.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: WColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: WRadius.all(WRadius.lg)),
      titleTextStyle: WText.h3,
      contentTextStyle: WText.body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: WColors.navy,
      contentTextStyle: WText.body.copyWith(color: WColors.white),
      shape: RoundedRectangleBorder(borderRadius: WRadius.all(WRadius.md)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: WColors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: WColors.coralSoft,
      height: 68,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => WText.caption.copyWith(
          color: s.contains(WidgetState.selected) ? WColors.ink : WColors.inkMuted,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? WColors.ink : WColors.inkMuted, size: 24),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? WColors.white : WColors.inkFaint),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? WColors.mintDeep : WColors.surfaceAlt),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: WColors.coral, linearTrackColor: WColors.line),
    listTileTheme: ListTileThemeData(
      iconColor: WColors.inkMuted,
      titleTextStyle: WText.bodyStrong,
      subtitleTextStyle: WText.small,
      contentPadding: const EdgeInsets.symmetric(horizontal: WSpace.lg, vertical: WSpace.xs),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: WColors.ink,
      unselectedLabelColor: WColors.inkMuted,
      labelStyle: WText.bodyStrong,
      unselectedLabelStyle: WText.body,
      indicatorColor: WColors.coral,
      dividerColor: WColors.line,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
