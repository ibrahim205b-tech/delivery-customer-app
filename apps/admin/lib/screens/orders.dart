import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

enum _Kind { stores, homeServices, taxi, tuktuk, errands }

enum _State { active, done, cancelled }

/// كل الطلبات من مكان واحد مع فلاتر النوع والحالة
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  _Kind _kind = _Kind.stores;
  _State _state = _State.active;
  String? _storeCat; // فلتر قسم المحلات (مطاعم، سوبر ماركت…)
  List<MerchantCategory> _cats = [];
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    adminApi.allCategories().then((c) {
      if (mounted) setState(() => _cats = c.where((x) => x.kind == CategoryKind.store).toList());
    }).catchError((_) {});
  }

  List<String> get _orderStatuses => switch (_state) {
        _State.active => ['placed', 'accepted', 'preparing', 'ready', 'picked_up', 'on_the_way'],
        _State.done => ['delivered'],
        _State.cancelled => ['cancelled'],
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الطلبات')),
        body: Column(children: [
          SizedBox(
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: WSpace.page), children: [
              for (final k in _Kind.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(switch (k) { _Kind.stores => 'المحلات', _Kind.homeServices => 'الخدمات المنزلية', _Kind.taxi => 'التكسي', _Kind.tuktuk => 'التكتك', _Kind.errands => 'توصيل الأغراض' }),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
                ),
            ]),
          ),
          if (_kind == _Kind.stores && _cats.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: WSpace.page), children: [
                Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: FilterChip(label: const Text('كل الأقسام'), selected: _storeCat == null, onSelected: (_) => setState(() => _storeCat = null))),
                for (final c in _cats)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: FilterChip(label: Text(c.name), selected: _storeCat == c.id, onSelected: (_) => setState(() => _storeCat = c.id)),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.page, 6, WSpace.page, 6),
            child: SegmentedButton<_State>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _State.active, label: Text('جارية')),
                ButtonSegment(value: _State.done, label: Text('مكتملة')),
                ButtonSegment(value: _State.cancelled, label: Text('ملغاة')),
              ],
              selected: {_state},
              onSelectionChanged: (v) => setState(() => _state = v.first),
            ),
          ),
          Expanded(child: KeyedSubtree(key: ValueKey('$_kind-$_state-$_storeCat-$_reloadKey'), child: _list())),
        ]),
      );

  Widget _list() => switch (_kind) {
        _Kind.stores => AsyncView<List<Order>>(
            load: () => adminApi.orders(statuses: _orderStatuses, categoryId: _storeCat),
            loading: const SkeletonList(),
            builder: (context, list, reload) => _wrap(reload, list.length, (i) => _OrderTile(order: list[i], onChanged: () => setState(() => _reloadKey++))),
          ),
        _Kind.taxi || _Kind.tuktuk => AsyncView<List<Ride>>(
            load: () => adminApi.rides(
              vehicle: _kind == _Kind.taxi ? 'taxi' : 'tuktuk',
              statuses: switch (_state) { _State.active => ['requested', 'accepted', 'arrived', 'in_progress'], _State.done => ['completed'], _State.cancelled => ['cancelled'] },
            ),
            loading: const SkeletonList(),
            builder: (context, list, reload) => _wrap(reload, list.length, (i) {
              final r = list[i];
              return WCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${r.customerName} · ${r.customerPhone}', style: WText.bodyStrong)),
                    StatusPill(r.status.label),
                  ]),
                  const SizedBox(height: 6),
                  InfoRow(icon: Icons.trip_origin_rounded, text: r.pickupText),
                  InfoRow(icon: Icons.flag_rounded, text: r.dropoffText),
                  const SizedBox(height: 6),
                  Text('${dateTimeAr(r.createdAt)} · ${kmAr(r.distanceKm)} · ${iqd(r.fare)}${r.driverName == null ? '' : ' · السائق ${r.driverName}'}', style: WText.caption),
                ]),
              );
            }),
          ),
        _Kind.errands => AsyncView<List<DeliveryTask>>(
            load: () => adminApi.errands(
              statuses: switch (_state) { _State.active => ['requested', 'assigned', 'picked_up', 'on_the_way'], _State.done => ['delivered'], _State.cancelled => ['cancelled'] },
            ),
            loading: const SkeletonList(),
            builder: (context, list, reload) => _wrap(reload, list.length, (i) {
              final t = list[i];
              return WCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StatusPill(t.kind.label, tone: PillTone.info),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.customerName, style: WText.bodyStrong)),
                    StatusPill(t.status.label),
                  ]),
                  const SizedBox(height: 6),
                  Text('${t.itemType} — ${t.description}', style: WText.small, maxLines: 2),
                  const SizedBox(height: 4),
                  Text('${dateTimeAr(t.createdAt)} · ${iqd(t.fee)}${t.driverName == null ? '' : ' · ${t.driverName}'}', style: WText.caption),
                ]),
              );
            }),
          ),
        _Kind.homeServices => AsyncView<List<ServiceBooking>>(
            load: () => adminApi.bookings(
              statuses: switch (_state) { _State.active => ['requested', 'accepted', 'in_progress'], _State.done => ['completed'], _State.cancelled => ['cancelled', 'rejected'] },
            ),
            loading: const SkeletonList(),
            builder: (context, list, reload) => _wrap(reload, list.length, (i) {
              final b = list[i];
              return WCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${b.serviceName ?? ''} · ${b.providerName ?? ''}', style: WText.bodyStrong)),
                    StatusPill(b.status.label),
                  ]),
                  const SizedBox(height: 4),
                  Text('${b.customerName} · ${b.customerPhone}', style: WText.small),
                  Text(b.description, style: WText.small, maxLines: 2),
                  Text('الموعد: ${dateAr(b.preferredTime)} ${timeAr(b.preferredTime)}', style: WText.caption),
                ]),
              );
            }),
          ),
      };

  Widget _wrap(Future<void> Function() reload, int count, Widget Function(int) item) => RefreshIndicator(
        onRefresh: reload,
        child: count == 0
            ? ListView(children: const [EmptyView(icon: Icons.inbox_outlined, title: 'ما اكو شي بهذا الفلتر')])
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 24),
                itemCount: count,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => item(i),
              ),
      );
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onChanged});
  final Order order;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          MerchantLogo(name: o.merchantName ?? '', url: o.merchantLogo, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o.code} · ${o.merchantName ?? ''}', style: WText.bodyStrong),
              Text(dateTimeAr(o.createdAt), style: WText.caption),
            ]),
          ),
          StatusPill(o.status.label, tone: o.status == OrderStatus.cancelled ? PillTone.danger : (o.status.isActive ? PillTone.accent : PillTone.success)),
        ]),
        const SizedBox(height: 8),
        Text(o.itemsSummary, style: WText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text('${o.customerName} · ${o.customerPhone}', style: WText.caption),
        if (o.driverName != null) Text('المندوب: ${o.driverName}', style: WText.caption),
        if ((o.cancelReason ?? '').isNotEmpty) Text('السبب: ${o.cancelReason}', style: WText.caption.copyWith(color: WColors.danger)),
        const SizedBox(height: 6),
        Row(children: [
          Text(iqd(o.total), style: WText.price),
          const Spacer(),
          if (o.status.isActive)
            TextButton(
              onPressed: () async {
                final r = await promptText(context, title: 'إلغاء الطلب ${o.code}', hint: 'سبب الإلغاء', confirm: 'إلغاء الطلب');
                if (r == null || !context.mounted) return;
                if (await runAction(context, () => adminApi.cancelOrder(o.id, r), success: 'انلغى الطلب')) onChanged();
              },
              child: Text('إلغاء إداري', style: WText.button.copyWith(color: WColors.danger)),
            ),
        ]),
      ]),
    );
  }
}
