import 'package:flutter/material.dart';

import '../theme/mode.dart';
import '../theme/tokens.dart';

/// اختيار المظهر: تلقائي / نهاري / ليلي (بطاقة إعدادات)
class ThemeModeTile extends StatelessWidget {
  const ThemeModeTile({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: themeController,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(WSpace.lg, 12, WSpace.lg, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(WColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, color: WColors.fg),
              const SizedBox(width: 16),
              Expanded(child: Text('المظهر', style: WText.bodyStrong)),
            ]),
            const SizedBox(height: 10),
            SegmentedButton<WaselThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: WaselThemeMode.system, icon: Icon(Icons.brightness_auto_outlined, size: 18), label: Text('تلقائي')),
                ButtonSegment(value: WaselThemeMode.light, icon: Icon(Icons.light_mode_outlined, size: 18), label: Text('نهاري')),
                ButtonSegment(value: WaselThemeMode.dark, icon: Icon(Icons.dark_mode_outlined, size: 18), label: Text('ليلي')),
              ],
              selected: {themeController.mode},
              onSelectionChanged: (v) => themeController.setMode(v.first),
            ),
          ]),
        ),
      );
}

/// ورقة سفلية لاختيار المظهر (للشاشات اللي ما بيها صفحة إعدادات)
Future<void> showThemeSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const SafeArea(child: ThemeModeTile()),
    );
