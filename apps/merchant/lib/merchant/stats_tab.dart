import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// إحصائيات اليوم والأسبوع (من الخادم بتوقيت بغداد)
class StatsTab extends StatelessWidget {
  const StatsTab({super.key, required this.merchant});
  final Merchant merchant;

  @override
  Widget build(BuildContext context) => AsyncView<Map<String, dynamic>>(
        load: () => merchantApi.stats(merchant.id),
        builder: (context, s, reload) {
          int n(String k) => (s[k] as num?)?.toInt() ?? 0;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
              WCard(
                color: WColors.ink,
                borderColor: WColors.ink,
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
                Expanded(child: _tile('طلبات اليوم', n('today_orders'), Icons.receipt_long_rounded, WColors.ink)),
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
              const SizedBox(height: 16),
              WCard(
                child: Row(children: [
                  const Icon(Icons.star_rounded, color: WColors.blue),
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
}
