import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import 'charts.dart';
import 'ops_map.dart';
import 'support_inbox.dart';

/// لوحة المؤشرات: أرقام لحظية + رسوم من بيانات حقيقية (admin_reports)
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onOpenMerchants, required this.onOpenOrders});
  final VoidCallback onOpenMerchants;
  final VoidCallback onOpenOrders;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _days = 14;
  late Future<(Map<String, dynamic>, Map<String, dynamic>?)> _data = _load();

  Future<(Map<String, dynamic>, Map<String, dynamic>?)> _load() async {
    final stats = await adminApi.stats();
    Map<String, dynamic>? reports;
    try {
      reports = await adminApi.reports(days: _days);
    } catch (e) {
      // فقط إذا الدالة غير موجودة (قاعدة البيانات ما محدّثة بـ 0006) نعرض التنبيه؛ غير ذلك خطأ حقيقي
      final msg = e.toString();
      if (!(msg.contains('PGRST202') || msg.contains('admin_reports'))) rethrow;
      reports = null;
    }
    return (stats, reports);
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _data = f);
    await f.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: WSpace.page,
          title: Row(children: [
            const WaselMark(size: 30),
            const SizedBox(width: 10),
            Text('لوحة التحكم', style: WText.h2),
          ]),
          actions: [
            const SupportInboxButton(),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(child: Text(auth.profile?.fullName ?? '', style: WText.caption)),
            ),
          ],
        ),
        body: FutureBuilder(
          future: _data,
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
            if (!s.hasData) return const SkeletonList(count: 4, itemHeight: 120);
            final (st, rep) = s.data!;
            int n(String k) => (st[k] as num?)?.toInt() ?? 0;
            return RefreshIndicator(
              onRefresh: _reload,
              child: LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final kpis = _kpiGrid(n, wide ? 4 : 2);
                return ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32), children: [
                  if (n('merchants_pending') > 0) ...[_pendingBanner(n('merchants_pending')), const SizedBox(height: 12)],
                  _liveHero(n),
                  const SizedBox(height: 12),
                  kpis,
                  const SizedBox(height: 16),
                  if (rep == null)
                    WCard(
                      color: WColors.warningSoft,
                      borderColor: Colors.transparent,
                      child: Text('الرسوم البيانية تحتاج تحديث قاعدة البيانات: شغّل الملف supabase/migrations/0006_admin_reports.sql بـ SQL Editor.', style: WText.small.copyWith(color: WColors.fg)),
                    )
                  else if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: _trendCard(rep)),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: _breakdownCard(rep)),
                    ])
                  else ...[
                    _trendCard(rep),
                    const SizedBox(height: 12),
                    _breakdownCard(rep),
                  ],
                  const SizedBox(height: 12),
                  _mapCard(),
                  const SizedBox(height: 12),
                  _areasCard(st),
                ]);
              }),
            );
          },
        ),
      );

  Widget _pendingBanner(int count) => WCard(
        color: WColors.lime,
        borderColor: Colors.transparent,
        onTap: widget.onOpenMerchants,
        child: Row(children: [
          Icon(Icons.pending_actions_rounded, color: WColors.ink),
          const SizedBox(width: 10),
          Expanded(child: Text('$count محل بانتظار الاعتماد', style: WText.h3.copyWith(color: WColors.ink))),
          Icon(Icons.arrow_back_rounded, color: WColors.ink),
        ]),
      );

  Widget _liveHero(int Function(String) n) => WCard(
        color: WColors.night,
        borderColor: WColors.night,
        onTap: widget.onOpenOrders,
        padding: const EdgeInsets.all(20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(2))),
                const SizedBox(width: 8),
                Text('جارية الآن', style: WText.label.copyWith(color: WColors.inkFaint)),
              ]),
              const SizedBox(height: 6),
              Text('${n('orders_active')}', style: WText.number.copyWith(fontSize: 48, color: WColors.white, height: 1)),
              Text('طلب من المحلات', style: WText.small.copyWith(color: WColors.inkFaint)),
            ]),
          ),
          _liveStat('رحلات', n('rides_active')),
          const SizedBox(width: 18),
          _liveStat('توصيل أغراض', n('tasks_active')),
          const SizedBox(width: 18),
          _liveStat('خدمات', n('bookings_open')),
        ]),
      );

  Widget _liveStat(String label, int v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$v', style: WText.number.copyWith(fontSize: 22, color: WColors.lime)),
        Text(label, style: WText.caption.copyWith(color: WColors.inkFaint)),
      ]);

  Widget _kpiGrid(int Function(String) n, int cols) {
    final items = [
      ('المستخدمون', n('users'), Icons.people_alt_outlined),
      ('المحلات', n('merchants'), Icons.storefront_outlined),
      ('كل الطلبات', n('orders'), Icons.receipt_long_outlined),
      ('مكتملة', n('orders_delivered'), Icons.check_circle_outline_rounded),
      ('ملغاة', n('orders_cancelled'), Icons.cancel_outlined),
      ('الخدمات المنزلية', n('bookings'), Icons.home_repair_service_outlined),
      ('السائقون', n('drivers'), Icons.two_wheeler_outlined),
      ('المتاحون الآن', n('drivers_available'), Icons.radar_rounded),
    ];
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: cols == 4 ? 3.0 : 1.9,
      children: [
        for (final it in items)
          WCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Expanded(child: Text(it.$1, style: WText.label.copyWith(color: WColors.inkMuted))),
                Icon(it.$3, size: 18, color: WColors.inkMuted),
              ]),
              Text('${it.$2}', style: WText.number.copyWith(fontSize: 26)),
            ]),
          ),
      ],
    );
  }

  Widget _trendCard(Map<String, dynamic> rep) {
    final daily = ((rep['daily'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final totalOrders = daily.fold<int>(0, (a, d) => a + (d['orders'] as num).toInt());
    final sales = daily.fold<int>(0, (a, d) => a + (d['sales'] as num).toInt());
    final rides = daily.fold<int>(0, (a, d) => a + (d['rides'] as num).toInt());
    return WCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('الطلبات اليومية', style: WText.h3)),
          SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [ButtonSegment(value: 7, label: Text('7 أيام')), ButtonSegment(value: 14, label: Text('14')), ButtonSegment(value: 30, label: Text('30'))],
            selected: {_days},
            onSelectionChanged: (v) {
              _days = v.first;
              _reload();
            },
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 22, runSpacing: 8, children: [
          _figure('طلبات', '$totalOrders'),
          _figure('مبيعات مسلّمة', iqd(sales)),
          _figure('رحلات', '$rides'),
        ]),
        const SizedBox(height: 16),
        DailyBarsChart(days: daily),
        const SizedBox(height: 8),
        Row(children: [
          _legend(WColors.fg, 'كل الطلبات'),
          const SizedBox(width: 14),
          _legend(WColors.lime, 'مسلّمة'),
        ]),
      ]),
    );
  }

  Widget _breakdownCard(Map<String, dynamic> rep) {
    final bs = (rep['by_status'] as Map?)?.cast<String, dynamic>() ?? const {};
    int st(List<String> keys) => keys.fold(0, (a, k) => a + ((bs[k] as num?)?.toInt() ?? 0));
    final cats = ((rep['by_category'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final top = ((rep['top_merchants'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return WCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('حالات الطلبات', style: WText.h3),
        const SizedBox(height: 12),
        StackedShareBar(parts: [
          ('مسلّمة', st(['delivered']), WColors.lime),
          ('جارية', st(['placed', 'accepted', 'preparing', 'ready', 'picked_up', 'on_the_way']), WColors.blue),
          ('ملغاة', st(['cancelled']), WColors.danger),
        ]),
        const Divider(height: 30),
        Text('حسب القسم', style: WText.h3),
        const SizedBox(height: 8),
        HorizontalBars(items: [for (final c in cats) (c['category'] as String, (c['orders'] as num).toInt())]),
        const Divider(height: 30),
        Text('أكثر المحلات تسليماً', style: WText.h3),
        const SizedBox(height: 8),
        if (top.isEmpty) Text('ما اكو طلبات مسلّمة بعد', style: WText.small),
        for (var i = 0; i < top.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${i + 1}', style: WText.number.copyWith(color: i == 0 ? WColors.fg : WColors.inkFaint))),
              Expanded(child: Text(top[i]['name'] as String, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${top[i]['delivered']} طلب', style: WText.caption),
              const SizedBox(width: 10),
              Text(iqd((top[i]['sales'] as num).toInt()), style: WText.price.copyWith(fontSize: 13)),
            ]),
          ),
      ]),
    );
  }

  Widget _mapCard() => WCard(
        padding: EdgeInsets.zero,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpsMapScreen())),
        child: Row(children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: WColors.night, borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(WRadius.lg))),
            child: Icon(Icons.map_rounded, color: WColors.lime, size: 36),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('خريطة العمليات', style: WText.h3),
              Text('السائقون، الطلبات الجارية، المحلات، والمناطق', style: WText.small),
            ]),
          ),
          const Padding(padding: EdgeInsets.all(14), child: Icon(Icons.arrow_back_rounded)),
        ]),
      );

  Widget _areasCard(Map<String, dynamic> st) {
    final areas = (st['areas'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return WCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('المناطق', style: WText.h3),
        const SizedBox(height: 8),
        if (areas.isEmpty) Text('ما مضاف مناطق بعد. أضفها من "المزيد ← المناطق".', style: WText.small),
        HorizontalBars(items: [for (final a in areas) (a['name'] as String, (a['orders'] as num).toInt())], color: WColors.blue),
        if (areas.isNotEmpty) Text('عدد الطلبات لكل منطقة', style: WText.caption),
      ]),
    );
  }

  Widget _figure(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: WText.number.copyWith(fontSize: 20)),
        Text(label, style: WText.caption),
      ]);

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: WRadius.all(3))),
        const SizedBox(width: 6),
        Text(t, style: WText.caption),
      ]);
}
