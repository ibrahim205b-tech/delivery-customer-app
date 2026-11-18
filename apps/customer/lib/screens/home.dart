import 'dart:async';

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
// الصفحة الرئيسية — مطابقة للتصميم المرجعي (design/home_reference.png)
//
// الترتيب: الرأس (المدينة، الشعار، الإشعارات) ← البانر ← البحث ← [طلبك الشغّال إذا موجود]
//   ← المطاعم + تاكسي ← عروض خاصة ← أقسام المطاعم.
// الصور ملفات حقيقية مقصوصة من المرجع (assets/home). العروض من بيانات المطاعم الفعلية فقط.
// الألوان ثابتة كما في المرجع (الصفحة مصممة للوضع الفاتح).
// =====================================================================

class _R {
  static const page = Color(0xFFF7F6FD);
  static const ink = Color(0xFF17171B);
  static const sub = Color(0xFF4C4C55);
  static const muted = Color(0xFF9B9BA4);
  static const line = Color(0xFFECEAF2);
  static const red = Color(0xFFE3161B);
  static const redDeep = Color(0xFFD60103);
  static const orange = Color(0xFFFF8C00);
  static const yellow = Color(0xFFFFC21C);
  static const peachFood = Color(0xFFFBE8D0);
  static const peachTaxi = Color(0xFFFCE3C8);
  static const tile = Color(0xFFFFEEEC);
  static const shadow = [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 4))];
}

TextStyle _t(double size, {FontWeight w = FontWeight.w700, Color color = _R.ink, double? height}) =>
    WText.body.copyWith(fontSize: size, fontWeight: w, color: color, height: height);

/// سهم ">" ثابت الاتجاه كما في المرجع
Widget _chevron(IconData icon, double size, Color color) =>
    Directionality(textDirection: TextDirection.ltr, child: Icon(icon, size: size, color: color));

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.unread});
  final int unread;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _data = _load();

  Future<_HomeData> _load() async {
    final r = await Future.wait<Object>([
      catalogApi.activePromotions().catchError((_) => <Promotion>[]),
      // العروض تحتاج ترحيل 0018؛ إذا ما مطبّق يرجع فارغاً بدل ما يكسر الصفحة
      catalogApi.offers(areaId: app.selectedAreaId).catchError((_) => <(Product, Merchant)>[]),
      customerApi.myOrders(limit: 3).catchError((_) => <Order>[]),
    ]);
    return _HomeData(r[0] as List<Promotion>, r[1] as List<(Product, Merchant)>, r[2] as List<Order>);
  }

  Future<void> _refresh() async {
    await app.load();
    final f = _load();
    setState(() => _data = f);
    await f.then((_) {}, onError: (_) {});
  }

  void _openRestaurants() {
    final c = _cat('restaurants');
    if (c == null) return showInfo(context, 'المطاعم غير متاحة حالياً.');
    openCategory(context, c);
  }

  void _openSection(String id, String name) {
    final c = _cat(id);
    if (c == null) return showInfo(context, 'قسم $name غير متاح حالياً.');
    openCategory(context, c);
  }

  void _openTaxi() {
    final c = _cat('taxi');
    if (c == null) return showInfo(context, 'خدمة التكسي غير متاحة حالياً.');
    openCategory(context, c);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _R.page,
        bottomNavigationBar: const CartBar(),
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) {
              if (app.loadError != null && !app.loaded) return SafeArea(child: ErrorView(error: app.loadError!, onRetry: _refresh));
              return SafeArea(
                bottom: false,
                child: RefreshIndicator(
                  color: _R.red,
                  onRefresh: _refresh,
                  child: FutureBuilder<_HomeData>(
                    future: _data,
                    builder: (context, s) {
                      final d = s.data;
                      final active = d?.recent.where((o) => o.status.isActive).firstOrNull;
                      return ListView(padding: const EdgeInsets.only(bottom: 8), children: [
                        _Header(
                          unread: widget.unread,
                          city: app.selectedArea?.city.isNotEmpty == true ? app.selectedArea!.city : 'بغداد',
                          onCity: () => pickAddressSheet(context, onAddNew: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressFormScreen()))),
                          onBell: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                        ),
                        _Banner(promos: d?.promotions ?? const [], onOrder: _openRestaurants),
                        const SizedBox(height: 12),
                        _SearchBox(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()))),
                        if (active != null) _LiveOrderStrip(order: active, onClosed: () => setState(() => _data = _load())),
                        const SizedBox(height: 17),
                        _Services(onRestaurants: _openRestaurants, onTaxi: _openTaxi),
                        const SizedBox(height: 12),
                        _MoreSections(onOpen: _openSection),
                        const SizedBox(height: 23),
                        _OffersSection(offers: d?.offers, error: s.hasError),
                        const SizedBox(height: 16),
                        _Categories(onMore: _openRestaurants),
                      ]);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );
}

class _HomeData {
  _HomeData(this.promotions, this.offers, this.recent);
  final List<Promotion> promotions;
  final List<(Product, Merchant)> offers;
  final List<Order> recent;
}

// ---------------------------------------------------------------------
// الرأس: المدينة (يمين) · الشعار (وسط) · الإشعارات (يسار)
// ---------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({required this.unread, required this.city, required this.onCity, required this.onBell});
  final int unread;
  final String city;
  final VoidCallback onCity;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 76,
        child: Stack(children: [
          // الشعار والعبارة
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 142,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/home/logo.png', width: 142, filterQuality: FilterQuality.high, semanticLabel: 'واصل'),
                Align(
                  // العبارة تحت كلمة "واصل" (يسار الشعار) كما في المرجع
                  alignment: const Alignment(-0.42, 0),
                  child: Text('اطلب .. نوصلك', style: _t(12.5, w: FontWeight.w600, color: _R.ink, height: 1.1)),
                ),
              ]),
            ),
          ),
          // المدينة
          PositionedDirectional(
            start: 14,
            top: 29,
            child: Semantics(
              button: true,
              label: 'المدينة: $city',
              child: GestureDetector(
                onTap: onCity,
                child: Container(
                  height: 31,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _R.line), boxShadow: _R.shadow),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_on_rounded, size: 18, color: _R.orange),
                    const SizedBox(width: 6),
                    Text(city, style: _t(14, height: 1.1)),
                  ]),
                ),
              ),
            ),
          ),
          // الإشعارات
          PositionedDirectional(
            end: 10,
            top: 24,
            child: Semantics(
              button: true,
              label: unread > 0 ? 'الإشعارات، $unread غير مقروءة' : 'الإشعارات',
              child: GestureDetector(
                onTap: onBell,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(clipBehavior: Clip.none, children: [
                    const Center(child: Icon(Icons.notifications_none_rounded, size: 32, color: _R.ink)),
                    if (unread > 0)
                      Positioned(
                        top: 0,
                        right: 2,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 19),
                          height: 19,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(color: _R.red, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 1.5)),
                          alignment: Alignment.center,
                          child: Text(unread > 99 ? '99+' : '$unread', style: _t(10.5, color: Colors.white, height: 1)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------
// البانر: شريحة واصل الرئيسية + عروض الإدارة الفعّالة (إن وجدت)
// ---------------------------------------------------------------------
class _Banner extends StatefulWidget {
  const _Banner({required this.promos, required this.onOrder});
  final List<Promotion> promos;
  final VoidCallback onOrder;
  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  final _ctrl = PageController();
  Timer? _auto;
  int _page = 0;

  int get _count => 1 + widget.promos.length;

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _count < 2 || !_ctrl.hasClients) return;
      _ctrl.animateToPage((_page + 1) % _count, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = w * 333 / 852;
        return SizedBox(
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(children: [
              PageView(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _BrandSlide(height: h, width: w, onOrder: widget.onOrder),
                  for (final p in widget.promos) _PromoSlide(promo: p),
                ],
              ),
              // مؤشرات السلايدر
              Positioned(
                left: 0,
                right: 0,
                bottom: h * 0.075,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  textDirection: TextDirection.ltr,
                  children: [
                    for (var i = 0; i < _count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: i == _page ? _R.red : Colors.white, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        );
      });
}

class _BrandSlide extends StatelessWidget {
  const _BrandSlide({required this.height, required this.width, required this.onOrder});
  final double height;
  final double width;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final fs = height * 0.14;
    return Stack(fit: StackFit.expand, children: [
      // خلفية المطعم الداكنة
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B2A1D), Color(0xFF1C140F), Color(0xFF0B0807)],
          ),
        ),
      ),
      // توهّج أحمر أسفل اليمين كما في المرجع
      Positioned(
        right: -width * 0.08,
        bottom: -height * 0.35,
        child: Container(
          width: width * 0.42,
          height: height * 0.8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Color(0x99B3060A), Color(0x00B3060A)]),
          ),
        ),
      ),
      // صورة البرغر والبطاطا (من المرجع)
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: Image.asset('assets/home/banner_food.png', height: height, fit: BoxFit.fitHeight, filterQuality: FilterQuality.high),
      ),
      // النص والزر
      PositionedDirectional(
        start: width * 0.045,
        top: height * 0.13,
        width: width * 0.40,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text('كل ما تشتهيه', style: _t(fs, w: FontWeight.w800, color: Colors.white, height: 1.25))),
          FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text('في مكان واحد', style: _t(fs, w: FontWeight.w800, color: _R.yellow, height: 1.25))),
          SizedBox(height: height * 0.07),
          Semantics(
            button: true,
            label: 'اطلب الآن',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onOrder,
              child: Transform.rotate(
                angle: -0.05,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: height * 0.06, vertical: height * 0.035),
                  decoration: BoxDecoration(color: const Color(0xFFD7141B), borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3))]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: height * 0.115,
                      height: height * 0.115,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: _chevron(Icons.chevron_right_rounded, height * 0.1, const Color(0xFFD7141B)),
                    ),
                    SizedBox(width: height * 0.05),
                    Text('اطلب الآن', style: _t(height * 0.09, w: FontWeight.w800, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// شريحة عرض من الإدارة (صورة العرض الحقيقية وعنوانه)
class _PromoSlide extends StatelessWidget {
  const _PromoSlide({required this.promo});
  final Promotion promo;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          final mid = promo.merchantId;
          if (mid == null) return;
          final m = await catalogApi.merchant(mid).catchError((_) => null);
          if (m != null && context.mounted) openMerchant(context, m);
        },
        child: Stack(fit: StackFit.expand, children: [
          if ((promo.imageUrl ?? '').isNotEmpty)
            WImage(promo.imageUrl, radius: 0, fallbackColor: const Color(0xFF2A1D14))
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B2A1D), Color(0xFF1C140F), Color(0xFF0B0807)]),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)])),
          ),
          PositionedDirectional(
            start: 16,
            end: 16,
            bottom: 30,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(promo.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(20, w: FontWeight.w800, color: Colors.white)),
              if (promo.description.isNotEmpty)
                Text(promo.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, w: FontWeight.w500, color: _R.yellow)),
            ]),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------
// البحث
// ---------------------------------------------------------------------
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Semantics(
          button: true,
          label: 'ابحث عن مطعم أو وجبة',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: _R.line), boxShadow: _R.shadow),
              child: Row(children: [
                const Icon(Icons.search_rounded, size: 24, color: _R.ink),
                const SizedBox(width: 12),
                Text('ابحث عن مطعم أو وجبة ...', style: _t(13.5, w: FontWeight.w500, color: _R.muted)),
              ]),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------
// الخدمتان: المطاعم وتاكسي (فقط)
// ---------------------------------------------------------------------
class _Services extends StatelessWidget {
  const _Services({required this.onRestaurants, required this.onTaxi});
  final VoidCallback onRestaurants;
  final VoidCallback onTaxi;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: SizedBox(
          height: 138,
          child: Row(children: [
            Expanded(child: _ServiceTile(title: 'المطاعم', sub: 'اكتشف المطاعم', asset: 'assets/home/restaurant.png', bg: _R.peachFood, onTap: onRestaurants)),
            const SizedBox(width: 12),
            Expanded(child: _ServiceTile(title: 'تاكسي', sub: 'اطلب سيارة الآن', asset: 'assets/home/taxi.png', bg: _R.peachTaxi, onTap: onTaxi)),
          ]),
        ),
      );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.title, required this.sub, required this.asset, required this.bg, required this.onTap});
  final String title;
  final String sub;
  final String asset;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$title، $sub',
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), boxShadow: _R.shadow),
            child: Column(children: [
              Expanded(child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.high)),
              const SizedBox(height: 2),
              Text(title, style: _t(16.5, w: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 25,
                  height: 25,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))]),
                  alignment: Alignment.center,
                  child: _chevron(Icons.chevron_right_rounded, 20, _R.ink),
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12, w: FontWeight.w500, color: _R.sub))),
              ]),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------
// أقسام إضافية: سوبر ماركت، طبخ منزلي، محلات الهواتف (صور القسم المعتمدة)
// ---------------------------------------------------------------------
class _MoreSections extends StatelessWidget {
  const _MoreSections({required this.onOpen});
  final void Function(String id, String name) onOpen;

  static const _items = [
    ('supermarket', 'سوبر ماركت', 'assets/home/section_supermarket.jpg'),
    ('home_cooking', 'طبخ منزلي', 'assets/home/section_home_cooking.jpg'),
    ('mobiles', 'محلات الهواتف', 'assets/home/section_phones.jpg'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: SizedBox(
          height: 128,
          child: Row(children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  button: true,
                  label: _items[i].$2,
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: () => onOpen(_items[i].$1, _items[i].$2),
                    child: Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: _R.shadow),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(fit: StackFit.expand, children: [
                        Image.asset(_items[i].$3, fit: BoxFit.cover, alignment: const Alignment(0, -0.1), filterQuality: FilterQuality.high),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)], stops: [0, 0.45, 1]),
                          ),
                        ),
                        PositionedDirectional(
                          end: 8,
                          top: 8,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: _chevron(Icons.chevron_right_rounded, 17, _R.ink),
                          ),
                        ),
                        // العنوان بعرض البطاقة كاملاً، ويصغر إذا ما وسعه (ما يُقص)
                        PositionedDirectional(
                          start: 9,
                          end: 9,
                          bottom: 9,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(_items[i].$2, maxLines: 1, style: _t(13.5, w: FontWeight.w800, color: Colors.white)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      );
}

// ---------------------------------------------------------------------
// عروض خاصة: منتجات حقيقية سعرها أقل من سعرها قبل الخصم
// ---------------------------------------------------------------------
class _OffersSection extends StatelessWidget {
  const _OffersSection({required this.offers, required this.error});
  final List<(Product, Merchant)>? offers;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final list = offers;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          const Icon(Icons.star_rounded, size: 24, color: _R.red),
          const SizedBox(width: 6),
          Text('عروض خاصة', style: _t(17, w: FontWeight.w800)),
          const Spacer(),
          Semantics(
            button: true,
            label: 'عرض كل العروض',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OffersScreen())),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _R.line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('عرض الكل', style: _t(12.5, w: FontWeight.w600)),
                  const SizedBox(width: 4),
                  _chevron(Icons.chevron_left_rounded, 20, _R.red),
                ]),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, box) {
        final cardW = (box.maxWidth - 26 - 12) / 2;
        final cardH = cardW * 199 / 385 + 50;
        if (list == null && !error) {
          return SizedBox(
            height: cardH,
            child: Row(children: [
              const SizedBox(width: 13),
              SkeletonBox(height: cardH, width: cardW, radius: 16),
              const SizedBox(width: 12),
              SkeletonBox(height: cardH, width: cardW, radius: 16),
            ]),
          );
        }
        if (list == null || list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _R.line)),
              child: Row(children: [
                const Icon(Icons.local_offer_outlined, color: _R.red),
                const SizedBox(width: 10),
                Expanded(child: Text('ما اكو عروض حالياً. العروض تظهر هنا لما المطاعم تضيف خصم على وجباتها.', style: _t(13.5, w: FontWeight.w500, color: _R.sub))),
              ]),
            ),
          );
        }
        return SizedBox(
          height: cardH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(width: cardW, child: OfferCard(product: list[i].$1, merchant: list[i].$2)),
          ),
        );
      }),
    ]);
  }
}

/// صورة الوجبة: صورة المنتج الحقيقية، وإلا صورة من المرجع تناسب نوع الوجبة، وإلا أيقونة
String? _offerAsset(String name) {
  final n = name;
  if (n.contains('بيتزا')) return 'assets/home/offer_pizza.jpg';
  if (n.contains('دجاج') || n.contains('كرسبي') || n.contains('بروستد')) return 'assets/home/offer_chicken.jpg';
  if (n.contains('شاورما')) return 'assets/home/cat_shawarma.jpg';
  if (n.contains('برغر') || n.contains('بركر')) return 'assets/home/cat_burger.jpg';
  if (n.contains('مشويات') || n.contains('كباب') || n.contains('تكة')) return 'assets/home/cat_grills.jpg';
  return null;
}

/// بطاقة عرض (تُستخدم بالرئيسية وبشاشة كل العروض)
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.product, required this.merchant});
  final Product product;
  final Merchant merchant;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final asset = _offerAsset(p.name);
    final Widget img = p.images.isNotEmpty
        ? WImage(p.images.first, radius: 0)
        : asset != null
            ? Image.asset(asset, fit: BoxFit.cover, filterQuality: FilterQuality.high)
            : Container(color: _R.tile, alignment: Alignment.center, child: const Icon(Icons.restaurant_rounded, color: _R.red, size: 34));
    return Semantics(
      button: true,
      label: '${p.name}، خصم ${p.discountPercent}٪، ${iqd(p.price)} بدل ${iqd(p.compareAtPrice!)}، ${merchant.name}',
      excludeSemantics: true,
      child: Pressable(
        onTap: () => showProductSheet(context, merchant, p),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: _R.shadow),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 385 / 199,
              child: LayoutBuilder(builder: (context, b) {
                // الشارة بنفس مكان شارة المرجع وأكبر قليلاً منها (تغطيها بالكامل في صورتي المرجع)
                final d = b.maxWidth * 0.30;
                return Stack(fit: StackFit.expand, children: [
                  img,
                  Positioned(
                    left: b.maxWidth * 0.8416 - d / 2,
                    top: b.maxHeight * 0.3116 - d / 2,
                    width: d,
                    height: d,
                    child: Container(
                      decoration: const BoxDecoration(color: _R.red, shape: BoxShape.circle),
                      padding: EdgeInsets.all(d * 0.12),
                      child: FittedBox(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('خصم', style: _t(15, w: FontWeight.w800, color: Colors.white, height: 1.05)),
                          Directionality(textDirection: TextDirection.ltr, child: Text('${p.discountPercent}%', style: _t(19, w: FontWeight.w800, color: Colors.white, height: 1.05))),
                        ]),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13.5, w: FontWeight.w800, height: 1.25)),
                  // السعر القديم مشطوب (يمين) والسعر الحالي بالأحمر (يسار) كما في المرجع؛ يتقلص ولا يُقص
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(iqd(p.compareAtPrice!),
                          style: _t(12, w: FontWeight.w600, color: _R.muted, height: 1.2).copyWith(decoration: TextDecoration.lineThrough, decorationColor: _R.muted)),
                      const SizedBox(width: 14),
                      Text(iqd(p.price), style: _t(13, w: FontWeight.w800, color: _R.red, height: 1.2)),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// كل العروض الحقيقية
class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('عروض خاصة')),
        bottomNavigationBar: const CartBar(),
        body: AsyncView<List<(Product, Merchant)>>(
          load: () => catalogApi.offers(areaId: app.selectedAreaId, limit: 100),
          builder: (context, list, reload) => list.isEmpty
              ? const EmptyView(icon: Icons.local_offer_outlined, title: 'ما اكو عروض حالياً', message: 'العروض تظهر هنا لما المطاعم تضيف خصم على وجباتها.')
              : RefreshIndicator(
                  onRefresh: reload,
                  child: LayoutBuilder(builder: (context, box) {
                    final w = (box.maxWidth - 26 - 12) / 2;
                    return GridView.builder(
                      padding: const EdgeInsets.all(13),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: w / (w * 199 / 385 + 50)),
                      itemCount: list.length,
                      itemBuilder: (context, i) => OfferCard(product: list[i].$1, merchant: list[i].$2),
                    );
                  }),
                ),
        ),
      );
}

// ---------------------------------------------------------------------
// أقسام المطاعم: كل قسم يفتح البحث الحقيقي بكلمته
// ---------------------------------------------------------------------
class _Categories extends StatelessWidget {
  const _Categories({required this.onMore});
  final VoidCallback onMore;

  static const _items = [
    ('شاورما', 'assets/home/cat_shawarma.jpg'),
    ('مشويات', 'assets/home/cat_grills.jpg'),
    ('برغر', 'assets/home/cat_burger.jpg'),
    ('بيتزا', 'assets/home/cat_pizza.jpg'),
  ];

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            const Icon(Icons.restaurant_rounded, size: 22, color: _R.red),
            const SizedBox(width: 6),
            Text('أقسام المطاعم', style: _t(17, w: FontWeight.w800)),
          ]),
        ),
        const SizedBox(height: 11),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: LayoutBuilder(builder: (context, box) {
            const gap = 6.5;
            final w = (box.maxWidth - gap * 4) / 5;
            final photoH = w * 101 / 149;
            final h = photoH + 20;
            return Row(children: [
              for (final (label, asset) in _items) ...[
                SizedBox(
                  width: w,
                  height: h,
                  child: Semantics(
                    button: true,
                    label: label,
                    excludeSemantics: true,
                    child: Pressable(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(initialQuery: label))),
                      child: Container(
                        decoration: BoxDecoration(color: _R.tile, borderRadius: BorderRadius.circular(13), boxShadow: _R.shadow),
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          SizedBox(height: photoH, width: w, child: Image.asset(asset, fit: BoxFit.cover, filterQuality: FilterQuality.high)),
                          Expanded(child: Center(child: Text(label, maxLines: 1, style: _t(12, w: FontWeight.w800, height: 1)))),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: gap),
              ],
              SizedBox(
                width: w,
                height: h,
                child: Semantics(
                  button: true,
                  label: 'المزيد',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: onMore,
                    child: Container(
                      decoration: BoxDecoration(color: _R.redDeep, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Color(0x40D60103), blurRadius: 10, offset: Offset(0, 4))]),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const _GridGlyph(size: 22),
                        const SizedBox(height: 6),
                        Text('المزيد', style: _t(12, w: FontWeight.w800, color: Colors.white, height: 1)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]);
          }),
        ),
      ]);
}

/// أيقونة "المزيد": أربعة مربعات بيضاء بحواف دائرية
class _GridGlyph extends StatelessWidget {
  const _GridGlyph({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    final s = size * 0.44;
    Widget sq() => Container(width: s, height: s, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(s * 0.32)));
    return SizedBox(
      width: size,
      height: size,
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [sq(), sq()]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [sq(), sq()]),
      ]),
    );
  }
}


// ---------------------------------------------------------------------
// طلبك الشغّال: شريط صغير (يظهر فقط إذا عندك طلب جاري) حتى لا يغيّر ترتيب الصفحة
// ---------------------------------------------------------------------
class _LiveOrderStrip extends StatelessWidget {
  const _LiveOrderStrip({required this.order, required this.onClosed});
  final Order order;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
        child: Semantics(
          button: true,
          label: 'تتبّع طلبك: ${order.status.label}',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id)));
              onClosed();
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _R.line)),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _R.red, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('طلبك الحالي: ${order.status.label}${(order.merchantName ?? '').isEmpty ? '' : ' · ${order.merchantName}'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12.5, w: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                Text('تتبّع', style: _t(13, w: FontWeight.w800, color: _R.red)),
                _chevron(Icons.chevron_left_rounded, 20, _R.red),
              ]),
            ),
          ),
        ),
      );
}

MerchantCategory? _cat(String id) => app.categories.where((c) => c.id == id).firstOrNull;
List<MerchantCategory> get _shopCategories => app.categories.where((c) => c.kind == CategoryKind.store && c.id != 'restaurants').toList();

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

