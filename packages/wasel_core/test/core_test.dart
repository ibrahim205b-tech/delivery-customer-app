import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  group('normalizeIraqiPhone', () {
    test('يقبل الصيغ الشائعة', () {
      expect(normalizeIraqiPhone('07701234567'), '07701234567');
      expect(normalizeIraqiPhone('+964 770 123 4567'), '07701234567');
      expect(normalizeIraqiPhone('009647701234567'), '07701234567');
      expect(normalizeIraqiPhone('7701234567'), '07701234567');
      expect(normalizeIraqiPhone('٠٧٧٠١٢٣٤٥٦٧'), '07701234567');
    });
    test('يرفض الأرقام غير الصالحة', () {
      expect(normalizeIraqiPhone('0770123'), isNull);
      expect(normalizeIraqiPhone('06701234567'), isNull);
      expect(normalizeIraqiPhone(''), isNull);
    });
    test('تحويل الرقم لبريد الدخول', () {
      expect(phoneToAuthEmail('07701234567'), '9647701234567@phone.wasel.app');
    });
  });

  test('تنسيق الدينار', () {
    expect(iqd(12500), '12,500 د.ع');
    expect(iqd(0), '0 د.ع');
  });

  test('المسافة تطابق معادلة الخادم تقريباً', () {
    final km = distanceKm(33.30, 44.43, 33.32, 44.40);
    expect(km, closeTo(3.54, 0.05));
  });

  test('ترجمة أخطاء الخادم للعربي', () {
    expect(friendlyError(Exception('below_min_order:3000')), contains('صار خطأ'));
    expect(friendlyError('out_of_delivery_area'), contains('خارج منطقة'));
    expect(friendlyError('below_min_order:3000'), contains('3000'));
  });

  test('قراءة الطلب من JSON', () {
    final o = Order.fromJson({
      'id': 'o1', 'code': 'W1001', 'customer_id': 'c', 'merchant_id': 'm', 'status': 'on_the_way',
      'address_lat': 33.3, 'address_lng': 44.4, 'subtotal': 10000, 'delivery_fee': 1500, 'total': 11500,
      'created_at': '2026-11-11T10:00:00Z', 'updated_at': '2026-11-11T10:05:00Z',
      'order_items': [{'id': 'i1', 'name': 'تكة', 'unit_price': 5000, 'qty': 2}],
      'merchants': {'name': 'مطعم', 'lat': 33.31, 'lng': 44.41},
    });
    expect(o.status, OrderStatus.onTheWay);
    expect(o.itemsSummary, '2× تكة');
    expect(o.merchantName, 'مطعم');
    final merged = o.mergeRow({
      'id': 'o1', 'code': 'W1001', 'customer_id': 'c', 'merchant_id': 'm', 'status': 'delivered',
      'address_lat': 33.3, 'address_lng': 44.4, 'subtotal': 10000, 'delivery_fee': 1500, 'total': 11500,
      'created_at': '2026-11-11T10:00:00Z', 'updated_at': '2026-11-11T10:20:00Z',
    });
    expect(merged.status, OrderStatus.delivered);
    expect(merged.items.length, 1, reason: 'التحديث اللحظي يحتفظ بالمنتجات');
  });

  test('أوقات عمل المحل (يعبر منتصف الليل)', () {
    Merchant m(Map<String, dynamic> hours) => Merchant.fromJson({
          'id': 'm', 'category_id': 'restaurants', 'name': 'محل', 'lat': 33.3, 'lng': 44.4,
          'status': 'approved', 'is_accepting_orders': true, 'working_hours': hours, 'created_at': '2026-01-01T00:00:00Z',
        });
    final all = {for (var d = 0; d < 7; d++) '$d': {'open': '00:00', 'close': '23:59', 'closed': false}};
    expect(m(all).isOpenNow, isTrue);
    final closed = {for (var d = 0; d < 7; d++) '$d': {'open': '09:00', 'close': '17:00', 'closed': true}};
    expect(m(closed).isOpenNow, isFalse);
  });
}
