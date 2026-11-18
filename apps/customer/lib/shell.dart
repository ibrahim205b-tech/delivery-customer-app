import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import 'main.dart';
import 'screens/account.dart';
import 'screens/favorites.dart';
import 'screens/home.dart';
import 'screens/orders.dart';
import 'screens/wallet.dart';

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
          const FavoritesScreen(),
          const WalletScreen(),
          const OrdersScreen(),
          const AccountScreen(),
        ]),
        // نفس ترتيب المرجع من اليسار لليمين: الرئيسية، المفضلة، محفظتي، طلباتي، حسابي
        bottomNavigationBar: _WaselNav(
          index: _tab,
          onSelect: (i) => setState(() => _tab = i),
          items: const [
            (Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
            (Icons.favorite_outline_rounded, Icons.favorite_rounded, 'المفضلة'),
            (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'محفظتي'),
            (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'طلباتي'),
            (Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
          ],
        ),
      );
}

/// شريط التنقل كما في المرجع: أبيض، خمس تبويبات من اليسار لليمين، والمختار أحمر مع خط تحته.
class _WaselNav extends StatelessWidget {
  const _WaselNav({required this.index, required this.onSelect, required this.items});
  final int index;
  final ValueChanged<int> onSelect;
  final List<(IconData, IconData, String)> items;

  static const _red = Color(0xFFE3161B);
  static const _grey = Color(0xFF55555E);

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFECEAF2))),
          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, -2))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      label: items[i].$3,
                      excludeSemantics: true,
                      onTap: () => onSelect(i),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i != index) HapticFeedback.selectionClick();
                          onSelect(i);
                        },
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Icon(i == index ? items[i].$2 : items[i].$1, size: 25, color: i == index ? _red : _grey),
                          const SizedBox(height: 3),
                          Text(items[i].$3,
                              maxLines: 1,
                              style: WText.label.copyWith(fontSize: 11.5, fontWeight: i == index ? FontWeight.w800 : FontWeight.w500, color: i == index ? _red : _grey)),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            height: 3,
                            width: i == index ? 52 : 0,
                            decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(2)),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
