import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';

import '../services/config.dart';
import '../services/errors.dart';
import '../theme/mode.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'basics.dart';

/// غلاف MaterialApp موحّد: عربي RTL، الثيم (نهاري/ليلي)، وشريط انقطاع الإنترنت.
class WaselApp extends StatefulWidget {
  const WaselApp({super.key, required this.title, required this.home, this.navigatorKey});
  final String title;
  final Widget home;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<WaselApp> createState() => _WaselAppState();
}

class _WaselAppState extends State<WaselApp> {
  @override
  void initState() {
    super.initState();
    themeController.addListener(_onTheme);
  }

  @override
  void dispose() {
    themeController.removeListener(_onTheme);
    super.dispose();
  }

  /// الألوان تُقرأ من [WColors] مباشرة بكل الشاشات، فعند تغيير الوضع نعيد بناء كل العناصر
  /// (بدون ما نفقد الحالة أو الشاشة المفتوحة).
  void _onTheme() {
    setState(() {});
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: widget.title,
        navigatorKey: widget.navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildWaselTheme(),
        themeAnimationDuration: Duration.zero,
        locale: const Locale('ar', 'IQ'),
        supportedLocales: const [Locale('ar', 'IQ'), Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: ConnectivityBanner(child: child ?? const SizedBox()),
        ),
        home: widget.home,
      );
}

/// يظهر شريط أعلى الشاشة عند انقطاع الإنترنت ويختفي عند العودة.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key, required this.child});
  final Widget child;
  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_update);
    _sub = Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> r) {
    final off = r.isEmpty || r.every((e) => e == ConnectivityResult.none);
    if (mounted && off != _offline) setState(() => _offline = off);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        AnimatedSize(
          duration: WDurations.base,
          child: _offline
              ? Material(
                  color: WColors.night,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(children: [
                        const Icon(Icons.wifi_off_rounded, color: WColors.lime, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('ما اكو إنترنت. راح نكمّل تلقائياً لما يرجع الاتصال.', style: WText.caption.copyWith(color: WColors.white))),
                      ]),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: _offline, child: widget.child)),
      ]);
}

/// شاشة تظهر إذا التطبيق انبنى بدون إعدادات Supabase
class NotConfiguredScreen extends StatelessWidget {
  const NotConfiguredScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: EmptyView(
          icon: Icons.settings_suggest_outlined,
          title: 'التطبيق غير مربوط بالخادم',
          message: 'هذه النسخة انبنت بدون SUPABASE_URL و SUPABASE_PUBLISHABLE_KEY.\nراجع ملف README لإعداد GitHub Secrets ثم أعد البناء.',
        ),
      );
}

/// شاشة البداية بهوية واصل
class SplashView extends StatelessWidget {
  const SplashView({super.key, this.caption});
  final String? caption;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WColors.night,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/brand/splash-lockup.png', package: 'wasel_core', width: 180),
            const SizedBox(height: 36),
            const SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 3, color: WColors.lime, backgroundColor: WColors.inkSurface)),
            if (caption != null) ...[const SizedBox(height: 12), Text(caption!, style: WText.caption.copyWith(color: WColors.inkFaint))],
          ]),
        ),
      );
}

/// اختيار صورة من المعرض أو الكاميرا (مضغوطة) — ترجع البايتات
Future<({Uint8List bytes, String ext})?> pickImage(BuildContext context, {double maxSide = 1280}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('من المعرض'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('بالكاميرا'), onTap: () => Navigator.pop(c, ImageSource.camera)),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (source == null) return null;
  try {
    final f = await ImagePicker().pickImage(source: source, maxWidth: maxSide, maxHeight: maxSide, imageQuality: 82);
    if (f == null) return null;
    final ext = f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    return (bytes: await f.readAsBytes(), ext: ext);
  } catch (e) {
    if (context.mounted) showError(context, 'تعذّر فتح الصور: ${friendlyError(e)}');
    return null;
  }
}

bool get backendReady => WaselConfig.isConfigured;
