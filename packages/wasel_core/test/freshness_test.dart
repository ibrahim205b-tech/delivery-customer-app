import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  final now = DateTime(2026, 11, 15, 12, 0, 0);
  DateTime ago(Duration d) => now.subtract(d);

  group('freshnessOf', () {
    test('بدون وقت = unknown (ما نعرض موقع وهمي)', () {
      expect(freshnessOf(null, now: now), Freshness.unknown);
    });
    test('أقل من دقيقة = live', () {
      expect(freshnessOf(ago(const Duration(seconds: 15)), now: now), Freshness.live);
      expect(freshnessOf(ago(const Duration(minutes: 1)), now: now), Freshness.live, reason: 'الحد يشمل الدقيقة نفسها');
    });
    test('دقيقة إلى 5 دقائق = recent', () {
      expect(freshnessOf(ago(const Duration(seconds: 61)), now: now), Freshness.recent);
      expect(freshnessOf(ago(const Duration(minutes: 5)), now: now), Freshness.recent);
    });
    test('أكثر من 5 دقائق = stale (لا يُعرض كمباشر)', () {
      expect(freshnessOf(ago(const Duration(minutes: 5, seconds: 1)), now: now), Freshness.stale);
      expect(freshnessOf(ago(const Duration(hours: 3)), now: now), Freshness.stale);
    });
    test('وقت في المستقبل بسبب ساعة الجهاز = live وما يطلع سالب', () {
      expect(freshnessOf(now.add(const Duration(seconds: 30)), now: now), Freshness.live);
    });
  });

  group('freshnessLabelAr', () {
    test('النص يوضح الحالة بالعربي', () {
      expect(freshnessLabelAr(null, now: now), 'ما وصلنا موقع بعد');
      expect(freshnessLabelAr(ago(const Duration(seconds: 10)), now: now), 'مباشر الآن');
      expect(freshnessLabelAr(ago(const Duration(minutes: 3)), now: now), 'آخر تحديث قبل 3 دقيقة');
      expect(freshnessLabelAr(ago(const Duration(minutes: 20)), now: now), 'آخر موقع معروف منذ 20 دقيقة');
      expect(freshnessLabelAr(ago(const Duration(hours: 2)), now: now), 'آخر موقع معروف منذ 2 ساعة');
    });
  });
}
