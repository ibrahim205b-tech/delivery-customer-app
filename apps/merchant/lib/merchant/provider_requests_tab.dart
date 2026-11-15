import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// تبويب الطلبات العام لمقدم الخدمة (كل الأنشطة التي تستقبل طلبات):
/// السعر قبل القبول، القبول أو الرفض بسبب، البدء، والإتمام.
class ProviderRequestsTab extends StatefulWidget {
  const ProviderRequestsTab({super.key, required this.merchant});
  final Merchant merchant;
  @override
  State<ProviderRequestsTab> createState() => _ProviderRequestsTabState();
}

class _ProviderRequestsTabState extends State<ProviderRequestsTab> {
  late Future<List<ServiceRequest>> _requests = merchantApi.providerRequests(widget.merchant.id);

  void _reload() => setState(() => _requests = merchantApi.providerRequests(widget.merchant.id));

  Future<void> _setAmount(ServiceRequest r) async {
    final v = await promptText(context, title: 'حدد السعر', hint: 'بالدينار العراقي', confirm: 'حفظ', keyboard: TextInputType.number);
    final amount = int.tryParse((v ?? '').trim());
    if (amount == null || amount < 0 || !mounted) return;
    if (await runAction(context, () => merchantApi.setRequestAmount(r.id, amount), success: 'انحفظ السعر')) _reload();
  }

  Future<void> _respond(ServiceRequest r, bool accept) async {
    var reason = '';
    if (!accept) {
      final v = await promptText(context, title: 'سبب الرفض', hint: 'مثال: غير متاح في هذا الموعد', confirm: 'رفض');
      if (v == null || v.trim().length < 3 || !mounted) return;
      reason = v.trim();
    }
    if (await runAction(context, () => merchantApi.respondServiceRequest(r.id, accept: accept, reason: reason), success: accept ? 'تم القبول' : 'تم الرفض')) _reload();
  }

  Future<void> _advance(ServiceRequest r, String to) async {
    if (await runAction(context, () => merchantApi.setServiceRequestStatus(r.id, to), success: to == 'completed' ? 'انتهى الطلب' : 'بدأ التنفيذ')) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ServiceRequest>>(
        future: _requests,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const SkeletonList(count: 4);
          final rows = snap.data!;
          if (rows.isEmpty) return const EmptyView(icon: Icons.inbox_outlined, title: 'ما في طلبات بعد', message: 'أول ما يطلب زبون خدمتك يظهر هنا.');
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: WCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(r.placeName.isEmpty ? (kServiceNames[r.serviceId] ?? 'طلب خدمة') : r.placeName, style: WText.bodyStrong)),
                        StatusPill(r.statusLabel, tone: r.status == 'requested' ? PillTone.accent : PillTone.neutral),
                      ]),
                      if (r.startsAt != null) Text(dateTimeAr(r.startsAt!), style: WText.small),
                      if (r.payload.isNotEmpty && r.placeName.isEmpty)
                        for (final e in r.payload.entries) Text('${e.key}: ${e.value}', style: WText.small),
                      Text(r.amount > 0 ? 'السعر: ${iqd(r.amount)}' : 'السعر: لم يُحدد بعد', style: WText.small),
                      const SizedBox(height: 8),
                      if (r.status == 'requested') ...[
                        WButton('حدد السعر', kind: WButtonKind.secondary, compact: true, onPressed: () => _setAmount(r)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: WButton('قبول', kind: WButtonKind.dark, compact: true, onPressed: r.amount > 0 ? () => _respond(r, true) : null)),
                          const SizedBox(width: 8),
                          Expanded(child: WButton('رفض', kind: WButtonKind.ghost, compact: true, onPressed: () => _respond(r, false))),
                        ]),
                      ],
                      if (r.status == 'accepted')
                        WButton('بدأ التنفيذ', kind: WButtonKind.secondary, compact: true, onPressed: () => _advance(r, 'in_progress')),
                      if (r.status == 'accepted' || r.status == 'in_progress')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: WButton('تم الإنجاز', compact: true, onPressed: () => _advance(r, 'completed')),
                        ),
                    ]),
                  ),
                ),
            ]),
          );
        },
      );
}
