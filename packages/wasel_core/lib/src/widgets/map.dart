import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location.dart';
import '../theme/tokens.dart';
import 'basics.dart';

/// علامة على الخريطة
class WMarker {
  const WMarker(this.point, {this.kind = WMarkerKind.place, this.label});
  final LatLng point;
  final WMarkerKind kind;
  final String? label;
}

enum WMarkerKind { place, store, home, driver, pickup, dropoff }

/// خريطة OpenStreetMap مجانية. [fitAll] يوسّط الخريطة على كل العلامات.
class WMap extends StatefulWidget {
  const WMap({super.key, this.markers = const [], this.route, this.center, this.zoom = 14.5, this.fitAll = true, this.interactive = true, this.controller});
  final List<WMarker> markers;
  final List<LatLng>? route;
  final LatLng? center;
  final double zoom;
  final bool fitAll;
  final bool interactive;
  final MapController? controller;

  @override
  State<WMap> createState() => _WMapState();
}

class _WMapState extends State<WMap> {
  late final MapController _c = widget.controller ?? MapController();
  bool _fitted = false;

  void _fit() {
    final pts = widget.markers.map((m) => m.point).toList();
    if (!widget.fitAll || pts.length < 2) return;
    _c.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.fromLTRB(60, 80, 60, 80), maxZoom: 16.5));
  }

  @override
  void didUpdateWidget(covariant WMap old) {
    super.didUpdateWidget(old);
    // نعيد التوسيط فقط إذا تغيّر عدد العلامات (مثلاً ظهر السائق)
    if (old.markers.length != widget.markers.length) WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.center ?? (widget.markers.isNotEmpty ? widget.markers.first.point : kDefaultCenter);
    return FlutterMap(
      mapController: _c,
      options: MapOptions(
        initialCenter: center,
        initialZoom: widget.zoom,
        interactionOptions: InteractionOptions(flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
        onMapReady: () {
          if (!_fitted) {
            _fitted = true;
            _fit();
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'iq.wasel.app',
          maxNativeZoom: 19,
        ),
        if (widget.route != null && widget.route!.length >= 2)
          PolylineLayer(polylines: [
            Polyline(points: widget.route!, strokeWidth: 5, color: WColors.navy.withValues(alpha: 0.75), strokeCap: StrokeCap.round, strokeJoin: StrokeJoin.round),
          ]),
        MarkerLayer(markers: [
          for (final m in widget.markers)
            Marker(point: m.point, width: 46, height: 46, alignment: Alignment.center, child: _MarkerDot(kind: m.kind)),
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')], alignment: AttributionAlignment.bottomLeft),
      ],
    );
  }
}

class _MarkerDot extends StatelessWidget {
  const _MarkerDot({required this.kind});
  final WMarkerKind kind;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (kind) {
      WMarkerKind.store => (WColors.navy, Icons.storefront_rounded),
      WMarkerKind.home => (WColors.mintDeep, Icons.home_rounded),
      WMarkerKind.driver => (WColors.coral, Icons.two_wheeler_rounded),
      WMarkerKind.pickup => (WColors.navy, Icons.trip_origin_rounded),
      WMarkerKind.dropoff => (WColors.coral, Icons.flag_rounded),
      WMarkerKind.place => (WColors.navy, Icons.place_rounded),
    };
    return Center(
      child: Container(
        width: kind == WMarkerKind.driver ? 42 : 36,
        height: kind == WMarkerKind.driver ? 42 : 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: WColors.white, width: 3),
          boxShadow: WShadow.soft,
        ),
        child: Icon(icon, color: WColors.white, size: 18),
      ),
    );
  }
}

/// شاشة اختيار موقع: الخريطة تتحرك والدبوس ثابت بالوسط.
/// ترجّع LatLng عند التأكيد.
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key, this.initial, this.title = 'حدّد الموقع', this.confirmLabel = 'تأكيد الموقع'});
  final LatLng? initial;
  final String title;
  final String confirmLabel;

  static Future<LatLng?> open(BuildContext context, {LatLng? initial, String title = 'حدّد الموقع', String confirmLabel = 'تأكيد الموقع'}) =>
      Navigator.of(context).push<LatLng>(MaterialPageRoute(builder: (_) => LocationPickerPage(initial: initial, title: title, confirmLabel: confirmLabel)));

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final _map = MapController();
  late LatLng _center = widget.initial ?? kDefaultCenter;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final r = await currentLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (r.position != null) {
      _map.move(r.position!, 17);
      setState(() => _center = r.position!);
    } else {
      showError(context, r.error!);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.initial == null ? 12 : 17,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onPositionChanged: (cam, _) => _center = cam.center,
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'iq.wasel.app'),
              const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')], alignment: AttributionAlignment.bottomLeft),
            ],
          ),
          // الدبوس الثابت بالوسط
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 44),
                child: Icon(Icons.location_on_rounded, size: 52, color: WColors.coral, shadows: [Shadow(color: Color(0x55000000), blurRadius: 10)]),
              ),
            ),
          ),
          PositionedDirectional(
            end: 16,
            bottom: 120,
            child: WIconButton(_locating ? Icons.more_horiz_rounded : Icons.my_location_rounded, onPressed: _locating ? null : _locate, tooltip: 'موقعي'),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: WButton(widget.confirmLabel, icon: Icons.check_rounded, onPressed: () => Navigator.pop(context, _center)),
            ),
          ),
        ]),
      );
}
