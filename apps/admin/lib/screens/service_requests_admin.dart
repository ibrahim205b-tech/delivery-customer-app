import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// مراقبة طلبات الخدمات: كل الطلبات، مع فلتر حسب الحالة، ومجموع العمولات لكل خدمة.
/// للقراءة فقط: التعديلات تتم من أصحاب المحلات عبر دوال الخادم، والإدارة تراقب وتتدخل عبر الدوال المخصصة.
class ServiceRequestsAdminScreen extends StatefulWidget {
  const ServiceRequestsAdminScreen({super.key});
  @override
  State<ServiceRequestsAdminScreen> createState() => _ServiceRequestsAdminScreenState();
}

class _ServiceRequestsAdminScreenState extends State<ServiceRequestsAdminScreen> {
  String? _status;
  late Future<({List<ServiceRequest> rows, Map<String, int> commissions})> _data = _load();

  Future<({List<ServiceRequest> rows, Map<String, int> commissions})> _load() async =>
      (rows: await adminApi.serviceRequests(status: _status), commissions: await adminApi.serviceCommissionTotals());

  void _reload() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('طلبات الخدمات')),
        body: FutureBuilder<({List<ServiceRequest> rows, Map<String, int> commissions})>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            if (!snap.hasData) return const SkeletonList(count: 4);
            final d = snap.data!;
            return ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32), children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in <String?>[null, 'requested', 'accepted', 'in_progress', 'completed', 'rejected', 'cancelled'])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(s == null ? 'الكل' : kServiceStatusLabels[s] ?? s),
                        selected: _status == s,
                        onSelected: (_) {
                          _status = s;
                          _reload();
                        },
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              if (d.commissions.isNotEmpty)
                WCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('عمولات واصل حسب الخدمة', style: WText.h3),
                    const SizedBox(height: 6),
                    for (final e in d.commissions.entries) Row(children: [Expanded(child: Text(e.key, style: WText.small)), Text(iqd(e.value), style: WText.bodyStrong)]),
                  ]),
                ),
              const SizedBox(height: 12),
              if (d.rows.isEmpty) const EmptyView(icon: Icons.assignment_outlined, title: 'ما في طلبات بهذا الفلتر'),
              for (final r in d.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(r.placeName.isEmpty ? r.serviceId : r.placeName, style: WText.bodyStrong)),
                        StatusPill(r.statusLabel, tone: PillTone.neutral),
                      ]),
                      Text('${dateTimeAr(r.createdAt)} · ${iqd(r.amount)}', style: WText.caption),
                      if (r.rejectReason.isNotEmpty) Text('سبب الرفض: ${r.rejectReason}', style: WText.small),
                      if (r.cancelReason.isNotEmpty) Text('سبب الإلغاء: ${r.cancelReason}', style: WText.small),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}
