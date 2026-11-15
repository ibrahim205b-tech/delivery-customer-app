import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

enum _Layer { drivers, orders, merchants, areas }

/// حالة السائق كما تظهر للإدارة
enum _DriverState { available, busy, offline }

/// خريطة العمليات للإدارة.
/// - مواقع السائقين تأتي Realtime من جدول drivers (لحظياً).
/// - الطلبات والمحلات والمناطق تُحدَّث كل دقيقة (تغيّرها أبطأ).
/// - السائق الذي لم يرسل موقعه منذ 30 دقيقة يختفي، وما بين 5 و30 دقيقة يظهر باهتاً مع وقت آخر تحديث.
class OpsMapScreen extends StatefulWidget {
  const OpsMapScreen({super.key});
  @override
  State<OpsMapScreen> createState() => _OpsMapScreenState();
}

const _hideAfter = Duration(minutes: 30);

class _OpsMapScreenState extends State<OpsMapScreen> {
  final Set<_Layer> _on = {..._Layer.values};
  ({List<Driver> drivers, List<Order> activeOrders, List<Merchant> merchants, List<ServiceArea> areas, Set<String> busyDriverIds})? _d;
  List<Driver>? _live; // آخر مواقع من Realtime (تُدمج مع الأسماء من _d)
  Object? _error;
  Timer? _timer;
  StreamSubscription<List<Driver>>? _sub;
  bool _streamOk = false;
  DateTime? _loadedAt;

  // الاختيار والفلاتر
  String? _selText;
  String? _selDriverId;
  Order? _selOrder;
  List<LatLng>? _routePts;
  RouteResult? _routeRes;
  _DriverState? _stateFilter; // null = الكل
  String? _areaFilter; // null = كل المناطق

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
    _sub = adminApi.watchDriverLocations().listen(
      (rows) {
        if (!mounted) return;
        final names = {for (final x in _d?.drivers ?? const <Driver>[]) x.id: x};
        setState(() {
          _streamOk = true;
          _live = [for (final r in rows) _merge(r, names[r.id])];
        });
      },
      onError: (_) {
        if (mounted) setState(() => _streamOk = false);
      },
    );
  }

  /// يدمج صف Realtime (بدون أسماء) مع الاسم والمركبة من آخر تحميل كامل
  static Driver _merge(Driver fresh, Driver? old) => Driver(
        id: fresh.id,
        vehicleType: fresh.vehicleType,
        areaId: fresh.areaId,
        isActive: fresh.isActive,
        isAvailable: fresh.isAvailable,
        lastLat: fresh.lastLat,
        lastLng: fresh.lastLng,
        lastSeenAt: fresh.lastSeenAt,
        fullName: old?.fullName,
        phone: old?.phone,
        plate: old?.plate,
        model: old?.model,
        color: old?.color,
      );

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await adminApi.opsMap();
      if (mounted) {
        setState(() {
          _d = d;
          _loadedAt = DateTime.now();
          _error = null;
          // أسماء جديدة قد تكون وصلت: نحدّث القائمة الحية بها
          if (_live != null) {
            final names = {for (final x in d.drivers) x.id: x};
            _live = [for (final r in _live!) _merge(r, names[r.id])];
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// يرسم مسار الطلب (من المحل إلى العنوان) — فقط للطلب المختار، حتى لا نكثر طلبات الخدمة.
  Future<void> _showOrderRoute(Order o) async {
    setState(() {
      _selOrder = o;
      _routePts = null;
      _routeRes = null;
    });
    if (o.merchantLat == null || o.merchantLng == null) return;
    final r = await geoApi.route(LatLng(o.merchantLat!, o.merchantLng!), LatLng(o.addressLat, o.addressLng));
    if (mounted && _selOrder?.id == o.id) {
      setState(() {
        _routePts = r.points;
        _routeRes = r;
      });
    }
  }

  _DriverState _stateOf(Driver x) {
    if (!x.isAvailable) return _DriverState.offline;
    if (_d?.busyDriverIds.contains(x.id) ?? false) return _DriverState.busy;
    return _DriverState.available;
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final now = DateTime.now();
    final drivers = (_live ?? d?.drivers ?? const <Driver>[])
        .where((x) => x.lastLat != null && x.lastLng != null && x.lastSeenAt != null && now.difference(x.lastSeenAt!) < _hideAfter)
        .where((x) => _areaFilter == null || x.areaId == _areaFilter)
        .toList();
    final visible = drivers.where((x) => _stateFilter == null || _stateOf(x) == _stateFilter).toList();
    // العدّاد يحسب المواقع الحديثة فقط؛ القديمة تظهر باهتة وتُذكر بسطر منفصل (لا تُحسب كمتاحة)
    final current = drivers.where((x) => freshnessOf(x.lastSeenAt, now: now) != Freshness.stale).toList();
    final staleCount = drivers.length - current.length;
    final counts = {for (final s in _DriverState.values) s: current.where((x) => _stateOf(x) == s).length};
    final merchantArea = {for (final m in d?.merchants ?? const <Merchant>[]) m.id: m.areaId};
    final orders = (d?.activeOrders ?? const <Order>[]).where((o) => _areaFilter == null || merchantArea[o.merchantId] == _areaFilter).toList();
    final selDriver = _selDriverId == null ? null : drivers.where((x) => x.id == _selDriverId).firstOrNull;
    final selDriverOrder = selDriver == null ? null : orders.where((o) => o.driverId == selDriver.id).firstOrNull;

    final markers = <WMarker>[
      if (d != null && _on.contains(_Layer.merchants))
        for (final m in d.merchants)
          WMarker(LatLng(m.lat, m.lng), kind: WMarkerKind.store, icon: categoryIcon(m.categoryId), onTap: () => setState(() {
                _selText = '${m.name} · ${m.phone}';
                _selDriverId = null;
              })),
      if (d != null && _on.contains(_Layer.orders))
        for (final o in orders)
          WMarker(LatLng(o.addressLat, o.addressLng), kind: WMarkerKind.home, onTap: () {
            setState(() {
              _selDriverId = null;
              _selText = '${o.code} · ${o.merchantName ?? ''} · ${o.status.label}';
            });
            _showOrderRoute(o);
          }),
      if (_on.contains(_Layer.drivers))
        for (final x in visible)
          WMarker(
            LatLng(x.lastLat!, x.lastLng!),
            kind: switch (x.vehicleType) { VehicleType.taxi => WMarkerKind.taxi, VehicleType.tuktuk => WMarkerKind.tuktuk, VehicleType.courier => WMarkerKind.courier },
            busy: _stateOf(x) == _DriverState.busy,
            stale: freshnessOf(x.lastSeenAt, now: now) == Freshness.stale,
            onTap: () => setState(() {
              _selDriverId = x.id;
              _selOrder = null;
              _routePts = null;
              _routeRes = null;
            }),
          ),
    ];
    final areas = d == null || !_on.contains(_Layer.areas) ? <WArea>[] : [for (final a in d.areas) WArea(LatLng(a.centerLat, a.centerLng), a.radiusKm, label: a.name, active: a.isActive)];
    final bottomInset = 24 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: WMap(
            markers: markers,
            areas: areas,
            route: _routePts,
            routeDashed: _routeRes?.isEstimate ?? false,
            zoom: 12,
            padding: const EdgeInsets.fromLTRB(40, 230, 40, 190),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          left: 16,
          right: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              WIconButton(Icons.arrow_forward_rounded, tooltip: 'رجوع', onPressed: () => Navigator.pop(context), bordered: true),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: WColors.ink, borderRadius: WRadius.all(WRadius.md)),
                  child: Row(children: [
                    Text('خريطة العمليات', style: WText.h3.copyWith(color: WColors.white)),
                    const Spacer(),
                    if (d == null && _error == null) SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: WColors.lime)),
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsetsDirectional.only(end: 6),
                      decoration: BoxDecoration(color: _streamOk ? WColors.success : WColors.warning, shape: BoxShape.circle),
                    ),
                    Text(_streamOk ? 'مباشر' : 'احتياطي', style: WText.caption.copyWith(color: WColors.white)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            // إحصائيات تشغيلية
            Row(children: [
              _Stat(label: 'متاح', value: counts[_DriverState.available] ?? 0, color: WColors.success),
              const SizedBox(width: 6),
              _Stat(label: 'مشغول', value: counts[_DriverState.busy] ?? 0, color: WColors.blue),
              const SizedBox(width: 6),
              _Stat(label: 'غير متصل', value: counts[_DriverState.offline] ?? 0, color: WColors.inkFaint),
              const SizedBox(width: 6),
              _Stat(label: 'طلب جارٍ', value: orders.length, color: WColors.ink),
            ]),
            if (staleCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('$staleCount سائق موقعه قديم (أكثر من 5 دقائق) — يظهر باهتاً ولا يُحسب ضمن الحالات', style: WText.caption.copyWith(color: WColors.ink)),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final l in _Layer.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      label: Text(switch (l) { _Layer.drivers => 'السائقون', _Layer.orders => 'الطلبات الجارية', _Layer.merchants => 'المحلات', _Layer.areas => 'المناطق' }),
                      selected: _on.contains(l),
                      labelStyle: WText.label.copyWith(color: _on.contains(l) ? WColors.white : WColors.ink),
                      onSelected: (v) => setState(() => v ? _on.add(l) : _on.remove(l)),
                    ),
                  ),
              ]),
            ),
            SizedBox(
              height: 38,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final s in [null, _DriverState.available, _DriverState.busy, _DriverState.offline])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(switch (s) { null => 'كل الحالات', _DriverState.available => 'متاح', _DriverState.busy => 'مشغول', _DriverState.offline => 'غير متصل' }),
                      selected: _stateFilter == s,
                      onSelected: (_) => setState(() => _stateFilter = s),
                    ),
                  ),
                if (d != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(_areaFilter == null ? 'كل المناطق' : (d.areas.where((a) => a.id == _areaFilter).firstOrNull?.name ?? 'منطقة')),
                      selected: _areaFilter != null,
                      avatar: const Icon(Icons.place_outlined, size: 16),
                      onSelected: (_) async {
                        final picked = await showModalBottomSheet<String?>(
                          context: context,
                          builder: (c) => SafeArea(
                            child: ListView(shrinkWrap: true, children: [
                              ListTile(title: const Text('كل المناطق'), onTap: () => Navigator.pop(c, '')),
                              for (final a in d.areas) ListTile(title: Text(a.name), subtitle: Text(a.isActive ? 'مفعّلة' : 'موقوفة'), onTap: () => Navigator.pop(c, a.id)),
                            ]),
                          ),
                        );
                        if (picked != null) setState(() => _areaFilter = picked.isEmpty ? null : picked);
                      },
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        if (_error != null)
          Positioned(left: 16, right: 16, bottom: bottomInset, child: WCard(color: WColors.dangerSoft, borderColor: Colors.transparent, child: Text(friendlyError(_error!), style: WText.small.copyWith(color: WColors.danger)))),
        if (selDriver != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset,
            child: WCard(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(selDriver.fullName ?? 'سائق', style: WText.bodyStrong)),
                  StatusPill(switch (_stateOf(selDriver)) { _DriverState.available => 'متاح', _DriverState.busy => 'مشغول', _DriverState.offline => 'غير متصل' },
                      tone: _stateOf(selDriver) == _DriverState.busy ? PillTone.info : PillTone.neutral),
                  IconButton(tooltip: 'إغلاق', onPressed: () => setState(() => _selDriverId = null), icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 4),
                Text('${selDriver.vehicleType.label}${selDriver.plate == null || selDriver.plate!.isEmpty ? '' : ' · ${selDriver.plate}'}', style: WText.small),
                const SizedBox(height: 8),
                FreshnessBadge(at: selDriver.lastSeenAt, now: now),
                if (selDriverOrder != null) ...[
                  const SizedBox(height: 8),
                  Text('الطلب الجاري: ${selDriverOrder.code} · ${selDriverOrder.merchantName ?? ''}', style: WText.small),
                ],
              ]),
            ),
          )
        else if (_selText != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset,
            child: WCard(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_selText!, style: WText.bodyStrong)),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => setState(() {
                      _selText = null;
                      _selOrder = null;
                      _routePts = null;
                      _routeRes = null;
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                if (_selOrder != null && _routeRes != null) ...[
                  const SizedBox(height: 4),
                  Text('${kmAr(_routeRes!.distanceKm)} · ${_routeRes!.minutes.ceil()} د ${_routeRes!.isEstimate ? '(تقريبي — خط مستقيم)' : '(حسب الطرق)'}', style: WText.small),
                ],
              ]),
            ),
          ),
        if (d != null && drivers.isEmpty && _on.contains(_Layer.drivers) && _selText == null && _selDriverId == null)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset,
            child: WCard(child: Text('ما اكو سائقين أرسلوا موقعهم خلال آخر 30 دقيقة.', style: WText.small)),
          ),
        if (_loadedAt != null && _selDriverId == null && _selText == null)
          Positioned(
            left: 16,
            bottom: bottomInset + 4,
            child: Text('تحديث الطلبات والمحلات: ${timeAr(_loadedAt!)}', style: WText.caption.copyWith(color: WColors.ink)),
          ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(WRadius.md), border: Border.all(color: WColors.line)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$value', style: WText.bodyStrong.copyWith(color: color)),
            Text(label, style: WText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}
