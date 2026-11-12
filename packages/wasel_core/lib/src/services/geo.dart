import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'location.dart';

/// مزوّدو الخرائط قابلين للتبديل وقت البناء بدون تغيير الكود:
///   --dart-define=MAP_TILE_URL=https://api.maptiler.com/maps/<style>/{z}/{x}/{y}.png?key=...
///   --dart-define=GEOCODER_URL=...   (متوافق مع Nominatim)
///   --dart-define=ROUTER_URL=...     (متوافق مع OSRM)
/// الافتراضي: خدمات OpenStreetMap المجانية العامة (لها حدود استخدام، مناسبة للتجربة).
abstract final class MapConfig {
  static const tileUrl = String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  static const tileAttribution = String.fromEnvironment('MAP_TILE_ATTRIBUTION', defaultValue: '© OpenStreetMap');
  static const geocoderUrl = String.fromEnvironment('GEOCODER_URL', defaultValue: 'https://nominatim.openstreetmap.org');
  static const routerUrl = String.fromEnvironment('ROUTER_URL', defaultValue: 'https://router.project-osrm.org');

  /// الخرائط الافتراضية تتلوّن بهوية واصل. مزوّد بستايل خاص ما يحتاج تلوين.
  static bool get tintTiles => !tileUrl.contains('maptiler') && !tileUrl.contains('mapbox');

  static const userAgent = 'WaselApp/1.0';
}

class PickedPlace {
  const PickedPlace(this.point, this.label);
  final LatLng point;
  final String label;
}

class RouteResult {
  const RouteResult({required this.points, required this.distanceKm, required this.minutes, required this.isEstimate});
  final List<LatLng> points;
  final double distanceKm;
  final double minutes;

  /// true إذا ما توفرت خدمة المسارات واستُخدم خط مستقيم وسرعة تقديرية
  final bool isEstimate;
}

/// البحث عن العناوين والمسارات. [client] قابل للحقن للاختبار.
class GeoApi {
  GeoApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final Map<String, RouteResult> _routeCache = {};

  Map<String, String> get _headers => {'User-Agent': MapConfig.userAgent, 'Accept-Language': 'ar'};

  /// يختصر عنوان Nominatim الطويل: "شارع 62، الكرادة، بغداد"
  static String shortLabel(String displayName, {int parts = 3}) {
    final p = displayName.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty && !RegExp(r'^\d{5}$').hasMatch(e)).toList();
    return p.take(parts).join('، ');
  }

  /// بحث داخل العراق، مع تفضيل المنطقة القريبة من [near]
  Future<List<PickedPlace>> search(String query, {LatLng? near}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final params = {
      'q': q,
      'format': 'jsonv2',
      'countrycodes': 'iq',
      'limit': '8',
      'accept-language': 'ar',
      if (near != null) 'viewbox': '${near.longitude - 0.35},${near.latitude + 0.35},${near.longitude + 0.35},${near.latitude - 0.35}',
    };
    final res = await _client.get(Uri.parse('${MapConfig.geocoderUrl}/search').replace(queryParameters: params), headers: _headers).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('geocoder_${res.statusCode}');
    return parseSearch(res.body);
  }

  static List<PickedPlace> parseSearch(String body) {
    final list = jsonDecode(body) as List;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        PickedPlace(LatLng(double.parse('${e['lat']}'), double.parse('${e['lon']}')), shortLabel('${e['display_name'] ?? ''}')),
    ];
  }

  /// اسم المكان من الإحداثيات (للدبوس)
  Future<String?> reverse(LatLng p) async {
    final res = await _client
        .get(
          Uri.parse('${MapConfig.geocoderUrl}/reverse').replace(queryParameters: {
            'lat': '${p.latitude}',
            'lon': '${p.longitude}',
            'format': 'jsonv2',
            'zoom': '18',
            'accept-language': 'ar',
          }),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return parseReverse(res.body);
  }

  static String? parseReverse(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final name = j['display_name'] as String?;
    return name == null ? null : shortLabel(name);
  }

  /// مسار بالطرق + الوقت. إذا فشلت الخدمة: خط مستقيم وسرعة 25 كم/س (يُعلَّم isEstimate).
  Future<RouteResult> route(LatLng from, LatLng to) async {
    final key = '${from.latitude.toStringAsFixed(4)},${from.longitude.toStringAsFixed(4)}>${to.latitude.toStringAsFixed(4)},${to.longitude.toStringAsFixed(4)}';
    final cached = _routeCache[key];
    if (cached != null) return cached;
    try {
      final url = '${MapConfig.routerUrl}/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson';
      final res = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final r = parseRoute(res.body);
        if (r != null) {
          if (_routeCache.length > 50) _routeCache.clear();
          return _routeCache[key] = r;
        }
      }
    } catch (_) {
      // نرجع للتقدير
    }
    return straightLine(from, to);
  }

  static RouteResult? parseRoute(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    if (j['code'] != 'Ok') return null;
    final routes = (j['routes'] as List).cast<Map<String, dynamic>>();
    if (routes.isEmpty) return null;
    final r = routes.first;
    final coords = ((r['geometry'] as Map)['coordinates'] as List).cast<List>();
    return RouteResult(
      points: [for (final c in coords) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())],
      distanceKm: (r['distance'] as num).toDouble() / 1000,
      // OSRM العام مبني على سرعات السيارات؛ نضيف 20% لزحمة المدينة
      minutes: (r['duration'] as num).toDouble() / 60 * 1.2,
      isEstimate: false,
    );
  }

  static RouteResult straightLine(LatLng from, LatLng to) {
    final km = distanceKm(from.latitude, from.longitude, to.latitude, to.longitude);
    return RouteResult(points: [from, to], distanceKm: km, minutes: km / 25 * 60, isEstimate: true);
  }
}

final geoApi = GeoApi();
