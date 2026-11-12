import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// إحصائيات اليوم والأسبوع (من الخادم بتوقيت بغداد)
class StatsTab extends StatelessWidget {
  const StatsTab({super.key, required this.merchant});
  final Merchant merchant;

  @override
  Widget build(BuildContext context) => AsyncView<Map<String, dynamic>>(
        load: () async {
          final r = await Future.wait([merchantApi.stats(merchant.id), merchantApi.commission(merchant.id).catchError((_) => <String, dynamic>{})]);
          return {...r[0], 'commission': r[1]};
        },
        builder: (context, s, reload) {
          int n(String k) => (s[k] as num?)?.toInt() ?? 0;
          final c = (s['commission'] as Map?)?.cast<String, dynamic>() ?? const {};
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
              WCard(
                color: WColors.night,
                borderColor: WColors.night,
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('مبيعات اليوم', style: WText.small.copyWith(color: WColors.lime)),
                  const SizedBox(height: 4),
                  Text(iqd(n('today_sales')), style: WText.display.copyWith(color: WColors.white)),
                  const SizedBox(height: 8),
                  Text('آخر 7 أيام: ${iqd(n('week_sales'))}', style: WText.body.copyWith(color: WColors.white.withValues(alpha: 0.8))),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _tile('طلبات اليوم', n('today_orders'), Icons.receipt_long_rounded, WColors.fg)),
                const SizedBox(width: 10),
                Expanded(child: _tile('قيد العمل', n('active'), Icons.timelapse_rounded, WColors.blue)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _tile('تم تسليمها', n('today_delivered'), Icons.check_circle_rounded, WColors.success)),
                const SizedBox(width: 10),
                Expanded(child: _tile('ملغاة', n('today_cancelled'), Icons.cancel_rounded, WColors.danger)),
              ]),
              const SizedBox(height: 16),
              Text('المبيعات تحسب الطلبات المسلّمة فقط (بدون أجور التوصيل).', style: WText.caption),
              if (c.isNotEmpty) ...[const SizedBox(height: 16), _commission(c)],
              const SizedBox(height: 16),
              WCard(
                child: Row(children: [
                  Icon(Icons.star_rounded, color: WColors.link),
                  const SizedBox(width: 8),
                  Expanded(child: Text('تقييم المحل', style: WText.bodyStrong)),
                  Text(merchant.ratingCount == 0 ? 'لا يوجد بعد' : '${merchant.ratingAvg.toStringAsFixed(1)} من ${merchant.ratingCount} تقييم', style: WText.small),
                ]),
              ),
            ]),
          );
        },
      );

  Widget _tile(String label, int value, IconData icon, Color color) => WCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text('$value', style: WText.h1),
          Text(label, style: WText.small),
        ]),
      );

  /// عمولة واصل: النسبة، عمولة الشهر، والمتبقي للتسليم نقداً
  Widget _commission(Map<String, dynamic> c) {
    final pct = (c['percent'] as num?) ?? 0;
    final pctText = pct == pct.roundToDouble() ? '${pct.toInt()}%' : '${pct.toStringAsFixed(1)}%';
    final due = (c['due'] as num?)?.toInt() ?? 0;
    final settlements = ((c['settlements'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return WCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('عمولة واصل', style: WText.h3)),
          StatusPill(pct == 0 ? 'بدون عمولة' : pctText, tone: pct == 0 ? PillTone.neutral : PillTone.info),
        ]),
        const SizedBox(height: 4),
        Text(pct == 0 ? 'حالياً ما اكو عمولة على طلباتك.' : 'على مبلغ المنتجات بالطلبات المسلّمة فقط، بدون أجور التوصيل.', style: WText.caption),
        const Divider(height: 24),
        Row(children: [
          Expanded(child: _fig('عمولة هذا الشهر', iqd((c['month_commission'] as num?)?.toInt() ?? 0))),
          Expanded(child: _fig('مبيعات الشهر المسلّمة', iqd((c['month_sales'] as num?)?.toInt() ?? 0))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _fig('المدفوع لواصل', iqd((c['settled_total'] as num?)?.toInt() ?? 0))),
          Expanded(child: _fig('المتبقي عليك', iqd(due), strong: due > 0)),
        ]),
        if (settlements.isNotEmpty) ...[
          const Divider(height: 24),
          Text('آخر الدفعات', style: WText.label.copyWith(color: WColors.inkMuted)),
          for (final x in settlements.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: Text('${dateAr(DateTime.parse(x['created_at'] as String).toLocal())}${(x['note'] as String? ?? '').isEmpty ? '' : ' · ${x['note']}'}', style: WText.small)),
                Text(iqd((x['amount'] as num).toInt()), style: WText.bodyStrong),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _fig(String label, String value, {bool strong = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: WText.price.copyWith(color: strong ? WColors.link : WColors.fg)),
        Text(label, style: WText.caption),
      ]);
}
