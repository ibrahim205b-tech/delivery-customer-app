import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// حداثة موقع السائق. السائق يرسل موقعه كل 15 ثانية، فالحدود مبنية على ذلك:
///   live    : أقل من دقيقة (وصلنا تحديث حديث)
///   recent  : من دقيقة إلى 5 دقائق (تأخر بسيط، ممكن ضعف إشارة)
///   stale   : أكثر من 5 دقائق — لا يُعرض كموقع مباشر
///   unknown : ما وصلنا أي موقع بعد
enum Freshness { live, recent, stale, unknown }

const kLiveWithin = Duration(minutes: 1);
const kRecentWithin = Duration(minutes: 5);

/// يحسب الحداثة من وقت آخر تحديث. [now] قابل للحقن للاختبار.
/// وقت في المستقبل (فرق ساعة الجهاز) يُعامل كـ live بدل ما يطلع سالب.
Freshness freshnessOf(DateTime? at, {DateTime? now}) {
  if (at == null) return Freshness.unknown;
  final age = (now ?? DateTime.now()).difference(at);
  if (age <= kLiveWithin) return Freshness.live;
  if (age <= kRecentWithin) return Freshness.recent;
  return Freshness.stale;
}

/// نص عربي واضح لوقت آخر تحديث
String freshnessLabelAr(DateTime? at, {DateTime? now}) {
  final f = freshnessOf(at, now: now);
  if (f == Freshness.unknown) return 'ما وصلنا موقع بعد';
  final age = (now ?? DateTime.now()).difference(at!);
  final mins = age.inMinutes;
  return switch (f) {
    Freshness.live => 'مباشر الآن',
    Freshness.recent => 'آخر تحديث قبل ${age.inSeconds < 90 ? 'دقيقة' : '$mins دقيقة'}',
    Freshness.stale => 'آخر موقع معروف منذ ${mins >= 60 ? '${age.inHours} ساعة' : '$mins دقيقة'}',
    Freshness.unknown => 'ما وصلنا موقع بعد',
  };
}

/// شارة صغيرة: نقطة ملونة + النص. ألوانها من نظام الألوان الحالي (تتبع الوضع الليلي).
class FreshnessBadge extends StatelessWidget {
  const FreshnessBadge({super.key, required this.at, this.now});
  final DateTime? at;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final f = freshnessOf(at, now: now);
    final color = switch (f) {
      Freshness.live => WColors.success,
      Freshness.recent => WColors.warning,
      Freshness.stale => WColors.danger,
      Freshness.unknown => WColors.inkFaint,
    };
    return Semantics(
      label: freshnessLabelAr(at, now: now),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(WRadius.pill), border: Border.all(color: WColors.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(freshnessLabelAr(at, now: now), style: WText.caption.copyWith(color: WColors.fg), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}
