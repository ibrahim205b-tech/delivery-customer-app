import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../widgets.dart';
import 'account.dart';
import 'cart.dart';
import 'home.dart';

// =====================================================================
// صفحة القسم (المطاعم، السوبر ماركت، طبخ منزلي، محلات الهواتف، وباقي أقسام المحلات)
// مبنية على تصميم "قسم المطاعم" المعتمد: رأس ثابت (التوصيل إلى + السلة) وبحث فوري،
// تصنيفات سريعة، فلاتر فرز، بطاقات محلات بصورة الغلاف، ودرج معاينة سريعة للقائمة.
// كل المحتوى من بيانات واصل الحقيقية: المحلات، الأسعار، التقييم، المفضلة، السلة، العروض.
// =====================================================================

class _C {
  static const ivory = Color(0xFFFAF8F5);
  static const charcoal = Color(0xFF1C1917);
  static const terracotta = Color(0xFFD95D39);
  static const terracottaLight = Color(0xFFFBF0EC);
  static const olive = Color(0xFF3F6212);
  static const oliveLight = Color(0xFFECF3E4);
  static const sand100 = Color(0xFFF5F2EB);
  static const sand200 = Color(0xFFE8E3D8);
  static const sand300 = Color(0xFFD6CFC0);
  static const stone400 = Color(0xFFA8A29E);
  static const stone500 = Color(0xFF78716C);
  static const stone600 = Color(0xFF57534E);
  static const card = [BoxShadow(color: Color(0x0A1C1917), blurRadius: 12, offset: Offset(0, 2))];
}

/// خط العناوين (Cairo متغيّر الوزن)
TextStyle _d(double size, {FontWeight w = FontWeight.w700, Color c = _C.charcoal, double? h}) =>
    TextStyle(fontFamily: 'Cairo', fontSize: size, fontWeight: w, color: c, height: h, fontVariations: [FontVariation('wght', w.value.toDouble())]);

/// خط النصوص (IBM Plex Sans Arabic)
TextStyle _b(double size, {FontWeight w = FontWeight.w400, Color c = _C.charcoal, double? h}) =>
    TextStyle(fontFamily: 'IBMPlexArabic', fontSize: size, fontWeight: w, color: c, height: h);

/// تصنيف سريع: كلمات يُبحث عنها في أسماء المحلات ووصفها ومنتجاتها
class _Pill {
  const _Pill(this.label, this.icon, [this.keywords = const []]);
  final String label;
  final IconData icon;
  final List<String> keywords;
  bool get isAll => keywords.isEmpty;
}

/// إعداد كل قسم: عنوان القائمة، نص البحث، التصنيفات، وصيغة العدد
class _Section {
  const _Section({required this.title, required this.hint, required this.pills, required this.one, required this.two, required this.many, required this.noMatch, required this.showAll});
  final String title;
  final String hint;
  final List<_Pill> pills;
  final String one;
  final String two;
  final String many;
  final String noMatch;
  final String showAll;

  String count(int n) => n == 1 ? one : n == 2 ? two : '$n $many';

  static const _all = _Pill('الكل', Icons.grid_view_rounded);

  static _Section of(MerchantCategory c) => switch (c.id) {
        'restaurants' => const _Section(
            title: 'المطاعم المتاحة',
            hint: 'ابحث عن مطعم، مشويات، برغر، مسكوف...',
            one: 'مطعم واحد',
            two: 'مطعمان',
            many: 'مطاعم',
            noMatch: 'لم نعثر على مطاعم مطابقة',
            showAll: 'عرض جميع المطاعم',
            pills: [
              _all,
              _Pill('مشويات', Icons.local_fire_department_outlined, ['مشويات', 'مشوي', 'كباب', 'تكة']),
              _Pill('مأكولات عراقية', Icons.rice_bowl_outlined, ['عراقي', 'مسكوف', 'قوزي', 'دولمة', 'تمن', 'باجة']),
              _Pill('برغر', Icons.lunch_dining_outlined, ['برغر', 'بركر']),
              _Pill('بيتزا', Icons.local_pizza_outlined, ['بيتزا']),
              _Pill('شاورما', Icons.kebab_dining_outlined, ['شاورما']),
              _Pill('حلويات', Icons.cake_outlined, ['حلويات', 'كنافة', 'بقلاوة', 'كيك']),
            ],
          ),
        'supermarket' => const _Section(
            title: 'المحلات المتاحة',
            hint: 'ابحث عن ماركت، خضار، ألبان، منظفات...',
            one: 'محل واحد',
            two: 'محلان',
            many: 'محلات',
            noMatch: 'لم نعثر على محلات مطابقة',
            showAll: 'عرض جميع المحلات',
            pills: [
              _all,
              _Pill('خضروات وفواكه', Icons.eco_outlined, ['خضار', 'خضروات', 'فواكه', 'فاكهة']),
              _Pill('ألبان وأجبان', Icons.egg_outlined, ['ألبان', 'حليب', 'لبن', 'جبن', 'قيمر']),
              _Pill('مخبوزات', Icons.bakery_dining_outlined, ['خبز', 'صمون', 'معجنات']),
              _Pill('مشروبات', Icons.local_drink_outlined, ['مشروب', 'عصير', 'ماء', 'مياه']),
              _Pill('منظفات', Icons.cleaning_services_outlined, ['منظف', 'منظفات', 'صابون', 'مسحوق']),
            ],
          ),
        'home_cooking' => const _Section(
            title: 'المطابخ المتاحة',
            hint: 'ابحث عن أكلة بيتية، دولمة، كبة...',
            one: 'مطبخ واحد',
            two: 'مطبخان',
            many: 'مطابخ',
            noMatch: 'لم نعثر على مطابخ مطابقة',
            showAll: 'عرض جميع المطابخ',
            pills: [
              _all,
              _Pill('أكلات عراقية', Icons.rice_bowl_outlined, ['دولمة', 'كبة', 'برياني', 'تمن', 'مرق', 'قوزي']),
              _Pill('معجنات', Icons.bakery_dining_outlined, ['معجنات', 'فطائر', 'سمبوسة', 'بورك']),
              _Pill('حلويات بيتية', Icons.cake_outlined, ['حلويات', 'كليجة', 'كيك']),
              _Pill('مقبلات وسلطات', Icons.set_meal_outlined, ['سلطة', 'مقبلات', 'حمص', 'متبل']),
            ],
          ),
        'mobiles' => const _Section(
            title: 'المحلات المتاحة',
            hint: 'ابحث عن هاتف، شاحن، سماعة...',
            one: 'محل واحد',
            two: 'محلان',
            many: 'محلات',
            noMatch: 'لم نعثر على محلات مطابقة',
            showAll: 'عرض جميع المحلات',
            pills: [
              _all,
              _Pill('هواتف', Icons.smartphone_outlined, ['هاتف', 'موبايل', 'ايفون', 'آيفون', 'سامسونج', 'شاومي']),
              _Pill('إكسسوارات', Icons.phone_iphone_outlined, ['كفر', 'غطاء', 'حماية', 'اكسسوار', 'إكسسوار']),
              _Pill('سماعات', Icons.headphones_outlined, ['سماعة', 'سماعات', 'ايربودز']),
              _Pill('ساعات ذكية', Icons.watch_outlined, ['ساعة', 'ساعات']),
              _Pill('شواحن وكيبلات', Icons.cable_outlined, ['شاحن', 'كيبل', 'باور']),
            ],
          ),
        _ => _Section(
            title: 'المحلات المتاحة',
            hint: 'ابحث في ${c.name}...',
            one: 'محل واحد',
            two: 'محلان',
            many: 'محلات',
            noMatch: 'لم نعثر على محلات مطابقة',
            showAll: 'عرض جميع المحلات',
            pills: const [_all],
          ),
      };
}

enum _Quick { topRated, fastest, freeDelivery, offers }

extension on _Quick {
  String get label => switch (this) {
        _Quick.topRated => 'الأعلى تقييماً',
        _Quick.fastest => 'الأسرع توصيلاً',
        _Quick.freeDelivery => 'توصيل مجاني',
        _Quick.offers => 'عروض خاصة',
      };
}

int _eta(Merchant m) => m.etaMinutes(distanceTo(m) ?? 2);

class MerchantListScreen extends StatefulWidget {
  const MerchantListScreen({super.key, required this.category});
  final MerchantCategory category;
  @override
  State<MerchantListScreen> createState() => _MerchantListScreenState();
}

class _MerchantListScreenState extends State<MerchantListScreen> {
  late final _Section _sec = _Section.of(widget.category);
  late Future<List<Merchant>> _load = _fetch();
  final _q = TextEditingController();
  Timer? _debounce;
  int _pill = 0;
  _Quick? _quick;
  String _query = '';

  /// نتائج البحث بالخادم (تشمل المحلات التي تطابق منتجاتها) لكل كلمة
  final Map<String, Set<String>> _matchCache = {};
  Set<String>? _pillIds; // المحلات المطابقة للتصنيف المختار
  Set<String>? _queryIds; // المحلات المطابقة للبحث النصي (من المنتجات)
  Set<String>? _offerIds;
  bool _filtering = false;

  Future<List<Merchant>> _fetch() => catalogApi.merchants(categoryId: widget.category.id, areaId: app.selectedAreaId);

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<Set<String>> _idsFor(List<String> words) async {
    final out = <String>{};
    await Future.wait(words.map((w) async {
      final cached = _matchCache[w];
      if (cached != null) {
        out.addAll(cached);
        return;
      }
      try {
        final r = await catalogApi.search(w);
        final ids = {...r.merchants.map((m) => m.id), ...r.products.map((e) => e.$2.id)};
        _matchCache[w] = ids;
        out.addAll(ids);
      } catch (_) {
        // البحث بالخادم تحسين؛ المطابقة بالاسم والوصف تبقى شغالة
      }
    }));
    return out;
  }

  Future<void> _selectPill(int i) async {
    HapticFeedback.selectionClick();
    setState(() {
      _pill = i;
      _pillIds = null;
    });
    final p = _sec.pills[i];
    if (p.isAll) return;
    setState(() => _filtering = true);
    final ids = await _idsFor(p.keywords);
    if (!mounted || _pill != i) return;
    setState(() {
      _pillIds = ids;
      _filtering = false;
    });
  }

  Future<void> _toggleQuick(_Quick q) async {
    HapticFeedback.selectionClick();
    setState(() => _quick = _quick == q ? null : q);
    if (_quick == _Quick.offers && _offerIds == null) {
      setState(() => _filtering = true);
      try {
        final list = await catalogApi.offers(areaId: app.selectedAreaId, limit: 200);
        _offerIds = list.map((e) => e.$2.id).toSet();
      } catch (_) {
        _offerIds = {};
      }
      if (mounted) setState(() => _filtering = false);
    }
  }

  void _onSearch(String v) {
    setState(() => _query = v.trim());
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() => _queryIds = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final ids = await _idsFor([q]);
      if (mounted && _query == q) setState(() => _queryIds = ids);
    });
  }

  void _resetAll() {
    _q.clear();
    setState(() {
      _pill = 0;
      _quick = null;
      _query = '';
      _pillIds = null;
      _queryIds = null;
    });
  }

  bool _textHas(Merchant m, Iterable<String> words) {
    final t = '${m.name} ${m.description}';
    return words.any(t.contains);
  }

  List<Merchant> _apply(List<Merchant> all) {
    var list = [...all];
    final p = _sec.pills[_pill];
    if (!p.isAll) list = list.where((m) => _textHas(m, p.keywords) || (_pillIds?.contains(m.id) ?? false)).toList();
    if (_query.isNotEmpty) list = list.where((m) => _textHas(m, [_query]) || (_queryIds?.contains(m.id) ?? false)).toList();
    switch (_quick) {
      case _Quick.topRated:
        list.sort((a, b) => b.ratingAvg.compareTo(a.ratingAvg));
      case _Quick.fastest:
        list.sort((a, b) => _eta(a).compareTo(_eta(b)));
      case _Quick.freeDelivery:
        list = list.where((m) => m.deliveryFee == 0).toList();
      case _Quick.offers:
        list = list.where((m) => _offerIds?.contains(m.id) ?? false).toList();
      case null:
        break;
    }
    // المفتوح أولاً دائماً
    list.sort((a, b) => (b.isOpenNow ? 1 : 0) - (a.isOpenNow ? 1 : 0));
    return list;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _C.ivory,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              _Header(controller: _q, hint: _sec.hint, onSearch: _onSearch, onClear: () {
                _q.clear();
                _onSearch('');
              }),
              Expanded(
                child: FutureBuilder<List<Merchant>>(
                  future: _load,
                  builder: (context, s) {
                    if (s.hasError) return ErrorView(error: s.error!, onRetry: () => setState(() => _load = _fetch()));
                    final all = s.data;
                    final list = all == null ? null : _apply(all);
                    return RefreshIndicator(
                      color: _C.terracotta,
                      onRefresh: () async {
                        final f = _fetch();
                        setState(() => _load = f);
                        await f;
                      },
                      child: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
                        if (_sec.pills.length > 1) _pills(),
                        _quickFilters(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                          child: Row(children: [
                            Expanded(child: Text(_sec.title, style: _d(18))),
                            if (_filtering) const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _C.terracotta))),
                            if (list != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: _C.sand100, borderRadius: BorderRadius.circular(20)),
                                child: Text(_sec.count(list.length), style: _b(12, w: FontWeight.w500, c: _C.stone500)),
                              ),
                          ]),
                        ),
                        if (list == null)
                          for (var i = 0; i < 3; i++)
                            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: SkeletonBox(height: 270, radius: 24))
                        else if (list.isEmpty)
                          _empty(all!.isEmpty)
                        else
                          for (final m in list)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: _MerchantCard(m: m, hasOffer: _offerIds?.contains(m.id) ?? false, onTap: () => _openPreview(m)),
                            ),
                      ]),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _pills() => SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          itemCount: _sec.pills.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final p = _sec.pills[i];
            final on = i == _pill;
            return Semantics(
              button: true,
              selected: on,
              label: p.label,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => _selectPill(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: on ? _C.terracotta : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: on ? _C.terracotta : _C.sand200),
                    boxShadow: on ? const [BoxShadow(color: Color(0x33D95D39), blurRadius: 6, offset: Offset(0, 2))] : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(p.icon, size: 16, color: on ? Colors.white : _C.terracotta),
                    const SizedBox(width: 8),
                    Text(p.label, style: _b(12, w: FontWeight.w600, c: on ? Colors.white : _C.charcoal)),
                  ]),
                ),
              ),
            );
          },
        ),
      );

  Widget _quickFilters() => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x99E8E3D8)))),
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _Quick.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final q = _Quick.values[i];
            final on = q == _quick;
            return Semantics(
              button: true,
              selected: on,
              label: q.label,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => _toggleQuick(q),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: on ? _C.charcoal : _C.sand100, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (on) ...[
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: _C.terracotta, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Text(q.label, style: _b(11.5, w: FontWeight.w500, c: on ? Colors.white : _C.stone600)),
                  ]),
                ),
              ),
            );
          },
        ),
      );

  Widget _empty(bool sectionEmpty) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: _C.sand100, borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.search_rounded, size: 32, color: _C.stone400),
          ),
          const SizedBox(height: 12),
          Text(sectionEmpty ? 'ما اكو محلات بهذا القسم بعد' : _sec.noMatch, style: _d(16), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            sectionEmpty ? 'راح تظهر هنا أول ما تعتمدها إدارة واصل.' : 'جرّب البحث بكلمة مختلفة أو إعادة ضبط الفلاتر المختارة',
            style: _b(12, c: _C.stone500),
            textAlign: TextAlign.center,
          ),
          if (!sectionEmpty) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _resetAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                decoration: BoxDecoration(color: _C.terracotta, borderRadius: BorderRadius.circular(12)),
                child: Text(_sec.showAll, style: _b(12, w: FontWeight.w600, c: Colors.white)),
              ),
            ),
          ],
        ]),
      );

  void _openPreview(Merchant m) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0x801C1917),
        builder: (_) => _PreviewSheet(m: m),
      );
}

// ---------------------------------------------------------------------
// الرأس الثابت: التوصيل إلى + السلة + البحث الفوري
// ---------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.hint, required this.onSearch, required this.onClear});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Color(0xF2FAF8F5), border: Border(bottom: BorderSide(color: Color(0xCCE8E3D8)))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(children: [
          Row(children: [
            // رجوع
            Semantics(
              button: true,
              label: 'رجوع',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: const SizedBox(width: 30, height: 40, child: Icon(Icons.arrow_forward_rounded, color: _C.charcoal, size: 22)),
              ),
            ),
            const SizedBox(width: 4),
            // التوصيل إلى
            Expanded(
              child: ListenableBuilder(
                listenable: app,
                builder: (context, _) {
                  final label = app.selectedAddress?.label ?? (app.selectedArea != null ? '${app.selectedArea!.city} - ${app.selectedArea!.name}' : 'اختار عنوانك');
                  return Semantics(
                    button: true,
                    label: 'التوصيل إلى $label',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => pickAddressSheet(context, onAddNew: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressFormScreen()))),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: _C.terracottaLight, borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.location_on_outlined, color: _C.terracotta, size: 21),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text('التوصيل إلى', style: _b(11, w: FontWeight.w500, c: _C.stone500, h: 1.2)),
                            Row(children: [
                              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _d(15, h: 1.3))),
                              const SizedBox(width: 2),
                              const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _C.terracotta),
                            ]),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            // السلة
            ListenableBuilder(
              listenable: app,
              builder: (context, _) => Semantics(
                button: true,
                label: 'سلة التسوق، ${app.cartCount} قطعة',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned.fill(
                        top: 2,
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.sand200), boxShadow: _C.card),
                          child: const Icon(Icons.shopping_bag_outlined, size: 21, color: _C.charcoal),
                        ),
                      ),
                      PositionedDirectional(
                        end: -5,
                        top: -3,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: _C.terracotta, borderRadius: BorderRadius.circular(10)),
                          child: Text('${app.cartCount}', style: _b(11, w: FontWeight.w700, c: Colors.white, h: 1)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          // البحث الفوري
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, v, _) => TextField(
              controller: controller,
              onChanged: onSearch,
              textInputAction: TextInputAction.search,
              style: _b(14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                hintText: hint,
                hintStyle: _b(13.5, c: _C.stone400),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: _C.stone400),
                suffixIcon: v.text.isEmpty
                    ? null
                    : IconButton(tooltip: 'مسح', onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18, color: _C.stone400)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _C.sand200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _C.sand200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _C.terracotta, width: 1.5)),
              ),
            ),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------
// بطاقة المحل
// ---------------------------------------------------------------------
class _MerchantCard extends StatelessWidget {
  const _MerchantCard({required this.m, required this.hasOffer, required this.onTap});
  final Merchant m;
  final bool hasOffer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eta = _eta(m);
    final free = m.deliveryFee == 0;
    final cover = (m.coverUrl ?? '').isNotEmpty ? m.coverUrl : m.logoUrl;
    // الشارة: مغلق الآن أهم معلومة، ثم التوصيل المجاني، ثم العروض
    final (String, Color)? badge = !m.isOpenNow
        ? ('مغلق الآن', _C.charcoal)
        : free
            ? ('توصيل مجاني', _C.olive)
            : hasOffer
                ? ('عروض خاصة', _C.terracotta)
                : null;
    return Semantics(
      button: true,
      label: '${m.name}، التوصيل ${free ? 'مجاني' : iqd(m.deliveryFee)}، حوالي $eta دقيقة',
      child: Pressable(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xCCE8E3D8)), boxShadow: _C.card),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 176,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(
                  color: _C.sand100,
                  child: cover == null
                      ? const Center(child: Icon(Icons.storefront_outlined, size: 44, color: _C.stone400))
                      : WImage(cover, radius: 0, fallbackIcon: Icons.storefront_outlined, fallbackColor: _C.sand100),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0x4D000000), Color(0x00000000), Color(0x26000000)], stops: [0, 0.55, 1]),
                  ),
                ),
                if (badge != null)
                  PositionedDirectional(
                    start: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: badge.$2, borderRadius: BorderRadius.circular(12)),
                      child: Text(badge.$1, style: _b(11, w: FontWeight.w700, c: Colors.white)),
                    ),
                  ),
                PositionedDirectional(end: 12, top: 12, child: _FavButton(merchantId: m.id)),
                PositionedDirectional(
                  end: 12,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xF2FFFFFF), borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.schedule_rounded, size: 14, color: _C.terracotta),
                      const SizedBox(width: 4),
                      Text('$eta-${eta + 10} دقيقة', style: _b(11, w: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(m.name, style: _d(16, h: 1.35), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  _RatingPill(m: m),
                ]),
                const SizedBox(height: 2),
                Text(m.description.isNotEmpty ? m.description : m.addressText, maxLines: 1, overflow: TextOverflow.ellipsis, style: _b(12, c: _C.stone500)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: _C.sand100))),
                  child: Row(children: [
                    Icon(Icons.local_shipping_outlined, size: 17, color: free ? _C.olive : _C.stone400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('التوصيل: ${free ? 'مجاناً' : iqd(m.deliveryFee)}',
                          style: _b(12, w: free ? FontWeight.w700 : FontWeight.w500, c: free ? _C.olive : _C.stone600)),
                    ),
                    Text('عرض القائمة', style: _b(11.5, w: FontWeight.w600, c: _C.terracotta)),
                    const Directionality(textDirection: TextDirection.ltr, child: Icon(Icons.chevron_left_rounded, size: 18, color: _C.terracotta)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.m});
  final Merchant m;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: _C.oliveLight, borderRadius: BorderRadius.circular(8)),
        child: m.ratingCount == 0
            ? Text('جديد', style: _b(11.5, w: FontWeight.w700, c: _C.olive))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded, size: 15, color: _C.olive),
                const SizedBox(width: 3),
                Text(m.ratingAvg.toStringAsFixed(1), style: _b(12, w: FontWeight.w700, c: _C.olive)),
                const SizedBox(width: 3),
                Text('(${m.ratingCount})', style: _b(10, c: _C.olive.withValues(alpha: 0.8))),
              ]),
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
            label: fav ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () async {
                HapticFeedback.selectionClick();
                try {
                  await app.toggleFavorite(merchantId);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: Color(0xE6FFFFFF), shape: BoxShape.circle, boxShadow: _C.card),
                child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 18, color: fav ? _C.terracotta : _C.charcoal),
              ),
            ),
          );
        },
      );
}

// ---------------------------------------------------------------------
// درج المعاينة السريعة: معلومات المحل + جزء من قائمته الحقيقية + الإضافة للسلة
// ---------------------------------------------------------------------
class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet({required this.m});
  final Merchant m;
  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  late final Future<List<Product>> _products = catalogApi.products(widget.m.id, onlyAvailable: true);

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final eta = _eta(m);
    final free = m.deliveryFee == 0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      child: Container(
        decoration: const BoxDecoration(color: _C.ivory, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            alignment: Alignment.center,
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _C.sand300, borderRadius: BorderRadius.circular(2))),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                      Text(m.name, style: _d(18)),
                      _RatingPill(m: m),
                    ]),
                    const SizedBox(height: 2),
                    Text(m.description.isNotEmpty ? m.description : m.addressText, maxLines: 2, overflow: TextOverflow.ellipsis, style: _b(12, c: _C.stone500)),
                  ]),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'إغلاق',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(color: _C.sand100, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, size: 17, color: _C.stone600),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _C.sand100))),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded, size: 15, color: _C.terracotta),
                  const SizedBox(width: 4),
                  Text('$eta-${eta + 10} دقيقة', style: _b(12, c: _C.stone600)),
                  const SizedBox(width: 16),
                  const Icon(Icons.check_rounded, size: 15, color: _C.olive),
                  const SizedBox(width: 4),
                  Text('التوصيل: ${free ? 'مجاناً' : iqd(m.deliveryFee)}', style: _b(12, c: _C.stone600)),
                  if (!m.isOpenNow) ...[
                    const SizedBox(width: 16),
                    Text('مغلق الآن', style: _b(12, w: FontWeight.w700, c: _C.terracotta)),
                  ],
                ]),
              ),
            ]),
          ),
          const Divider(height: 1, color: _C.sand200),
          Flexible(
            child: FutureBuilder<List<Product>>(
              future: _products,
              builder: (context, s) {
                if (s.hasError) return Padding(padding: const EdgeInsets.all(24), child: ErrorView(error: s.error!));
                if (!s.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: _C.terracotta)));
                final items = s.data!;
                if (items.isEmpty) {
                  return Padding(padding: const EdgeInsets.all(28), child: Text('ما اكو منتجات متوفرة بهذا المحل حالياً.', style: _b(13, c: _C.stone500), textAlign: TextAlign.center));
                }
                return ListenableBuilder(
                  listenable: app,
                  builder: (context, _) => ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (i == 0) return Text('من القائمة', style: _b(12, w: FontWeight.w700, c: _C.stone500));
                      return _MenuItem(m: m, p: items[i - 1]);
                    },
                  ),
                );
              },
            ),
          ),
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
            child: Row(children: [
              Expanded(
                child: _SheetButton(label: 'متابعة التصفح', dark: true, onTap: () => Navigator.pop(context)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetButton(
                  label: 'القائمة الكاملة',
                  dark: false,
                  onTap: () {
                    Navigator.pop(context);
                    openMerchant(context, m);
                  },
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.label, required this.dark, required this.onTap});
  final String label;
  final bool dark;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: dark ? _C.charcoal : _C.terracotta, borderRadius: BorderRadius.circular(16)),
            child: Text(label, style: _d(14, c: Colors.white)),
          ),
        ),
      );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.m, required this.p});
  final Merchant m;
  final Product p;

  @override
  Widget build(BuildContext context) {
    final qty = app.qtyOf(p.id);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xCCE8E3D8)), boxShadow: _C.card),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 80,
            height: 80,
            child: p.images.isEmpty
                ? const ColoredBox(color: _C.sand100, child: Icon(Icons.restaurant_menu_rounded, color: _C.stone400))
                : WImage(p.images.first, radius: 0, fallbackColor: _C.sand100),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _d(14)),
            if (p.description.isNotEmpty) Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: _b(11, c: _C.stone500, h: 1.5)),
            const SizedBox(height: 8),
            Row(children: [
              Text(iqd(p.price), style: _b(12, w: FontWeight.w700, c: _C.terracotta)),
              if (p.isOnOffer) ...[
                const SizedBox(width: 6),
                Text(iqd(p.compareAtPrice!), style: _b(10.5, c: _C.stone400).copyWith(decoration: TextDecoration.lineThrough, decorationColor: _C.stone400)),
              ],
              const Spacer(),
              if (qty == 0)
                Semantics(
                  button: true,
                  label: 'أضف ${p.name}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => addToCart(context, m, p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: _C.terracottaLight, borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.add_rounded, size: 15, color: _C.terracotta),
                        const SizedBox(width: 4),
                        Text('أضف', style: _b(12, w: FontWeight.w700, c: _C.terracotta)),
                      ]),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(color: _C.sand100, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _QtyBtn(icon: Icons.remove_rounded, filled: false, label: 'إنقاص', onTap: () => app.remove(p)),
                    SizedBox(width: 26, child: Text('$qty', textAlign: TextAlign.center, style: _b(12, w: FontWeight.w700))),
                    _QtyBtn(icon: Icons.add_rounded, filled: true, label: 'زيادة', onTap: () => addToCart(context, m, p)),
                  ]),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.filled, required this.label, required this.onTap});
  final IconData icon;
  final bool filled;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: filled ? _C.terracotta : Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: _C.card),
            child: Icon(icon, size: 15, color: filled ? Colors.white : _C.charcoal),
          ),
        ),
      );
}
