import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wasel_core/wasel_core.dart';

// نماذج حقيقية الشكل من استجابات Nominatim و OSRM (بدون اتصال بالشبكة)
const _search = '''[
 {"lat":"33.3038","lon":"44.4326","display_name":"شارع 62، الكرادة، بغداد، 10071، العراق"},
 {"lat":"33.3152","lon":"44.4210","display_name":"ساحة الفردوس، السعدون، بغداد، العراق"}
]''';
const _reverse = '{"display_name":"زقاق 12، الكرادة داخل، الكرادة، بغداد، 10071، العراق"}';
const _route = '''{"code":"Ok","routes":[{"distance":3540.2,"duration":420.0,
 "geometry":{"type":"LineString","coordinates":[[44.43,33.30],[44.425,33.305],[44.40,33.32]]}}]}''';

void main() {
  test('تحليل نتائج البحث واختصار العنوان', () {
    final r = GeoApi.parseSearch(_search);
    expect(r.length, 2);
    expect(r.first.point.latitude, 33.3038);
    expect(r.first.label, 'شارع 62، الكرادة، بغداد');
  });

  test('الاسم من الإحداثيات يُختصر بدون الرمز البريدي', () {
    expect(GeoApi.parseReverse(_reverse), 'زقاق 12، الكرادة داخل، الكرادة');
  });

  test('تحليل المسار: نقاط + مسافة + وقت مع هامش زحمة', () {
    final r = GeoApi.parseRoute(_route)!;
    expect(r.points.length, 3);
    expect(r.points.first.latitude, 33.30);
    expect(r.distanceKm, closeTo(3.54, 0.01));
    expect(r.minutes, closeTo(8.4, 0.01)); // 7 دقائق × 1.2
    expect(r.isEstimate, isFalse);
  });

  test('إذا فشلت خدمة المسارات نرجع لتقدير بخط مستقيم', () async {
    final api = GeoApi(client: MockClient((_) async => http.Response('down', 503)));
    final r = await api.route(const LatLng(33.30, 44.43), const LatLng(33.32, 44.40));
    expect(r.isEstimate, isTrue);
    expect(r.points.length, 2);
    expect(r.minutes, greaterThan(0));
  });

  test('البحث يرسل تفضيل العراق والمنطقة القريبة', () async {
    late Uri seen;
    final api = GeoApi(client: MockClient((req) async {
      seen = req.url;
      return http.Response(_search, 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final r = await api.search('الكرادة', near: const LatLng(33.30, 44.43));
    expect(r.length, 2);
    expect(seen.queryParameters['countrycodes'], 'iq');
    expect(seen.queryParameters['accept-language'], 'ar');
    expect(seen.queryParameters['viewbox'], isNotNull);
  });

  test('رد مسار غير صالح يرجع null', () {
    expect(GeoApi.parseRoute('{"code":"NoRoute","routes":[]}'), isNull);
  });
}
