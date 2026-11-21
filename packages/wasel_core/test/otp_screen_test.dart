import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildWaselTheme(),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      );

  testWidgets('الرمز يُرسل تلقائياً عند اكتمال 6 أرقام، والأرقام العربية تتحول', (t) async {
    String? sent;
    await t.pumpWidget(host(OtpScreen(phone: '07801112233', onVerify: (c) async => sent = c, onResend: () async => 60)));
    await t.enterText(find.byType(TextField), '١٢٣٤٥٦');
    await t.pump();
    expect(sent, '123456');
    await t.pump(const Duration(seconds: 61));
  });

  testWidgets('عداد إعادة الإرسال ثم زر الإعادة', (t) async {
    var resends = 0;
    await t.pumpWidget(host(OtpScreen(phone: '07801112233', resendIn: 3, onVerify: (_) async {}, onResend: () async {
      resends++;
      return 60;
    })));
    expect(find.textContaining('إعادة الإرسال بعد'), findsOneWidget);
    expect(find.text('إعادة إرسال الرمز'), findsNothing);
    await t.pump(const Duration(seconds: 4));
    expect(find.text('إعادة إرسال الرمز'), findsOneWidget);
    await t.tap(find.text('إعادة إرسال الرمز'));
    await t.pump();
    expect(resends, 1);
    expect(find.textContaining('إعادة الإرسال بعد'), findsOneWidget);
    await t.pump(const Duration(seconds: 61));
  });

  testWidgets('رمز خاطئ يعرض المحاولات المتبقية ويمسح الحقل', (t) async {
    await t.pumpWidget(host(OtpScreen(
      phone: '07801112233',
      onVerify: (_) async => throw const AuthFlowException('otp_invalid', remaining: 3),
      onResend: () async => 60,
    )));
    await t.enterText(find.byType(TextField), '000000');
    await t.pump();
    await t.pump();
    expect(find.text('الرمز غير صحيح. باقي لك 3 محاولات.'), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await t.pump(const Duration(seconds: 61));
  });

  test('رسائل أخطاء المهلة', () {
    expect(friendlyError(const AuthFlowException('otp_cooldown', retryIn: 42)), 'انتظر 42 ثانية قبل طلب رمز جديد.');
    expect(friendlyError(const AuthFlowException('otp_send_failed')), contains('الواتساب'));
  });
}
