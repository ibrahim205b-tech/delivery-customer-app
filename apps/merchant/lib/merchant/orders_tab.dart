import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

enum _Filter { incoming, inProgress, history }

/// الطلبات لحظياً: الجديدة، قيد العمل، السابقة. مع تنبيه صوتي للطلب الجديد.
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key, required this.merchant});
  final Merchant merchant;
  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  late Stream<List<Order>> _stream = merchantApi.watchOrders(widget.merchant.id);
  _Filter _filter = _Filter.incoming;
  final Set<String> _seen = {};
  bool _first = true;

  void _alertOnNew(List<Order> list) {
    final placed = list.where((o) => o.status == OrderStatus.placed).map((o) => o.id).toSet();
    final fresh = placed.difference(_seen);
    _seen.addAll(placed);
    if (_first) {
      _first = false;
      return;
    }
    if (fresh.isNotEmpty) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showInfo(context, fresh.length == 1 ? 'وصلك طلب جديد!' : 'وصلتك ${fresh.length} طلبات جديدة');
      });
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Order>>(
        stream: _stream,
        builder: (context, s) {
          if (s.hasError) return ErrorView(error: s.error!, onRetry: () => setState(() => _stream = merchantApi.watchOrders(widget.merchant.id)));
          if (!s.hasData) return const SkeletonList();
          final all = s.data!;
          _alertOnNew(all);
          final incoming = all.where((o) => o.status == OrderStatus.placed).toList();
          final progress = all.where((o) => o.status.isActive && o.status != OrderStatus.placed).toList();
          final history = all.where((o) => !o.status.isActive).toList();
          final list = switch (_filter) { _Filter.incoming => incoming, _Filter.inProgress => progress, _Filter.history => history };
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 8),
              child: SegmentedButton<_Filter>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: _Filter.incoming, label: Text('جديدة (${incoming.length})')),
                  ButtonSegment(value: _Filter.inProgress, label: Text('قيد العمل (${progress.length})')),
                  const ButtonSegment(value: _Filter.history, label: Text('السابقة')),
                ],
                selected: {_filter},
                onSelectionChanged: (v) => setState(() => _filter = v.first),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? EmptyView(
                      icon: _filter == _Filter.incoming ? Icons.notifications_paused_outlined : Icons.receipt_long_outlined,
                      title: switch (_filter) { _Filter.incoming => 'ما اكو طلبات جديدة', _Filter.inProgress => 'ما اكو طلبات قيد العمل', _Filter.history => 'ما اكو طلبات سابقة' },
                      message: _filter == _Filter.incoming ? 'الطلبات الجديدة تظهر هنا فوراً مع تنبيه صوتي.' : null,
                    )
                  : LayoutBuilder(builder: (context, c) {
                      // تابلت: عمودين من البطاقات
                      if (c.maxWidth >= 760) {
                        final cols = c.maxWidth >= 1200 ? 3 : 2;
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 24),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (var col = 0; col < cols; col++) ...[
                              if (col > 0) const SizedBox(width: 12),
                              Expanded(
                                child: Column(children: [
                                  for (var i = col; i < list.length; i += cols) Padding(padding: const EdgeInsets.only(bottom: 12), child: _OrderCard(key: ValueKey(list[i].id), order: list[i])),
                                ]),
                              ),
                            ],
                          ]),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _OrderCard(key: ValueKey(list[i].id), order: list[i]),
                      );
                    }),
            ),
          ]);
        },
      );
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({super.key, required this.order});
  final Order order;
  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  late final Future<List<OrderItem>> _items = merchantApi.orderItems(widget.order.id);
  bool _busy = false;

  Future<void> _set(OrderStatus s, {String? reason}) async {
    setState(() => _busy = true);
    await runAction(context, () => merchantApi.setOrderStatus(widget.order.id, s, reason: reason));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reject() async {
    const reasons = ['المنتج خلص', 'المحل مزدحم هسه', 'العنوان بعيد', 'المحل راح يسكّر'];
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('سبب الرفض', style: WText.h3)),
          for (final x in reasons) ListTile(title: Text(x), onTap: () => Navigator.pop(c, x)),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('سبب ثاني…'),
            onTap: () async {
              final t = await promptText(c, title: 'اكتب السبب', confirm: 'رفض');
              if (c.mounted) Navigator.pop(c, t);
            },
          ),
        ]),
      ),
    );
    if (r != null && r.isNotEmpty) await _set(OrderStatus.cancelled, reason: r);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final isNew = o.status == OrderStatus.placed;
    return WCard(
      borderColor: isNew ? WColors.blue : WColors.line,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(o.code, style: WText.h3),
          const SizedBox(width: 8),
          Text(relativeAr(o.createdAt), style: WText.caption),
          const Spacer(),
          StatusPill(o.status.label, tone: switch (o.status) {
            OrderStatus.placed => PillTone.accent,
            OrderStatus.cancelled => PillTone.danger,
            OrderStatus.delivered => PillTone.success,
            _ => PillTone.info,
          }),
        ]),
        const SizedBox(height: 10),
        FutureBuilder<List<OrderItem>>(
          future: _items,
          builder: (context, s) {
            if (!s.hasData) return const SkeletonBox(height: 40);
            return Column(children: [
              for (final it in s.data!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: WColors.ink, borderRadius: WRadius.all(6)),
                      child: Text('${it.qty}', style: WText.caption.copyWith(color: WColors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.name, style: WText.bodyStrong),
                        if (it.note.isNotEmpty) Text(it.note, style: WText.caption.copyWith(color: WColors.blue)),
                      ]),
                    ),
                    Text(iqd(it.unitPrice * it.qty), style: WText.small),
                  ]),
                ),
            ]);
          },
        ),
        if (o.customerNote.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: WColors.warningSoft, borderRadius: WRadius.all(WRadius.sm)),
            child: Text('ملاحظة الزبون: ${o.customerNote}', style: WText.small.copyWith(color: WColors.ink)),
          ),
        ],
        const Divider(height: 22),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.customerName, style: WText.bodyStrong),
              Text(o.addressText, style: WText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (o.customerPhone.isNotEmpty) WIconButton(Icons.call_outlined, background: WColors.surfaceAlt, onPressed: () => callPhone(o.customerPhone), tooltip: 'اتصال بالزبون'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('المجموع', style: WText.small),
          const Spacer(),
          Text(iqd(o.subtotal), style: WText.price),
          Text('  + توصيل ${iqd(o.deliveryFee)}', style: WText.caption),
        ]),
        if (o.status == OrderStatus.cancelled && (o.cancelReason ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('السبب: ${o.cancelReason}', style: WText.caption.copyWith(color: WColors.danger)),
        ],
        if (o.driverName != null && o.status.isActive) ...[
          const SizedBox(height: 8),
          InfoRow(icon: Icons.two_wheeler_rounded, text: 'المندوب: ${o.driverName}${(o.driverPhone ?? '').isEmpty ? '' : ' · ${o.driverPhone}'}', color: WColors.ink),
        ],
        const SizedBox(height: 12),
        ..._actions(o),
      ]),
    );
  }

  List<Widget> _actions(Order o) => switch (o.status) {
        OrderStatus.placed => [
            Row(children: [
              Expanded(flex: 2, child: WButton('قبول الطلب', icon: Icons.check_rounded, kind: WButtonKind.dark, loading: _busy, onPressed: () => _set(OrderStatus.accepted))),
              const SizedBox(width: 10),
              Expanded(child: WButton('رفض', kind: WButtonKind.danger, onPressed: _busy ? null : _reject)),
            ]),
          ],
        OrderStatus.accepted => [WButton('بدء التحضير', icon: Icons.soup_kitchen_outlined, kind: WButtonKind.dark, loading: _busy, onPressed: () => _set(OrderStatus.preparing))],
        OrderStatus.preparing => [WButton('جاهز للاستلام', icon: Icons.inventory_rounded, loading: _busy, onPressed: () => _set(OrderStatus.ready))],
        OrderStatus.ready => [
            StatusPill(o.driverName == null ? 'بانتظار مندوب يقبل التوصيل' : 'المندوب بالطريق لاستلام الطلب', tone: PillTone.info, icon: Icons.hourglass_top_rounded),
          ],
        _ => const [],
      };
}
