import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import 'main.dart';
import 'screens/cart.dart';

double? distanceTo(Merchant m) {
  final p = app.referencePoint;
  if (p == null) return null;
  return distanceKm(p.latitude, p.longitude, m.lat, m.lng);
}

/// سطر معلومات المحل: تقييم · وقت · توصيل · مسافة (سطر واحد دائماً)
class MerchantMeta extends StatelessWidget {
  const MerchantMeta(this.m, {super.key, this.light = false, this.showDistance = true});
  final Merchant m;
  final bool light;
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final d = distanceTo(m);
    final color = light ? WColors.white.withValues(alpha: 0.75) : WColors.inkMuted;
    final style = WText.caption.copyWith(color: color);
    Widget sep() => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Container(width: 3, height: 3, decoration: BoxDecoration(color: color, shape: BoxShape.circle)));
    return Row(children: [
      if (m.ratingCount > 0) ...[
        Icon(Icons.star_rounded, size: 14, color: light ? WColors.lime : WColors.ink),
        const SizedBox(width: 2),
        Text(m.ratingAvg.toStringAsFixed(1), style: style.copyWith(color: light ? WColors.white : WColors.ink, fontWeight: FontWeight.w600)),
        sep(),
      ],
      Text('${m.etaMinutes(d ?? 2)} د', style: style),
      sep(),
      Flexible(child: Text(m.deliveryFee == 0 ? 'توصيل مجاني' : iqd(m.deliveryFee), style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
      if (showDistance && d != null) ...[sep(), Text(kmAr(d), style: style)],
    ]);
  }
}

/// بطاقة محل عريضة بغلاف (للقوائم الأفقية "قريب منك")
class MerchantCard extends StatelessWidget {
  const MerchantCard(this.m, {super.key, required this.onTap, this.width = 248});
  final Merchant m;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: _Pressable(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              WImage(m.coverUrl, height: 132, width: width, radius: WRadius.lg, fallbackIcon: categoryIcon(m.categoryId), fallbackColor: WColors.surfaceAlt),
              PositionedDirectional(
                top: 10,
                start: 10,
                child: m.isOpenNow ? const StatusPill('مفتوح', tone: PillTone.dark) : const StatusPill('مسكّر', tone: PillTone.neutral),
              ),
              if (!m.isOpenNow)
                Positioned.fill(
                  child: DecoratedBox(decoration: BoxDecoration(color: WColors.paper.withValues(alpha: 0.45), borderRadius: WRadius.all(WRadius.lg))),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              MerchantLogo(name: m.name, url: m.logoUrl, size: 30),
              const SizedBox(width: 8),
              Expanded(child: Text(m.name, style: WText.h3, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 4),
            MerchantMeta(m),
          ]),
        ),
      );
}

/// صف محل مضغوط. [rank] يعرض رقم الترتيب (لقائمة الأكثر طلباً)
class MerchantRow extends StatelessWidget {
  const MerchantRow(this.m, {super.key, required this.onTap, this.rank});
  final Merchant m;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) => _Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WSpace.page, vertical: 10),
          child: Row(children: [
            if (rank != null)
              SizedBox(
                width: 34,
                child: Text('$rank', style: WText.number.copyWith(fontSize: 26, color: rank! <= 3 ? WColors.ink : WColors.inkFaint, height: 1)),
              ),
            MerchantLogo(name: m.name, url: m.logoUrl, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(m.name, style: WText.h3, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (!m.isOpenNow) const StatusPill('مسكّر'),
                ]),
                if (m.description.isNotEmpty) Text(m.description, style: WText.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                MerchantMeta(m),
              ]),
            ),
            ListenableBuilder(
              listenable: app,
              builder: (context, _) {
                final fav = app.favorites.contains(m.id);
                return IconButton(
                  tooltip: fav ? 'شيل من المفضلة' : 'أضف للمفضلة',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    runAction(context, () => app.toggleFavorite(m.id));
                  },
                  icon: AnimatedSwitcher(
                    duration: WDurations.base,
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, key: ValueKey(fav), color: fav ? WColors.ink : WColors.inkFaint),
                  ),
                );
              },
            ),
          ]),
        ),
      );
}

/// ضغط مع تصغير خفيف (بدل الموجة الافتراضية)
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onTap();
        },
        child: AnimatedScale(scale: _down ? 0.98 : 1, duration: WDurations.fast, child: widget.child),
      );
}

class Pressable extends _Pressable {
  const Pressable({required super.child, required super.onTap});
}

/// شريط السلة العائم
class CartBar extends StatelessWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => AnimatedSwitcher(
          duration: WDurations.base,
          transitionBuilder: (c, a) => SizeTransition(sizeFactor: a, axisAlignment: -1, child: FadeTransition(opacity: a, child: c)),
          child: app.cartCount == 0
              ? const SizedBox(width: double.infinity)
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Semantics(
                      container: true,
                      button: true,
                      label: 'عرض السلة',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                      excludeSemantics: true,
                      child: _Pressable(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
                          decoration: BoxDecoration(color: WColors.ink, borderRadius: WRadius.all(WRadius.lg), boxShadow: WShadow.lifted),
                          child: Row(children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(12)),
                              child: AnimatedSwitcher(
                                duration: WDurations.fast,
                                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                                child: Text('${app.cartCount}', key: ValueKey(app.cartCount), style: WText.number.copyWith(fontSize: 16, color: WColors.ink)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('السلة', style: WText.bodyStrong.copyWith(color: WColors.white, fontWeight: FontWeight.w600)),
                                Text(app.cartMerchant?.name ?? '', style: WText.caption.copyWith(color: WColors.inkFaint), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ]),
                            ),
                            Text(iqd(app.cartSubtotal), style: WText.price.copyWith(color: WColors.lime, fontSize: 16)),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_left_rounded, color: WColors.white),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
}

/// إضافة منتج للسلة مع تأكيد إذا السلة من محل ثاني
Future<void> addToCart(BuildContext context, Merchant m, Product p) async {
  if (!m.isOpenNow) {
    showError(context, 'المحل مسكّر هسه، ما يستقبل طلبات.');
    return;
  }
  HapticFeedback.selectionClick();
  if (app.add(m, p)) return;
  final ok = await confirmDialog(
    context,
    title: 'نبدأ سلة جديدة؟',
    message: 'سلتك بيها أغراض من ${app.cartMerchant?.name}. إذا ضفت من ${m.name} راح تنمسح السلة الحالية.',
    confirm: 'سلة جديدة',
  );
  if (ok) {
    app.clearCart();
    app.add(m, p);
  }
}

/// عداد الكمية: زر "+" حبر صغير، ويتحوّل لعداد عند الإضافة
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.qty, required this.onAdd, required this.onRemove, this.compact = false});
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: WDurations.base,
        transitionBuilder: (c, a) => ScaleTransition(scale: a, alignment: AlignmentDirectional.centerEnd.resolve(Directionality.of(context)), child: c),
        child: qty == 0
            ? Semantics(
                key: const ValueKey('add'),
                container: true,
                button: true,
                label: 'أضف للسلة',
                // excludeSemantics يحذف فعل النقر من InkWell، لذلك نعطيه هنا صراحةً
                onTap: onAdd,
                excludeSemantics: true,
                child: Material(
                  color: WColors.ink,
                  borderRadius: WRadius.all(12),
                  child: InkWell(
                    borderRadius: WRadius.all(12),
                    onTap: onAdd,
                    child: const SizedBox(width: 40, height: 40, child: Icon(Icons.add_rounded, color: WColors.lime, size: 22)),
                  ),
                ),
              )
            : Container(
                key: const ValueKey('stepper'),
                height: 40,
                decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(12)),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _btn(qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, onRemove, 'نقّص'),
                  SizedBox(
                    width: 24,
                    child: AnimatedSwitcher(
                      duration: WDurations.fast,
                      child: Text('$qty', key: ValueKey(qty), textAlign: TextAlign.center, style: WText.number.copyWith(fontSize: 15, color: WColors.ink)),
                    ),
                  ),
                  _btn(Icons.add_rounded, onAdd, 'زيد'),
                ]),
              ),
      );

  Widget _btn(IconData i, VoidCallback f, String label) => Semantics(
        container: true,
        button: true,
        label: label,
        onTap: f,
        excludeSemantics: true,
        child: InkResponse(
          onTap: () {
            HapticFeedback.selectionClick();
            f();
          },
          radius: 20,
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(i, size: 18, color: WColors.ink)),
        ),
      );
}

/// اختيار عنوان من قائمة العناوين
Future<void> pickAddressSheet(BuildContext context, {required VoidCallback onAddNew}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => ListenableBuilder(
        listenable: app,
        builder: (c, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('وين نوصلك؟', style: WText.h2),
              const SizedBox(height: 12),
              if (app.addresses.isEmpty) Text('ما عندك عناوين محفوظة بعد.', style: WText.small),
              for (final a in app.addresses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    borderColor: app.selectedAddress?.id == a.id ? WColors.ink : WColors.line,
                    onTap: () {
                      app.selectAddress(a.id);
                      Navigator.pop(c);
                    },
                    child: Row(children: [
                      Icon(a.label == 'الدوام' ? Icons.work_outline_rounded : Icons.home_outlined, color: WColors.ink),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.label, style: WText.h3),
                          Text([a.details, if (a.landmark.isNotEmpty) landmarkAr(a.landmark)].join(' · '), style: WText.small, maxLines: 2),
                        ]),
                      ),
                      if (app.selectedAddress?.id == a.id) const Icon(Icons.check_circle_rounded, color: WColors.blue),
                    ]),
                  ),
                ),
              const SizedBox(height: 4),
              WButton('عنوان جديد', icon: Icons.add_location_alt_outlined, kind: WButtonKind.secondary, onPressed: () {
                Navigator.pop(c);
                onAddNew();
              }),
            ]),
          ),
        ),
      ),
    );
