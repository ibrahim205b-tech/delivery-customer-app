import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../widgets.dart';
import 'account.dart';
import 'errand.dart';
import 'home_services.dart';
import 'merchant_list.dart';
import 'merchant_page.dart';
import 'notifications.dart';
import 'order_tracking.dart';
import 'rides.dart';
import 'search.dart';

/// يفتح القسم بالشاشة المناسبة لطبيعة الخدمة
void openCategory(BuildContext context, MerchantCategory c) {
  final Widget page = switch (c.kind) {
    CategoryKind.store => MerchantListScreen(category: c),
    CategoryKind.homeService => const HomeServicesScreen(),
    CategoryKind.ride => RideRequestScreen(vehicle: c.id == 'tuktuk' ? VehicleType.tuktuk : VehicleType.taxi),
    CategoryKind.courier => const ErrandRequestScreen(kind: TaskKind.courier),
    CategoryKind.parcel => const ErrandRequestScreen(kind: TaskKind.parcel),
  };
  Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

void openMerchant(BuildContext context, Merchant m) => Navigator.push(context, MaterialPageRoute(builder: (_) => MerchantPage(merchant: m)));

// =====================================================================
// الصفحة الرئيسية — الإصدار 4
//
// الترتيب حسب الأولوية:
//   1. وين أوصل (العنوان) + التنبيهات
//   2. البحث (يثبت أعلى الشاشة عند التمرير)
//   3. المنطقة
//   4. طلبك الشغّال (إذا موجود) — أهم شي يشوفه الزبون
//   5. العروض (بطاقات كبيرة تتقلّب)
//   6. المشاوير (لوحة تحكم: تكسي، تكتك، مندوب، أغراض)
//   7. الأسواق (رف أقسام بأحجام وألوان مختلفة + الخدمات المنزلية)
//   8. مقترح لك (بطاقات محلات كبيرة)
//   9. الأكثر طلباً (لوحة ترتيب)
//  10. توصيل مجاني قريب منك
//  11. اطلب مرة ثانية
// كل الأرقام والصور من بيانات الخادم الحقيقية؛ القسم يختفي إذا ما عنده بيانات.
// =====================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.unread});
  final int unread;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _data = _load();

  Future<_HomeData> _load() async {
    final r = await Future.wait([
      catalogApi.merchants(areaId: app.selectedAreaId),
      catalogApi.activePromotions(),
      customerApi.myOrders(limit: 6),
      catalogApi.homeServices().catchError((_) => <HomeService>[]),
    ]);
    return _HomeData(r[0] as List<Merchant>, r[1] as List<Promotion>, r[2] as List<Order>, r[3] as List<HomeService>);
  }

  Future<void> _refresh() async {
    await app.load();
    final f = _load();
    setState(() => _data = f);
    await f.then((_) {}, onError: (_) {});
  }

  void _addAddress() => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressFormScreen()));

  void _selectArea(String? id) {
    HapticFeedback.selectionClick();
    app.selectArea(id);
    setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WColors.paper,
        bottomNavigationBar: const CartBar(),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            if (app.loadError != null && !app.loaded) return SafeArea(child: ErrorView(error: app.loadError!, onRetry: _refresh));
            return SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: WColors.fg,
                onRefresh: _refresh,
                child: FutureBuilder<_HomeData>(
                  future: _data,
                  builder: (context, s) {
                    final d = s.data;
                    final active = d?.recent.where((o) => o.status.isActive).firstOrNull;
                    var i = 0;
                    Widget reveal(Widget w) => _Reveal(index: i++, child: w);
                    return CustomScrollView(slivers: [
                      SliverToBoxAdapter(child: _Header(unread: widget.unread, onAddress: () => pickAddressSheet(context, onAddNew: _addAddress))),
                      SliverPersistentHeader(pinned: true, delegate: _SearchHeader()),
                      SliverToBoxAdapter(child: _AreaTabs(onSelect: _selectArea)),
                      if (active != null) SliverToBoxAdapter(child: reveal(_LiveOrder(order: active, onClosed: () => setState(() => _data = _load())))),
                      if (s.hasError) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(error: s.error!, onRetry: _refresh))),
                      if (d == null && !s.hasError) const SliverToBoxAdapter(child: _Loading()),
                      if (d != null && d.promotions.isNotEmpty) SliverToBoxAdapter(child: reveal(_OfferDeck(promos: d.promotions))),
                      SliverToBoxAdapter(child: reveal(const _MoveDock())),
                      if (d != null) SliverToBoxAdapter(child: reveal(_Markets(data: d))),
                      if (d != null) ..._stores(d, reveal),
                      if (d != null && d.recent.where((o) => !o.status.isActive).isNotEmpty) SliverToBoxAdapter(child: reveal(_Reorder(orders: d.recent.where((o) => !o.status.isActive).toList()))),
                      const SliverToBoxAdapter(child: _Footer()),
                    ]);
                  },
                ),
              ),
            );
          },
        ),
      );

  List<Widget> _stores(_HomeData d, Widget Function(Widget) reveal) {
    final storeCatIds = app.categories.where((c) => c.kind == CategoryKind.store).map((c) => c.id).toSet();
    if (!d.merchants.any((m) => storeCatIds.contains(m.categoryId))) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyView(icon: Icons.storefront_outlined, title: 'ما اكو محلات بهذه المنطقة بعد', message: 'المحلات تظهر هنا بعد ما تعتمدها إدارة واصل.'),
          ),
        ),
      ];
    }
    final ref = app.referencePoint;
    // أقسام المحلات فقط (مزودي الخدمات المنزلية لهم شاشتهم الخاصة)
    final storeCats = app.categories.where((c) => c.kind == CategoryKind.store).map((c) => c.id).toSet();
    final picks = d.merchants.where((m) => storeCats.contains(m.categoryId)).toList();
    if (ref != null) {
      picks.sort((a, b) => distanceKm(ref.latitude, ref.longitude, a.lat, a.lng).compareTo(distanceKm(ref.latitude, ref.longitude, b.lat, b.lng)));
    }
    // المفتوح أولاً
    picks.sort((a, b) => (b.isOpenNow ? 1 : 0) - (a.isOpenNow ? 1 : 0));
    final popular = picks.where((m) => m.orderCount > 0).toList()..sort((a, b) => b.orderCount.compareTo(a.orderCount));
    final free = picks.where((m) => m.deliveryFee == 0 && m.isOpenNow).toList();
    return [
      SliverToBoxAdapter(child: reveal(_Picks(merchants: picks.take(10).toList(), nearby: ref != null))),
      if (popular.length >= 2) SliverToBoxAdapter(child: reveal(_Leaderboard(merchants: popular.take(6).toList()))),
      if (free.isNotEmpty) SliverToBoxAdapter(child: reveal(_FreeDelivery(merchants: free.take(8).toList()))),
    ];
  }
}

class _HomeData {
  _HomeData(this.merchants, this.promotions, this.recent, this.homeServices);
  final List<Merchant> merchants;
  final List<Promotion> promotions;
  final List<Order> recent;
  final List<HomeService> homeServices;
}

// =====================================================================
// عناصر مشتركة
// =====================================================================

/// عنوان قسم: سطر عريض + وصف قصير
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.title, {this.sub});
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.page, 30, WSpace.page, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: WText.h1.copyWith(fontSize: 22)),
          if (sub != null) Text(sub!, style: WText.small),
        ]),
      );
}

/// ظهور تدريجي للأقسام عند أول تحميل (حركة قصيرة وهادئة)
class _Reveal extends StatefulWidget {
  const _Reveal({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _shown = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(Duration(milliseconds: 40 + 55 * math.min(widget.index, 6)), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: WDurations.slow,
        curve: WDurations.curve,
        child: AnimatedSlide(offset: _shown ? Offset.zero : const Offset(0, 0.04), duration: WDurations.slow, curve: WDurations.curve, child: widget.child),
      );
}

/// شارة صغيرة (عدد، حالة)
class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: WRadius.all(7)),
        child: Text(text, style: WText.label.copyWith(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
      );
}

// =====================================================================
// 1) الرأس: العنوان + التنبيهات
// =====================================================================
class _Header extends StatelessWidget {
  const _Header({required this.unread, required this.onAddress});
  final int unread;
  final VoidCallback onAddress;

  @override
  Widget build(BuildContext context) {
    final a = app.selectedAddress;
    final h = DateTime.now().hour;
    final greet = h < 5 ? 'سهرانين؟' : (h < 12 ? 'صباح الخير' : 'مساء الخير');
    final first = (auth.profile?.fullName ?? '').split(' ').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(WSpace.page, 12, WSpace.page, 4),
      child: Row(children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'تغيير عنوان التوصيل',
            onTap: onAddress,
            excludeSemantics: true,
            child: Pressable(
              onTap: onAddress,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(first.isEmpty ? greet : '$greet، $first', style: WText.caption),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(7)),
                    child: const Icon(Icons.near_me_rounded, size: 14, color: WColors.ink),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Text(a == null ? 'أضف عنوان التوصيل' : a.oneLine, style: WText.h3.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Icon(Icons.keyboard_arrow_down_rounded, color: WColors.fg, size: 22),
                ]),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Stack(clipBehavior: Clip.none, children: [
          WIconButton(Icons.notifications_none_rounded, bordered: true, tooltip: 'الإشعارات', onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          }),
          if (unread > 0)
            PositionedDirectional(
              top: -5,
              end: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: WColors.blue, borderRadius: WRadius.all(8), border: Border.all(color: WColors.paper, width: 2)),
                child: Text('${unread > 9 ? '9+' : unread}', textAlign: TextAlign.center, style: WText.number.copyWith(fontSize: 10.5, color: WColors.white)),
              ),
            ),
        ]),
      ]),
    );
  }
}

// =====================================================================
// 2) البحث — يثبت فوق عند التمرير
// =====================================================================
class _SearchHeader extends SliverPersistentHeaderDelegate {
  static const _h = 76.0;

  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final pinned = overlapsContent || shrinkOffset > 0;
    return AnimatedContainer(
      duration: WDurations.fast,
      color: WColors.paper,
      padding: const EdgeInsets.fromLTRB(WSpace.page, 10, WSpace.page, 10),
      foregroundDecoration: BoxDecoration(border: Border(bottom: BorderSide(color: pinned ? WColors.line : Colors.transparent))),
      child: Semantics(
        button: true,
        label: 'بحث',
        onTap: () => _open(context),
        excludeSemantics: true,
        child: Pressable(
          onTap: () => _open(context),
          child: Container(
            height: 56,
            padding: const EdgeInsetsDirectional.only(start: 18, end: 6),
            decoration: BoxDecoration(color: WColors.night, borderRadius: WRadius.all(18)),
            child: Row(children: [
              Expanded(child: Text('دوّر على مطعم، منتج أو محل', style: WText.body.copyWith(color: const Color(0xFFB9BCC0)), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(14)),
                child: const Icon(Icons.search_rounded, color: WColors.ink),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));

  @override
  bool shouldRebuild(covariant _SearchHeader old) => false;
}

// =====================================================================
// 3) المنطقة — تبويبات نصية بخط سفلي ليموني
// =====================================================================
class _AreaTabs extends StatelessWidget {
  const _AreaTabs({required this.onSelect});
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final areas = app.areas.where((a) => a.isActive).toList();
    if (areas.length < 2) return const SizedBox(height: 4);
    Widget tab(String label, bool sel, VoidCallback f) => Semantics(
          selected: sel,
          button: true,
          child: InkWell(
            onTap: f,
            borderRadius: WRadius.all(8),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 18, top: 6, bottom: 4),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: (sel ? WText.bodyStrong.copyWith(fontWeight: FontWeight.w700) : WText.body).copyWith(color: sel ? WColors.fg : WColors.inkMuted)),
                const SizedBox(height: 4),
                AnimatedContainer(duration: WDurations.base, curve: WDurations.curve, height: 4, width: sel ? 26 : 0, decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(2))),
              ]),
            ),
          ),
        );
    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: WSpace.page), children: [
        tab('كل المناطق', app.selectedAreaId == null, () => onSelect(null)),
        for (final ar in areas) tab(ar.name, app.selectedAreaId == ar.id, () => onSelect(ar.id)),
      ]),
    );
  }
}

// =====================================================================
// 4) الطلب الشغّال — تذكرة حيّة
// =====================================================================
class _LiveOrder extends StatelessWidget {
  const _LiveOrder({required this.order, required this.onClosed});
  final Order order;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final group = switch (o.status) {
      OrderStatus.placed => 0,
      OrderStatus.accepted || OrderStatus.preparing || OrderStatus.ready => 1,
      OrderStatus.pickedUp || OrderStatus.onTheWay => 2,
      _ => 3,
    };
    const steps = ['انرسل', 'يتجهّز', 'بالطريق', 'وصل'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(WSpace.page, 14, WSpace.page, 0),
      child: Semantics(
        button: true,
        label: 'تتبّع طلبك: ${o.status.label}',
        child: Pressable(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: o.id)));
            onClosed();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(color: WColors.night, borderRadius: WRadius.all(WRadius.xl)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const _LivePulse(),
                const SizedBox(width: 8),
                Expanded(child: Text('طلبك الحالي · ${o.merchantName ?? ''}', style: WText.label.copyWith(color: const Color(0xFFB9BCC0)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(o.code, style: WText.label.copyWith(color: WColors.lime)),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Text(o.status.label, style: WText.h1.copyWith(color: WColors.white, fontSize: 22))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('تتبّع', style: WText.label.copyWith(color: WColors.ink, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_back_rounded, size: 16, color: WColors.ink),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AnimatedContainer(
                        duration: WDurations.slow,
                        height: 6,
                        decoration: BoxDecoration(color: i <= group ? WColors.lime : WColors.white.withValues(alpha: 0.12), borderRadius: WRadius.all(3)),
                      ),
                      const SizedBox(height: 6),
                      Text(steps[i], style: WText.caption.copyWith(fontSize: 11, color: i <= group ? WColors.white : const Color(0xFF7D8186))),
                    ]),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse();
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
        child: Container(width: 8, height: 8, decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(2))),
      );
}

// =====================================================================
// 5) العروض — بطاقات كبيرة تتقلّب تلقائياً
// =====================================================================
class _OfferDeck extends StatefulWidget {
  const _OfferDeck({required this.promos});
  final List<Promotion> promos;
  @override
  State<_OfferDeck> createState() => _OfferDeckState();
}

class _OfferDeckState extends State<_OfferDeck> {
  final _pc = PageController(viewportFraction: 0.9);
  int _page = 0;
  Timer? _auto;
  DateTime _touched = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (widget.promos.length > 1) {
      _auto = Timer.periodic(const Duration(seconds: 5), (_) {
        // يوقف التقليب التلقائي إذا المستخدم يتصفح بنفسه
        if (!_pc.hasClients || DateTime.now().difference(_touched).inSeconds < 8) return;
        _pc.animateToPage((_page + 1) % widget.promos.length, duration: const Duration(milliseconds: 520), curve: Curves.easeInOutCubic);
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pc.dispose();
    super.dispose();
  }

  Future<void> _open(Promotion p) async {
    if (p.merchantId == null) return;
    final m = await catalogApi.merchant(p.merchantId!);
    if (m != null && mounted) openMerchant(context, m);
  }

  @override
  Widget build(BuildContext context) {
    final promos = widget.promos;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(children: [
        SizedBox(
          height: 176,
          child: Listener(
            onPointerDown: (_) => _touched = DateTime.now(),
            child: PageView.builder(
              controller: _pc,
              padEnds: false,
              itemCount: promos.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsetsDirectional.only(start: i == 0 ? WSpace.page : 6, end: i == promos.length - 1 ? WSpace.page : 6),
                child: _OfferCard(p: promos[i], style: i % 3, onTap: () => _open(promos[i])),
              ),
            ),
          ),
        ),
        if (promos.length > 1) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < promos.length; i++)
              AnimatedContainer(
                duration: WDurations.base,
                curve: WDurations.curve,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 22 : 6,
                height: 6,
                decoration: BoxDecoration(color: i == _page ? WColors.fg : WColors.line, borderRadius: WRadius.all(3)),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// بطاقة عرض: صورة حقيقية إذا موجودة، وإلا ملصق طباعي بألوان الهوية
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.p, required this.style, required this.onTap});
  final Promotion p;
  final int style; // 0 ليموني، 1 حبر، 2 أزرق
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImg = p.imageUrl != null && p.imageUrl!.isNotEmpty;
    final (bg, fg, sub, tagBg, tagFg) = switch (style) {
      0 => (WColors.lime, WColors.ink, const Color(0xFF3B4A12), WColors.ink, WColors.lime),
      1 => (WColors.night, WColors.white, const Color(0xFFB9BCC0), WColors.lime, WColors.ink),
      _ => (WColors.blue, WColors.white, const Color(0xFFDCE7FB), WColors.white, WColors.blue),
    };
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _Tag(p.merchantId == null ? 'عرض واصل' : 'عرض', bg: hasImg ? WColors.lime : tagBg, fg: hasImg ? WColors.ink : tagFg),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.title, style: WText.h1.copyWith(fontSize: 22, height: 1.2, color: hasImg ? WColors.white : fg), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (p.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(p.description, style: WText.small.copyWith(color: hasImg ? const Color(0xFFE5E5E5) : sub), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ]),
    ]);
    return Semantics(
      button: p.merchantId != null,
      label: p.title,
      child: Pressable(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: bg, borderRadius: WRadius.all(WRadius.xl)),
          child: hasImg
              ? Stack(fit: StackFit.expand, children: [
                  WImage(p.imageUrl, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x0017191B), Color(0xCC17191B)], stops: [0.25, 1])),
                  ),
                  Padding(padding: const EdgeInsets.all(18), child: text),
                ])
              : Stack(children: [
                  // علامة واصل كبيرة مقصوصة بزاوية البطاقة — شخصية بدون صور مخترعة
                  PositionedDirectional(end: -26, bottom: -34, child: Opacity(opacity: style == 0 ? 0.16 : 0.22, child: WaselMark(size: 170, route: style == 0 ? WColors.ink : WColors.lime))),
                  Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 18), child: text),
                ]),
        ),
      ),
    );
  }
}

// =====================================================================
// 6) المشاوير — لوحة تحكم داكنة بأربع خانات
// =====================================================================
class _MoveDock extends StatelessWidget {
  const _MoveDock();

  String _label(MerchantCategory c) => switch (c.id) { 'courier' => 'مندوب', 'parcel' => 'أغراض', _ => c.name.replaceFirst('ال', '') };
  String _hint(MerchantCategory c) => switch (c.kind) {
        CategoryKind.ride => 'مشوار',
        CategoryKind.courier => 'يشتري لك',
        CategoryKind.parcel => 'يوصّل غرض',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final items = app.categories.where((c) => c.kind == CategoryKind.ride || c.kind == CategoryKind.courier || c.kind == CategoryKind.parcel).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _SectionHead('مشاوير وتوصيل', sub: 'تكسي، تكتك، أو مندوب لأي غرض'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: WColors.night, borderRadius: WRadius.all(WRadius.xl)),
          child: IntrinsicHeight(
            child: Row(children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 14), color: WColors.white.withValues(alpha: 0.08)),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: items[i].name,
                    onTap: () => openCategory(context, items[i]),
                    excludeSemantics: true,
                    child: _DockButton(icon: categoryIcon(items[i].icon), label: _label(items[i]), hint: _hint(items[i]), onTap: () => openCategory(context, items[i])),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({required this.icon, required this.label, required this.hint, required this.onTap});
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: WDurations.fast,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(color: _down ? WColors.lime : Colors.transparent, borderRadius: WRadius.all(WRadius.lg)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 28, color: _down ? WColors.ink : WColors.lime),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown, child: Text(widget.label, style: WText.bodyStrong.copyWith(color: _down ? WColors.ink : WColors.white, fontWeight: FontWeight.w700))),
            if (widget.hint.isNotEmpty) FittedBox(fit: BoxFit.scaleDown, child: Text(widget.hint, style: WText.caption.copyWith(fontSize: 11, color: _down ? WColors.ink : const Color(0xFF8E9297)))),
          ]),
        ),
      );
}

// =====================================================================
// 7) الأسواق — رف أقسام بأحجام وألوان مختلفة
// =====================================================================
class _Markets extends StatelessWidget {
  const _Markets({required this.data});
  final _HomeData data;

  @override
  Widget build(BuildContext context) {
    final stores = app.categories.where((c) => c.kind == CategoryKind.store).toList();
    final homeSvc = app.categories.where((c) => c.kind == CategoryKind.homeService).firstOrNull;
    if (stores.isEmpty && homeSvc == null) return const SizedBox.shrink();
    final byCat = <String, List<Merchant>>{};
    for (final m in data.merchants) {
      byCat.putIfAbsent(m.categoryId, () => []).add(m);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _SectionHead('الأسواق', sub: 'كل شي تحتاجه، من محلات منطقتك'),
      if (stores.isNotEmpty)
        SizedBox(
          height: 204,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
            itemCount: stores.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _ShelfCard(category: stores[i], stores: byCat[stores[i].id] ?? const [], featured: i == 0, tone: i == 0 ? 0 : (i % 3) + 1),
          ),
        ),
      if (homeSvc != null) Padding(padding: const EdgeInsets.fromLTRB(WSpace.page, 12, WSpace.page, 0), child: _HomeServicesBanner(category: homeSvc, services: data.homeServices)),
    ]);
  }
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({required this.category, required this.stores, required this.featured, required this.tone});
  final MerchantCategory category;
  final List<Merchant> stores;
  final bool featured;
  final int tone; // 0 حبر (المميّز)، 1 سطح، 2 أزرق، 3 ليموني

  @override
  Widget build(BuildContext context) {
    final c = category;
    final open = stores.where((m) => m.isOpenNow).length;
    final (bg, fg, sub, iconBg, iconFg, border) = switch (tone) {
      0 => (WColors.night, WColors.white, const Color(0xFFB9BCC0), WColors.lime, WColors.ink, null),
      2 => (WColors.blue, WColors.white, const Color(0xFFDCE7FB), WColors.white, WColors.blue, null),
      3 => (WColors.lime, WColors.ink, const Color(0xFF3B4A12), WColors.ink, WColors.lime, null),
      _ => (WColors.surface, WColors.fg, WColors.inkMuted, WColors.paper, WColors.fg, WColors.line),
    };
    final tagBg = switch (tone) { 0 => const Color(0x1AFFFFFF), 2 => const Color(0x33FFFFFF), 3 => const Color(0x1A17191B), _ => WColors.paper };
    // صور حقيقية: شعارات/أغلفة محلات هذا القسم (إذا موجودة)
    final faces = stores.map((m) => m.logoUrl ?? m.coverUrl).whereType<String>().where((u) => u.isNotEmpty).take(3).toList();
    final names = stores.take(2).map((m) => m.name).join('، ');
    return SizedBox(
      width: featured ? 228 : 148,
      child: Semantics(
        button: true,
        label: c.name,
        onTap: () => openCategory(context, c),
        excludeSemantics: true,
        child: Pressable(
          onTap: () => openCategory(context, c),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: bg, borderRadius: WRadius.all(WRadius.xl), border: border == null ? null : Border.all(color: border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: featured ? 48 : 40,
                  height: featured ? 48 : 40,
                  decoration: BoxDecoration(color: iconBg, borderRadius: WRadius.all(featured ? 15 : 13)),
                  child: Icon(categoryIcon(c.icon), color: iconFg, size: featured ? 26 : 22),
                ),
                const Spacer(),
                if (stores.isNotEmpty) _Tag(open > 0 ? '$open مفتوح' : '${stores.length} محل', bg: tagBg, fg: fg),
              ]),
              const Spacer(),
              Text(c.name, style: WText.h1.copyWith(fontSize: featured ? 26 : 19, height: 1.15, color: fg), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (featured && names.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(names, style: WText.caption.copyWith(color: sub), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              if (faces.isNotEmpty) ...[
                const SizedBox(height: 10),
                _FaceStack(urls: faces, ring: bg),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// صور محلات القسم متراكبة (حقيقية من الخادم)
class _FaceStack extends StatelessWidget {
  const _FaceStack({required this.urls, required this.ring});
  final List<String> urls;
  final Color ring;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 30,
        width: 30.0 + (urls.length - 1) * 20,
        child: Stack(children: [
          for (var i = 0; i < urls.length; i++)
            PositionedDirectional(
              start: i * 20.0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: ring, borderRadius: WRadius.all(10)),
                child: WImage(urls[i], width: 26, height: 26, radius: 8),
              ),
            ),
        ]),
      );
}

class _HomeServicesBanner extends StatelessWidget {
  const _HomeServicesBanner({required this.category, required this.services});
  final MerchantCategory category;
  final List<HomeService> services;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: category.name,
        onTap: () => openCategory(context, category),
        excludeSemantics: true,
        child: Pressable(
          onTap: () => openCategory(context, category),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(WRadius.xl), border: Border.all(color: WColors.line)),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: WColors.blue, borderRadius: WRadius.all(16)),
                child: const Icon(Icons.handyman_rounded, color: WColors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(category.name, style: WText.h3.copyWith(fontWeight: FontWeight.w700)),
                  if (services.isNotEmpty)
                    Text(services.take(4).map((s) => s.name).join(' · '), style: WText.small, maxLines: 1, overflow: TextOverflow.ellipsis)
                  else
                    Text('فني يوصلك للبيت', style: WText.small),
                ]),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: WColors.paper, borderRadius: WRadius.all(12)),
                child: Icon(Icons.arrow_back_rounded, size: 18, color: WColors.fg),
              ),
            ]),
          ),
        ),
      );
}

// =====================================================================
// 8) مقترح لك — بطاقات محلات كبيرة
// =====================================================================
class _Picks extends StatelessWidget {
  const _Picks({required this.merchants, required this.nearby});
  final List<Merchant> merchants;
  final bool nearby;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SectionHead(nearby ? 'قريب منك' : 'مقترح لك', sub: nearby ? 'المفتوح والأقرب أولاً' : 'المفتوح أولاً'),
        SizedBox(
          height: 252,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
            itemCount: merchants.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _StoreCard(m: merchants[i]),
          ),
        ),
      ]);
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.m});
  final Merchant m;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 270,
        child: Semantics(
          button: true,
          label: m.name,
          child: Pressable(
            onTap: () => openMerchant(context, m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 160,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(child: WImage(m.coverUrl, radius: WRadius.xl, fallbackIcon: categoryIcon(m.categoryId), fallbackColor: WColors.surfaceAlt)),
                  if (!m.isOpenNow) Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: WColors.paper.withValues(alpha: 0.5), borderRadius: WRadius.all(WRadius.xl)))),
                  PositionedDirectional(top: 12, start: 12, child: m.isOpenNow ? const _Tag('مفتوح', bg: WColors.ink, fg: WColors.lime) : _Tag('مسكّر', bg: WColors.surface, fg: WColors.fg)),
                  if (m.deliveryFee == 0) const PositionedDirectional(top: 12, end: 12, child: _Tag('توصيل مجاني', bg: WColors.lime, fg: WColors.ink)),
                  PositionedDirectional(
                    bottom: -18,
                    start: 14,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: WColors.paper, borderRadius: WRadius.all(16)),
                      child: MerchantLogo(name: m.name, url: m.logoUrl, size: 46),
                    ),
                  ),
                  PositionedDirectional(bottom: 10, end: 10, child: _FavButton(merchantId: m.id)),
                ]),
              ),
              const SizedBox(height: 24),
              Text(m.name, style: WText.h3.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              MerchantMeta(m),
            ]),
          ),
        ),
      );
}

class _FavButton extends StatelessWidget {
  const _FavButton({required this.merchantId});
  final String merchantId;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final fav = app.favorites.contains(merchantId);
          return Semantics(
            button: true,
            label: fav ? 'شيل من المفضلة' : 'أضف للمفضلة',
            child: Material(
              color: fav ? WColors.lime : WColors.surface,
              borderRadius: WRadius.all(12),
              child: InkWell(
                borderRadius: WRadius.all(12),
                onTap: () {
                  HapticFeedback.selectionClick();
                  runAction(context, () => app.toggleFavorite(merchantId));
                },
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: AnimatedSwitcher(
                    duration: WDurations.base,
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, key: ValueKey(fav), size: 19, color: fav ? WColors.ink : WColors.fg),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

// =====================================================================
// 9) الأكثر طلباً — لوحة ترتيب (الأول بطاقة كبيرة، الباقي صفوف)
// =====================================================================
class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.merchants});
  final List<Merchant> merchants;
  @override
  Widget build(BuildContext context) {
    final top = merchants.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _SectionHead('الأكثر طلباً', sub: 'حسب عدد الطلبات على واصل'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
        child: Semantics(
          button: true,
          label: 'الأول: ${top.name}',
          child: Pressable(
            onTap: () => openMerchant(context, top),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(WRadius.xl)),
              child: Row(children: [
                Text('1', style: WText.number.copyWith(fontSize: 64, height: 1, color: WColors.ink)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _Tag('الأكثر طلباً', bg: WColors.ink, fg: WColors.lime),
                    const SizedBox(height: 6),
                    Text(top.name, style: WText.h2.copyWith(color: WColors.ink, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${top.orderCount} طلب${top.ratingCount > 0 ? ' · ★ ${top.ratingAvg.toStringAsFixed(1)}' : ''}', style: WText.small.copyWith(color: const Color(0xFF3B4A12))),
                  ]),
                ),
                MerchantLogo(name: top.name, url: top.logoUrl, size: 58),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      for (var i = 1; i < merchants.length; i++) MerchantRow(merchants[i], rank: i + 1, onTap: () => openMerchant(context, merchants[i])),
    ]);
  }
}

// =====================================================================
// 10) توصيل مجاني قريب منك (من أجور التوصيل الحقيقية)
// =====================================================================
class _FreeDelivery extends StatelessWidget {
  const _FreeDelivery({required this.merchants});
  final List<Merchant> merchants;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _SectionHead('توصيل مجاني', sub: 'محلات مفتوحة هسه وما تاخذ أجرة توصيل'),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
            itemCount: merchants.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final m = merchants[i];
              final d = distanceTo(m);
              return Semantics(
                button: true,
                label: m.name,
                child: Pressable(
                  onTap: () => openMerchant(context, m),
                  child: Container(
                    width: 236,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(WRadius.lg), border: Border.all(color: WColors.line)),
                    child: Row(children: [
                      MerchantLogo(name: m.name, url: m.logoUrl, size: 54),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(m.name, style: WText.bodyStrong.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(children: [
                            const _Tag('مجاني', bg: WColors.lime, fg: WColors.ink),
                            const SizedBox(width: 6),
                            Flexible(child: Text('${m.etaMinutes(d ?? 2)} د${d == null ? '' : ' · ${kmAr(d)}'}', style: WText.caption, maxLines: 1)),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]);
}

// =====================================================================
// 11) اطلب مرة ثانية
// =====================================================================
class _Reorder extends StatelessWidget {
  const _Reorder({required this.orders});
  final List<Order> orders;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _SectionHead('طلباتك السابقة', sub: 'افتح الطلب وشوف تفاصيله'),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final o = orders[i];
              final ok = o.status == OrderStatus.delivered;
              return Semantics(
                button: true,
                label: 'طلب ${o.merchantName ?? ''}',
                child: Pressable(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: o.id))),
                  child: Container(
                    width: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(WRadius.lg), border: Border.all(color: WColors.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        MerchantLogo(name: o.merchantName ?? '', url: o.merchantLogo, size: 36),
                        const SizedBox(width: 10),
                        Expanded(child: Text(o.merchantName ?? '', style: WText.bodyStrong.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      const Spacer(),
                      Row(children: [
                        Expanded(child: Text(iqd(o.total), style: WText.price.copyWith(fontSize: 14))),
                        _Tag(ok ? 'وصل' : o.status.label, bg: ok ? WColors.paper : WColors.dangerSoft, fg: ok ? WColors.fg : WColors.danger),
                      ]),
                      Text(dateTimeAr(o.createdAt), style: WText.caption.copyWith(fontSize: 11)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]);
}

// =====================================================================
// التحميل والذيل
// =====================================================================
class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.page, 18, WSpace.page, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SkeletonBox(height: 176, radius: WRadius.xl),
          const SizedBox(height: 24),
          SkeletonBox(height: 96, radius: WRadius.xl),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(flex: 3, child: SkeletonBox(height: 190, radius: WRadius.xl)),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: SkeletonBox(height: 190, radius: WRadius.xl)),
          ]),
        ]),
      );
}

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.page, 40, WSpace.page, 36),
        child: Column(children: [
          WaselMark(size: 34, route: WColors.inkFaint),
          const SizedBox(height: 6),
          Text('واصل · كل احتياجاتك أقرب', style: WText.caption),
        ]),
      );
}
