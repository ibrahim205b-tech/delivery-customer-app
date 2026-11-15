import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  test('خدمة مفعّلة تُقرأ من صف الكتالوج', () {
    final s = ServiceItem.fromJson({
      'id': 'parcel_delivery', 'group_id': 'transport', 'name_ar': 'توصيل الأمانات',
      'description': 'توصيل غرض', 'engine': 'task', 'is_active': true, 'sort_order': 1,
    });
    expect(s.isActive, isTrue);
    expect(s.engine, 'task');
    expect(s.groupId, 'transport');
  });

  test('خدمة بلا تنفيذ تقرأ كمعطّلة حتى لو الصف ناقص', () {
    final s = ServiceItem.fromJson({'id': 'x', 'group_id': 'bookings', 'name_ar': 'x', 'engine': 'none'});
    expect(s.isActive, isFalse);
  });

  test('نتيجة البحث الفارغة', () {
    final r = SearchResult.fromJson({'services': [], 'merchants': []});
    expect(r.isEmpty, isTrue);
  });

  test('نتيجة البحث فيها خدمات ومحلات', () {
    final r = SearchResult.fromJson({
      'services': [{'id': 'parcel_delivery', 'name': 'توصيل الأمانات'}],
      'merchants': [{'id': 'm1', 'name': 'مطعم', 'business_type': 'restaurant'}],
    });
    expect(r.isEmpty, isFalse);
    expect(r.services.single['id'], 'parcel_delivery');
    expect(r.merchants.single['business_type'], 'restaurant');
  });

  test('تصنيف الخدمة مع ترتيب', () {
    final g = ServiceGroup.fromJson({'id': 'jobs', 'name_ar': 'الوظائف', 'sort_order': 2});
    expect(g.name, 'الوظائف');
    expect(g.sortOrder, 2);
  });
}
