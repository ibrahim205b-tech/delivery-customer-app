import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import 'screens/dashboard.dart';
import 'screens/drivers.dart';
import 'screens/merchants.dart';
import 'screens/more.dart';
import 'screens/orders.dart';

late final AuthController auth;

Future<void> main() async {
  final ready = await bootstrapWasel();
  if (ready) auth = AuthController();
  runApp(WaselApp(title: 'إدارة واصل', home: ready ? const Root() : const NotConfiguredScreen()));
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          if (!auth.isSignedIn) {
            return PhoneAuthScreen(
              auth: auth,
              allowSignUp: false,
              badge: 'الإدارة',
              headline: 'مركز التحكم.',
              subline: 'المحلات، الطلبات، السائقون، والإعدادات من مكان واحد.',
            );
          }
          if (auth.profile == null) {
            if (auth.loadError != null) return Scaffold(body: ErrorView(error: auth.loadError!, onRetry: auth.refresh));
            return const SplashView();
          }
          if (!auth.hasRole(AppRole.admin) || !auth.profile!.isActive) {
            return Scaffold(
              body: EmptyView(
                icon: Icons.admin_panel_settings_outlined,
                title: 'هذا الحساب ما عنده صلاحية إدارة',
                message: 'صلاحية الإدارة تُمنح من قاعدة البيانات (راجع README).',
                action: WButton('تسجيل الخروج', onPressed: auth.signOut, kind: WButtonKind.secondary, expand: false),
              ),
            );
          }
          return const AdminShell();
        },
      );
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tab = 0;

  void go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onOpenMerchants: () => go(2), onOpenOrders: () => go(1)),
      const AdminOrdersScreen(),
      const MerchantsScreen(),
      const DriversScreen(),
      const MoreScreen(),
    ];
    const dests = [
      (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'اللوحة'),
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'الطلبات'),
      (Icons.storefront_outlined, Icons.storefront_rounded, 'المحلات'),
      (Icons.two_wheeler_outlined, Icons.two_wheeler_rounded, 'السائقون'),
      (Icons.tune_outlined, Icons.tune_rounded, 'المزيد'),
    ];
    final body = IndexedStack(index: _tab, children: pages);
    if (MediaQuery.sizeOf(context).width >= 900) {
      // تابلت/شاشة واسعة: شريط جانبي داكن مثل لوحات SaaS
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: WaselMark(size: 36, route: WColors.lime, ring: WColors.white)),
            destinations: [
              for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: go,
        destinations: [
          for (final d in dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
