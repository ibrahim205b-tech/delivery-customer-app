import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import 'bookings_tab.dart';
import 'orders_tab.dart';
import 'products_tab.dart';
import 'stats_tab.dart';
import 'store_tab.dart';

/// لوحة التاجر. إذا الحساب يملك أكثر من محل يختار بينها.
class MerchantHome extends StatefulWidget {
  const MerchantHome({super.key});
  @override
  State<MerchantHome> createState() => _MerchantHomeState();
}

class _MerchantHomeState extends State<MerchantHome> {
  List<Merchant>? _mine;
  Merchant? _current;
  Object? _error;
  int _tab = 0;

  // مراقبة الطلبات/الحجوزات الجديدة على مستوى الصفحة (حتى لو التاجر على تبويب ثاني)
  StreamSubscription<Object>? _watch;
  String? _watchedId;
  Set<String>? _known;
  int _newCount = 0;

  void _watchIncoming(Merchant m) {
    if (_watchedId == m.id) return;
    _watch?.cancel();
    _watchedId = m.id;
    _known = null;
    final isProvider = m.categoryId == 'home_services';
    final Stream<Set<String>> pending = isProvider
        ? merchantApi.watchBookings(m.id).map((l) => l.where((b) => b.status == BookingStatus.requested).map((b) => b.id).toSet())
        : merchantApi.watchOrders(m.id).map((l) => l.where((o) => o.status == OrderStatus.placed).map((o) => o.id).toSet());
    _watch = pending.listen((ids) {
      final fresh = _known == null ? <String>{} : ids.difference(_known!);
      _known = {...?_known, ...ids};
      if (mounted) setState(() => _newCount = ids.length);
      if (fresh.isEmpty) return;
      final what = isProvider ? 'حجز' : 'طلب';
      notifier.show(fresh.length == 1 ? '$what جديد!' : '${fresh.length} ${isProvider ? 'حجوزات' : 'طلبات'} جديدة', 'افتح واصل شريك وأكّد بسرعة', channel: WChannel.orders);
      if (mounted) showInfo(context, fresh.length == 1 ? 'وصلك $what جديد!' : 'وصلتك ${fresh.length} ${isProvider ? 'حجوزات' : 'طلبات'} جديدة');
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    notifier.requestPermission();
  }

  Future<void> _load() async {
    try {
      final list = await merchantApi.myMerchants();
      setState(() {
        _mine = list;
        _error = null;
        _current = list.where((m) => m.id == _current?.id).firstOrNull ?? list.firstOrNull;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  void _updated(Merchant m) => setState(() {
        _current = m;
        _mine = [for (final x in _mine!) x.id == m.id ? m : x];
      });

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(body: ErrorView(error: _error!, onRetry: _load));
    if (_mine == null) return const Scaffold(body: LoadingView());
    final m = _current;
    if (m == null) {
      return Scaffold(
        body: EmptyView(
          icon: Icons.storefront_outlined,
          title: 'ما مربوط بحسابك أي محل',
          message: 'إدارة واصل تضيف المحل وتربطه برقمك.',
          action: Column(mainAxisSize: MainAxisSize.min, children: [
            WButton('تحديث', onPressed: _load, kind: WButtonKind.secondary, expand: false),
            const SizedBox(height: 10),
            WButton('تواصل مع الدعم', icon: Icons.support_agent_rounded, kind: WButtonKind.ghost, expand: false, onPressed: () => showSupportSheet(context, app: SupportApp.merchant)),
          ]),
        ),
      );
    }
    _watchIncoming(m);
    final isProvider = m.categoryId == 'home_services';
    final tabs = <(String, IconData, IconData, Widget)>[
      if (isProvider)
        ('الحجوزات', Icons.event_note_outlined, Icons.event_note_rounded, BookingsTab(merchant: m))
      else
        ('الطلبات', Icons.receipt_long_outlined, Icons.receipt_long_rounded, OrdersTab(merchant: m)),
      if (!isProvider) ('المنتجات', Icons.inventory_2_outlined, Icons.inventory_2_rounded, ProductsTab(merchant: m)),
      if (!isProvider) ('المبيعات', Icons.insights_outlined, Icons.insights_rounded, StatsTab(merchant: m)),
      ('المحل', Icons.storefront_outlined, Icons.storefront_rounded, StoreTab(merchant: m, onUpdated: _updated)),
    ];
    final tab = _tab.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: WSpace.page,
        title: Row(children: [
          MerchantLogo(name: m.name, url: m.logoUrl, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: _mine!.length > 1
                ? DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: m.id,
                      isExpanded: true,
                      style: WText.h3,
                      items: [for (final x in _mine!) DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))],
                      onChanged: (id) => setState(() => _current = _mine!.firstWhere((x) => x.id == id)),
                    ),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, style: WText.h3, overflow: TextOverflow.ellipsis),
                    Text(_statusText(m), style: WText.caption.copyWith(color: m.isOpenNow ? WColors.success : WColors.danger)),
                  ]),
          ),
        ]),
        actions: const [SupportIconButton(app: SupportApp.merchant), SizedBox(width: 6)],
      ),
      body: KeyedSubtree(key: ValueKey('${m.id}-$tab'), child: tabs[tab].$4),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (var i = 0; i < tabs.length; i++)
            NavigationDestination(
              // شارة بعدد الطلبات/الحجوزات الجديدة على أول تبويب
              icon: Badge(isLabelVisible: i == 0 && _newCount > 0, label: Text('$_newCount'), child: Icon(tabs[i].$2)),
              selectedIcon: Badge(isLabelVisible: i == 0 && _newCount > 0, label: Text('$_newCount'), child: Icon(tabs[i].$3)),
              label: tabs[i].$1,
            ),
        ],
      ),
    );
  }

  String _statusText(Merchant m) {
    if (m.status == MerchantStatus.pending) return 'بانتظار اعتماد الإدارة';
    if (m.status == MerchantStatus.suspended) return 'موقوف من الإدارة';
    if (!m.isAcceptingOrders) return 'استقبال الطلبات موقف';
    return m.isOpenNow ? 'مفتوح ويستقبل طلبات' : 'خارج أوقات العمل';
  }
}

/// مستخدم في أكثر من تبويب
Future<void> signOutFlow(BuildContext context) async {
  if (await confirmDialog(context, title: 'تسجيل الخروج؟', confirm: 'خروج')) await auth.signOut();
}
