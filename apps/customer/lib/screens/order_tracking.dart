import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// تتبع الطلب لحظياً: الحالة، خط زمني بكل المراحل، موقع المندوب، الإلغاء، والتقييم.
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
  bool _rated = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      _sub?.cancel();
      _sub = customerApi.watchOrderRow(widget.orderId).listen((row) async {
        if (row == null || _order == null || !mounted) return;
        final prev = _order!.status;
        setState(() => _order = _order!.mergeRow(row));
        if (_order!.status != prev) {
          final h2 = await customerApi.orderHistory(widget.orderId);
          if (mounted) setState(() => _history = h2);
        }
      }, onError: (_) {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Scaffold(
      appBar: AppBar(title: Text(o == null ? 'تتبع الطلب' : 'طلب ${o.code}')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : o == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: EdgeInsets.zero, children: [
                    _mapSection(o),
                    Padding(
                      padding: const EdgeInsets.all(WSpace.page),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (widget.justPlaced && o.status == OrderStatus.placed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: WCard(
                              color: WColors.mintSoft,
                              borderColor: WColors.mintSoft,
                              child: Row(children: [
                                const Icon(Icons.check_circle_rounded, color: WColors.mintDeep),
                                const SizedBox(width: 10),
                                Expanded(child: Text('وصل طلبك للمحل. راح نبلغك أول ما يوافق.', style: WText.bodyStrong)),
                              ]),
                            ),
                          ),
                        _statusHeader(o),
                        const SizedBox(height: 16),
                        if (o.driverName != null && o.status.isActive) ...[_driverCard(o), const SizedBox(height: 16)],
                        _timeline(o),
                        const SizedBox(height: 16),
                        _summary(o),
                        if (o.status == OrderStatus.placed) ...[
                          const SizedBox(height: 16),
                          WButton('إلغاء الطلب', kind: WButtonKind.danger, icon: Icons.close_rounded, onPressed: () async {
                            if (!await confirmDialog(context, title: 'إلغاء الطلب؟', message: 'تگدر تلغي قبل ما يوافق المحل فقط.', confirm: 'ألغِ الطلب', danger: true)) return;
                            if (!context.mounted) return;
                            if (await runAction(context, () => customerApi.cancelOrder(o.id), success: 'انلغى الطلب')) _load();
                          }),
                        ],
                        if (o.status == OrderStatus.delivered && !_rated) ...[const SizedBox(height: 16), _rateCard(o)],
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ]),
                ),
    );
  }

  Widget _mapSection(Order o) {
    final markers = <WMarker>[
      if (o.merchantLat != null) WMarker(LatLng(o.merchantLat!, o.merchantLng!), kind: WMarkerKind.store),
      WMarker(LatLng(o.addressLat, o.addressLng), kind: WMarkerKind.home),
      if (o.driverLat != null && o.status.isActive) WMarker(LatLng(o.driverLat!, o.driverLng!), kind: WMarkerKind.driver),
    ];
    return SizedBox(height: 230, child: WMap(markers: markers));
  }

  Widget _statusHeader(Order o) {
    final cancelled = o.status == OrderStatus.cancelled;
    // 4 مجموعات مرئية لشريط التقدم
    final group = switch (o.status) {
      OrderStatus.placed => 0,
      OrderStatus.accepted || OrderStatus.preparing || OrderStatus.ready => 1,
      OrderStatus.pickedUp || OrderStatus.onTheWay => 2,
      OrderStatus.delivered => 3,
      OrderStatus.cancelled => -1,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(o.status.label, style: WText.h1)),
        if (cancelled) const StatusPill('ملغي', tone: PillTone.danger) else if (o.status.isActive) const _LiveDot(),
      ]),
      if (cancelled && (o.cancelReason ?? '').isNotEmpty) Text('السبب: ${o.cancelReason}', style: WText.small.copyWith(color: WColors.danger)),
      if (!cancelled) ...[
        const SizedBox(height: 14),
        StepProgress(steps: const ['أُرسل', 'يتجهّز', 'بالطريق', 'وصل'], current: group),
      ],
    ]);
  }

  Widget _driverCard(Order o) => WCard(
        child: Row(children: [
          const CircleAvatar(radius: 24, backgroundColor: WColors.coralSoft, child: Icon(Icons.two_wheeler_rounded, color: WColors.coralDeep)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.driverName!, style: WText.bodyStrong),
              Text(o.driverVehicle?.isNotEmpty == true ? o.driverVehicle! : 'مندوب واصل', style: WText.small),
            ]),
          ),
          if ((o.driverPhone ?? '').isNotEmpty)
            WIconButton(Icons.call_rounded, background: WColors.mintDeep, color: WColors.white, tooltip: 'اتصال', onPressed: () => callPhone(o.driverPhone!)),
        ]),
      );

  Widget _timeline(Order o) {
    final steps = OrderStatus.values.where((s) => s != OrderStatus.cancelled).toList();
    final reached = {for (final e in _history) e.status: e.at};
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('مراحل الطلب', style: WText.h3),
        const SizedBox(height: 10),
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            label: steps[i].label,
            at: reached[steps[i]],
            done: reached.containsKey(steps[i]),
            current: o.status == steps[i],
            last: i == steps.length - 1,
          ),
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
            Expanded(child: Text(o.merchantName ?? '', style: WText.bodyStrong)),
            Text(dateTimeAr(o.createdAt), style: WText.caption),
          ]),
          const Divider(height: 22),
          for (final it in o.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Text('${it.qty}×', style: WText.bodyStrong.copyWith(color: WColors.coralDeep)),
                const SizedBox(width: 8),
                Expanded(child: Text(it.note.isEmpty ? it.name : '${it.name} — ${it.note}', style: WText.body)),
                Text(iqd(it.unitPrice * it.qty), style: WText.body),
              ]),
            ),
          if (o.customerNote.isNotEmpty) ...[const SizedBox(height: 6), InfoRow(icon: Icons.sticky_note_2_outlined, text: o.customerNote)],
          const Divider(height: 22),
          InfoRow(icon: Icons.location_on_outlined, text: o.addressText),
          const SizedBox(height: 6),
          const InfoRow(icon: Icons.payments_outlined, text: 'نقداً عند الاستلام'),
          const Divider(height: 22),
          Row(children: [Expanded(child: Text('التوصيل', style: WText.small)), Text(iqd(o.deliveryFee), style: WText.small)]),
          const SizedBox(height: 4),
          Row(children: [Expanded(child: Text('المبلغ النهائي', style: WText.bodyStrong)), Text(iqd(o.total), style: WText.price)]),
        ]),
      );

  Widget _rateCard(Order o) {
    var stars = 0;
    final comment = TextEditingController();
    return StatefulBuilder(
      builder: (context, set) => WCard(
        child: Column(children: [
          Text('شلون كانت تجربتك؟', style: WText.h3),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => set(() => stars = i),
                icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: WColors.coral, size: 34),
              ),
          ]),
          TextField(controller: comment, decoration: const InputDecoration(hintText: 'ملاحظاتك (اختياري)')),
          const SizedBox(height: 10),
          WButton('إرسال التقييم', onPressed: stars == 0
              ? null
              : () async {
                  if (await runAction(context, () => customerApi.rateOrder(o.id, stars, comment.text.trim()), success: 'شكراً لتقييمك')) {
                    setState(() => _rated = true);
                  }
                }),
        ]),
      ),
    );
  }
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
    final color = danger ? WColors.danger : (done ? WColors.mintDeep : WColors.line);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 24,
          child: Column(children: [
            Container(
              width: current ? 18 : 14,
              height: current ? 18 : 14,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                color: done ? color : WColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: done && !danger ? const Icon(Icons.check_rounded, size: 10, color: WColors.white) : null,
            ),
            if (!last) Expanded(child: Container(width: 2, color: done ? WColors.mint : WColors.line)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: (current ? WText.bodyStrong : WText.body).copyWith(color: done ? (danger ? WColors.danger : WColors.ink) : WColors.inkFaint)),
              ),
              if (at != null) Text(timeAr(at!), style: WText.caption),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(opacity: _c, child: const CircleAvatar(radius: 5, backgroundColor: WColors.coral)),
        const SizedBox(width: 6),
        Text('مباشر', style: WText.caption.copyWith(color: WColors.coralDeep)),
      ]);
}
