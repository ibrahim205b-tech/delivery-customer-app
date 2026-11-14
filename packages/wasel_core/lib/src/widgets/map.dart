import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/geo.dart';
import '../services/location.dart';
import '../theme/tokens.dart';
import 'basics.dart';

/// أنواع العلامات على خرائط واصل
enum WMarkerKind { place, store, home, pickup, dropoff, courier, taxi, tuktuk, me }

class WMarker {
  const WMarker(this.point, {this.kind = WMarkerKind.place, this.label, this.icon, this.onTap});
  final LatLng point;
  final WMarkerKind kind;
  final String? label;
  final IconData? icon; // مثلاً أيقونة قسم المحل
  final VoidCallback? onTap;

  /// للتوافق: كان اسمه driver
  static const driver = WMarkerKind.courier;
}

/// دائرة منطقة خدمة
class WArea {
  const WArea(this.center, this.radiusKm, {this.label, this.active = true});
  final LatLng center;
  final double radiusKm;
  final String? label;
  final bool active;
}

/// تلوين البلاطات بهوية واصل: تقليل التشبع + دفء ورقي خفيف، فتطلع الطرق واضحة والألوان هادئة.
const _brandTint = ColorFilter.matrix([
  0.42, 0.50, 0.08, 0, 14, //
  0.36, 0.56, 0.08, 0, 12,
  0.34, 0.50, 0.16, 0, 6,
  0, 0, 0, 1, 0,
]);

Widget _tile(BuildContext context, Widget tileWidget, TileImage tile) =>
    MapConfig.tintTiles ? ColorFiltered(colorFilter: _brandTint, child: tileWidget) : tileWidget;

TileLayer wTileLayer() => TileLayer(
      urlTemplate: MapConfig.tileUrl,
      userAgentPackageName: 'iq.wasel.app',
      maxNativeZoom: 19,
      tileBuilder: _tile,
    );

/// خريطة واصل. [fitAll] يوسّط الخريطة على كل العلامات. [etaLabel] فقاعة وقت فوق آخر نقطة بالمسار.
class WMap extends StatefulWidget {
  const WMap({
    super.key,
    this.markers = const [],
    this.route,
    this.areas = const [],
    this.center,
    this.zoom = 14.5,
    this.fitAll = true,
    this.interactive = true,
    this.controller,
    this.padding = const EdgeInsets.fromLTRB(60, 90, 60, 90),
    this.routeDashed = false,
  });
  final List<WMarker> markers;
  final List<LatLng>? route;
  final List<WArea> areas;
  final LatLng? center;
  final double zoom;
  final bool fitAll;
  final bool interactive;
  final MapController? controller;
  final EdgeInsets padding;
  final bool routeDashed;

  @override
  State<WMap> createState() => _WMapState();
}

class _WMapState extends State<WMap> {
  late final MapController _c = widget.controller ?? MapController();
  bool _ready = false;

  void _fit() {
    if (!_ready || !widget.fitAll) return;
    final pts = [...widget.markers.map((m) => m.point), ...?widget.route];
    if (pts.length < 2) return;
    _c.fitCamera(CameraFit.coordinates(coordinates: pts, padding: widget.padding, maxZoom: 16.5));
  }

  @override
  void didUpdateWidget(covariant WMap old) {
    super.didUpdateWidget(old);
    if (old.markers.length != widget.markers.length || (old.route?.length ?? 0) != (widget.route?.length ?? 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.center ?? (widget.markers.isNotEmpty ? widget.markers.first.point : kDefaultCenter);
    return ClipRect(
      child: FlutterMap(
        mapController: _c,
        options: MapOptions(
          initialCenter: center,
          initialZoom: widget.zoom,
          backgroundColor: WColors.surfaceAlt,
          interactionOptions: InteractionOptions(flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
          onMapReady: () {
            _ready = true;
            _fit();
          },
        ),
        children: [
          wTileLayer(),
          if (widget.areas.isNotEmpty)
            CircleLayer(circles: [
              for (final a in widget.areas)
                CircleMarker(
                  point: a.center,
                  radius: a.radiusKm * 1000,
                  useRadiusInMeter: true,
                  color: (a.active ? WColors.blue : WColors.inkFaint).withValues(alpha: 0.08),
                  borderColor: (a.active ? WColors.blue : WColors.inkFaint).withValues(alpha: 0.7),
                  borderStrokeWidth: 2,
                ),
            ]),
          if (widget.route != null && widget.route!.length >= 2)
            PolylineLayer(polylines: [
              Polyline(
                points: widget.route!,
                strokeWidth: 6,
                color: WColors.blue,
                borderStrokeWidth: 2.5,
                borderColor: WColors.ink.withValues(alpha: 0.35),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
                pattern: widget.routeDashed ? StrokePattern.dashed(segments: const [10, 8]) : const StrokePattern.solid(),
              ),
            ]),
          MarkerLayer(markers: [
            for (final m in widget.markers)
              Marker(
                point: m.point,
                width: m.label == null ? 52 : 150,
                height: m.label == null ? 52 : 76,
                alignment: m.label == null ? Alignment.center : const Alignment(0, -0.35),
                child: GestureDetector(onTap: m.onTap, child: WMapPin(kind: m.kind, icon: m.icon, label: m.label)),
              ),
          ]),
          RichAttributionWidget(
            attributions: [TextSourceAttribution(MapConfig.tileAttribution)],
            alignment: AttributionAlignment.bottomLeft,
            showFlutterMapAttribution: false,
          ),
        ],
      ),
    );
  }
}

/// العلامة نفسها (تُستخدم بالخريطة وبالأدلة)
class WMapPin extends StatelessWidget {
  const WMapPin({super.key, required this.kind, this.icon, this.label});
  final WMarkerKind kind;
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final pin = switch (kind) {
      // المركبات: مربع حبر بأيقونة ليمونية + حلقة نبض
      WMarkerKind.courier || WMarkerKind.taxi || WMarkerKind.tuktuk => _Pulse(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: WColors.ink, borderRadius: WRadius.all(12), border: Border.all(color: WColors.white, width: 2.5), boxShadow: WShadow.soft),
            child: Icon(
              switch (kind) { WMarkerKind.taxi => Icons.local_taxi_rounded, WMarkerKind.tuktuk => Icons.electric_rickshaw_rounded, _ => Icons.two_wheeler_rounded },
              color: WColors.lime,
              size: 21,
            ),
          ),
        ),
      // المحل: بطاقة بيضاء بإطار حبر
      WMarkerKind.store => Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: WColors.white, borderRadius: WRadius.all(11), border: Border.all(color: WColors.ink, width: 2), boxShadow: WShadow.soft),
          child: Icon(icon ?? Icons.storefront_rounded, color: WColors.ink, size: 19),
        ),
      // الوجهة/البيت: أزرق
      WMarkerKind.home || WMarkerKind.dropoff => Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: WColors.blue, shape: BoxShape.circle, border: Border.all(color: WColors.white, width: 3), boxShadow: WShadow.soft),
          child: Icon(kind == WMarkerKind.home ? Icons.home_rounded : Icons.flag_rounded, color: WColors.white, size: 18),
        ),
      // الانطلاق: حلقة حبر (مثل بداية مسار العلامة)
      WMarkerKind.pickup => Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: WColors.white, shape: BoxShape.circle, border: Border.all(color: WColors.ink, width: 6), boxShadow: WShadow.soft),
        ),
      WMarkerKind.me => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: WColors.blue, shape: BoxShape.circle, border: Border.all(color: WColors.white, width: 4), boxShadow: WShadow.soft),
        ),
      WMarkerKind.place => Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: WColors.ink, shape: BoxShape.circle, border: Border.all(color: WColors.white, width: 3)),
          child: Icon(icon ?? Icons.place_rounded, color: WColors.lime, size: 15),
        ),
    };
    if (label == null) return Center(child: pin);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: WColors.ink, borderRadius: WRadius.all(8)),
        child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: WText.label.copyWith(color: WColors.white, fontSize: 11.5)),
      ),
      const SizedBox(height: 4),
      pin,
    ]);
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Container(
            width: 40 + 22 * _c.value,
            height: 40 + 22 * _c.value,
            decoration: BoxDecoration(color: WColors.lime.withValues(alpha: 0.45 * (1 - _c.value)), borderRadius: WRadius.all(14 + 6 * _c.value)),
          ),
        ),
        widget.child,
      ]);
}

/// اختيار موقع: بحث عن عنوان، أو تحريك الخريطة تحت دبوس ثابت، مع اسم المكان تلقائياً.
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key, this.initial, this.title = 'حدّد الموقع', this.confirmLabel = 'تأكيد الموقع'});
  final LatLng? initial;
  final String title;
  final String confirmLabel;

  /// يرجّع النقطة فقط (للتوافق)
  static Future<LatLng?> open(BuildContext context, {LatLng? initial, String title = 'حدّد الموقع', String confirmLabel = 'تأكيد الموقع'}) async =>
      (await openPlace(context, initial: initial, title: title, confirmLabel: confirmLabel))?.point;

  /// يرجّع النقطة + اسم المكان
  static Future<PickedPlace?> openPlace(BuildContext context, {LatLng? initial, String title = 'حدّد الموقع', String confirmLabel = 'تأكيد الموقع'}) =>
      Navigator.of(context).push<PickedPlace>(MaterialPageRoute(builder: (_) => LocationPickerPage(initial: initial, title: title, confirmLabel: confirmLabel)));

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final _map = MapController();
  final _search = TextEditingController();
  late LatLng _center = widget.initial ?? kDefaultCenter;
  bool _locating = false;
  bool _moving = false;
  String? _label;
  bool _labelLoading = false;
  List<PickedPlace> _results = [];
  bool _searching = false;
  String? _searchError;
  Timer? _debounce;
  Timer? _reverseDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    } else {
      _reverse();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reverseDebounce?.cancel();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final r = await currentLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (r.position != null) {
      _moveTo(r.position!, 17);
    } else {
      showError(context, r.error!);
    }
  }

  void _moveTo(LatLng p, double zoom) {
    _map.move(p, zoom);
    setState(() => _center = p);
    _reverse();
  }

  void _reverse() {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _labelLoading = true);
      String? l;
      try {
        l = await geoApi.reverse(_center);
      } catch (_) {
        l = null;
      }
      if (mounted) {
        setState(() {
          _label = l;
          _labelLoading = false;
        });
      }
    });
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (q.trim().length < 2) {
        setState(() {
          _results = [];
          _searchError = null;
        });
        return;
      }
      setState(() => _searching = true);
      try {
        final r = await geoApi.search(q, near: _center);
        if (mounted) {
          setState(() {
            _results = r;
            _searchError = r.isEmpty ? 'ما لگينا هذا العنوان. جرّب اسم منطقة أو معلم قريب.' : null;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searchError = 'البحث غير متاح هسه. حرّك الخريطة وحدد يدوياً.');
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
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
              backgroundColor: WColors.surfaceAlt,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onPositionChanged: (cam, hasGesture) {
                _center = cam.center;
                if (hasGesture && !_moving) setState(() => _moving = true);
              },
              onMapEvent: (e) {
                if (e is MapEventMoveEnd || e is MapEventFlingAnimationEnd) {
                  setState(() => _moving = false);
                  _reverse();
                }
              },
            ),
            children: [
              wTileLayer(),
              RichAttributionWidget(attributions: [TextSourceAttribution(MapConfig.tileAttribution)], alignment: AttributionAlignment.bottomLeft, showFlutterMapAttribution: false),
            ],
          ),
          // الدبوس الثابت: يرتفع شوية أثناء التحريك
          IgnorePointer(
            child: Center(
              child: AnimatedSlide(
                duration: WDurations.fast,
                offset: Offset(0, _moving ? -0.62 : -0.5),
                child: const _CenterPin(),
              ),
            ),
          ),
          // البحث
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(children: [
              Material(
                elevation: 0,
                color: WColors.white,
                shape: RoundedRectangleBorder(borderRadius: WRadius.all(WRadius.md), side: BorderSide(color: WColors.line)),
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن منطقة، شارع، أو معلم',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searching
                        ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        : (_search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _results = []);
                                },
                              )),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              if (_results.isNotEmpty || _searchError != null)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(color: WColors.white, borderRadius: WRadius.all(WRadius.md), border: Border.all(color: WColors.line), boxShadow: WShadow.soft),
                  child: _searchError != null
                      ? Padding(padding: const EdgeInsets.all(14), child: Text(_searchError!, style: WText.small))
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(indent: 52),
                          itemBuilder: (context, i) => ListTile(
                            dense: true,
                            leading: Icon(Icons.place_outlined, color: WColors.ink),
                            title: Text(_results[i].label, maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              final r = _results[i];
                              setState(() {
                                _results = [];
                                _label = r.label;
                              });
                              _map.move(r.point, 17);
                              _center = r.point;
                            },
                          ),
                        ),
                ),
            ]),
          ),
          PositionedDirectional(
            end: 16,
            bottom: 170,
            child: WIconButton(_locating ? Icons.more_horiz_rounded : Icons.my_location_rounded, onPressed: _locating ? null : _locate, tooltip: 'موقعي الحالي', bordered: true),
          ),
          // ورقة سفلية: اسم المكان + التأكيد
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(color: WColors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(WRadius.xl)), boxShadow: WShadow.lifted),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('الموقع المحدد', style: WText.overline),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: WDurations.base,
                  child: Text(
                    _moving ? 'حرّك الخريطة…' : (_labelLoading ? 'نتعرّف على المكان…' : (_label ?? 'نقطة على الخريطة')),
                    key: ValueKey('$_moving$_labelLoading$_label'),
                    style: WText.h3,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 14),
                WButton(widget.confirmLabel, icon: Icons.check_rounded, onPressed: _moving ? null : () => Navigator.pop(context, PickedPlace(_center, _label ?? ''))),
              ]),
            ),
          ),
        ]),
      );
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 64,
        child: Column(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: WColors.ink, borderRadius: WRadius.all(14), boxShadow: WShadow.lifted),
            child: Center(child: Container(width: 14, height: 14, decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(5)))),
          ),
          Container(width: 3, height: 16, color: WColors.ink),
          Container(width: 8, height: 4, decoration: BoxDecoration(color: WColors.ink.withValues(alpha: 0.3), borderRadius: WRadius.all(4))),
        ]),
      );
}

/// اهتزاز خفيف عند تأكيد الموقع
void hapticConfirm() => HapticFeedback.lightImpact();
