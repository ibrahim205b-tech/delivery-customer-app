import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

enum _Layer { drivers, orders, merchants, areas }

/// خريطة العمليات للإدارة: السائقون (آخر موقع)، الطلبات الجارية، المحلات، مناطق الخدمة.
/// تتحدّث كل 20 ثانية.
class OpsMapScreen extends StatefulWidget {
  const OpsMapScreen({super.key});
  @override
  State<OpsMapScreen> createState() => _OpsMapScreenState();
}

class _OpsMapScreenState extends State<OpsMapScreen> {
  final Set<_Layer> _on = {..._Layer.values};
  ({List<Driver> drivers, List<Order> activeOrders, List<Merchant> merchants, List<ServiceArea> areas})? _d;
  Object? _error;
  Timer? _timer;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await adminApi.opsMap();
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final fresh = d?.drivers.where((x) => x.lastSeenAt != null && DateTime.now().difference(x.lastSeenAt!).inMinutes < 30).toList() ?? [];
    final markers = <WMarker>[
      if (d != null && _on.contains(_Layer.merchants))
        for (final m in d.merchants) WMarker(LatLng(m.lat, m.lng), kind: WMarkerKind.store, icon: categoryIcon(m.categoryId), onTap: () => setState(() => _selected = '🏪 ${m.name} · ${m.phone}')),
      if (d != null && _on.contains(_Layer.orders))
        for (final o in d.activeOrders)
          WMarker(LatLng(o.addressLat, o.addressLng), kind: WMarkerKind.home, onTap: () => setState(() => _selected = '${o.code} · ${o.merchantName ?? ''} · ${o.status.label}')),
      if (d != null && _on.contains(_Layer.drivers))
        for (final x in fresh)
          WMarker(
            LatLng(x.lastLat!, x.lastLng!),
            kind: switch (x.vehicleType) { VehicleType.taxi => WMarkerKind.taxi, VehicleType.tuktuk => WMarkerKind.tuktuk, VehicleType.courier => WMarkerKind.courier },
            onTap: () => setState(() => _selected = '${x.fullName ?? ''} · ${x.vehicleType.label} · ${x.isAvailable ? 'متاح' : 'غير متاح'} · آخر ظهور ${relativeAr(x.lastSeenAt!)}'),
          ),
    ];
    final areas = d == null || !_on.contains(_Layer.areas) ? <WArea>[] : [for (final a in d.areas) WArea(LatLng(a.centerLat, a.centerLng), a.radiusKm, label: a.name, active: a.isActive)];

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: WMap(markers: markers, areas: areas, zoom: 12, padding: const EdgeInsets.fromLTRB(40, 140, 40, 160))),
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
                    if (d == null && _error == null) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: WColors.lime)),
                    if (d != null) Text('${fresh.length} سائق · ${d.activeOrders.length} طلب', style: WText.caption.copyWith(color: WColors.lime)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 10),
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
          ]),
        ),
        if (_error != null)
          Positioned(left: 16, right: 16, bottom: 24, child: WCard(color: WColors.dangerSoft, borderColor: Colors.transparent, child: Text(friendlyError(_error!), style: WText.small.copyWith(color: WColors.danger)))),
        if (_selected != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            child: WCard(
              child: Row(children: [
                Expanded(child: Text(_selected!.replaceAll('🏪 ', ''), style: WText.bodyStrong)),
                IconButton(tooltip: 'إغلاق', onPressed: () => setState(() => _selected = null), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
          ),
        if (d != null && fresh.isEmpty && _on.contains(_Layer.drivers) && _selected == null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            child: WCard(child: Text('ما اكو سائقين ظهروا خلال آخر 30 دقيقة.', style: WText.small)),
          ),
      ]),
    );
  }
}
