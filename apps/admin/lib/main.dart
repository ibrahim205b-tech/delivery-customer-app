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
  runApp(WaselApp(title: 'إدارة واصل', accent: WColors.navy, home: ready ? const Root() : const NotConfiguredScreen()));
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
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        indicatorColor: WColors.mintSoft,
        onDestinationSelected: go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'اللوحة'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'الطلبات'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'المحلات'),
          NavigationDestination(icon: Icon(Icons.two_wheeler_outlined), selectedIcon: Icon(Icons.two_wheeler_rounded), label: 'السائقون'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'المزيد'),
        ],
      ),
    );
  }
}
