import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import 'main.dart';
import 'screens/cart.dart';

double? distanceTo(Merchant m) {
  final p = app.referencePoint;
  if (p == null) return null;
  return distanceKm(p.latitude, p.longitude, m.lat, m.lng);
}

/// سطر معلومات المحل: تقييم · وقت · توصيل
class MerchantMeta extends StatelessWidget {
  const MerchantMeta(this.m, {super.key, this.light = false});
  final Merchant m;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final d = distanceTo(m);
    final color = light ? WColors.white.withValues(alpha: 0.85) : WColors.inkMuted;
    final style = WText.caption.copyWith(color: color);
    Widget dot() => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('·', style: style));
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (m.ratingCount > 0) ...[
        const Icon(Icons.star_rounded, size: 15, color: WColors.coral),
        const SizedBox(width: 2),
        Text(m.ratingAvg.toStringAsFixed(1), style: style.copyWith(fontWeight: FontWeight.w600, color: light ? WColors.white : WColors.ink)),
        dot(),
      ],
      Text('${m.etaMinutes(d ?? 2)} دقيقة', style: style),
      dot(),
      Text(m.deliveryFee == 0 ? 'توصيل مجاني' : 'توصيل ${iqd(m.deliveryFee)}', style: style),
      if (d != null) ...[dot(), Text(kmAr(d), style: style)],
    ]);
  }
}

/// بطاقة محل كبيرة (غلاف + شعار) للقوائم الأفقية
class MerchantCard extends StatelessWidget {
  const MerchantCard(this.m, {super.key, required this.onTap, this.width = 260});
  final Merchant m;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: GestureDetector(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              WImage(m.coverUrl, height: 130, width: width, radius: WRadius.lg, fallbackIcon: categoryIcon(m.categoryId), fallbackColor: categoryTint(m.categoryId).withValues(alpha: 0.12)),
              if (!m.isOpenNow)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(color: WColors.navy.withValues(alpha: 0.55), borderRadius: WRadius.all(WRadius.lg)),
                    alignment: Alignment.center,
                    child: Text('مسكّر هسه', style: WText.bodyStrong.copyWith(color: WColors.white)),
                  ),
                ),
              PositionedDirectional(
                start: 12,
                bottom: -20,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: WColors.white, borderRadius: WRadius.all(16), boxShadow: WShadow.soft),
                  child: MerchantLogo(name: m.name, url: m.logoUrl, size: 44),
                ),
              ),
            ]),
            const SizedBox(height: 26),
            Text(m.name, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            MerchantMeta(m),
          ]),
        ),
      );
}

/// صف محل مضغوط للقوائم العمودية
class MerchantRow extends StatelessWidget {
  const MerchantRow(this.m, {super.key, required this.onTap});
  final Merchant m;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WSpace.page, vertical: 10),
          child: Row(children: [
            MerchantLogo(name: m.name, url: m.logoUrl, size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(m.name, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (!m.isOpenNow) const StatusPill('مسكّر', tone: PillTone.neutral),
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
                  onPressed: () => runAction(context, () => app.toggleFavorite(m.id)),
                  icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? WColors.coral : WColors.inkFaint),
                );
              },
            ),
          ]),
        ),
      );
}

/// شريط السلة العائم أسفل الشاشة
class CartBar extends StatelessWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => AnimatedSwitcher(
          duration: WDurations.base,
          transitionBuilder: (c, a) => SizeTransition(sizeFactor: a, axisAlignment: -1, child: c),
          child: app.cartCount == 0
              ? const SizedBox(width: double.infinity)
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Material(
                      color: WColors.navy,
                      borderRadius: WRadius.all(WRadius.lg),
                      child: InkWell(
                        borderRadius: WRadius.all(WRadius.lg),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(children: [
                            Container(
                              width: 30,
                              height: 30,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(color: WColors.coral, shape: BoxShape.circle),
                              child: Text('${app.cartCount}', style: WText.bodyStrong.copyWith(color: WColors.white, height: 1)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('عرض السلة', style: WText.bodyStrong.copyWith(color: WColors.white)),
                                Text(app.cartMerchant?.name ?? '', style: WText.caption.copyWith(color: WColors.mint)),
                              ]),
                            ),
                            Text(iqd(app.cartSubtotal), style: WText.price.copyWith(color: WColors.white)),
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

class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.qty, required this.onAdd, required this.onRemove, this.compact = false});
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (qty == 0) {
      return Material(
        color: WColors.white,
        shape: const StadiumBorder(side: BorderSide(color: WColors.navy, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onAdd,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, size: 18, color: WColors.navy),
              if (!compact) ...[const SizedBox(width: 2), Text('أضف', style: WText.caption.copyWith(color: WColors.navy, fontWeight: FontWeight.w600))],
            ]),
          ),
        ),
      );
    }
    Widget btn(IconData i, VoidCallback f) => InkResponse(onTap: f, radius: 20, child: Padding(padding: const EdgeInsets.all(6), child: Icon(i, size: 18, color: WColors.white)));
    return Container(
      decoration: const ShapeDecoration(color: WColors.navy, shape: StadiumBorder()),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, onRemove),
        SizedBox(width: 22, child: Text('$qty', textAlign: TextAlign.center, style: WText.bodyStrong.copyWith(color: WColors.white))),
        btn(Icons.add_rounded, onAdd),
      ]),
    );
  }
}

/// اختيار عنوان من قائمة العناوين (Bottom sheet)
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
                RadioListTile<String>(
                  value: a.id,
                  groupValue: app.selectedAddress?.id,
                  onChanged: (v) {
                    app.selectAddress(v!);
                    Navigator.pop(c);
                  },
                  contentPadding: EdgeInsets.zero,
                  activeColor: WColors.coral,
                  title: Text(a.label, style: WText.bodyStrong),
                  subtitle: Text([a.details, if (a.landmark.isNotEmpty) 'قرب ${a.landmark}'].join(' · '), style: WText.small),
                ),
              const SizedBox(height: 8),
              WButton('إضافة عنوان جديد', icon: Icons.add_location_alt_outlined, kind: WButtonKind.secondary, onPressed: () {
                Navigator.pop(c);
                onAddNew();
              }),
            ]),
          ),
        ),
      ),
    );
