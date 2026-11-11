import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../state.dart';
import '../widgets.dart';
import 'account.dart';
import 'order_tracking.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _placing = false;
  late final _note = TextEditingController(text: app.cartNote);

  Future<void> _place() async {
    final m = app.cartMerchant;
    final a = app.selectedAddress;
    if (m == null) return;
    if (a == null) {
      showError(context, 'أضف عنوان التوصيل أولاً.');
      return;
    }
    final d = distanceKm(m.lat, m.lng, a.lat, a.lng);
    if (d > m.deliveryRadiusKm) {
      // الخادم يتحقق نهائياً (وقد تسمح الإدارة بالطلب خارج النطاق)، هنا تنبيه مبكر فقط
      final go = await confirmDialog(context,
          title: 'العنوان بعيد عن المحل', message: 'المسافة ${kmAr(d)} ونطاق توصيل المحل ${m.deliveryRadiusKm} كم. نحاول نرسل الطلب؟', confirm: 'أرسل');
      if (!go) return;
    }
    setState(() => _placing = true);
    app.cartNote = _note.text.trim();
    try {
      final order = await app.placeOrder();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id, justPlaced: true)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('السلة')),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final m = app.cartMerchant;
            if (m == null || app.cart.isEmpty) {
              return EmptyView(
                icon: Icons.shopping_bag_outlined,
                title: 'سلتك فارغة',
                message: 'ضيف منتجات من أي محل وترجع هنا.',
                action: WButton('رجوع للتسوق', onPressed: () => Navigator.pop(context), kind: WButtonKind.secondary, expand: false),
              );
            }
            final a = app.selectedAddress;
            final minOrder = m.minOrder;
            final belowMin = app.cartSubtotal < minOrder;
            final total = app.cartSubtotal + m.deliveryFee;
            return Column(children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
                  WCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        MerchantLogo(name: m.name, url: m.logoUrl, size: 40),
                        const SizedBox(width: 10),
                        Expanded(child: Text(m.name, style: WText.h3)),
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('+ أضف')),
                      ]),
                      const Divider(height: 24),
                      for (final l in app.cart) _line(l),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  WCard(
                    onTap: () => pickAddressSheet(context, onAddNew: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressFormScreen()))),
                    child: Row(children: [
                      const CircleAvatar(backgroundColor: WColors.coralSoft, child: Icon(Icons.location_on_rounded, color: WColors.coralDeep)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('التوصيل إلى', style: WText.caption),
                          Text(a?.oneLine ?? 'اختار أو أضف عنوان', style: WText.bodyStrong),
                          if (a != null && a.landmark.isNotEmpty) Text('قرب ${a.landmark}', style: WText.small),
                        ]),
                      ),
                      const Icon(Icons.chevron_left_rounded, color: WColors.inkMuted),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  WCard(
                    child: Row(children: [
                      const CircleAvatar(backgroundColor: WColors.mintSoft, child: Icon(Icons.payments_outlined, color: WColors.mintDeep)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('طريقة الدفع', style: WText.caption),
                          Text('نقداً عند الاستلام', style: WText.bodyStrong),
                        ]),
                      ),
                      const Icon(Icons.check_circle_rounded, color: WColors.mintDeep),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'ملاحظة للمحل (اختياري)', hintText: 'مثلاً: بدون بصل، اتصل قبل لا توصل'),
                  ),
                  WCard(
                    child: Column(children: [
                      _sum('المنتجات', iqd(app.cartSubtotal)),
                      _sum('أجور التوصيل', m.deliveryFee == 0 ? 'مجاني' : iqd(m.deliveryFee)),
                      const Divider(height: 20),
                      _sum('المبلغ النهائي', iqd(total), strong: true),
                    ]),
                  ),
                  if (belowMin) ...[
                    const SizedBox(height: 10),
                    StatusPill('الحد الأدنى للطلب من هذا المحل ${iqd(minOrder)}', tone: PillTone.warning, icon: Icons.info_outline_rounded),
                  ],
                ]),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: const BoxDecoration(color: WColors.white, border: Border(top: BorderSide(color: WColors.line))),
                  child: WButton(
                    'تأكيد الطلب',
                    onPressed: belowMin || a == null || !m.isOpenNow ? null : _place,
                    loading: _placing,
                    trailing: Text(iqd(total), style: WText.price.copyWith(color: WColors.white)),
                  ),
                ),
              ),
            ]);
          },
        ),
      );

  Widget _line(CartLine l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.product.name, style: WText.bodyStrong),
                Text(iqd(l.total), style: WText.small),
              ]),
            ),
            QtyStepper(qty: l.qty, onAdd: () => app.add(app.cartMerchant!, l.product), onRemove: () => app.remove(l.product)),
          ]),
          InkWell(
            onTap: () async {
              final n = await promptText(context, title: 'ملاحظة على ${l.product.name}', initial: l.note, hint: 'مثلاً: حار، بدون مخللات');
              app.setLineNote(l.product, n ?? '');
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l.note.isEmpty ? '+ ملاحظة' : '✎ ${l.note}', style: WText.caption.copyWith(color: WColors.coralDeep)),
            ),
          ),
        ]),
      );

  Widget _sum(String k, String v, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: strong ? WText.bodyStrong : WText.body.copyWith(color: WColors.inkMuted))),
          Text(v, style: strong ? WText.price.copyWith(fontSize: 17) : WText.bodyStrong),
        ]),
      );
}
