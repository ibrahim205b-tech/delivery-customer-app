import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  // خط شرق-غرب في بغداد، طوله ≈ 1 كم
  const a = LatLng(33.3000, 44.4300);
  const b = LatLng(33.3000, 44.4400);
  const line = [a, b];

  group('distanceToPolylineM', () {
    test('نقطة على الخط = صفر تقريباً', () {
      final d = distanceToPolylineM(const LatLng(33.3000, 44.4350), line);
      expect(d, lessThan(0.5));
    });

    test('نقطة تبعد 0.0005 درجة شمالاً ≈ 55 م', () {
      final d = distanceToPolylineM(const LatLng(33.3005, 44.4350), line);
      expect(d, closeTo(55, 3));
    });

    test('نقطة خلف طرف الخط تُقاس من الطرف', () {
      // تبعد عن النهاية b بمقدار 0.001 درجة شرقاً (≈ 96 م)
      final d = distanceToPolylineM(const LatLng(33.3000, 44.4410), line);
      expect(d, closeTo(96, 4));
    });

    test('خط فارغ = مسافة لا نهائية (لا نقرر انحرافاً من بيانات ناقصة)', () {
      expect(distanceToPolylineM(a, const []), double.infinity);
    });

    test('مسار من أكثر من قطعة: يختار أقرب قطعة', () {
      const bend = [LatLng(33.3000, 44.4300), LatLng(33.3000, 44.4350), LatLng(33.3050, 44.4350)];
      // نقطة قرب القطعة الثانية الشمالية
      final d = distanceToPolylineM(const LatLng(33.3025, 44.4352), bend);
      expect(d, lessThan(30));
    });
  });

  group('isOffRoute', () {
    test('داخل حد 60 م ما يعتبر انحرافاً (دقّة GPS عادية)', () {
      expect(isOffRoute(const LatLng(33.3005, 44.4350), line), isFalse); // ≈ 55 م
    });
    test('أكثر من 60 م = انحراف', () {
      expect(isOffRoute(const LatLng(33.3007, 44.4350), line), isTrue); // ≈ 78 م
    });
    test('حد مخصص', () {
      expect(isOffRoute(const LatLng(33.3005, 44.4350), line, thresholdM: 30), isTrue);
    });
  });
}
