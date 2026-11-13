import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import 'errand.dart';

/// طلب رحلة تكسي/تكتك: انطلاق، وجهة، نوع المركبة، الأجرة التقديرية.
class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({super.key, required this.vehicle, this.destination});
  final VehicleType vehicle;

  /// وجهة معبّأة مسبقاً (من الوجهات المتكررة بالرئيسية)
  final RideDestination? destination;
  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  late VehicleType _vehicle = widget.vehicle;
  final _pickup = PointValue(label: 'موقعي الحالي');
  late final _dropoff = widget.destination == null ? PointValue() : PointValue(point: LatLng(widget.destination!.lat, widget.destination!.lng), label: widget.destination!.text);
  List<RideDestination> _frequent = const [];
  ({double distanceKm, int fare})? _estimate;
  Object? _estimateError;
  bool _sending = false;
  RouteResult? _route;

  @override
  void initState() {
    super.initState();
    _useMyLocation();
    if (widget.destination == null) {
      customerApi.rideDestinations().then((list) {
        if (mounted) setState(() => _frequent = list);
      }, onError: (_) {});
    }
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
    geoApi.route(p, d).then((r) {
      if (mounted) setState(() => _route = r);
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
          ], route: p != null && d != null ? (_route?.points ?? [p, d]) : null, routeDashed: _route?.isEstimate ?? true),
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
            if (d == null && _frequent.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('وجهاتك المتكررة', style: WText.overline),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in _frequent)
                  ActionChip(
                    avatar: Icon(Icons.history_rounded, size: 18, color: WColors.fg),
                    label: Text(f.text, style: WText.label),
                    onPressed: () {
                      setState(() {
                        _dropoff.point = LatLng(f.lat, f.lng);
                        _dropoff.label = f.text;
                      });
                      _estimateFare();
                    },
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            if (p != null && d != null)
              WCard(
                color: WColors.night,
                borderColor: WColors.night,
                child: _estimateError != null
                    ? Text(friendlyError(_estimateError!), style: WText.body.copyWith(color: WColors.white))
                    : _estimate == null
                        ? const LinearProgressIndicator()
                        : Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('الأجرة التقديرية', style: WText.caption.copyWith(color: WColors.inkFaint)),
                                Text(iqd(_estimate!.fare), style: WText.number.copyWith(fontSize: 26, color: WColors.lime)),
                              ]),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(_route == null || _route!.isEstimate ? 'المسافة' : 'الطريق', style: WText.caption.copyWith(color: WColors.inkFaint)),
                              Text(kmAr(_route != null && !_route!.isEstimate ? _route!.distanceKm : _estimate!.distanceKm), style: WText.h3.copyWith(color: WColors.white)),
                              if (_route != null && !_route!.isEstimate) Text('~${_route!.minutes.ceil()} دقيقة', style: WText.caption.copyWith(color: WColors.lime)),
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
                  if (r.driverLat != null && r.status.isActive) WMarker(LatLng(r.driverLat!, r.driverLng!), kind: r.vehicle == VehicleType.tuktuk ? WMarkerKind.tuktuk : WMarkerKind.taxi),
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
                        CircleAvatar(radius: 24, backgroundColor: WColors.limeSoft, child: Icon(Icons.person_rounded, color: WColors.link)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.driverName!, style: WText.bodyStrong),
                            Text((r.driverVehicle ?? '').isEmpty ? r.vehicle.label : r.driverVehicle!, style: WText.small),
                          ]),
                        ),
                        if ((r.driverPhone ?? '').isNotEmpty && r.status.isActive)
                          WIconButton(Icons.call_rounded, background: WColors.success, color: WColors.white, tooltip: 'اتصال بالسائق', onPressed: () => callPhone(r.driverPhone!)),
                      ]),
                    ),
                  if (r.driverName != null && r.status.isActive) ...[
                    const SizedBox(height: 10),
                    WButton('شارك رحلتك ويا أهلك', kind: WButtonKind.secondary, icon: Icons.shield_outlined, onPressed: () => _shareRide(context, r)),
                  ],
                  if (r.status == RideStatus.completed && r.driverId != null) ...[
                    const SizedBox(height: 12),
                    if (r.rating == null)
                      _RideRateCard(rideId: r.id, driverName: r.driverName ?? 'السائق')
                    else
                      WCard(
                        child: Row(children: [
                          Expanded(child: Text('تقييمك للسائق', style: WText.bodyStrong)),
                          for (var i = 1; i <= 5; i++) Icon(i <= r.rating! ? Icons.star_rounded : Icons.star_outline_rounded, size: 22, color: i <= r.rating! ? WColors.fg : WColors.inkFaint),
                        ]),
                      ),
                  ],
                  const SizedBox(height: 12),
                  WCard(
                    child: Column(children: [
                      InfoRow(icon: Icons.trip_origin_rounded, text: r.pickupText, color: WColors.fg),
                      const SizedBox(height: 8),
                      InfoRow(icon: Icons.flag_rounded, text: r.dropoffText, color: WColors.blue),
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

/// يشارك تفاصيل الرحلة (السائق، المركبة، المسار، موقع حي) بالواتساب، وإذا ما انفتح ينسخها.
Future<void> _shareRide(BuildContext context, Ride r) async {
  final at = r.driverLat != null ? mapLinkFor(r.driverLat!, r.driverLng!) : mapLinkFor(r.pickupLat, r.pickupLng);
  final text = [
    'أنا برحلة ${r.vehicle.label} ويا واصل.',
    'السائق: ${r.driverName ?? ''}${(r.driverVehicle ?? '').isEmpty ? '' : ' · ${r.driverVehicle}'}',
    if ((r.driverPhone ?? '').isNotEmpty) 'رقمه: ${r.driverPhone}',
    'من: ${r.pickupText}',
    'إلى: ${r.dropoffText}',
    'آخر موقع: $at',
  ].join('\n');
  final ok = await shareViaWhatsapp(text).then((v) => v, onError: (_) => false);
  if (ok) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showInfo(context, 'ما انفتح واتساب، فنسخنا تفاصيل الرحلة. الصقها بأي محادثة');
}

/// تقييم السائق بعد نهاية الرحلة
class _RideRateCard extends StatefulWidget {
  const _RideRateCard({required this.rideId, required this.driverName});
  final String rideId;
  final String driverName;
  @override
  State<_RideRateCard> createState() => _RideRateCardState();
}

class _RideRateCardState extends State<_RideRateCard> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _busy = false;
  bool _ok = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WCard(
        child: Column(children: [
          Text('شلون كانت رحلتك ويا ${widget.driverName}؟', style: WText.h3, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i من 5',
                onPressed: () => setState(() => _stars = i),
                icon: AnimatedScale(
                  scale: i <= _stars ? 1.1 : 1,
                  duration: WDurations.fast,
                  child: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= _stars ? WColors.fg : WColors.inkFaint, size: 34),
                ),
              ),
          ]),
          TextField(controller: _comment, maxLength: 500, decoration: const InputDecoration(hintText: 'ملاحظاتك (اختياري)', counterText: '')),
          const SizedBox(height: 10),
          WButton('إرسال التقييم', loading: _busy, success: _ok, onPressed: _stars == 0
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await runAction(context, () => customerApi.rateRide(widget.rideId, _stars, _comment.text.trim()), success: 'شكراً لتقييمك');
                  if (!mounted) return;
                  setState(() {
                    _busy = false;
                    _ok = ok;
                  });
                }),
        ]),
      );
}
