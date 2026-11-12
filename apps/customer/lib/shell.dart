import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import 'main.dart';
import 'screens/account.dart';
import 'screens/favorites.dart';
import 'screens/home.dart';
import 'screens/orders.dart';

/// الهيكل الرئيسي: أربع تبويبات + تنبيهات داخل التطبيق لحظياً.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _tab = 0;
  StreamSubscription<List<AppNotification>>? _notifSub;
  int? _lastSeenId;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    app.load();
    notifier.requestPermission();
    _notifSub = customerApi.watchNotifications().listen((list) {
      if (!mounted) return;
      setState(() => _unread = list.where((n) => !n.isRead).length);
      final newest = list.firstOrNull;
      if (newest == null) return;
      // أول تحميل: نسجل آخر إشعار بدون عرضه
      if (_lastSeenId != null && newest.id > _lastSeenId! && !newest.isRead) {
        // إشعار نظام بصوت (يظهر حتى لو التطبيق بالخلفية) + تنبيه داخل التطبيق
        notifier.show(newest.title, newest.body, channel: newest.data['type'] == 'support' ? WChannel.support : WChannel.updates);
        showInfo(context, '${newest.title}${newest.body.isEmpty ? '' : ' · ${newest.body}'}');
      }
      _lastSeenId = newest.id;
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: [
          HomeScreen(unread: _unread),
          const OrdersScreen(),
          const FavoritesScreen(),
          const AccountScreen(),
        ]),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: WColors.line))),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
              NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'طلباتي'),
              NavigationDestination(icon: Icon(Icons.favorite_outline_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'المفضلة'),
              NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'حسابي'),
            ],
          ),
        ),
      );
}
