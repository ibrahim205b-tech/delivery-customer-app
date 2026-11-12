import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// اختيار المظهر: تلقائي (يتبع الهاتف)، نهاري، ليلي. ينحفظ على الجهاز.
enum WaselThemeMode {
  system('تلقائي'),
  light('نهاري'),
  dark('ليلي');

  const WaselThemeMode(this.label);
  final String label;
}

class WaselThemeController extends ChangeNotifier with WidgetsBindingObserver {
  WaselThemeController._();
  static final instance = WaselThemeController._();
  static const _key = 'wasel_theme_mode';

  WaselThemeMode _mode = WaselThemeMode.system;
  WaselThemeMode get mode => _mode;
  bool _observing = false;

  /// يقرأ الاختيار المحفوظ ويضبط [WColors.isDark] قبل أول رسم.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      _mode = WaselThemeMode.values.firstWhere((m) => m.name == v, orElse: () => WaselThemeMode.system);
    } catch (_) {
      _mode = WaselThemeMode.system;
    }
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _apply(notify: false);
  }

  Future<void> setMode(WaselThemeMode m) async {
    _mode = m;
    _apply();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, m.name);
    } catch (_) {}
  }

  bool get _systemDark => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

  void _apply({bool notify = true}) {
    final dark = switch (_mode) { WaselThemeMode.system => _systemDark, WaselThemeMode.light => false, WaselThemeMode.dark => true };
    final changed = dark != WColors.isDark;
    WColors.isDark = dark;
    if (notify && changed) notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == WaselThemeMode.system) _apply();
  }
}

final themeController = WaselThemeController.instance;
