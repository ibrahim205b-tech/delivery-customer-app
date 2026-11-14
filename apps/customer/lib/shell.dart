import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        bottomNavigationBar: _WaselNav(
          index: _tab,
          onSelect: (i) => setState(() => _tab = i),
          items: const [
            (Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
            (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'طلباتي'),
            (Icons.favorite_outline_rounded, Icons.favorite_rounded, 'المفضلة'),
            (Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
          ],
        ),
      );
}

/// شريط التنقل: كبسولة داكنة طافية. التبويب المختار يتمدد لزر ليموني مع اسمه، والباقي أيقونات.
class _WaselNav extends StatelessWidget {
  const _WaselNav({required this.index, required this.onSelect, required this.items});
  final int index;
  final ValueChanged<int> onSelect;
  final List<(IconData, IconData, String)> items;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: WColors.paper,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Container(
              height: 64,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(22), border: Border.all(color: WColors.line), boxShadow: WShadow.soft),
              child: Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    flex: i == index ? 5 : 3,
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      label: items[i].$3,
                      onTap: () => onSelect(i),
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i != index) HapticFeedback.selectionClick();
                          onSelect(i);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 380),
                          curve: Curves.easeOutBack,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(color: i == index ? WColors.night : Colors.transparent, borderRadius: WRadius.all(16)),
                          child: Center(
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              TweenAnimationBuilder<double>(
                                key: ValueKey('nav-$i-${i == index}'),
                                tween: Tween(begin: i == index ? 0.6 : 1, end: 1),
                                duration: const Duration(milliseconds: 520),
                                curve: Curves.elasticOut,
                                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                                child: Icon(i == index ? items[i].$2 : items[i].$1, size: 22, color: i == index ? WColors.white : WColors.inkFaint),
                              ),
                              if (i == index) ...[
                                const SizedBox(width: 6),
                                Flexible(child: Text(items[i].$3, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: WText.label.copyWith(color: WColors.white, fontWeight: FontWeight.w700))),
                              ],
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}
