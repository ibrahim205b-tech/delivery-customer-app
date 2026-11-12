import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../widgets.dart';

/// صفحة المحل: غلاف، بطاقة معلومات، أقسام داخلية، بحث، منتجات، وتفاصيل المنتج.
class MerchantPage extends StatefulWidget {
  const MerchantPage({super.key, required this.merchant});
  final Merchant merchant;
  @override
  State<MerchantPage> createState() => _MerchantPageState();
}

class _MerchantPageState extends State<MerchantPage> {
  late Merchant m = widget.merchant;
  late Future<(List<ProductCategory>, List<Product>)> _data = _load();
  String _query = '';
  String? _section;

  Future<(List<ProductCategory>, List<Product>)> _load() async {
    final r = await Future.wait([catalogApi.productCategories(m.id), catalogApi.products(m.id), catalogApi.merchant(m.id)]);
    final fresh = r[2] as Merchant?;
    if (fresh != null && mounted) setState(() => m = fresh);
    return (r[0] as List<ProductCategory>, r[1] as List<Product>);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        bottomNavigationBar: const CartBar(),
        body: FutureBuilder(
          future: _data,
          builder: (context, s) => CustomScrollView(slivers: [
            _hero(),
            SliverToBoxAdapter(child: _info()),
            if (s.hasError)
              SliverFillRemaining(hasScrollBody: false, child: ErrorView(error: s.error!, onRetry: () => setState(() => _data = _load())))
            else if (!s.hasData)
              const SliverToBoxAdapter(child: SizedBox(height: 320, child: SkeletonList(count: 3, itemHeight: 104)))
            else
              ..._products(s.data!.$1, s.data!.$2),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ]),
        ),
      );

  Widget _hero() => SliverAppBar(
        expandedHeight: 200,
        pinned: true,
        backgroundColor: WColors.ink,
        foregroundColor: WColors.white,
        automaticallyImplyLeading: false,
        title: LayoutBuilder(builder: (context, c) => Text(m.name, style: WText.h3.copyWith(color: WColors.white))),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: WIconButton(Icons.arrow_forward_rounded, tooltip: 'رجوع', onPressed: () => Navigator.pop(context), size: 40, background: WColors.white),
        ),
        actions: [
          ListenableBuilder(
            listenable: app,
            builder: (context, _) {
              final fav = app.favorites.contains(m.id);
              return Padding(
                padding: const EdgeInsets.all(8),
                child: WIconButton(
                  fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  tooltip: fav ? 'شيل من المفضلة' : 'أضف للمفضلة',
                  background: fav ? WColors.lime : WColors.white,
                  size: 40,
                  onPressed: () => runAction(context, () => app.toggleFavorite(m.id)),
                ),
              );
            },
          ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          collapseMode: CollapseMode.parallax,
          background: Stack(fit: StackFit.expand, children: [
            if (m.coverUrl != null)
              WImage(m.coverUrl, radius: 0, height: 260)
            else
              Container(
                color: WColors.ink,
                child: Align(
                  alignment: AlignmentDirectional.bottomStart,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Opacity(opacity: 0.12, child: Icon(categoryIcon(m.categoryId), size: 150, color: WColors.lime)),
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66111923), Colors.transparent, Color(0x33111923)])),
            ),
          ]),
        ),
      );

  Widget _info() => Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.page, 18, WSpace.page, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MerchantLogo(name: m.name, url: m.logoUrl, size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: WText.h1),
                if (m.description.isNotEmpty) Text(m.description, style: WText.small),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          // شريط مقاييس: 3 أعمدة بأرقام واضحة
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: WColors.white, borderRadius: WRadius.all(WRadius.lg), border: Border.all(color: WColors.line)),
            child: IntrinsicHeight(
              child: Row(children: [
                _metric(m.ratingCount > 0 ? m.ratingAvg.toStringAsFixed(1) : '—', m.ratingCount > 0 ? '${m.ratingCount} تقييم' : 'بدون تقييم', Icons.star_rounded),
                const VerticalDivider(width: 1),
                _metric('${m.etaMinutes(distanceTo(m) ?? 2)}', 'دقيقة توصيل', Icons.schedule_rounded),
                const VerticalDivider(width: 1),
                _metric(m.deliveryFee == 0 ? 'مجاني' : iqd(m.deliveryFee).replaceAll(' د.ع', ''), m.deliveryFee == 0 ? 'التوصيل' : 'د.ع توصيل', Icons.delivery_dining_rounded),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            m.isOpenNow ? const StatusPill('مفتوح هسه', tone: PillTone.dark) : const StatusPill('مسكّر هسه', tone: PillTone.danger),
            if (m.minOrder > 0) ...[const SizedBox(width: 8), StatusPill('أقل طلب ${iqd(m.minOrder)}')],
            const Spacer(),
            TextButton.icon(onPressed: _showInfo, icon: const Icon(Icons.info_outline_rounded, size: 18), label: const Text('المعلومات')),
          ]),
          const SizedBox(height: 4),
          TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(hintText: 'ابحث داخل المحل', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ]),
      );

  Widget _metric(String value, String label, IconData icon) => Expanded(
        child: Column(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: WColors.ink),
            const SizedBox(width: 4),
            Text(value, style: WText.number.copyWith(fontSize: 16)),
          ]),
          Text(label, style: WText.caption),
        ]),
      );

  void _showInfo() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(m.name, style: WText.h2),
              const SizedBox(height: 12),
              if (m.addressText.isNotEmpty) InfoRow(icon: Icons.place_outlined, text: m.addressText),
              if (m.phone.isNotEmpty) ...[const SizedBox(height: 6), InfoRow(icon: Icons.phone_outlined, text: m.phone)],
              const SizedBox(height: 14),
              SizedBox(
                height: 160,
                child: ClipRRect(
                  borderRadius: WRadius.all(WRadius.lg),
                  child: WMap(markers: [WMarker(LatLng(m.lat, m.lng), kind: WMarkerKind.store, icon: categoryIcon(m.categoryId))], zoom: 15.5, interactive: false),
                ),
              ),
              const SizedBox(height: 8),
              WButton('افتح الموقع بالخرائط', kind: WButtonKind.secondary, compact: true, icon: Icons.navigation_outlined, onPressed: () => openInMaps(m.lat, m.lng, label: m.name)),
              const SizedBox(height: 14),
              Text('أوقات العمل', style: WText.h3),
              const SizedBox(height: 6),
              if (m.workingHours.isEmpty) Text('مفتوح طول اليوم', style: WText.small),
              for (var d = 0; d < 7; d++)
                if (m.workingHours['$d'] != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 90, child: Text(weekdaysAr[d], style: (DateTime.now().weekday % 7 == d) ? WText.bodyStrong : WText.body)),
                      Text(m.workingHours['$d']!.closed ? 'مسكّر' : '${m.workingHours['$d']!.open} - ${m.workingHours['$d']!.close}',
                          style: WText.body.copyWith(color: WColors.inkMuted), textDirection: TextDirection.ltr),
                    ]),
                  ),
            ]),
          ),
        ),
      );

  List<Widget> _products(List<ProductCategory> cats, List<Product> products) {
    if (products.isEmpty) {
      return const [SliverToBoxAdapter(child: EmptyView(icon: Icons.inventory_2_outlined, title: 'ما اكو منتجات بعد', message: 'المحل لسه ما ضاف منتجاته.'))];
    }
    final q = _query;
    var list = products.where((p) => q.isEmpty || p.name.contains(q) || p.description.contains(q)).toList();
    final usedCats = cats.where((c) => products.any((p) => p.categoryId == c.id)).toList();
    final hasUncategorized = products.any((p) => p.categoryId == null || !cats.any((c) => c.id == p.categoryId));
    if (_section != null) list = list.where((p) => _section == '_' ? !usedCats.any((c) => c.id == p.categoryId) : p.categoryId == _section).toList();

    final groups = <(String, List<Product>)>[
      for (final c in usedCats)
        if (list.any((p) => p.categoryId == c.id)) (c.name, list.where((p) => p.categoryId == c.id).toList()),
      if (list.any((p) => !usedCats.any((c) => c.id == p.categoryId)))
        (usedCats.isEmpty ? 'القائمة' : 'أخرى', list.where((p) => !usedCats.any((c) => c.id == p.categoryId)).toList()),
    ];

    Widget chip(String label, bool sel, VoidCallback f) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ChoiceChip(label: Text(label), selected: sel, onSelected: (_) => f(), labelStyle: WText.label.copyWith(color: sel ? WColors.white : WColors.ink)),
        );

    return [
      if (usedCats.length > 1 || (usedCats.isNotEmpty && hasUncategorized))
        SliverPersistentHeader(
          pinned: true,
          delegate: _ChipsHeader(
            ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: WSpace.page, vertical: 9), children: [
              chip('الكل', _section == null, () => setState(() => _section = null)),
              for (final c in usedCats) chip(c.name, _section == c.id, () => setState(() => _section = c.id)),
              if (hasUncategorized) chip('أخرى', _section == '_', () => setState(() => _section = '_')),
            ]),
          ),
        ),
      if (list.isEmpty) SliverToBoxAdapter(child: EmptyView(icon: Icons.search_off_rounded, title: 'ما لگينا "$q"')),
      for (final g in groups) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.page, 22, WSpace.page, 10),
            child: Row(children: [
              Text(g.$1, style: WText.h2),
              const SizedBox(width: 8),
              Text('${g.$2.length}', style: WText.caption),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
          sliver: SliverList.separated(
            itemCount: g.$2.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ProductTile(merchant: m, product: g.$2[i]),
          ),
        ),
      ],
    ];
  }
}

class _ChipsHeader extends SliverPersistentHeaderDelegate {
  _ChipsHeader(this.child);
  final Widget child;
  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(decoration: BoxDecoration(color: WColors.paper, border: overlapsContent ? const Border(bottom: BorderSide(color: WColors.line)) : null), child: child);
  @override
  bool shouldRebuild(covariant _ChipsHeader old) => true;
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.merchant, required this.product});
  final Merchant merchant;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final available = p.isAvailable && (p.stock == null || p.stock! > 0);
    return Opacity(
      opacity: available ? 1 : 0.5,
      child: WCard(
        padding: const EdgeInsets.all(10),
        onTap: () => showProductSheet(context, merchant, p),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          WImage(p.imageUrl, width: 92, height: 92, radius: WRadius.md, fallbackIcon: categoryIcon(merchant.categoryId)),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 92,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: WText.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (p.description.isNotEmpty) Text(p.description, style: WText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
                const Spacer(),
                Row(children: [
                  Text(iqd(p.price), style: WText.price),
                  if (!available) ...[const SizedBox(width: 8), const StatusPill('غير متوفر')],
                  if (available && p.stock != null && p.stock! <= 5) ...[const SizedBox(width: 8), StatusPill('باقي ${p.stock}', tone: PillTone.warning)],
                  const Spacer(),
                  if (available)
                    ListenableBuilder(
                      listenable: app,
                      builder: (context, _) => QtyStepper(
                        qty: app.cartMerchant?.id == merchant.id ? app.qtyOf(p.id) : 0,
                        onAdd: () => addToCart(context, merchant, p),
                        onRemove: () => app.remove(p),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// تفاصيل المنتج: صورة كبيرة، الوصف، الكمية، ملاحظة، والإضافة
Future<void> showProductSheet(BuildContext context, Merchant m, Product p) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (c) => _ProductSheet(merchant: m, product: p),
    );

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.merchant, required this.product});
  final Merchant merchant;
  final Product product;
  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  int _qty = 1;
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final available = p.isAvailable && (p.stock == null || p.stock! > 0);
    final maxQty = p.stock ?? 99;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(WRadius.xl)),
                child: AspectRatio(aspectRatio: 16 / 10, child: WImage(p.imageUrl, radius: 0, fallbackIcon: categoryIcon(widget.merchant.categoryId))),
              ),
              PositionedDirectional(top: 12, end: 12, child: WIconButton(Icons.close_rounded, tooltip: 'إغلاق', onPressed: () => Navigator.pop(context), size: 40)),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(p.name, style: WText.h1),
                const SizedBox(height: 4),
                Text(iqd(p.price), style: WText.price.copyWith(fontSize: 20, color: WColors.blue)),
                if (p.description.isNotEmpty) ...[const SizedBox(height: 10), Text(p.description, style: WText.body.copyWith(color: WColors.graphite))],
                const SizedBox(height: 16),
                TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', hintText: 'مثلاً: حار، بدون بصل')),
                const SizedBox(height: 16),
                if (available)
                  Row(children: [
                    Container(
                      height: 54,
                      decoration: BoxDecoration(color: WColors.white, borderRadius: WRadius.all(WRadius.md), border: Border.all(color: WColors.line)),
                      child: Row(children: [
                        IconButton(tooltip: 'نقّص', onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove_rounded)),
                        SizedBox(width: 28, child: Text('$_qty', textAlign: TextAlign.center, style: WText.number.copyWith(fontSize: 18))),
                        IconButton(tooltip: 'زيد', onPressed: _qty < maxQty ? () => setState(() => _qty++) : null, icon: const Icon(Icons.add_rounded)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WButton(
                        'أضف',
                        trailing: Text(iqd(p.price * _qty), style: WText.price.copyWith(color: WColors.ink)),
                        onPressed: () async {
                          for (var i = 0; i < _qty; i++) {
                            await addToCart(context, widget.merchant, p);
                            if (app.cartMerchant?.id != widget.merchant.id) return; // المستخدم رفض تفريغ السلة
                          }
                          if (_note.text.trim().isNotEmpty) app.setLineNote(p, _note.text.trim());
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                  ])
                else
                  const StatusPill('هذا المنتج غير متوفر هسه', tone: PillTone.warning),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
