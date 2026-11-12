import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildWaselTheme(),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Center(child: child))),
    );

void main() {
  testWidgets('WButton: قارئ الشاشة يقدر يضغطه (فعل tap موجود بالـ semantics)', (t) async {
    var taps = 0;
    final h = t.ensureSemantics();
    await t.pumpWidget(_host(WButton('دخول', onPressed: () => taps++)));
    final node = t.getSemantics(find.bySemanticsLabel('دخول'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.semantics.tap(find.semantics.byLabel('دخول'));
    await t.pump();
    expect(taps, 1);
    h.dispose();
  });

  testWidgets('WButton المعطّل ما يستجيب', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_host(const WButton('دخول', onPressed: null)));
    final node = t.getSemantics(find.bySemanticsLabel('دخول'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    h.dispose();
  });

  testWidgets('WButton يعرض مؤشر التحميل ويمنع الضغط', (t) async {
    var taps = 0;
    await t.pumpWidget(_host(WButton('حفظ', loading: true, onPressed: () => taps++)));
    await t.tap(find.byType(WButton), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 300));
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
