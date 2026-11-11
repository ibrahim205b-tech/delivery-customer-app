import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import 'errand.dart';

/// طلب رحلة تكسي/تكتك: انطلاق، وجهة، نوع المركبة، الأجرة التقديرية.
class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({super.key, required this.vehicle});
  final VehicleType vehicle;
  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  late VehicleType _vehicle = widget.vehicle;
  final _pickup = PointValue(label: 'موقعي الحالي');
  final _dropoff = PointValue();
  ({double distanceKm, int fare})? _estimate;
  Object? _estimateError;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _useMyLocation();
  }

  Future<void> _useMyLocation() async {
    final r = await currentLocation();
    if (!mounted) return;
    if (r.position != null) {
      setState(() => _pickup.point = r.position);
      _estimateFare();
    } else {
      showError(context, r.error!);
    }
  }

  Future<void> _estimateFare() async {
    final p = _pickup.point, d = _dropoff.point;
    if (p == null || d == null) return;
    setState(() {
      _estimate = null;
      _estimateError = null;
    });
    try {
      final e = await customerApi.estimate(_vehicle.name, p.latitude, p.longitude, d.latitude, d.longitude);
      if (mounted) setState(() => _estimate = e);
    } catch (e) {
      if (mounted) setState(() => _estimateError = e);
    }
  }

  Future<void> _request() async {
    final p = _pickup.point, d = _dropoff.point;
    if (p == null || d == null) return showError(context, 'حدّد الانطلاق والوجهة.');
    setState(() => _sending = true);
    try {
      final ride = await customerApi.requestRide(
        vehicle: _vehicle,
        pickupText: _pickup.label.isEmpty ? 'نقطة الانطلاق' : _pickup.label,
        pLat: p.latitude,
        pLng: p.longitude,
        dropoffText: _dropoff.label.isEmpty ? 'الوجهة' : _dropoff.label,
        dLat: d.latitude,
        dLng: d.longitude,
      );
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: ride.id)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pickup.point, d = _dropoff.point;
    return Scaffold(
      appBar: AppBar(title: Text('اطلب ${_vehicle.label}')),
      body: Column(children: [
        SizedBox(
          height: 220,
          child: WMap(markers: [
            if (p != null) WMarker(p, kind: WMarkerKind.pickup),
            if (d != null) WMarker(d, kind: WMarkerKind.dropoff),
          ], route: p != null && d != null ? [p, d] : null),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
            SegmentedButton<VehicleType>(
              segments: const [
                ButtonSegment(value: VehicleType.taxi, label: Text('تكسي'), icon: Icon(Icons.local_taxi_rounded)),
                ButtonSegment(value: VehicleType.tuktuk, label: Text('تكتك'), icon: Icon(Icons.electric_rickshaw_rounded)),
              ],
              selected: {_vehicle},
              onSelectionChanged: (s) {
                setState(() => _vehicle = s.first);
                _estimateFare();
              },
            ),
            const SizedBox(height: 16),
            PointField(title: 'من وين؟', value: _pickup, kind: WMarkerKind.pickup, onChanged: () {
              setState(() {});
              _estimateFare();
            }, trailing: TextButton.icon(onPressed: _useMyLocation, icon: const Icon(Icons.my_location_rounded, size: 18), label: const Text('موقعي'))),
            const SizedBox(height: 10),
            PointField(title: 'لوين؟', value: _dropoff, kind: WMarkerKind.dropoff, onChanged: () {
              setState(() {});
              _estimateFare();
            }),
            const SizedBox(height: 16),
            if (p != null && d != null)
              WCard(
                color: WColors.navy,
                borderColor: WColors.navy,
                child: _estimateError != null
                    ? Text(friendlyError(_estimateError!), style: WText.body.copyWith(color: WColors.white))
                    : _estimate == null
                        ? const LinearProgressIndicator()
                        : Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('الأجرة التقديرية', style: WText.caption.copyWith(color: WColors.mint)),
                                Text(iqd(_estimate!.fare), style: WText.h1.copyWith(color: WColors.white)),
                              ]),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('المسافة', style: WText.caption.copyWith(color: WColors.mint)),
                              Text(kmAr(_estimate!.distanceKm), style: WText.h3.copyWith(color: WColors.white)),
                            ]),
                          ]),
              ),
            const SizedBox(height: 8),
            Text('الدفع نقداً للسائق عند الوصول.', style: WText.small),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: WButton('اطلب ${_vehicle.label}', icon: Icons.near_me_rounded, onPressed: p == null || d == null ? null : _request, loading: _sending),
          ),
        ),
      ]),
    );
  }
}

/// متابعة الرحلة لحظياً
class RideTrackingScreen extends StatelessWidget {
  const RideTrackingScreen({super.key, required this.rideId});
  final String rideId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('رحلتك')),
        body: StreamBuilder<Ride?>(
          stream: customerApi.watchRide(rideId),
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!);
            final r = s.data;
            if (r == null) return const LoadingView(message: 'نحمّل الرحلة…');
            final step = switch (r.status) {
              RideStatus.requested => 0,
              RideStatus.accepted || RideStatus.arrived => 1,
              RideStatus.inProgress => 2,
              RideStatus.completed => 3,
              RideStatus.cancelled => -1,
            };
            return Column(children: [
              SizedBox(
                height: 260,
                child: WMap(markers: [
                  WMarker(LatLng(r.pickupLat, r.pickupLng), kind: WMarkerKind.pickup),
                  WMarker(LatLng(r.dropoffLat, r.dropoffLng), kind: WMarkerKind.dropoff),
                  if (r.driverLat != null && r.status.isActive) WMarker(LatLng(r.driverLat!, r.driverLng!), kind: WMarkerKind.driver),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
                  Text(r.status.label, style: WText.h1),
                  if (r.status == RideStatus.requested) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text('طلبك وصل للسائقين القريبين المتاحين…', style: WText.small),
                  ],
                  if (r.status != RideStatus.cancelled) ...[
                    const SizedBox(height: 14),
                    StepProgress(steps: const ['طلب', 'السائق جاي', 'بالطريق', 'وصلت'], current: step),
                  ],
                  const SizedBox(height: 16),
                  if (r.driverName != null)
                    WCard(
                      child: Row(children: [
                        const CircleAvatar(radius: 24, backgroundColor: WColors.coralSoft, child: Icon(Icons.person_rounded, color: WColors.coralDeep)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.driverName!, style: WText.bodyStrong),
                            Text((r.driverVehicle ?? '').isEmpty ? r.vehicle.label : r.driverVehicle!, style: WText.small),
                          ]),
                        ),
                        if ((r.driverPhone ?? '').isNotEmpty && r.status.isActive)
                          WIconButton(Icons.call_rounded, background: WColors.mintDeep, color: WColors.white, onPressed: () => callPhone(r.driverPhone!)),
                      ]),
                    ),
                  const SizedBox(height: 12),
                  WCard(
                    child: Column(children: [
                      InfoRow(icon: Icons.trip_origin_rounded, text: r.pickupText, color: WColors.navy),
                      const SizedBox(height: 8),
                      InfoRow(icon: Icons.flag_rounded, text: r.dropoffText, color: WColors.coralDeep),
                      const Divider(height: 22),
                      Row(children: [
                        Expanded(child: Text('${r.vehicle.label} · ${kmAr(r.distanceKm)}', style: WText.small)),
                        Text(iqd(r.fare), style: WText.price),
                      ]),
                    ]),
                  ),
                  if (r.status == RideStatus.requested || r.status == RideStatus.accepted || r.status == RideStatus.arrived) ...[
                    const SizedBox(height: 16),
                    WButton('إلغاء الرحلة', kind: WButtonKind.danger, onPressed: () async {
                      if (await confirmDialog(context, title: 'إلغاء الرحلة؟', confirm: 'إلغاء', danger: true) && context.mounted) {
                        await runAction(context, () => customerApi.cancelRide(r.id), success: 'انلغت الرحلة');
                      }
                    }),
                  ],
                ]),
              ),
            ]);
          },
        ),
      );
}
