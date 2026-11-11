import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../widgets.dart';

/// صفحة المحل: غلاف، شعار، معلومات، أقسام داخلية، بحث، منتجات.
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
  String? _section; // null = الكل

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
              const SliverToBoxAdapter(child: SizedBox(height: 320, child: SkeletonList(count: 3, itemHeight: 96)))
            else
              ..._products(s.data!.$1, s.data!.$2),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        ),
      );

  Widget _hero() => SliverAppBar(
        expandedHeight: 210,
        pinned: true,
        backgroundColor: WColors.ivory,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: WIconButton(Icons.arrow_back_rounded, onPressed: () => Navigator.pop(context), size: 40),
        ),
        actions: [
          ListenableBuilder(
            listenable: app,
            builder: (context, _) {
              final fav = app.favorites.contains(m.id);
              return Padding(
                padding: const EdgeInsets.all(8),
                child: WIconButton(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: fav ? WColors.coral : WColors.ink, size: 40, onPressed: () => runAction(context, () => app.toggleFavorite(m.id))),
              );
            },
          ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          background: Stack(fit: StackFit.expand, children: [
            WImage(m.coverUrl, radius: 0, height: 260, fallbackIcon: categoryIcon(m.categoryId), fallbackColor: categoryTint(m.categoryId).withValues(alpha: 0.14)),
            const DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55172E3B), Colors.transparent])),
            ),
          ]),
        ),
      );

  Widget _info() => Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.page, 16, WSpace.page, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MerchantLogo(name: m.name, url: m.logoUrl, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: WText.h1),
                if (m.description.isNotEmpty) Text(m.description, style: WText.small),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            m.isOpenNow ? const StatusPill('مفتوح', tone: PillTone.success, icon: Icons.circle) : const StatusPill('مسكّر هسه', tone: PillTone.danger),
            if (m.ratingCount > 0) StatusPill('${m.ratingAvg.toStringAsFixed(1)} (${m.ratingCount})', icon: Icons.star_rounded, tone: PillTone.accent),
            StatusPill('${m.etaMinutes(distanceTo(m) ?? 2)} دقيقة', icon: Icons.schedule_rounded),
            StatusPill(m.deliveryFee == 0 ? 'توصيل مجاني' : 'توصيل ${iqd(m.deliveryFee)}', icon: Icons.delivery_dining_rounded),
            if (m.minOrder > 0) StatusPill('أقل طلب ${iqd(m.minOrder)}'),
          ]),
          const SizedBox(height: 10),
          InkWell(
            onTap: _showInfo,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: WColors.inkMuted),
                const SizedBox(width: 6),
                Text('معلومات المحل وأوقات العمل', style: WText.small.copyWith(color: WColors.ink)),
                const Icon(Icons.chevron_left_rounded, color: WColors.inkMuted),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(hintText: 'ابحث داخل المحل', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
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
              SizedBox(height: 150, child: ClipRRect(borderRadius: WRadius.all(WRadius.md), child: WMap(markers: [WMarker(LatLng(m.lat, m.lng), kind: WMarkerKind.store)], zoom: 15, interactive: false))),
              const SizedBox(height: 14),
              Text('أوقات العمل', style: WText.h3),
              const SizedBox(height: 6),
              if (m.workingHours.isEmpty) Text('مفتوح طول اليوم', style: WText.small),
              for (var d = 0; d < 7; d++)
                if (m.workingHours['$d'] != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 90, child: Text(weekdaysAr[d], style: WText.body)),
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

    return [
      if (usedCats.length > 1 || (usedCats.isNotEmpty && hasUncategorized))
        SliverPersistentHeader(
          pinned: true,
          delegate: _ChipsHeader(
            ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: WSpace.page, vertical: 8), children: [
              Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: const Text('الكل'), selected: _section == null, onSelected: (_) => setState(() => _section = null))),
              for (final c in usedCats)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(label: Text(c.name), selected: _section == c.id, onSelected: (_) => setState(() => _section = c.id)),
                ),
              if (hasUncategorized) ChoiceChip(label: const Text('أخرى'), selected: _section == '_', onSelected: (_) => setState(() => _section = '_')),
            ]),
          ),
        ),
      if (list.isEmpty) SliverToBoxAdapter(child: EmptyView(icon: Icons.search_off_rounded, title: 'ما لگينا "$q"')),
      for (final g in groups) ...[
        SliverToBoxAdapter(child: SectionTitle(g.$1, padding: const EdgeInsets.fromLTRB(WSpace.page, 18, WSpace.page, 6))),
        SliverList.separated(
          itemCount: g.$2.length,
          separatorBuilder: (_, __) => const Divider(indent: WSpace.page, endIndent: WSpace.page),
          itemBuilder: (context, i) => _ProductTile(merchant: m, product: g.$2[i]),
        ),
      ],
    ];
  }
}

class _ChipsHeader extends SliverPersistentHeaderDelegate {
  _ChipsHeader(this.child);
  final Widget child;
  @override
  double get minExtent => 54;
  @override
  double get maxExtent => 54;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: WColors.ivory, child: child);
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WSpace.page, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: WText.bodyStrong),
              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(p.description, style: WText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Text(iqd(p.price), style: WText.price),
                if (!available) ...[const SizedBox(width: 8), const StatusPill('غير متوفر')],
                if (available && p.stock != null && p.stock! <= 5) ...[const SizedBox(width: 8), StatusPill('باقي ${p.stock}', tone: PillTone.warning)],
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 104,
            child: Column(children: [
              WImage(p.imageUrl, width: 104, height: 92, radius: WRadius.md, fallbackIcon: categoryIcon(merchant.categoryId)),
              const SizedBox(height: 8),
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
          ),
        ]),
      ),
    );
  }
}
