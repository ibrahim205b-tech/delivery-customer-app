import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../widgets.dart';
import 'account.dart';
import 'errand.dart';
import 'home_sections.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.unread});
  final int unread;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _data = _load();

  Future<_HomeData> _load() async {
    final r = await Future.wait<Object?>([
      catalogApi.merchants(areaId: app.selectedAreaId),
      catalogApi.activePromotions(),
      customerApi.myOrders(limit: 6),
      catalogApi.homeLayout(),
      // الرحلة الشغّالة والوجهات إضافات: فشلها ما يوقف الرئيسية
      customerApi.activeRide().then<Ride?>((v) => v, onError: (_) => null),
      customerApi.rideDestinations(),
    ]);
    return _HomeData(r[0] as List<Merchant>, r[1] as List<Promotion>, r[2] as List<Order>, r[3] as List<HomeSection>, r[4] as Ride?, r[5] as List<RideDestination>);
  }

  void _reload() {
    if (mounted) setState(() => _data = _load());
  }

  Future<void> _refresh() async {
    await app.load();
    final f = _load();
    setState(() => _data = f);
    await f.then((_) {}, onError: (_) {});
  }

  void _addAddress() => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressFormScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WColors.paper,
        bottomNavigationBar: const CartBar(),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            if (app.loadError != null && !app.loaded) return SafeArea(child: ErrorView(error: app.loadError!, onRetry: _refresh));
            return RefreshIndicator(
              color: WColors.fg,
              onRefresh: _refresh,
              child: FutureBuilder<_HomeData>(
                future: _data,
                builder: (context, s) {
                  final d = s.data;
                  final active = d?.recent.where((o) => o.status.isActive).firstOrNull;
                  return CustomScrollView(slivers: [
                    SliverToBoxAdapter(child: _hero()),
                    if (active != null) SliverToBoxAdapter(child: _activeOrder(active)),
                    if (d?.activeRide != null) SliverToBoxAdapter(child: ActiveRideCard(d!.activeRide!, onClosed: _reload)),
                    if (s.hasError) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(error: s.error!, onRetry: _refresh))),
                    // قبل وصول البيانات: شبكة الأقسام (محمّلة مسبقاً) + هيكل تحميل
                    if (d == null) SliverToBoxAdapter(child: _bento('الأقسام')),
                    if (d == null && !s.hasError) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: SkeletonBox(height: 180, radius: WRadius.lg))),
                    // الأقسام بالترتيب اللي حددته الإدارة
                    if (d != null) ..._sections(d),
                    const SliverToBoxAdapter(child: SizedBox(height: 36)),
                  ]);
                },
              ),
            );
          },
        ),
      );

  // ======================= القسم الداكن العلوي =======================
  Widget _hero() {
    final a = app.selectedAddress;
    final greet = DateTime.now().hour < 12 ? 'صباح الخير' : 'مساء الخير';
    final first = (auth.profile?.fullName ?? '').split(' ').first;
    final mobility = app.categories.where((c) => c.kind == CategoryKind.ride || c.kind == CategoryKind.courier || c.kind == CategoryKind.parcel).toList();
    return Container(
      decoration: BoxDecoration(color: WColors.night, borderRadius: BorderRadius.vertical(bottom: Radius.circular(WRadius.xl))),
      padding: EdgeInsets.fromLTRB(WSpace.page, MediaQuery.paddingOf(context).top + 10, WSpace.page, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'تغيير عنوان التوصيل',
              child: InkWell(
                borderRadius: WRadius.all(WRadius.md),
                onTap: () => pickAddressSheet(context, onAddNew: _addAddress),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(3))),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(a == null ? 'أضف عنوان التوصيل' : a.oneLine, style: WText.bodyStrong.copyWith(color: WColors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Icon(Icons.expand_more_rounded, color: WColors.inkFaint, size: 20),
                  ]),
                ),
              ),
            ),
          ),
          if (app.rewards != null && app.rewards!.enabled) ...[RewardsChip(app.rewards!), const SizedBox(width: 8)],
          Stack(clipBehavior: Clip.none, children: [
            WIconButton(Icons.notifications_none_rounded, background: WColors.inkSurface, color: WColors.white, tooltip: 'الإشعارات', onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            }),
            if (widget.unread > 0)
              PositionedDirectional(
                top: -4,
                end: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(8), border: Border.all(color: WColors.ink, width: 2)),
                  child: Text('${widget.unread > 9 ? '9+' : widget.unread}', style: WText.number.copyWith(fontSize: 10.5, color: WColors.fg)),
                ),
              ),
          ]),
        ]),
        const SizedBox(height: 18),
        Text(first.isEmpty ? greet : '$greet، $first', style: WText.body.copyWith(color: WColors.inkFaint)),
        const SizedBox(height: 2),
        Text('شتحتاج اليوم؟', style: WText.display.copyWith(color: WColors.white, fontSize: 30)),
        const SizedBox(height: 16),
        // البحث
        Semantics(
          button: true,
          label: 'بحث',
          child: InkWell(
            borderRadius: WRadius.all(WRadius.md),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(WRadius.md)),
              child: Row(children: [
                Icon(Icons.search_rounded, color: WColors.fg),
                const SizedBox(width: 10),
                Expanded(child: Text('مطعم، منتج، أو محل…', style: WText.body.copyWith(color: WColors.inkFaint))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: WColors.paper, borderRadius: WRadius.all(8)),
                  child: Text('بحث', style: WText.label.copyWith(color: WColors.fg)),
                ),
              ]),
            ),
          ),
        ),
        if (mobility.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('تنقّل وتوصيل', style: WText.overline.copyWith(color: WColors.inkFaint)),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < mobility.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _mobilityTile(mobility[i])),
            ],
          ]),
        ],
        _areaPills(),
      ]),
    );
  }

  Widget _mobilityTile(MerchantCategory c) => Semantics(
        button: true,
        label: c.name,
        onTap: () => openCategory(context, c),
        excludeSemantics: true,
        child: Pressable(
          onTap: () => openCategory(context, c),
          child: Container(
            height: 78,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: WColors.inkSurface, borderRadius: WRadius.all(WRadius.md), border: Border.all(color: WColors.graphite)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(categoryIcon(c.icon), color: WColors.lime, size: 24),
              Text(c.id == 'courier' ? 'مندوب' : (c.id == 'parcel' ? 'أغراض' : c.name.replaceAll('ال', '')),
                  style: WText.label.copyWith(color: WColors.white, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );

  Widget _areaPills() {
    final areas = app.areas.where((a) => a.isActive).toList();
    if (areas.length < 2) return const SizedBox.shrink();
    Widget pill(String label, bool sel, VoidCallback f) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: InkWell(
            borderRadius: WRadius.all(WRadius.pill),
            onTap: f,
            child: AnimatedContainer(
              duration: WDurations.base,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? WColors.lime : Colors.transparent,
                borderRadius: WRadius.all(WRadius.pill),
                border: Border.all(color: sel ? WColors.lime : WColors.graphite),
              ),
              child: Text(label, style: WText.label.copyWith(color: sel ? WColors.ink : WColors.white)),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          pill('كل المناطق', app.selectedAreaId == null, () => _selectArea(null)),
          for (final ar in areas) pill(ar.name, app.selectedAreaId == ar.id, () => _selectArea(ar.id)),
        ]),
      ),
    );
  }

  void _selectArea(String? id) {
    app.selectArea(id);
    setState(() => _data = _load());
  }

  // ======================= الطلب الشغّال =======================
  Widget _activeOrder(Order o) {
    final group = switch (o.status) {
      OrderStatus.placed => 0,
      OrderStatus.accepted || OrderStatus.preparing || OrderStatus.ready => 1,
      OrderStatus.pickedUp || OrderStatus.onTheWay => 2,
      _ => 3,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(WSpace.page, 16, WSpace.page, 0),
      child: Pressable(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: o.id)));
          if (mounted) setState(() => _data = _load());
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(WRadius.lg)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const _LivePulse(),
              const SizedBox(width: 8),
              Text('طلبك الحالي · ${o.merchantName ?? ''}', style: WText.label.copyWith(color: WColors.ink)),
              const Spacer(),
              const Icon(Icons.arrow_back_rounded, color: WColors.ink, size: 20),
            ]),
            const SizedBox(height: 8),
            Text(o.status.label, style: WText.h2.copyWith(color: WColors.ink)),
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: WDurations.slow,
                    height: 5,
                    decoration: BoxDecoration(color: i <= group ? WColors.ink : WColors.ink.withValues(alpha: 0.15), borderRadius: WRadius.all(3)),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  // ======================= شبكة الأقسام (Bento) =======================
  // ======================= ترتيب الأقسام من الإدارة =======================
  List<Widget> _sections(_HomeData d) {
    Widget box(Widget child) => SliverToBoxAdapter(child: child);
    Widget title(String t, {double top = 26}) => box(SectionTitle(t, padding: EdgeInsets.fromLTRB(WSpace.page, top, WSpace.page, 12)));
    final ref = app.referencePoint;
    final past = d.recent.where((o) => !o.status.isActive).toList();
    final out = <Widget>[];
    var emptyShown = false;
    void emptyMerchants() {
      if (emptyShown) return;
      emptyShown = true;
      out.add(box(const EmptyView(icon: Icons.storefront_outlined, title: 'ما اكو محلات بهذه المنطقة بعد', message: 'المحلات تظهر هنا بعد ما تعتمدها إدارة واصل.')));
    }

    for (final s in d.layout) {
      switch (s.type) {
        case HomeSectionType.categories:
          out.add(box(_bento(s.title.isEmpty ? 'الأقسام' : s.title)));
        case HomeSectionType.promotions:
          if (d.promotions.isNotEmpty) out.add(box(_promotions(d.promotions)));
        case HomeSectionType.destinations:
          if (d.destinations.isNotEmpty) {
            out.add(title(s.title.isEmpty ? 'وين رايح؟' : s.title, top: 24));
            out.add(box(HomeDestinations(d.destinations)));
          }
        case HomeSectionType.slider:
          if (s.items.isNotEmpty) {
            if (s.title.isNotEmpty) out.add(title(s.title, top: 24));
            out.add(box(Padding(padding: EdgeInsets.only(top: s.title.isEmpty ? 24 : 0), child: HomeSlider(s.items))));
          }
        case HomeSectionType.banner:
          if (s.items.isNotEmpty) {
            if (s.title.isNotEmpty) out.add(title(s.title, top: 24));
            out.add(box(Padding(padding: EdgeInsets.fromLTRB(WSpace.page, s.title.isEmpty ? 24 : 0, WSpace.page, 0), child: HomeBannerCard(s.items.first))));
          }
        case HomeSectionType.cards:
          if (s.items.isNotEmpty) {
            if (s.title.isNotEmpty) out.add(title(s.title, top: 24));
            out.add(box(Padding(padding: EdgeInsets.only(top: s.title.isEmpty ? 24 : 0), child: HomeCards(s.items))));
          }
        case HomeSectionType.nearby:
          if (d.merchants.isEmpty) {
            emptyMerchants();
          } else {
            out.add(title(s.title.isNotEmpty ? s.title : (ref == null ? 'محلات مختارة' : 'قريب منك'), top: 28));
            out.add(box(_nearby(d.merchants, ref)));
          }
        case HomeSectionType.popular:
          if (d.merchants.isEmpty) {
            emptyMerchants();
          } else {
            out.add(box(SectionTitle(s.title.isEmpty ? 'الأكثر طلباً' : s.title, padding: const EdgeInsets.fromLTRB(WSpace.page, 26, WSpace.page, 4))));
            out.add(_popular(d.merchants));
          }
        case HomeSectionType.reorder:
          if (past.isNotEmpty) out.add(box(_recent(past, s.title.isEmpty ? 'اطلب مرة ثانية' : s.title)));
        case HomeSectionType.unknown:
          break;
      }
    }
    return out;
  }

  Widget _bento(String heading) {
    final stores = app.categories.where((c) => c.kind == CategoryKind.store).toList();
    final homeSvc = app.categories.where((c) => c.kind == CategoryKind.homeService).firstOrNull;
    if (stores.isEmpty && homeSvc == null) return const SizedBox.shrink();
    const gap = 10.0;
    const small = 106.0;

    Widget tile(MerchantCategory c, {bool big = false, double? height}) => Semantics(
          button: true,
          label: c.name,
          onTap: () => openCategory(context, c),
          excludeSemantics: true,
          child: Pressable(
            onTap: () => openCategory(context, c),
            child: Container(
              height: height ?? (big ? small * 2 + gap : small),
              padding: EdgeInsets.all(big ? 14 : 11),
              decoration: BoxDecoration(
                color: big ? WColors.night : WColors.surface,
                borderRadius: WRadius.all(WRadius.lg),
                border: big ? null : Border.all(color: WColors.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  width: big ? 48 : 36,
                  height: big ? 48 : 36,
                  decoration: BoxDecoration(color: big ? WColors.lime : WColors.paper, borderRadius: WRadius.all(big ? 14 : 11)),
                  child: Icon(categoryIcon(c.icon), color: big ? WColors.ink : WColors.fg, size: big ? 26 : 20),
                ),
                if (big)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, style: WText.h2.copyWith(color: WColors.white, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text('أكل، مشويات، بيتزا وأكثر', style: WText.caption.copyWith(color: WColors.inkFaint), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ])
                else ...[
                  const SizedBox(height: 6),
                  // البلاطة الصغيرة ضيقة: كل كلمة بسطر (الكلمة ما تنكسر أبداً)، وإذا ما وسعت يصغر الخط
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.bottomStart,
                      child: Text(
                        c.name.trim().split(RegExp(r'\s+')).join('\n'),
                        style: WText.bodyStrong.copyWith(color: WColors.fg, fontWeight: FontWeight.w600, height: 1.2),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        );

    Widget homeTile(MerchantCategory homeSvc) => Semantics(
          button: true,
          label: homeSvc.name,
          onTap: () => openCategory(context, homeSvc),
          excludeSemantics: true,
          child: Pressable(
            onTap: () => openCategory(context, homeSvc),
            child: Container(
              height: small,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: WColors.blue, borderRadius: WRadius.all(WRadius.lg)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(homeSvc.name, style: WText.bodyStrong.copyWith(color: WColors.white, fontWeight: FontWeight.w600)),
                    Text('سباكة · كهرباء · تنظيف', style: WText.caption.copyWith(color: WColors.white.withValues(alpha: 0.75))),
                  ]),
                ),
                const Icon(Icons.handyman_rounded, color: WColors.lime, size: 30),
              ]),
            ),
          ),
        );

    final first = stores.isNotEmpty ? stores.first : null;
    final grid = stores.skip(1).take(4).toList();
    final rest = stores.skip(5).toList();

    // شاشة ضيقة (عرض صغير أو «حجم العرض» مكبّر بالهاتف): القسم الأول بعرض كامل، والباقي عمودين
    // حتى ما تصغر الأسماء أو تنكسر.
    Widget narrow() {
      final others = [...grid, ...rest];
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (first != null) tile(first, big: true, height: 150),
        for (var r = 0; r < (others.length + 1) ~/ 2; r++) ...[
          const SizedBox(height: gap),
          Row(children: [
            Expanded(child: tile(others[r * 2])),
            const SizedBox(width: gap),
            Expanded(child: r * 2 + 1 < others.length ? tile(others[r * 2 + 1]) : const SizedBox(height: small)),
          ]),
        ],
        if (homeSvc != null) ...[const SizedBox(height: gap), homeTile(homeSvc)],
      ]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(WSpace.page, 24, WSpace.page, 0),
      child: LayoutBuilder(
          builder: (context, box) => box.maxWidth < 340
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(heading, style: WText.h2), const SizedBox(height: 12), narrow()])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(heading, style: WText.h2),
                  const SizedBox(height: 12),
                  if (first != null)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: tile(first, big: true)),
                      const SizedBox(width: gap),
                      Expanded(
                        child: Column(children: [
                          for (var r = 0; r < 2; r++) ...[
                            if (r > 0) const SizedBox(height: gap),
                            Row(children: [
                              for (var c = 0; c < 2; c++) ...[
                                if (c > 0) const SizedBox(width: gap),
                                Expanded(child: r * 2 + c < grid.length ? tile(grid[r * 2 + c]) : const SizedBox(height: small)),
                              ],
                            ]),
                          ],
                        ]),
                      ),
                    ]),
                  if (rest.isNotEmpty || homeSvc != null) ...[
                    const SizedBox(height: gap),
                    Row(children: [
                      for (final c in rest) ...[Expanded(child: tile(c)), const SizedBox(width: gap)],
                      if (homeSvc != null) Expanded(flex: rest.isEmpty ? 1 : 2, child: homeTile(homeSvc)),
                    ]),
                  ],
                ])),
    );
  }

  // ======================= العروض =======================
  Widget _promotions(List<Promotion> promos) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: SizedBox(
          height: 128,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.86),
            padEnds: false,
            itemCount: promos.length,
            itemBuilder: (context, i) {
              final p = promos[i];
              return Padding(
                padding: EdgeInsetsDirectional.only(start: i == 0 ? WSpace.page : 5, end: 5),
                child: Pressable(
                  onTap: () async {
                    if (p.merchantId == null) return;
                    final m = await catalogApi.merchant(p.merchantId!);
                    if (m != null && context.mounted) openMerchant(context, m);
                  },
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: i.isEven ? WColors.lime : WColors.surface, borderRadius: WRadius.all(WRadius.lg), border: i.isEven ? null : Border.all(color: WColors.line)),
                    child: Row(children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                            // البطاقة الليمونية نصها حبر بالوضعين، والبيضاء نصها يتبع الوضع
                            Text('عرض', style: WText.overline.copyWith(color: i.isEven ? WColors.ink : WColors.fg)),
                            const SizedBox(height: 4),
                            Text(p.title, style: WText.h3.copyWith(fontWeight: FontWeight.w700, color: i.isEven ? WColors.ink : WColors.fg), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (p.description.isNotEmpty) Text(p.description, style: WText.caption.copyWith(color: i.isEven ? WColors.graphite : WColors.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ),
                      if (p.imageUrl != null) WImage(p.imageUrl, width: 120, height: 128, radius: 0) else Padding(padding: const EdgeInsets.all(16), child: WaselMark(size: 64, route: i.isEven ? WColors.ink : null)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      );

  // ======================= المحلات =======================
  Widget _nearby(List<Merchant> merchants, LatLng? ref) {
    final nearby = [...merchants];
    if (ref != null) {
      nearby.sort((a, b) => distanceKm(ref.latitude, ref.longitude, a.lat, a.lng).compareTo(distanceKm(ref.latitude, ref.longitude, b.lat, b.lng)));
    }
    return SizedBox(
      height: 222,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
        itemCount: nearby.take(10).length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) => MerchantCard(nearby[i], onTap: () => openMerchant(context, nearby[i])),
      ),
    );
  }

  Widget _popular(List<Merchant> merchants) {
    final popular = [...merchants]..sort((a, b) => b.orderCount.compareTo(a.orderCount));
    return SliverList.list(children: [
      for (var i = 0; i < popular.take(8).length; i++) MerchantRow(popular[i], rank: i + 1, onTap: () => openMerchant(context, popular[i])),
    ]);
  }

  // ======================= اطلب مرة ثانية =======================
  Widget _recent(List<Order> orders, String heading) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle(heading, padding: const EdgeInsets.fromLTRB(WSpace.page, 26, WSpace.page, 12)),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final o = orders[i];
              return WCard(
                padding: const EdgeInsets.all(10),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: o.id))),
                child: SizedBox(
                  width: 200,
                  child: Row(children: [
                    MerchantLogo(name: o.merchantName ?? '', url: o.merchantLogo, size: 46),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(o.merchantName ?? '', style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${iqd(o.total)} · ${dateTimeAr(o.createdAt)}', style: WText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]);
}

class _HomeData {
  _HomeData(this.merchants, this.promotions, this.recent, this.layout, this.activeRide, this.destinations);
  final List<Merchant> merchants;
  final List<Promotion> promotions;
  final List<Order> recent;
  final List<HomeSection> layout;
  final Ride? activeRide;
  final List<RideDestination> destinations;
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
        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: WColors.ink, shape: BoxShape.circle)),
      );
}
