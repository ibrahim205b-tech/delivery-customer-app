import 'package:flutter/material.dart';
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

void openMerchant(BuildContext context, Merchant m) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => MerchantPage(merchant: m)));

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
    ]);
    return _HomeData(r[0] as List<Merchant>, r[1] as List<Promotion>, r[2] as List<Order>);
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
        bottomNavigationBar: const CartBar(),
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) {
              if (app.loadError != null && !app.loaded) return ErrorView(error: app.loadError!, onRetry: _refresh);
              return RefreshIndicator(
                color: WColors.coral,
                onRefresh: _refresh,
                child: CustomScrollView(slivers: [
                  SliverToBoxAdapter(child: _header()),
                  SliverToBoxAdapter(child: _searchBar()),
                  SliverToBoxAdapter(
                    child: FutureBuilder<_HomeData>(
                      future: _data,
                      builder: (context, s) {
                        if (s.hasError) return Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(error: s.error!, onRetry: _refresh));
                        final d = s.data;
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (d != null && d.promotions.isNotEmpty) _promotions(d.promotions),
                          _storeCategories(),
                          _mobilityRow(),
                          _homeServicesBanner(),
                          if (d == null) const Padding(padding: EdgeInsets.all(20), child: SkeletonBox(height: 180, radius: WRadius.lg)),
                          if (d != null) ..._merchantSections(d),
                          if (d != null && d.recent.isNotEmpty) _recent(d.recent),
                          const SizedBox(height: 32),
                        ]);
                      },
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
      );

  // ---------------- الرأس: العنوان + المنطقة + الإشعارات ----------------
  Widget _header() {
    final a = app.selectedAddress;
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'صباح الخير' : 'مساء الخير';
    final first = (auth.profile?.fullName ?? '').split(' ').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(WSpace.page, 12, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: WRadius.all(WRadius.md),
              onTap: () => pickAddressSheet(context, onAddNew: _addAddress),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(color: WColors.coralSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.location_on_rounded, color: WColors.coralDeep, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('التوصيل إلى', style: WText.caption),
                      Row(children: [
                        Flexible(
                          child: Text(a == null ? 'أضف عنوان التوصيل' : a.oneLine,
                              style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          Stack(children: [
            WIconButton(Icons.notifications_none_rounded, background: Colors.transparent, tooltip: 'الإشعارات', onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            }),
            if (widget.unread > 0)
              const PositionedDirectional(top: 10, end: 10, child: CircleAvatar(radius: 5, backgroundColor: WColors.coral)),
          ]),
        ]),
        const SizedBox(height: 14),
        Text(first.isEmpty ? greet : '$greet $first', style: WText.small),
        const SizedBox(height: 2),
        Text('شتحتاج اليوم؟', style: WText.h1),
        const SizedBox(height: 10),
        _areaChips(),
      ]),
    );
  }

  Widget _areaChips() {
    final areas = app.areas.where((a) => a.isActive).toList();
    if (areas.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 38,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ChoiceChip(
            label: const Text('كل المناطق'),
            selected: app.selectedAreaId == null,
            onSelected: (_) => _selectArea(null),
          ),
        ),
        for (final ar in areas)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(label: Text(ar.name), selected: app.selectedAreaId == ar.id, onSelected: (_) => _selectArea(ar.id)),
          ),
      ]),
    );
  }

  void _selectArea(String? id) {
    app.selectArea(id);
    setState(() => _data = _load());
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.page, 14, WSpace.page, 4),
        child: Material(
          color: WColors.white,
          shape: RoundedRectangleBorder(borderRadius: WRadius.all(WRadius.md), side: const BorderSide(color: WColors.line)),
          child: InkWell(
            borderRadius: WRadius.all(WRadius.md),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              child: Row(children: [
                const Icon(Icons.search_rounded, color: WColors.inkMuted),
                const SizedBox(width: 10),
                Text('دوّر على مطعم، منتج، أو محل', style: WText.body.copyWith(color: WColors.inkFaint)),
              ]),
            ),
          ),
        ),
      );

  // ---------------- العروض ----------------
  Widget _promotions(List<Promotion> promos) => SizedBox(
        height: 150,
        child: PageView.builder(
          controller: PageController(viewportFraction: 0.88),
          padEnds: false,
          itemCount: promos.length,
          itemBuilder: (context, i) {
            final p = promos[i];
            return Padding(
              padding: EdgeInsetsDirectional.only(start: i == 0 ? WSpace.page : 6, end: 6, top: 14),
              child: Material(
                color: WColors.navy,
                borderRadius: WRadius.all(WRadius.lg),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: p.merchantId == null
                      ? null
                      : () async {
                          final m = await catalogApi.merchant(p.merchantId!);
                          if (m != null && context.mounted) openMerchant(context, m);
                        },
                  child: Stack(fit: StackFit.expand, children: [
                    if (p.imageUrl != null) Opacity(opacity: 0.55, child: WImage(p.imageUrl, radius: 0)),
                    PositionedDirectional(
                      start: -30,
                      bottom: -40,
                      child: Opacity(opacity: 0.18, child: const WaselMark(size: 150, stroke: WColors.coral, dot: WColors.mint)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                        const StatusPill('عرض', tone: PillTone.accent),
                        const SizedBox(height: 8),
                        Text(p.title, style: WText.h3.copyWith(color: WColors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (p.description.isNotEmpty)
                          Text(p.description, style: WText.small.copyWith(color: WColors.mint), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      );

  // ---------------- الأقسام: محلات ----------------
  Widget _storeCategories() {
    final cats = app.categories.where((c) => c.kind == CategoryKind.store).toList();
    if (cats.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('الأقسام'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Wrap(
          runSpacing: 14,
          children: [
            for (final c in cats)
              FractionallySizedBox(
                widthFactor: 0.25,
                child: InkWell(
                  borderRadius: WRadius.all(WRadius.md),
                  onTap: () => openCategory(context, c),
                  child: Column(children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(color: categoryTint(c.icon).withValues(alpha: 0.11), borderRadius: WRadius.all(20)),
                      child: Icon(categoryIcon(c.icon), color: categoryTint(c.icon), size: 28),
                    ),
                    const SizedBox(height: 6),
                    Text(c.name, style: WText.caption.copyWith(color: WColors.ink), textAlign: TextAlign.center, maxLines: 2),
                  ]),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  // ---------------- التنقل والتوصيل: بطاقات داكنة عريضة ----------------
  Widget _mobilityRow() {
    final cats = app.categories.where((c) => c.kind == CategoryKind.ride || c.kind == CategoryKind.courier || c.kind == CategoryKind.parcel).toList();
    if (cats.isEmpty) return const SizedBox.shrink();
    String hint(MerchantCategory c) => switch (c.id) {
          'taxi' => 'وصلة لأي مكان',
          'tuktuk' => 'مشاوير قريبة',
          'courier' => 'نشتريلك أي شي',
          _ => 'من باب لباب',
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('تنقّل وتوصيل'),
      SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final c = cats[i];
            return Material(
              color: WColors.navy,
              borderRadius: WRadius.all(WRadius.lg),
              child: InkWell(
                borderRadius: WRadius.all(WRadius.lg),
                onTap: () => openCategory(context, c),
                child: Container(
                  width: 150,
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Icon(categoryIcon(c.icon), color: WColors.coral, size: 28),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: WText.bodyStrong.copyWith(color: WColors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(hint(c), style: WText.caption.copyWith(color: WColors.mint)),
                    ]),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ---------------- الخدمات المنزلية: بطاقة عريضة ----------------
  Widget _homeServicesBanner() {
    final c = app.categories.where((c) => c.kind == CategoryKind.homeService).firstOrNull;
    if (c == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(WSpace.page, 20, WSpace.page, 0),
      child: Material(
        color: WColors.mintSoft,
        borderRadius: WRadius.all(WRadius.lg),
        child: InkWell(
          borderRadius: WRadius.all(WRadius.lg),
          onTap: () => openCategory(context, c),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: WText.h3),
                  const SizedBox(height: 2),
                  Text('سباكة، كهرباء، صيانة وتنظيف — احجز فني لبيتك بالوقت اللي يناسبك', style: WText.small),
                ]),
              ),
              const SizedBox(width: 12),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final i in [Icons.plumbing_rounded, Icons.electrical_services_rounded, Icons.cleaning_services_rounded])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: CircleAvatar(radius: 17, backgroundColor: WColors.white, child: Icon(i, size: 18, color: WColors.mintDeep)),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------- المحلات: القريبة + الأكثر طلباً ----------------
  List<Widget> _merchantSections(_HomeData d) {
    if (d.merchants.isEmpty) {
      return [
        const SizedBox(height: 24),
        const EmptyView(
          icon: Icons.storefront_outlined,
          title: 'ما اكو محلات بهذه المنطقة بعد',
          message: 'المحلات تظهر هنا بعد ما تضيفها وتعتمدها إدارة واصل.',
        ),
      ];
    }
    final ref = app.referencePoint;
    final nearby = [...d.merchants];
    if (ref != null) {
      nearby.sort((a, b) => distanceKm(ref.latitude, ref.longitude, a.lat, a.lng).compareTo(distanceKm(ref.latitude, ref.longitude, b.lat, b.lng)));
    }
    final popular = [...d.merchants]..sort((a, b) => b.orderCount.compareTo(a.orderCount));
    return [
      SectionTitle(ref == null ? 'محلات مختارة' : 'قريبة منك'),
      SizedBox(
        height: 240,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
          itemCount: nearby.take(10).length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, i) => MerchantCard(nearby[i], onTap: () => openMerchant(context, nearby[i])),
        ),
      ),
      const SectionTitle('الأكثر طلباً'),
      for (final m in popular.take(8)) MerchantRow(m, onTap: () => openMerchant(context, m)),
    ];
  }

  // ---------------- اطلب مرة ثانية ----------------
  Widget _recent(List<Order> orders) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('طلباتك الأخيرة'),
        SizedBox(
          height: 76,
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
                  width: 210,
                  child: Row(children: [
                    MerchantLogo(name: o.merchantName ?? '', url: o.merchantLogo, size: 46),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(o.merchantName ?? '', style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(o.status.isActive ? o.status.label : dateTimeAr(o.createdAt), style: WText.caption, maxLines: 1),
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
  _HomeData(this.merchants, this.promotions, this.recent);
  final List<Merchant> merchants;
  final List<Promotion> promotions;
  final List<Order> recent;
}
