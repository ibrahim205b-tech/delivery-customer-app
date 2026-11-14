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
                      if (active != null) SliverToBoxAdapter(child: reveal(_LiveOrder(order: active, onClosed: () => setState(() => _data = _load())))),
                      // الأقسام الأربعة الرئيسية — أهم عنصر بالصفحة
                      SliverToBoxAdapter(child: reveal(const _ServiceGrid())),
                      SliverToBoxAdapter(child: reveal(const _MoreServices())),
                      if (s.hasError) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(error: s.error!, onRetry: _refresh))),
                      if (d == null && !s.hasError) const SliverToBoxAdapter(child: _Loading()),
                      if (d != null && d.promotions.isNotEmpty) SliverToBoxAdapter(child: reveal(_OfferDeck(promos: d.promotions))),
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
      return [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 24), child: _AreaTabs(onSelect: _selectArea))),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 12),
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
      SliverToBoxAdapter(child: reveal(_Picks(merchants: picks.take(10).toList(), nearby: ref != null, onArea: _selectArea))),
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
                    child: Icon(Icons.near_me_rounded, size: 14, color: WColors.ink),
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
            height: 54,
            padding: const EdgeInsetsDirectional.only(start: 16, end: 5),
            decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(17), border: Border.all(color: WColors.line, width: 1.2)),
            child: Row(children: [
              Expanded(child: Text('دوّر على مطعم، منتج أو محل', style: WText.body.copyWith(color: WColors.inkFaint), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: WColors.blue, borderRadius: WRadius.all(13)),
                child: const Icon(Icons.search_rounded, color: WColors.white),
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
                    Icon(Icons.arrow_back_rounded, size: 16, color: WColors.ink),
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
      _ => (WColors.coral, WColors.white, const Color(0xFFFFE3DC), WColors.white, WColors.coral),
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
// 5) الأقسام الأربعة الرئيسية — بطاقات مربعة برسومات أصلية
//    التكسي الأبرز: تعبئة صفراء كاملة + زر "اطلب" + حركة خفيفة للسيارة.
//    كل بطاقة مربوطة بقسم حقيقي من قاعدة البيانات، وتختفي إذا القسم معطّل من الإدارة.
// =====================================================================
MerchantCategory? _cat(String id) => app.categories.where((c) => c.id == id).firstOrNull;

/// أقسام المحلات (غير المطاعم) — تظهر تحت بطاقة "المحلات"
List<MerchantCategory> get _shopCategories => app.categories.where((c) => c.kind == CategoryKind.store && c.id != 'restaurants').toList();

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid();

  @override
  Widget build(BuildContext context) {
    final taxi = _cat('taxi');
    final food = _cat('restaurants');
    final parcel = _cat('parcel');
    final shops = _shopCategories;
    final cards = <Widget>[
      if (taxi != null)
        _ServiceCard(
          id: 'taxi',
          title: 'تكسي',
          sub: 'تكسي أو تكتك',
          asset: 'assets/illustrations/taxi.png',
          featured: true,
          bg: WColors.lime,
          onTap: () => openCategory(context, taxi),
        ),
      if (food != null)
        _ServiceCard(
          id: 'food',
          title: 'طعام',
          sub: 'مطاعم منطقتك',
          asset: 'assets/illustrations/food.png',
          bg: WColors.isDark ? const Color(0xFF3A1F1A) : const Color(0xFFFFE8E2),
          accent: WColors.coral,
          onTap: () => openCategory(context, food),
        ),
      if (parcel != null)
        _ServiceCard(
          id: 'parcel',
          title: 'ودّي أغراضك',
          sub: 'بأمان، من باب لباب',
          asset: 'assets/illustrations/parcel.png',
          bg: WColors.isDark ? const Color(0xFF0F2E27) : const Color(0xFFDDF4EC),
          accent: WColors.mint,
          onTap: () => openCategory(context, parcel),
        ),
      if (shops.isNotEmpty)
        _ServiceCard(
          id: 'shops',
          title: 'المحلات',
          sub: shops.take(2).map((c) => c.name).join('، '),
          asset: 'assets/illustrations/shops.png',
          bg: WColors.blueSoft,
          accent: WColors.blue,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopsHubScreen())),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(WSpace.page, 14, WSpace.page, 0),
      child: LayoutBuilder(builder: (context, box) {
        const gap = 12.0;
        final side = (box.maxWidth - gap) / 2;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in cards) SizedBox(width: side, height: side, child: c)]);
      }),
    );
  }
}

class _ServiceCard extends StatefulWidget {
  const _ServiceCard({required this.id, required this.title, required this.sub, required this.asset, required this.bg, required this.onTap, this.accent, this.featured = false});
  final String id;
  final String title;
  final String sub;
  final String asset;
  final Color bg;
  final Color? accent;
  final bool featured;
  final VoidCallback onTap;
  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> with SingleTickerProviderStateMixin {
  bool _down = false;
  // حركة "تنفّس" خفيفة لسيارة التكسي فقط
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.featured) _bob.repeat(reverse: true);
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.featured;
    final titleColor = f ? WColors.ink : WColors.fg;
    final subColor = f ? WColors.ink.withValues(alpha: 0.72) : WColors.inkMuted;
    return Semantics(
      button: true,
      label: '${widget.title}، ${widget.sub}',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: WDurations.fast,
          curve: WDurations.curve,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: widget.bg,
              borderRadius: WRadius.all(26),
              boxShadow: f ? [BoxShadow(color: WColors.lime.withValues(alpha: WColors.isDark ? 0.0 : 0.45), blurRadius: 22, offset: const Offset(0, 10))] : null,
            ),
            child: LayoutBuilder(builder: (context, box) {
              final s = box.maxWidth;
              return Stack(children: [
                // الرسم بالنص السفلي فقط (ما يغطي العنوان ولا الزر)
                PositionedDirectional(
                  end: f ? -s * 0.03 : -s * 0.06,
                  bottom: -s * 0.03,
                  width: s * (f ? 0.86 : 0.8),
                  child: AnimatedBuilder(
                    animation: _bob,
                    builder: (context, child) => Transform.translate(offset: Offset(0, f ? -3 * Curves.easeInOut.transform(_bob.value) : 0), child: child),
                    child: Image.asset(widget.asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(s * 0.085),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(widget.title, style: WText.display.copyWith(fontSize: f ? 30 : 23, height: 1.05, color: titleColor)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // زر واضح للتكسي، وسهم صغير للبقية — بالزاوية العليا حتى ما يغطي الرسم
                      f && s >= 150
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                              decoration: BoxDecoration(color: WColors.ink, borderRadius: WRadius.all(13)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('اطلب', style: WText.label.copyWith(color: WColors.lime, fontWeight: FontWeight.w700, fontSize: 13)),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_back_rounded, size: 15, color: WColors.lime),
                              ]),
                            )
                          : Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(color: f ? WColors.ink : (widget.accent ?? WColors.blue), borderRadius: WRadius.all(11)),
                              child: Icon(Icons.arrow_back_rounded, size: 17, color: f ? WColors.lime : WColors.white),
                            ),
                    ]),
                    const SizedBox(height: 3),
                    Text(widget.sub, style: WText.caption.copyWith(color: subColor, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

/// خدمات ثانية (حتى ما تضيع أي خدمة): مندوب، تكتك، الأعمال المنزلية
class _MoreServices extends StatelessWidget {
  const _MoreServices();
  @override
  Widget build(BuildContext context) {
    final items = <(MerchantCategory, String, IconData)>[
      if (_cat('courier') case final c?) (c, 'مندوب يشتري لك', Icons.directions_bike_rounded),
      if (_cat('tuktuk') case final c?) (c, 'تكتك', Icons.electric_rickshaw_rounded),
      for (final c in app.categories.where((c) => c.kind == CategoryKind.homeService)) (c, c.name, Icons.handyman_rounded),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final (c, label, icon) = items[i];
            return Semantics(
              button: true,
              label: label,
              onTap: () => openCategory(context, c),
              excludeSemantics: true,
              child: Material(
                color: WColors.surface,
                borderRadius: WRadius.all(14),
                child: InkWell(
                  borderRadius: WRadius.all(14),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    openCategory(context, c);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(borderRadius: WRadius.all(14), border: Border.all(color: WColors.line)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 20, color: WColors.link),
                      const SizedBox(width: 8),
                      Text(label, style: WText.bodyStrong.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// شاشة "المحلات": كل أقسام المحلات (غير المطاعم) من قاعدة البيانات
class ShopsHubScreen extends StatelessWidget {
  const ShopsHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final cats = _shopCategories;
    final tints = [WColors.blueSoft, WColors.limeSoft, WColors.isDark ? const Color(0xFF0F2E27) : const Color(0xFFDDF4EC), WColors.isDark ? const Color(0xFF3A1F1A) : const Color(0xFFFFE8E2)];
    final accents = [WColors.blue, WColors.limeDeep, WColors.mint, WColors.coral];
    return Scaffold(
      appBar: AppBar(title: const Text('المحلات')),
      body: ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32), children: [
        Text('شنو تحتاج؟', style: WText.h1),
        Text('اختار القسم وشوف محلات منطقتك', style: WText.small),
        const SizedBox(height: 16),
        if (cats.isEmpty) const EmptyView(icon: Icons.storefront_outlined, title: 'ما اكو أقسام محلات مفعّلة'),
        LayoutBuilder(builder: (context, box) {
          final side = (box.maxWidth - 12) / 2;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (var i = 0; i < cats.length; i++)
              SizedBox(
                width: side,
                height: side * 0.72,
                child: Semantics(
                  button: true,
                  label: cats[i].name,
                  child: Pressable(
                    onTap: () => openCategory(context, cats[i]),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: tints[i % 4], borderRadius: WRadius.all(22)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: accents[i % 4], borderRadius: WRadius.all(13)),
                          child: Icon(categoryIcon(cats[i].icon), color: WColors.white, size: 22),
                        ),
                        const Spacer(),
                        Text(cats[i].name, style: WText.h3.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        }),
      ]),
    );
  }
}

// =====================================================================
// 8) مقترح لك — بطاقات محلات كبيرة
// =====================================================================
class _Picks extends StatelessWidget {
  const _Picks({required this.merchants, required this.nearby, required this.onArea});
  final List<Merchant> merchants;
  final bool nearby;
  final ValueChanged<String?> onArea;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SectionHead(nearby ? 'مطاعم ومحلات قريبة' : 'مطاعم ومحلات مقترحة', sub: nearby ? 'المفتوح والأقرب أولاً' : 'المفتوح أولاً'),
        _AreaTabs(onSelect: onArea),
        const SizedBox(height: 8),
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
                  PositionedDirectional(top: 12, start: 12, child: m.isOpenNow ? _Tag('مفتوح', bg: WColors.ink, fg: WColors.lime) : _Tag('مسكّر', bg: WColors.surface, fg: WColors.fg)),
                  if (m.deliveryFee == 0) PositionedDirectional(top: 12, end: 12, child: _Tag('توصيل مجاني', bg: WColors.lime, fg: WColors.ink)),
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
                    _Tag('الأكثر طلباً', bg: WColors.ink, fg: WColors.lime),
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
                            _Tag('مجاني', bg: WColors.lime, fg: WColors.ink),
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
