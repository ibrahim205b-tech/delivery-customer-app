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

  test('أقرب نقطة دالة بدون تكرار "قرب"', () {
    expect(landmarkAr('الجامع'), 'قرب الجامع');
    expect(landmarkAr('قرب الجامع'), 'قرب الجامع');
    expect(landmarkAr('مقابل الصيدلية'), 'مقابل الصيدلية');
    expect(landmarkAr('  '), '');
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

  group('النمو', () {
    test('روابط عناصر الرئيسية', () {
      expect(HomeLink.parse(''), isNull);
      expect(HomeLink.parse('wasel://nothing'), isNull);
      expect(HomeLink.parse('wasel://category'), isNull, reason: 'القسم بدون معرّف ما ينفتح');
      expect((HomeLink.parse('wasel://category/restaurants') as HomeLinkCategory).categoryId, 'restaurants');
      expect((HomeLink.parse(' wasel://merchant/abc-123 ') as HomeLinkMerchant).merchantId, 'abc-123');
      expect((HomeLink.parse('wasel://ride/tuktuk') as HomeLinkRide).vehicle, VehicleType.tuktuk);
      expect((HomeLink.parse('wasel://ride') as HomeLinkRide).vehicle, VehicleType.taxi);
      expect(HomeLink.parse('wasel://rewards'), isA<HomeLinkRewards>());
      expect(HomeLink.parse('wasel://invite'), isA<HomeLinkInvite>());
      expect(HomeLink.parse('https://wasel.iq/offer'), isA<HomeLinkWeb>());
      expect(HomeLink.parse('javascript:alert(1)'), isNull);
    });

    test('قسم بنوع غير معروف يتحوّل unknown بدل ما يكسر التطبيق', () {
      final s = HomeSection.fromJson({'id': 's', 'type': 'future_type', 'items': null});
      expect(s.type, HomeSectionType.unknown);
      final ok = HomeSection.fromJson({
        'id': 's', 'type': 'slider', 'title': 'عروض',
        'items': [
          {'id': 'b', 'title': 'ثاني', 'sort': 2, 'tone': 'weird', 'image_url': ' '},
          {'id': 'a', 'title': 'أول', 'sort': 1, 'tone': 'lime', 'link': 'wasel://rewards'},
        ],
      });
      expect(ok.type.hasItems, isTrue);
      expect(ok.items.map((e) => e.id), ['a', 'b'], reason: 'العناصر مرتبة حسب sort');
      expect(ok.items.last.tone, HomeTone.plain, reason: 'لون غير معروف يرجع للافتراضي');
      expect(ok.items.last.imageUrl, isNull, reason: 'رابط صورة فارغ = بدون صورة');
    });

    test('حسابات النقاط', () {
      Rewards r(int points) => Rewards.fromJson({'enabled': true, 'wallet': 0, 'points': points, 'redeem_points': 100, 'redeem_value': 1000, 'referral_code': 'WABC234'});
      expect(r(64).redeemableValue, 0);
      expect(r(64).pointsToNext, 36);
      expect(r(64).progress, closeTo(0.64, 0.001));
      expect(r(250).redeemableValue, 2000);
      expect(r(250).pointsToNext, 50);
      expect(Rewards.fromJson({'points': 50}).redeemableValue, 0, reason: 'إعدادات ناقصة ما تسبب قسمة على صفر');
    });

    test('الطلب يقرأ الخصم والرصيد ويحتفظ بيهم بالتحديث اللحظي', () {
      final row = {
        'id': 'o1', 'code': 'W1', 'customer_id': 'c', 'merchant_id': 'm', 'status': 'placed', 'address_lat': 33.3, 'address_lng': 44.4,
        'subtotal': 14000, 'delivery_fee': 1500, 'discount': 2500, 'wallet_used': 5000, 'promo_code': 'WASEL20', 'total': 8000,
        'created_at': '2026-11-11T10:00:00Z', 'updated_at': '2026-11-11T10:05:00Z',
      };
      final o = Order.fromJson(row);
      expect((o.discount, o.walletUsed, o.promoCode), (2500, 5000, 'WASEL20'));
      expect(o.mergeRow({...row, 'status': 'accepted'}).discount, 2500);
      final old = Order.fromJson({...row}..remove('discount')..remove('wallet_used')..remove('promo_code'));
      expect((old.discount, old.walletUsed, old.promoCode), (0, 0, null), reason: 'خادم قبل 0009');
    });

    test('أخطاء الأكواد والدعوات بالعربي', () {
      expect(friendlyError('promo_min:10000'), contains('10000'));
      expect(friendlyError('promo_used'), isNot(contains('غير متوقع')));
      expect(friendlyError('referral_self'), isNot(contains('غير متوقع')));
      expect(friendlyError('points_not_enough:100'), contains('100'));
    });
  });
}
