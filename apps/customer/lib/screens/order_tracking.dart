import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// تتبع الطلب: خريطة بكامل الشاشة + ورقة سفلية قابلة للسحب.
/// الحالة والموقع لحظياً (Realtime)، والمسار والوقت المتوقع من خدمة المسارات.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId, this.justPlaced = false});
  final String orderId;
  final bool justPlaced;
  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Order? _order;
  List<OrderStatusEvent> _history = [];
  Object? _error;
  StreamSubscription<Json?>? _sub;
  RouteResult? _route;
  LatLng? _routeFrom;
  bool _rated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await customerApi.order(widget.orderId);
      final h = await customerApi.orderHistory(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = o;
        _history = h;
        _error = null;
      });
      _updateRoute();
      _sub?.cancel();
      _sub = customerApi.watchOrderRow(widget.orderId).listen((row) async {
        if (row == null || _order == null || !mounted) return;
        final prev = _order!.status;
        setState(() => _order = _order!.mergeRow(row));
        _updateRoute();
        if (_order!.status != prev) {
          final h2 = await customerApi.orderHistory(widget.orderId);
          if (mounted) setState(() => _history = h2);
        }
      }, onError: (_) {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// المسار: من المندوب (أو المحل قبل الاستلام) إلى البيت. يُحدَّث إذا تحرك المندوب أكثر من 150 م.
  Future<void> _updateRoute() async {
    final o = _order;
    if (o == null || !o.status.isActive) return;
    final home = LatLng(o.addressLat, o.addressLng);
    final LatLng? from = o.driverLat != null
        ? LatLng(o.driverLat!, o.driverLng!)
        : (o.merchantLat != null ? LatLng(o.merchantLat!, o.merchantLng!) : null);
    if (from == null) return;
    if (_routeFrom != null && distanceKm(_routeFrom!.latitude, _routeFrom!.longitude, from.latitude, from.longitude) < 0.15) return;
    _routeFrom = from;
    final r = await geoApi.route(from, home);
    if (mounted) setState(() => _route = r);
  }

  int get _group => switch (_order!.status) {
        OrderStatus.placed => 0,
        OrderStatus.accepted || OrderStatus.preparing || OrderStatus.ready => 1,
        OrderStatus.pickedUp || OrderStatus.onTheWay => 2,
        OrderStatus.delivered => 3,
        OrderStatus.cancelled => -1,
      };

  String? get _eta {
    final o = _order!;
    if (!o.status.isActive || _route == null) return null;
    final travel = _route!.minutes.ceil();
    // قبل الاستلام نضيف وقت تحضير تقريبي
    final extra = switch (o.status) { OrderStatus.placed || OrderStatus.accepted => 15, OrderStatus.preparing => 8, OrderStatus.ready => 3, _ => 0 };
    final total = (travel + extra).clamp(1, 240);
    return '$total د';
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    if (_error != null) return Scaffold(appBar: AppBar(), body: ErrorView(error: _error!, onRetry: _load));
    if (o == null) return const Scaffold(body: LoadingView());
    final home = LatLng(o.addressLat, o.addressLng);
    final markers = <WMarker>[
      if (o.merchantLat != null) WMarker(LatLng(o.merchantLat!, o.merchantLng!), kind: WMarkerKind.store),
      WMarker(home, kind: WMarkerKind.home, label: _eta),
      if (o.driverLat != null && o.status.isActive) WMarker(LatLng(o.driverLat!, o.driverLng!), kind: WMarkerKind.courier),
    ];
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: WMap(
            markers: markers,
            route: o.status.isActive ? _route?.points : null,
            routeDashed: _route?.isEstimate ?? false,
            padding: EdgeInsets.fromLTRB(60, MediaQuery.paddingOf(context).top + 80, 60, MediaQuery.sizeOf(context).height * 0.45),
          ),
        ),
        // شريط علوي عائم
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 16,
          right: 16,
          child: Row(children: [
            WIconButton(Icons.arrow_forward_rounded, tooltip: 'رجوع', onPressed: () => Navigator.pop(context), bordered: true),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: WColors.night, borderRadius: WRadius.all(12)),
              child: Text('طلب ${o.code}', style: WText.label.copyWith(color: WColors.white)),
            ),
          ]),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.46,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          snap: true,
          builder: (context, scroll) => Container(
            decoration: BoxDecoration(color: WColors.paper, borderRadius: BorderRadius.vertical(top: Radius.circular(WRadius.xl)), boxShadow: WShadow.lifted),
            child: ListView(controller: scroll, padding: EdgeInsets.zero, children: [
              Center(child: Container(margin: const EdgeInsets.only(top: 10), width: 40, height: 4, decoration: BoxDecoration(color: WColors.line, borderRadius: WRadius.all(2)))),
              _statusBlock(o),
              Padding(
                padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (o.driverName != null && o.status.isActive) ...[_driverCard(o), const SizedBox(height: 12)],
                  _timeline(o),
                  const SizedBox(height: 12),
                  _summary(o),
                  if (o.status == OrderStatus.placed) ...[
                    const SizedBox(height: 14),
                    WButton('إلغاء الطلب', kind: WButtonKind.danger, icon: Icons.close_rounded, onPressed: () async {
                      if (!await confirmDialog(context, title: 'إلغاء الطلب؟', message: 'تگدر تلغي قبل ما يوافق المحل فقط.', confirm: 'ألغِ الطلب', danger: true)) return;
                      if (!context.mounted) return;
                      if (await runAction(context, () => customerApi.cancelOrder(o.id), success: 'انلغى الطلب')) _load();
                    }),
                  ],
                  if (o.status == OrderStatus.delivered && !_rated) ...[const SizedBox(height: 14), _RateCard(orderId: o.id, onDone: () => setState(() => _rated = true))],
                  const SizedBox(height: 10),
                  WButton('مساعدة بهذا الطلب', kind: WButtonKind.ghost, icon: Icons.support_agent_rounded, onPressed: () => showSupportSheet(context, app: SupportApp.customer, orderCode: o.code)),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _statusBlock(Order o) {
    final cancelled = o.status == OrderStatus.cancelled;
    return Container(
      margin: const EdgeInsets.fromLTRB(WSpace.page, 14, WSpace.page, 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cancelled ? WColors.dangerSoft : WColors.night, borderRadius: WRadius.all(WRadius.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: WDurations.slow,
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: c)),
              child: Text(o.status.label, key: ValueKey(o.status), style: WText.h1.copyWith(color: cancelled ? WColors.danger : WColors.white)),
            ),
          ),
          if (_eta != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(10)),
              child: Column(children: [
                Text(_eta!, style: WText.number.copyWith(fontSize: 18, color: WColors.ink, height: 1.1)),
                Text(_route!.isEstimate ? 'تقريباً' : 'للوصول', style: WText.caption.copyWith(fontSize: 10, color: WColors.fg)),
              ]),
            ),
        ]),
        if (widget.justPlaced && o.status == OrderStatus.placed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('وصل طلبك للمحل، راح نبلغك أول ما يوافق.', style: WText.small.copyWith(color: WColors.inkFaint)),
          ),
        if (cancelled && (o.cancelReason ?? '').isNotEmpty) Text('السبب: ${o.cancelReason}', style: WText.small.copyWith(color: WColors.danger)),
        if (!cancelled) ...[
          const SizedBox(height: 16),
          StepProgress(steps: const ['أُرسل', 'يتجهّز', 'بالطريق', 'وصل'], current: _group, onDark: true),
        ],
      ]),
    );
  }

  Widget _driverCard(Order o) => WCard(
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: WColors.night, borderRadius: WRadius.all(14)),
            child: const Icon(Icons.two_wheeler_rounded, color: WColors.lime),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.driverName!, style: WText.h3),
              Text(o.driverVehicle?.isNotEmpty == true ? o.driverVehicle! : 'مندوب واصل', style: WText.small),
            ]),
          ),
          if ((o.driverPhone ?? '').isNotEmpty)
            WIconButton(Icons.call_rounded, background: WColors.lime, color: WColors.ink, tooltip: 'اتصال بالمندوب', onPressed: () => callPhone(o.driverPhone!)),
        ]),
      );

  Widget _timeline(Order o) {
    final steps = OrderStatus.values.where((s) => s != OrderStatus.cancelled).toList();
    final reached = {for (final e in _history) e.status: e.at};
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('مراحل الطلب', style: WText.overline),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(label: steps[i].label, at: reached[steps[i]], done: reached.containsKey(steps[i]), current: o.status == steps[i], last: i == steps.length - 1),
        if (o.status == OrderStatus.cancelled)
          _TimelineRow(label: OrderStatus.cancelled.label, at: reached[OrderStatus.cancelled], done: true, current: true, last: true, danger: true),
      ]),
    );
  }

  Widget _summary(Order o) => WCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            MerchantLogo(name: o.merchantName ?? '', url: o.merchantLogo, size: 36),
            const SizedBox(width: 10),
            Expanded(child: Text(o.merchantName ?? '', style: WText.h3)),
            Text(dateTimeAr(o.createdAt), style: WText.caption),
          ]),
          const Divider(height: 24),
          for (final it in o.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: WColors.paper, borderRadius: WRadius.all(6)),
                  child: Text('${it.qty}×', style: WText.number.copyWith(fontSize: 12.5)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(it.note.isEmpty ? it.name : '${it.name} — ${it.note}', style: WText.body)),
                Text(iqd(it.unitPrice * it.qty), style: WText.price.copyWith(fontWeight: FontWeight.w500, fontSize: 14)),
              ]),
            ),
          if (o.customerNote.isNotEmpty) ...[const SizedBox(height: 6), InfoRow(icon: Icons.sticky_note_2_outlined, text: o.customerNote)],
          const Divider(height: 24),
          InfoRow(icon: Icons.location_on_outlined, text: o.addressText),
          const SizedBox(height: 6),
          const InfoRow(icon: Icons.payments_outlined, text: 'نقداً عند الاستلام'),
          const Divider(height: 24),
          Row(children: [Expanded(child: Text('التوصيل', style: WText.small)), Text(iqd(o.deliveryFee), style: WText.small)]),
          const SizedBox(height: 4),
          Row(children: [Expanded(child: Text('المبلغ النهائي', style: WText.h3)), Text(iqd(o.total), style: WText.price.copyWith(fontSize: 18))]),
        ]),
      );
}

class _RateCard extends StatefulWidget {
  const _RateCard({required this.orderId, required this.onDone});
  final String orderId;
  final VoidCallback onDone;
  @override
  State<_RateCard> createState() => _RateCardState();
}

class _RateCardState extends State<_RateCard> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _busy = false;
  bool _ok = false;

  @override
  Widget build(BuildContext context) => WCard(
        child: Column(children: [
          Text('شلون كانت تجربتك؟', style: WText.h3),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i',
                onPressed: () => setState(() => _stars = i),
                icon: AnimatedScale(
                  scale: i <= _stars ? 1.1 : 1,
                  duration: WDurations.fast,
                  child: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= _stars ? WColors.fg : WColors.inkFaint, size: 34),
                ),
              ),
          ]),
          TextField(controller: _comment, decoration: const InputDecoration(hintText: 'ملاحظاتك (اختياري)')),
          const SizedBox(height: 10),
          WButton('إرسال التقييم', loading: _busy, success: _ok, onPressed: _stars == 0
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await runAction(context, () => customerApi.rateOrder(widget.orderId, _stars, _comment.text.trim()), success: 'شكراً لتقييمك');
                  if (!mounted) return;
                  setState(() {
                    _busy = false;
                    _ok = ok;
                  });
                  if (ok) Future.delayed(const Duration(milliseconds: 900), widget.onDone);
                }),
        ]),
      );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.label, required this.at, required this.done, required this.current, required this.last, this.danger = false});
  final String label;
  final DateTime? at;
  final bool done;
  final bool current;
  final bool last;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? WColors.danger : (done ? WColors.fg : WColors.line);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 24,
          child: Column(children: [
            AnimatedContainer(
              duration: WDurations.slow,
              width: current ? 18 : 14,
              height: current ? 18 : 14,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                color: current && !danger ? WColors.lime : (done ? color : WColors.surface),
                borderRadius: WRadius.all(5),
                border: Border.all(color: color, width: 2),
              ),
            ),
            if (!last) Expanded(child: Container(width: 2, color: done ? WColors.fg : WColors.line)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Expanded(child: Text(label, style: (current ? WText.bodyStrong.copyWith(fontWeight: FontWeight.w600) : WText.body).copyWith(color: done ? (danger ? WColors.danger : WColors.fg) : WColors.inkFaint))),
              if (at != null) Text(timeAr(at!), style: WText.caption),
            ]),
          ),
        ),
      ]),
    );
  }
}
