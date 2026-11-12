import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// رسم أعمدة يومية: العمود الكامل = كل الطلبات، الجزء الليموني = المسلّمة.
class DailyBarsChart extends StatelessWidget {
  const DailyBarsChart({super.key, required this.days, this.height = 170});
  final List<Map<String, dynamic>> days;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxV = days.fold<int>(0, (a, d) => math.max(a, (d['orders'] as num).toInt()));
    if (maxV == 0) {
      return SizedBox(
        height: height,
        child: Center(child: Text('ما اكو طلبات بهذه الفترة بعد', style: WText.small)),
      );
    }
    return Semantics(
      label: 'رسم الطلبات اليومية: أعلى يوم $maxV طلب',
      child: SizedBox(
        height: height + 22,
        child: Column(children: [
          SizedBox(
            height: height,
            child: Directionality(
              // الزمن من اليسار لليمين مثل كل الرسوم
              textDirection: TextDirection.ltr,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final d in days)
                  Expanded(
                    child: Tooltip(
                      message: '${d['day']}: ${d['orders']} طلب، ${d['delivered']} مسلّم',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: _bar((d['orders'] as num).toInt(), (d['delivered'] as num).toInt(), maxV),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Text(
                    i == 0 || i == days.length - 1 || i == days.length ~/ 2 ? '${DateTime.parse(days[i]['day'] as String).day}/${DateTime.parse(days[i]['day'] as String).month}' : '',
                    textAlign: TextAlign.center,
                    style: WText.caption.copyWith(fontSize: 10.5),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bar(int total, int delivered, int maxV) => LayoutBuilder(builder: (context, c) {
        final h = c.maxHeight;
        final th = total == 0 ? 3.0 : math.max(6.0, h * total / maxV);
        final dh = total == 0 ? 0.0 : th * delivered / total;
        return Stack(alignment: Alignment.bottomCenter, children: [
          AnimatedContainer(duration: WDurations.slow, curve: WDurations.curve, height: th, decoration: BoxDecoration(color: total == 0 ? WColors.line : WColors.fg, borderRadius: WRadius.all(4))),
          AnimatedContainer(duration: WDurations.slow, curve: WDurations.curve, height: dh, decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(4))),
        ]);
      });
}

/// أعمدة أفقية لقائمة (قسم → عدد)
class HorizontalBars extends StatelessWidget {
  const HorizontalBars({super.key, required this.items, this.color});
  final List<(String, int)> items;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('ما اكو بيانات بعد', style: WText.small));
    final maxV = items.map((e) => e.$2).reduce(math.max);
    return Column(children: [
      for (final it in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 110, child: Text(it.$1, style: WText.small.copyWith(color: WColors.fg), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedContainer(
                    duration: WDurations.slow,
                    height: 12,
                    width: math.max(4, c.maxWidth * it.$2 / maxV),
                    decoration: BoxDecoration(color: color ?? WColors.fg, borderRadius: WRadius.all(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 34, child: Text('${it.$2}', style: WText.number.copyWith(fontSize: 13), textAlign: TextAlign.end)),
          ]),
        ),
    ]);
  }
}

/// شريط توزيع مكدّس (حالات الطلبات)
class StackedShareBar extends StatelessWidget {
  const StackedShareBar({super.key, required this.parts});
  final List<(String, int, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<int>(0, (a, p) => a + p.$2);
    if (total == 0) return Text('ما اكو طلبات بهذه الفترة', style: WText.small);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: WRadius.all(6),
        child: SizedBox(
          height: 14,
          child: Row(children: [
            for (final p in parts.where((p) => p.$2 > 0)) Expanded(flex: p.$2, child: Container(color: p.$3)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final p in parts)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: p.$3, borderRadius: WRadius.all(3))),
            const SizedBox(width: 6),
            Text('${p.$1} ${p.$2}', style: WText.caption.copyWith(color: WColors.fg)),
          ]),
      ]),
    ]);
  }
}
