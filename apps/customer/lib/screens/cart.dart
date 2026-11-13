import 'dart:async';

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
  late final _promo = TextEditingController(text: app.cartPromo ?? '');
  bool _promoOpen = app.cartPromo != null;
  bool _quoting = false;
  String? _promoTried; // آخر كود جرّبه المستخدم (حتى لو انرفض)
  CheckoutQuote? _quote; // null = الخادم ما يدعم العرض أو ما وصل بعد؛ نحسب محلياً
  String _quotedFor = '';
  Timer? _debounce;

  /// بصمة السلة: إذا تغيّرت نطلب عرض سعر جديد
  String get _signature => '${app.cartMerchant?.id}|${app.cart.map((l) => '${l.product.id}x${l.qty}').join(',')}|${app.cartPromo}|${app.cartUseWallet}';

  @override
  void initState() {
    super.initState();
    app.addListener(_onCartChanged);
    _requote();
  }

  @override
  void dispose() {
    app.removeListener(_onCartChanged);
    _debounce?.cancel();
    _note.dispose();
    _promo.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (_signature == _quotedFor) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _requote);
  }

  Future<void> _requote({String? tryPromo}) async {
    final m = app.cartMerchant;
    if (m == null || app.cart.isEmpty) return;
    final sig = _signature;
    final code = tryPromo ?? app.cartPromo;
    if (mounted) setState(() => _quoting = true);
    try {
      final q = await customerApi.checkoutQuote(merchantId: m.id, items: app.cartItemsPayload, promoCode: code, useWallet: app.cartUseWallet);
      if (!mounted) return;
      _quotedFor = sig;
      setState(() {
        _quote = q;
        if (tryPromo != null) _promoTried = tryPromo;
      });
      // الكود ينحفظ بالسلة فقط إذا الخادم قبله؛ وإذا صار ما ينطبق (نزل المبلغ مثلاً) ينشال
      // (العرض الحالي يبقى صحيح بالحالتين، فما نطلب عرض ثاني)
      if (tryPromo != null && q.promoError == null) {
        app.setCartPromo(tryPromo);
        _debounce?.cancel();
        _quotedFor = _signature;
      } else if (tryPromo == null && q.promoError != null && app.cartPromo != null) {
        _promoTried = app.cartPromo;
        _promoOpen = true;
        app.setCartPromo(null);
        _debounce?.cancel();
        _quotedFor = _signature;
      }
    } catch (_) {
      // خادم قبل تحديث المكافآت أو انقطاع: السلة تشتغل بالحساب المحلي بدون كود ورصيد
      if (mounted) setState(() => _quote = null);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  void _applyPromo() {
    final code = _promo.text.trim().toUpperCase();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    _requote(tryPromo: code);
  }

  void _removePromo() {
    _promo.clear();
    setState(() => _promoTried = null);
    app.setCartPromo(null);
  }

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
            final q = _quote;
            final discount = q?.discount ?? 0;
            final walletUsed = q?.walletUsed ?? 0;
            final total = app.cartSubtotal + m.deliveryFee - discount - walletUsed;
            final promoError = app.cartPromo == null && _promoTried != null ? q?.promoError : null;
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
                      CircleAvatar(backgroundColor: WColors.limeSoft, child: Icon(Icons.location_on_rounded, color: WColors.link)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('التوصيل إلى', style: WText.caption),
                          Text(a?.oneLine ?? 'اختار أو أضف عنوان', style: WText.bodyStrong),
                          if (a != null && a.landmark.isNotEmpty) Text(landmarkAr(a.landmark), style: WText.small),
                        ]),
                      ),
                      Icon(Icons.chevron_left_rounded, color: WColors.inkMuted),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  WCard(
                    child: Row(children: [
                      CircleAvatar(backgroundColor: WColors.successSoft, child: Icon(Icons.payments_outlined, color: WColors.success)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('طريقة الدفع', style: WText.caption),
                          Text('نقداً عند الاستلام', style: WText.bodyStrong),
                        ]),
                      ),
                      const Icon(Icons.check_circle_rounded, color: WColors.success),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'ملاحظة للمحل (اختياري)', hintText: 'مثلاً: بدون بصل، اتصل قبل لا توصل'),
                  ),
                  if (q != null) ...[
                    _promoCard(discount, promoError),
                    const SizedBox(height: 12),
                    if (q.walletBalance > 0) ...[_walletCard(q), const SizedBox(height: 12)],
                  ],
                  WCard(
                    child: Column(children: [
                      _sum('المنتجات', iqd(app.cartSubtotal)),
                      if (discount > 0) _sum('خصم الكود ${app.cartPromo ?? ''}', '− ${iqd(discount)}', accent: true),
                      if (walletUsed > 0) _sum('من رصيدك', '− ${iqd(walletUsed)}', accent: true),
                      _sum('أجور التوصيل', m.deliveryFee == 0 ? 'مجاني' : iqd(m.deliveryFee)),
                      const Divider(height: 20),
                      _sum('المبلغ النهائي', iqd(total), strong: true),
                      if (discount + walletUsed > 0)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Padding(padding: const EdgeInsets.only(top: 6), child: StatusPill('وفّرت ${iqd(discount + walletUsed)}', tone: PillTone.success, icon: Icons.savings_outlined)),
                        ),
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
                  decoration: BoxDecoration(color: WColors.surface, border: Border(top: BorderSide(color: WColors.line))),
                  child: WButton(
                    'تأكيد الطلب',
                    onPressed: belowMin || a == null || !m.isOpenNow || _quoting ? null : _place,
                    loading: _placing,
                    trailing: Text(iqd(total), style: WText.price.copyWith(color: WColors.ink)),
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
              child: Text(l.note.isEmpty ? '+ ملاحظة' : '✎ ${l.note}', style: WText.caption.copyWith(color: WColors.link)),
            ),
          ),
        ]),
      );

  Widget _sum(String k, String v, {bool strong = false, bool accent = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: strong ? WText.bodyStrong : WText.body.copyWith(color: accent ? WColors.success : WColors.inkMuted))),
          Text(v, style: strong ? WText.price.copyWith(fontSize: 17) : WText.bodyStrong.copyWith(color: accent ? WColors.success : null)),
        ]),
      );

  // ---------------- كود الخصم ----------------
  Widget _promoCard(int discount, String? error) {
    final applied = app.cartPromo;
    if (applied != null) {
      return WCard(
        child: Row(children: [
          CircleAvatar(backgroundColor: WColors.successSoft, child: const Icon(Icons.local_offer_rounded, color: WColors.success, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('كود الخصم', style: WText.caption),
              Text(discount > 0 ? '$applied · خصم ${iqd(discount)}' : applied, style: WText.bodyStrong, textDirection: TextDirection.rtl),
            ]),
          ),
          TextButton(onPressed: _removePromo, child: const Text('إزالة')),
        ]),
      );
    }
    if (!_promoOpen) {
      return WCard(
        onTap: () => setState(() => _promoOpen = true),
        child: Row(children: [
          CircleAvatar(backgroundColor: WColors.blueSoft, child: Icon(Icons.local_offer_outlined, color: WColors.link, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text('عندك كود خصم؟', style: WText.bodyStrong)),
          Icon(Icons.chevron_left_rounded, color: WColors.inkMuted),
        ]),
      );
    }
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _promo,
              autofocus: true,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              maxLength: 24,
              onSubmitted: (_) => _applyPromo(),
              decoration: InputDecoration(labelText: 'كود الخصم', counterText: '', errorText: error == null ? null : friendlyError(error), errorMaxLines: 2),
            ),
          ),
          const SizedBox(width: 10),
          Padding(padding: const EdgeInsets.only(top: 4), child: WButton('تطبيق', kind: WButtonKind.dark, expand: false, loading: _quoting, onPressed: _applyPromo)),
        ]),
      ]),
    );
  }

  // ---------------- رصيد المحفظة ----------------
  Widget _walletCard(CheckoutQuote q) => WCard(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
        child: Row(children: [
          CircleAvatar(backgroundColor: WColors.limeSoft, child: Icon(Icons.stars_rounded, color: WColors.isDark ? WColors.lime : WColors.limeDeep, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('استخدم رصيدي', style: WText.bodyStrong),
              Text(
                q.walletAvailable <= 0
                    ? 'رصيدك ${iqd(q.walletBalance)} · ما ينطبق على هذا الطلب'
                    : app.cartUseWallet
                        ? 'ينخصم ${iqd(q.walletUsed)} من هذا الطلب'
                        : 'عندك ${iqd(q.walletBalance)} · يغطي ${iqd(q.walletAvailable)}',
                style: WText.caption,
              ),
            ]),
          ),
          Switch(value: app.cartUseWallet && q.walletAvailable > 0, onChanged: q.walletAvailable <= 0 ? null : app.setCartUseWallet),
        ]),
      );
}
