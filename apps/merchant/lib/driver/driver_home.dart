import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';

/// لوحة السائق/المندوب: متاح أو لا، المهام المتاحة، المهمة الحالية، والسجل.
/// يرى فقط ما تسمح به سياسات الخادم لنوع مركبته (RLS).
class DriverHome extends StatefulWidget {
  const DriverHome({super.key});
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  Driver? _me;
  Object? _error;
  LatLng? _pos;
  Timer? _locTimer;
  bool _toggling = false;
  int _tab = 0;
  final Set<String> _hidden = {}; // مهام أخذها غيري
  Stream<List<DeliveryTask>>? _tasks;
  Stream<List<Ride>>? _rides;
  int _lastAvailableCount = -1;

  bool get _doesTasks => _me != null && _me!.vehicleType != VehicleType.taxi;
  bool get _doesRides => _me != null && _me!.vehicleType != VehicleType.courier;

  @override
  void initState() {
    super.initState();
    _load();
    notifier.requestPermission();
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await driverApi.me();
      setState(() {
        _me = me;
        _error = null;
        _tasks = driverApi.watchTasks().asBroadcastStream();
        _rides = driverApi.watchRides().asBroadcastStream();
      });
      if (me?.isAvailable == true) _startTracking();
    } catch (e) {
      setState(() => _error = e);
    }
  }

  void _startTracking() {
    _locTimer?.cancel();
    _sendLocation();
    _locTimer = Timer.periodic(const Duration(seconds: 15), (_) => _sendLocation());
  }

  Future<void> _sendLocation() async {
    final r = await currentLocation();
    if (r.position == null) return;
    if (mounted) setState(() => _pos = r.position);
    try {
      await driverApi.updateLocation(r.position!.latitude, r.position!.longitude);
    } catch (_) {
      // إذا انقطع النت نحاول بالدورة الجاية
    }
  }

  Future<void> _toggle(bool v) async {
    setState(() => _toggling = true);
    LatLng? p;
    if (v) {
      final r = await currentLocation();
      if (r.position == null) {
        if (mounted) showError(context, r.error!);
        setState(() => _toggling = false);
        return;
      }
      p = r.position;
      _pos = p;
    }
    try {
      final me = await driverApi.setAvailable(v, lat: p?.latitude, lng: p?.longitude);
      setState(() => _me = Driver(
            id: me.id, vehicleType: me.vehicleType, areaId: me.areaId, isActive: me.isActive, isAvailable: me.isAvailable,
            lastLat: me.lastLat, lastLng: me.lastLng, fullName: _me?.fullName, plate: _me?.plate, model: _me?.model, color: _me?.color,
          ));
      v ? _startTracking() : _locTimer?.cancel();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(body: ErrorView(error: _error!, onRetry: _load));
    if (_tasks == null) return const Scaffold(body: LoadingView());
    final me = _me;
    if (me == null || !me.isActive) {
      return Scaffold(
        body: EmptyView(
          icon: Icons.no_transfer_outlined,
          title: me == null ? 'حساب السائق غير مكتمل' : 'حساب السائق موقوف',
          message: 'تواصل مع دعم واصل.',
          action: Column(mainAxisSize: MainAxisSize.min, children: [
            const SupportContactButtons(),
            const SizedBox(height: 10),
            WButton('تسجيل الخروج', onPressed: auth.signOut, kind: WButtonKind.ghost, expand: false),
          ]),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(me),
          Expanded(child: _tab == 0 ? _jobs() : _history()),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route_rounded), label: 'المهام'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'السجل'),
        ],
      ),
    );
  }

  Widget _header(Driver me) => Container(
        margin: const EdgeInsets.all(WSpace.lg),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: me.isAvailable ? WColors.night : WColors.surface, borderRadius: WRadius.all(WRadius.xl), border: Border.all(color: me.isAvailable ? WColors.ink : WColors.line)),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: me.isAvailable ? WColors.blue : WColors.surfaceAlt,
            child: Icon(switch (me.vehicleType) { VehicleType.taxi => Icons.local_taxi_rounded, VehicleType.tuktuk => Icons.electric_rickshaw_rounded, VehicleType.courier => Icons.two_wheeler_rounded },
                color: me.isAvailable ? WColors.white : WColors.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me.isAvailable ? 'متاح للمهام' : 'غير متاح', style: WText.h3.copyWith(color: me.isAvailable ? WColors.white : WColors.fg)),
              Text([auth.profile?.fullName ?? '', me.vehicleType.label].join(' · '), style: WText.caption.copyWith(color: me.isAvailable ? WColors.lime : WColors.inkMuted)),
            ]),
          ),
          _toggling
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Switch(value: me.isAvailable, onChanged: _toggle),
          SupportIconButton(app: SupportApp.driver, color: me.isAvailable ? WColors.white : WColors.fg),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: me.isAvailable ? WColors.white : WColors.fg),
            onSelected: (v) async {
              if (v == 'theme') return showThemeSheet(context);
              if (v == 'out' && await confirmDialog(context, title: 'تسجيل الخروج؟', confirm: 'خروج')) {
                if (me.isAvailable) await driverApi.setAvailable(false).catchError((_) => me);
                await auth.signOut();
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'theme', child: Text('المظهر (نهاري / ليلي)')), PopupMenuItem(value: 'out', child: Text('تسجيل الخروج'))],
          ),
        ]),
      );

  // ---------------- المهام ----------------
  Widget _jobs() => StreamBuilder<List<DeliveryTask>>(
        stream: _doesTasks ? _tasks : Stream.value(const []),
        builder: (context, ts) => StreamBuilder<List<Ride>>(
          stream: _doesRides ? _rides : Stream.value(const []),
          builder: (context, rs) {
            if (ts.hasError) return ErrorView(error: ts.error!, onRetry: _load);
            if (rs.hasError) return ErrorView(error: rs.error!, onRetry: _load);
            if (!ts.hasData || !rs.hasData) return const SkeletonList();
            final uid = auth.userId;
            final myTask = ts.data!.where((t) => t.driverId == uid && t.status.isActive).firstOrNull;
            final myRide = rs.data!.where((r) => r.driverId == uid && r.status.isActive).firstOrNull;
            final availTasks = ts.data!.where((t) => t.status == TaskStatus.requested && t.driverId == null && !_hidden.contains(t.id)).toList();
            final availRides = rs.data!.where((r) => r.status == RideStatus.requested && r.driverId == null && !_hidden.contains(r.id)).toList();
            final count = availTasks.length + availRides.length;
            if (_lastAvailableCount >= 0 && count > _lastAvailableCount && _me!.isAvailable && myTask == null && myRide == null) {
              notifier.show('مهمة جديدة متاحة', 'افتح واصل شريك واقبلها قبل غيرك', channel: WChannel.orders);
            }
            _lastAvailableCount = count;

            if (myTask != null) return _ActiveTask(task: myTask, me: _pos, vehicle: _me!.vehicleType);
            if (myRide != null) return _ActiveRide(ride: myRide, me: _pos, vehicle: _me!.vehicleType);
            if (!_me!.isAvailable) {
              return const EmptyView(icon: Icons.toggle_off_outlined, title: 'شغّل "متاح" حتى تستلم مهام', message: 'موقعك يتحدّث كل 15 ثانية وأنت متاح.');
            }
            if (count == 0) {
              return const EmptyView(icon: Icons.radar_rounded, title: 'ماكو مهام هسه', message: 'أول ما يجي طلب يظهر هنا مع تنبيه.');
            }
            return ListView(padding: const EdgeInsets.fromLTRB(WSpace.lg, 0, WSpace.lg, 24), children: [
              Text('مهام متاحة ($count)', style: WText.h3),
              const SizedBox(height: 10),
              for (final r in availRides) ...[_offerRide(r), const SizedBox(height: 10)],
              for (final t in availTasks) ...[_offerTask(t), const SizedBox(height: 10)],
            ]);
          },
        ),
      );

  String? _distTo(double lat, double lng) => _pos == null ? null : kmAr(distanceKm(_pos!.latitude, _pos!.longitude, lat, lng));

  Future<void> _accept(String id, Future<void> Function() action) async {
    try {
      await action();
      HapticFeedback.mediumImpact();
    } catch (e) {
      final msg = friendlyError(e);
      if (msg.contains('سبقك')) setState(() => _hidden.add(id));
      if (mounted) showError(context, msg);
    }
  }

  Widget _offerTask(DeliveryTask t) => WCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusPill(t.kind.label, tone: PillTone.info),
            const Spacer(),
            Text(iqd(t.fee), style: WText.price.copyWith(fontSize: 18)),
          ]),
          const SizedBox(height: 10),
          InfoRow(icon: Icons.trip_origin_rounded, text: 'استلام: ${t.pickupText.isEmpty ? 'على الخريطة' : t.pickupText}${_distTo(t.pickupLat, t.pickupLng) == null ? '' : ' · يبعد ${_distTo(t.pickupLat, t.pickupLng)}'}', color: WColors.fg),
          const SizedBox(height: 4),
          InfoRow(icon: Icons.flag_rounded, text: 'تسليم: ${t.dropoffText.isEmpty ? 'على الخريطة' : t.dropoffText}', color: WColors.blue),
          if (t.description.isNotEmpty) ...[const SizedBox(height: 6), Text(t.description, style: WText.small, maxLines: 2, overflow: TextOverflow.ellipsis)],
          if (t.distanceKm != null) ...[const SizedBox(height: 4), Text('مسافة التوصيل ${kmAr(t.distanceKm!)}', style: WText.caption)],
          const SizedBox(height: 12),
          WButton('قبول المهمة', kind: WButtonKind.dark, icon: Icons.check_rounded, onPressed: () => _accept(t.id, () => driverApi.acceptTask(t.id))),
        ]),
      );

  Widget _offerRide(Ride r) => WCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusPill('رحلة ${r.vehicle.label}', tone: PillTone.accent),
            const Spacer(),
            Text(iqd(r.fare), style: WText.price.copyWith(fontSize: 18)),
          ]),
          const SizedBox(height: 10),
          InfoRow(icon: Icons.trip_origin_rounded, text: '${r.pickupText}${_distTo(r.pickupLat, r.pickupLng) == null ? '' : ' · يبعد ${_distTo(r.pickupLat, r.pickupLng)}'}', color: WColors.fg),
          const SizedBox(height: 4),
          InfoRow(icon: Icons.flag_rounded, text: '${r.dropoffText} · ${kmAr(r.distanceKm)}', color: WColors.blue),
          const SizedBox(height: 12),
          WButton('قبول الرحلة', kind: WButtonKind.dark, icon: Icons.check_rounded, onPressed: () => _accept(r.id, () => driverApi.acceptRide(r.id))),
        ]),
      );

  // ---------------- السجل ----------------
  Widget _history() => StreamBuilder<List<DeliveryTask>>(
        stream: _doesTasks ? _tasks : Stream.value(const []),
        builder: (context, ts) => StreamBuilder<List<Ride>>(
          stream: _doesRides ? _rides : Stream.value(const []),
          builder: (context, rs) {
            if (!ts.hasData || !rs.hasData) return const SkeletonList();
            final uid = auth.userId;
            final items = <(DateTime, String, String, int, bool)>[
              for (final t in ts.data!.where((t) => t.driverId == uid && !t.status.isActive))
                (t.createdAt, t.kind.label, t.dropoffText, t.fee, t.status == TaskStatus.delivered),
              for (final r in rs.data!.where((r) => r.driverId == uid && !r.status.isActive))
                (r.createdAt, 'رحلة ${r.vehicle.label}', r.dropoffText, r.fare, r.status == RideStatus.completed),
            ]..sort((a, b) => b.$1.compareTo(a.$1));
            if (items.isEmpty) return const EmptyView(icon: Icons.history_rounded, title: 'ما عندك مهام سابقة بعد');
            final today = DateTime.now();
            final todayTotal = items.where((e) => e.$5 && e.$1.year == today.year && e.$1.month == today.month && e.$1.day == today.day).fold<int>(0, (a, e) => a + e.$4);
            return ListView(padding: const EdgeInsets.fromLTRB(WSpace.lg, 0, WSpace.lg, 24), children: [
              WCard(
                color: WColors.successSoft,
                borderColor: Colors.transparent,
                child: Row(children: [
                  Expanded(child: Text('حصيلة اليوم (نقداً)', style: WText.bodyStrong)),
                  Text(iqd(todayTotal), style: WText.price.copyWith(fontSize: 18)),
                ]),
              ),
              const SizedBox(height: 10),
              for (final e in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(e.$5 ? Icons.check_circle_rounded : Icons.cancel_outlined, color: e.$5 ? WColors.success : WColors.inkFaint),
                  title: Text('${e.$2} · ${e.$3}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(dateTimeAr(e.$1)),
                  trailing: Text(iqd(e.$4), style: WText.bodyStrong),
                ),
            ]);
          },
        ),
      );
}

/// المهمة الحالية (توصيل طلب / مندوب / غرض)
class _ActiveTask extends StatelessWidget {
  const _ActiveTask({required this.task, required this.me, required this.vehicle});
  final DeliveryTask task;
  final LatLng? me;
  final VehicleType vehicle;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final goingToPickup = t.status == TaskStatus.assigned;
    final (label, next) = switch (t.status) {
      TaskStatus.assigned => ('استلمت الطلب', TaskStatus.pickedUp),
      TaskStatus.pickedUp => ('انطلقت للتسليم', TaskStatus.onTheWay),
      _ => ('تم التسليم', TaskStatus.delivered),
    };
    return ListView(padding: const EdgeInsets.fromLTRB(WSpace.lg, 0, WSpace.lg, 24), children: [
      ClipRRect(
        borderRadius: WRadius.all(WRadius.lg),
        child: SizedBox(
          height: 260,
          child: _RouteMap(
            pickup: LatLng(t.pickupLat, t.pickupLng),
            dropoff: LatLng(t.dropoffLat, t.dropoffLng),
            me: me,
            vehicle: vehicle,
            toPickup: goingToPickup,
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text(t.status.label, style: WText.h2)),
        StatusPill(t.kind.label, tone: PillTone.info),
      ]),
      const SizedBox(height: 12),
      _stop(context, 'الاستلام', t.pickupText, t.pickupLat, t.pickupLng, Icons.trip_origin_rounded, WColors.fg, active: goingToPickup),
      const SizedBox(height: 10),
      _stop(context, 'التسليم', t.dropoffText, t.dropoffLat, t.dropoffLng, Icons.flag_rounded, WColors.blue, active: !goingToPickup,
          phone: t.recipientPhone.isNotEmpty ? t.recipientPhone : t.customerPhone),
      const SizedBox(height: 12),
      WCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.itemType, style: WText.bodyStrong),
          if (t.description.isNotEmpty) Text(t.description, style: WText.small),
          if (t.notes.isNotEmpty) ...[const SizedBox(height: 6), InfoRow(icon: Icons.sticky_note_2_outlined, text: t.notes)],
          const Divider(height: 20),
          Row(children: [
            Expanded(child: Text('الزبون: ${t.customerName}', style: WText.small)),
            if (t.customerPhone.isNotEmpty) TextButton.icon(onPressed: () => callPhone(t.customerPhone), icon: const Icon(Icons.call_outlined, size: 18), label: const Text('اتصال')),
          ]),
          Row(children: [Expanded(child: Text('الأجرة (نقداً)', style: WText.bodyStrong)), Text(iqd(t.fee), style: WText.price)]),
        ]),
      ),
      const SizedBox(height: 16),
      WButton(label, icon: Icons.arrow_back_rounded, onPressed: () async {
        if (next == TaskStatus.delivered && !await confirmDialog(context, title: 'تأكيد التسليم؟', message: 'تأكد إنك سلّمت واستلمت المبلغ.', confirm: 'تم التسليم')) return;
        if (context.mounted) await runAction(context, () => driverApi.updateTask(t.id, next), success: next == TaskStatus.delivered ? 'أحسنت! انتهت المهمة' : null);
      }),
      if (t.status == TaskStatus.assigned) ...[
        const SizedBox(height: 8),
        WButton('التخلي عن المهمة', kind: WButtonKind.ghost, onPressed: () async {
          if (await confirmDialog(context, title: 'تتخلى عن المهمة؟', message: 'ترجع متاحة لباقي المندوبين.', confirm: 'نعم', danger: true) && context.mounted) {
            await runAction(context, () => driverApi.releaseTask(t.id));
          }
        }),
      ],
    ]);
  }
}

/// الرحلة الحالية (تكسي / تكتك)
class _ActiveRide extends StatelessWidget {
  const _ActiveRide({required this.ride, required this.me, required this.vehicle});
  final Ride ride;
  final LatLng? me;
  final VehicleType vehicle;

  @override
  Widget build(BuildContext context) {
    final r = ride;
    final (label, next) = switch (r.status) {
      RideStatus.accepted => ('وصلت لمكان الزبون', RideStatus.arrived),
      RideStatus.arrived => ('بدء الرحلة', RideStatus.inProgress),
      _ => ('إنهاء الرحلة', RideStatus.completed),
    };
    return ListView(padding: const EdgeInsets.fromLTRB(WSpace.lg, 0, WSpace.lg, 24), children: [
      ClipRRect(
        borderRadius: WRadius.all(WRadius.lg),
        child: SizedBox(
          height: 260,
          child: _RouteMap(
            pickup: LatLng(r.pickupLat, r.pickupLng),
            dropoff: LatLng(r.dropoffLat, r.dropoffLng),
            me: me,
            vehicle: vehicle,
            toPickup: r.status != RideStatus.inProgress,
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(r.status.label, style: WText.h2),
      const SizedBox(height: 12),
      _stop(context, 'الانطلاق', r.pickupText, r.pickupLat, r.pickupLng, Icons.trip_origin_rounded, WColors.fg,
          active: r.status != RideStatus.inProgress, phone: r.customerPhone),
      const SizedBox(height: 10),
      _stop(context, 'الوجهة', r.dropoffText, r.dropoffLat, r.dropoffLng, Icons.flag_rounded, WColors.blue, active: r.status == RideStatus.inProgress),
      const SizedBox(height: 12),
      WCard(
        child: Row(children: [
          Expanded(child: Text('${r.customerName} · ${kmAr(r.distanceKm)}', style: WText.body)),
          Text(iqd(r.fare), style: WText.price.copyWith(fontSize: 18)),
        ]),
      ),
      const SizedBox(height: 16),
      WButton(label, onPressed: () => runAction(context, () => driverApi.updateRide(r.id, next), success: next == RideStatus.completed ? 'انتهت الرحلة · استلم ${iqd(r.fare)}' : null)),
      if (r.status != RideStatus.inProgress) ...[
        const SizedBox(height: 8),
        WButton('إلغاء الرحلة', kind: WButtonKind.ghost, onPressed: () async {
          if (await confirmDialog(context, title: 'إلغاء الرحلة؟', confirm: 'إلغاء', danger: true) && context.mounted) {
            await runAction(context, () => driverApi.updateRide(r.id, RideStatus.cancelled));
          }
        }),
      ],
    ]);
  }
}

Widget _stop(BuildContext context, String title, String text, double lat, double lng, IconData icon, Color color, {required bool active, String? phone}) => WCard(
      borderColor: active ? color : WColors.line,
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: WText.caption),
            Text(text.isEmpty ? 'نقطة على الخريطة' : text, style: WText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (phone != null && phone.isNotEmpty) WIconButton(Icons.call_outlined, background: WColors.surfaceAlt, onPressed: () => callPhone(phone)),
        const SizedBox(width: 6),
        WIconButton(Icons.navigation_rounded, background: active ? color : WColors.surfaceAlt, color: active ? WColors.white : WColors.fg, tooltip: 'افتح بالخرائط', onPressed: () => openInMaps(lat, lng, label: title)),
      ]),
    );


/// خريطة المهمة مع مسار الطريق: من موقعي للاستلام، أو من الاستلام للتسليم.
/// المسار من خدمة التوجيه (OSRM افتراضياً)؛ إذا فشلت يُرسم خط تقديري منقّط.
class _RouteMap extends StatefulWidget {
  const _RouteMap({required this.pickup, required this.dropoff, required this.me, required this.vehicle, required this.toPickup});
  final LatLng pickup;
  final LatLng dropoff;
  final LatLng? me;
  final VehicleType vehicle;
  final bool toPickup;
  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  RouteResult? _route;
  LatLng? _from;
  bool? _leg;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _RouteMap old) {
    super.didUpdateWidget(old);
    _fetch();
  }

  Future<void> _fetch() async {
    final from = widget.toPickup ? (widget.me ?? widget.pickup) : widget.pickup;
    final to = widget.toPickup ? widget.pickup : widget.dropoff;
    // لا نعيد الطلب إلا إذا تغيّرت المرحلة أو تحركت أكثر من 150 م
    if (_leg == widget.toPickup && _from != null && distanceKm(_from!.latitude, _from!.longitude, from.latitude, from.longitude) < 0.15) return;
    _from = from;
    _leg = widget.toPickup;
    if (from == to) return;
    final r = await geoApi.route(from, to);
    if (mounted) setState(() => _route = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _route;
    return Stack(children: [
      Positioned.fill(
        child: WMap(
          markers: [
            WMarker(widget.pickup, kind: WMarkerKind.pickup),
            WMarker(widget.dropoff, kind: WMarkerKind.dropoff),
            if (widget.me != null)
              WMarker(widget.me!, kind: switch (widget.vehicle) { VehicleType.taxi => WMarkerKind.taxi, VehicleType.tuktuk => WMarkerKind.tuktuk, VehicleType.courier => WMarkerKind.courier }),
          ],
          route: r?.points,
          routeDashed: r?.isEstimate ?? false,
        ),
      ),
      if (r != null)
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: WColors.night, borderRadius: WRadius.all(WRadius.sm)),
            child: Text('${r.isEstimate ? '≈ ' : ''}${kmAr(r.distanceKm)} · ${r.minutes.ceil()} د', style: WText.label.copyWith(color: WColors.lime)),
          ),
        ),
    ]);
  }
}
