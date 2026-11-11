import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenMerchants, required this.onOpenOrders});
  final VoidCallback onOpenMerchants;
  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: WSpace.page,
          title: const WaselWordmark(height: 30),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Center(child: Text(auth.profile?.fullName ?? '', style: WText.caption)),
            ),
          ],
        ),
        body: AsyncView<Map<String, dynamic>>(
          load: adminApi.stats,
          builder: (context, s, reload) {
            int n(String k) => (s[k] as num?)?.toInt() ?? 0;
            final areas = (s['areas'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
                if (n('merchants_pending') > 0) ...[
                  WCard(
                    color: WColors.warningSoft,
                    borderColor: Colors.transparent,
                    onTap: onOpenMerchants,
                    child: Row(children: [
                      const Icon(Icons.pending_actions_rounded, color: WColors.warning),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${n('merchants_pending')} محل بانتظار الاعتماد', style: WText.bodyStrong)),
                      const Icon(Icons.chevron_left_rounded),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
                WCard(
                  color: WColors.navy,
                  borderColor: WColors.navy,
                  onTap: onOpenOrders,
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('طلبات جارية الآن', style: WText.small.copyWith(color: WColors.mint)),
                        Text('${n('orders_active')}', style: WText.display.copyWith(color: WColors.white, fontSize: 40)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('رحلات جارية ${n('rides_active')}', style: WText.small.copyWith(color: WColors.white)),
                      Text('توصيل أغراض ${n('tasks_active')}', style: WText.small.copyWith(color: WColors.white)),
                      Text('خدمات مفتوحة ${n('bookings_open')}', style: WText.small.copyWith(color: WColors.white)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.55,
                  children: [
                    _tile('المستخدمون', n('users'), Icons.people_alt_outlined, WColors.navy),
                    _tile('المحلات', n('merchants'), Icons.storefront_outlined, WColors.coralDeep),
                    _tile('كل الطلبات', n('orders'), Icons.receipt_long_outlined, WColors.info),
                    _tile('مكتملة', n('orders_delivered'), Icons.check_circle_outline_rounded, WColors.mintDeep),
                    _tile('ملغاة', n('orders_cancelled'), Icons.cancel_outlined, WColors.danger),
                    _tile('الخدمات المنزلية', n('bookings'), Icons.home_repair_service_outlined, WColors.warning),
                    _tile('السائقون', n('drivers'), Icons.two_wheeler_outlined, WColors.navy),
                    _tile('المتاحون الآن', n('drivers_available'), Icons.radar_rounded, WColors.mintDeep),
                  ],
                ),
                const SectionTitle('المناطق', padding: EdgeInsets.fromLTRB(0, 24, 0, 10)),
                if (areas.isEmpty)
                  Text('ما مضاف مناطق بعد. أضفها من "المزيد ← المناطق".', style: WText.small)
                else
                  WCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (final a in areas)
                        ListTile(
                          leading: const Icon(Icons.map_outlined),
                          title: Text(a['name'] as String),
                          trailing: Text('${a['merchants']} محل · ${a['orders']} طلب', style: WText.small),
                        ),
                    ]),
                  ),
              ]),
            );
          },
        ),
      );

  Widget _tile(String label, int v, IconData icon, Color c) => WCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(icon, color: c),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$v', style: WText.h1),
            Text(label, style: WText.small),
          ]),
        ]),
      );
}
