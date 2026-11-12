import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  group('whatsappIntl', () {
    test('يحوّل الأرقام العراقية لصيغة wa.me', () {
      expect(whatsappIntl('07701234567'), '9647701234567');
      expect(whatsappIntl('0770 123 4567'), '9647701234567');
      expect(whatsappIntl('+964 770 123 4567'), '9647701234567');
      expect(whatsappIntl('009647701234567'), '9647701234567');
      expect(whatsappIntl('7701234567'), '9647701234567');
      expect(whatsappIntl('٠٧٧٠١٢٣٤٥٦٧'), '9647701234567');
    });
    test('يرفض الأرقام الناقصة أو الفارغة', () {
      expect(whatsappIntl(''), isNull);
      expect(whatsappIntl('0770'), isNull);
    });
  });

  test('رابط واتساب مع رسالة مرمّزة', () {
    expect(whatsappUri('9647701234567', text: 'مرحبا W1024').toString(), startsWith('https://wa.me/9647701234567?text='));
    expect(whatsappUri('9647701234567').toString(), 'https://wa.me/9647701234567');
  });

  test('أرقام الدعم: واتساب يرجع لرقم الاتصال إذا فارغ', () {
    final c = SupportContacts.fromJson({'phone': '07701234567', 'whatsapp': ''});
    expect(c.hasPhone, isTrue);
    expect(c.whatsappNumber, '9647701234567');
    final none = SupportContacts.fromJson(null);
    expect(none.hasPhone, isFalse);
    expect(none.hasWhatsapp, isFalse);
  });
}
