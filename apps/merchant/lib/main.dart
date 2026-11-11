import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import 'driver/driver_home.dart';
import 'merchant/merchant_home.dart';

late final AuthController auth;

Future<void> main() async {
  final ready = await bootstrapWasel();
  if (ready) auth = AuthController();
  runApp(WaselApp(
    title: 'واصل للأعمال',
    accent: WColors.navy,
    home: ready ? const Root() : const NotConfiguredScreen(),
  ));
}

/// الواجهة تتحدد حسب دور الحساب بقاعدة البيانات:
/// تاجر ← لوحة المحل، سائق/مندوب ← لوحة المهام. الصلاحيات مفصولة بالخادم (RLS).
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  AppRole? _chosen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          if (!auth.isSignedIn) {
            _chosen = null;
            return PhoneAuthScreen(
              auth: auth,
              badge: 'للأعمال',
              headline: 'شغلك أسهل مع واصل.',
              subline: 'للمحلات ومقدّمي الخدمات والسائقين والمندوبين.',
            );
          }
          if (auth.profile == null) {
            if (auth.loadError != null) return Scaffold(body: ErrorView(error: auth.loadError!, onRetry: auth.refresh));
            return const SplashView();
          }
          if (!auth.profile!.isActive) return const _Blocked();
          final isMerchant = auth.hasRole(AppRole.merchant);
          final isDriver = auth.hasRole(AppRole.driver);
          if (!isMerchant && !isDriver) return const _PendingAccess();
          if (isMerchant && isDriver && _chosen == null) {
            return _RoleChooser(onChoose: (r) => setState(() => _chosen = r));
          }
          final role = _chosen ?? (isMerchant ? AppRole.merchant : AppRole.driver);
          return role == AppRole.merchant ? const MerchantHome() : const DriverHome();
        },
      );
}

class _PendingAccess extends StatelessWidget {
  const _PendingAccess();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(WSpace.xxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Spacer(),
              const WaselMark(size: 72, stroke: WColors.navy, dot: WColors.coral),
              const SizedBox(height: 24),
              Text('حسابك بانتظار الربط', style: WText.h1, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                'إدارة واصل تربط حسابك بمحلك أو بمركبتك. أعطهم رقمك حتى يفعّلوك:',
                style: WText.body.copyWith(color: WColors.inkMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: WColors.white, borderRadius: WRadius.all(WRadius.md), border: Border.all(color: WColors.line)),
                  child: Text(auth.profile?.phone ?? '', style: WText.h2, textDirection: TextDirection.ltr),
                ),
              ),
              const Spacer(),
              WButton('تحقّق مرة ثانية', icon: Icons.refresh_rounded, onPressed: auth.refresh, loading: auth.loading),
              const SizedBox(height: 10),
              WButton('تسجيل الخروج', kind: WButtonKind.ghost, onPressed: auth.signOut),
            ]),
          ),
        ),
      );
}

class _Blocked extends StatelessWidget {
  const _Blocked();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: EmptyView(
          icon: Icons.block_rounded,
          title: 'الحساب موقوف',
          message: 'تواصل مع إدارة واصل.',
          action: WButton('تسجيل الخروج', onPressed: auth.signOut, kind: WButtonKind.secondary, expand: false),
        ),
      );
}

class _RoleChooser extends StatelessWidget {
  const _RoleChooser({required this.onChoose});
  final ValueChanged<AppRole> onChoose;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(WSpace.xxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 40),
              Text('أهلاً ${auth.profile?.fullName.split(' ').first ?? ''}', style: WText.h1),
              Text('حسابك عنده أكثر من صلاحية. شنو تشتغل هسه؟', style: WText.small),
              const SizedBox(height: 28),
              _choice(Icons.storefront_rounded, 'لوحة المحل', 'الطلبات والمنتجات والمبيعات', () => onChoose(AppRole.merchant)),
              const SizedBox(height: 12),
              _choice(Icons.two_wheeler_rounded, 'لوحة السائق', 'المهام والرحلات', () => onChoose(AppRole.driver)),
              const Spacer(),
              WButton('تسجيل الخروج', kind: WButtonKind.ghost, onPressed: auth.signOut),
            ]),
          ),
        ),
      );

  Widget _choice(IconData i, String t, String s, VoidCallback f) => WCard(
        onTap: f,
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          CircleAvatar(radius: 26, backgroundColor: WColors.coralSoft, child: Icon(i, color: WColors.coralDeep)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: WText.h3), Text(s, style: WText.small)])),
          const Icon(Icons.chevron_left_rounded),
        ]),
      );
}
