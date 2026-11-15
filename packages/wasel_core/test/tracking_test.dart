import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  group('shouldTrack: التتبع فقط أثناء العمل', () {
    test('متاح بدون مهمة = نتتبع', () {
      expect(shouldTrack(available: true, hasJob: false), isTrue);
    });
    test('غير متاح بدون مهمة = لا نتتبع (خارج العمل)', () {
      expect(shouldTrack(available: false, hasJob: false), isFalse);
    });
    test('غير متاح لكن عنده مهمة جارية = نكمل التتبع حتى يكمّل المهمة', () {
      expect(shouldTrack(available: false, hasJob: true), isTrue);
    });
    test('متاح ومعه مهمة = نتتبع', () {
      expect(shouldTrack(available: true, hasJob: true), isTrue);
    });
  });

  group('shouldSend: حد أدنى 15 ثانية بين الإرسالات', () {
    final now = DateTime(2026, 11, 15, 12, 0, 0);
    test('أول إرسال مسموح دائماً', () {
      expect(shouldSend(null, now), isTrue);
    });
    test('قبل 5 ثواني = ممنوع (حماية البطارية والشبكة)', () {
      expect(shouldSend(now.subtract(const Duration(seconds: 5)), now), isFalse);
    });
    test('بالضبط 15 ثانية = مسموح', () {
      expect(shouldSend(now.subtract(const Duration(seconds: 15)), now), isTrue);
    });
    test('فاصل مخصص', () {
      expect(shouldSend(now.subtract(const Duration(seconds: 30)), now, every: const Duration(minutes: 1)), isFalse);
    });
  });

  test('DriverTracker يبدأ متوقفاً ويتوقف بأمان بدون بدء', () async {
    final t = DriverTracker();
    expect(t.running, isFalse);
    await t.stop();
    expect(t.running, isFalse);
    expect(t.lastPosition, isNull);
  });

  group('ThrottledSender: آخر موقع يصل حتى لو توقف السائق', () {
    test('أول قيمة تُرسل فوراً، والقيم اللي داخل الفترة تنتظر وتُرسل آخرها', () async {
      final sent = <int>[];
      final s = ThrottledSender<int>(send: (v) async => sent.add(v), every: const Duration(milliseconds: 200));
      s.offer(1);
      s.offer(2);
      s.offer(3);
      expect(sent, [1], reason: 'أول قيمة فقط ضمن الفترة');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(sent, [1, 3], reason: 'بعد انتهاء الفترة يُرسل آخر قيمة فقط');
      s.cancel();
    });

    test('بعد الفترة القيم الجديدة تُرسل فوراً من جديد', () async {
      final sent = <int>[];
      final s = ThrottledSender<int>(send: (v) async => sent.add(v), every: const Duration(milliseconds: 100));
      s.offer(1);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      s.offer(2);
      expect(sent, [1, 2]);
      s.cancel();
    });

    test('cancel يلغي الإرسال المعلّق', () async {
      final sent = <int>[];
      final s = ThrottledSender<int>(send: (v) async => sent.add(v), every: const Duration(milliseconds: 100));
      s.offer(1);
      s.offer(2);
      s.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sent, [1]);
    });
  });
}
