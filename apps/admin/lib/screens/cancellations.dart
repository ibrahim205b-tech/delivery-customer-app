import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';


const _partyLabels = {'customer': 'زبون', 'driver': 'سائق', 'admin': 'الإدارة', 'system': 'النظام'};
const _actionLabels = {'ride.cancel': 'إلغاء رحلة من الإدارة', 'restriction.lift': 'رفع إيقاف'};
const _kindLabels = {'customer_rides': 'إيقاف طلب الرحلات (زبون · 24 ساعة)', 'driver_dispatch': 'إيقاف استقبال الطلبات (سائق · 25 دقيقة)'};

DateTime _at(Object? v) => DateTime.parse('$v').toLocal();
String _when(Object? v) => dateTimeAr(_at(v));

/// الإلغاءات والإيقافات: كل البيانات من قاعدة البيانات (دوال الإدارة مع فحص الصلاحية في الخادم)
class CancellationsScreen extends StatelessWidget {
  const CancellationsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الإلغاءات والإيقافات'),
            bottom: const TabBar(tabs: [Tab(text: 'الإلغاءات'), Tab(text: 'الإيقافات'), Tab(text: 'سجل التدقيق')]),
          ),
          body: const TabBarView(children: [_CancelTab(), _RestrictionsTab(), _AuditTab()]),
        ),
      );
}

class _CancelTab extends StatefulWidget {
  const _CancelTab();
  @override
  State<_CancelTab> createState() => _CancelTabState();
}

class _CancelTabState extends State<_CancelTab> {
  int _key = 0;
  String? _party;
  String _search = '';
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
        _search = _q.text.trim();
        _key++;
      });

  @override
  Widget build(BuildContext context) => AsyncView<(Json, List<Json>)>(
        key: ValueKey(_key),
        load: () async => (await adminApi.cancellationSummary(), await adminApi.cancellations(party: _party, search: _search)),
        builder: (context, d, reload) {
          final s = d.$1;
          final rows = d.$2;
          return ListView(padding: const EdgeInsets.all(WSpace.page), children: [
            Text('اليوم (بتوقيت بغداد)', style: WText.h3),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _stat('إجمالي الإلغاءات', '${s['today_total']}'),
              _stat('من الزبائن', '${s['today_customer']}'),
              _stat('من السائقين', '${s['today_driver']}'),
              _stat('من الإدارة', '${s['today_admin']}'),
              _stat('زبائن موقوفون', '${s['restricted_customers']}'),
              _stat('سائقون موقوفون', '${s['restricted_drivers']}'),
            ]),
            const SizedBox(height: 14),
            if ((s['reasons_today'] as List).isNotEmpty) ...[
              Text('أسباب اليوم', style: WText.h3),
              const SizedBox(height: 6),
              WCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final r in (s['reasons_today'] as List).cast<Json>())
                    ListTile(
                      dense: true,
                      title: Text('${r['reason']}'),
                      subtitle: Text(_partyLabels['${r['party']}'] ?? '${r['party']}', style: WText.small),
                      trailing: Text('${r['count']}', style: WText.bodyStrong),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
            ],
            Text('السجل', style: WText.h3),
            const SizedBox(height: 8),
            TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: 'ابحث برقم الرحلة أو اسم/هاتف الزبون أو السائق',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _refresh),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final e in const [(null, 'الكل'), ('customer', 'الزبائن'), ('driver', 'السائقون'), ('admin', 'الإدارة'), ('system', 'النظام')])
                ChoiceChip(
                  label: Text(e.$2),
                  selected: _party == e.$1,
                  onSelected: (_) => setState(() {
                    _party = e.$1;
                    _key++;
                  }),
                ),
            ]),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const EmptyView(icon: Icons.search_off_rounded, title: 'ما في إلغاءات', message: 'غيّر الفلتر أو البحث.')
            else
              WCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final c in rows)
                    ExpansionTile(
                      title: Text('${_partyLabels[c['party']] ?? c['party']} · ${c['reason_label']}', style: WText.bodyStrong),
                      subtitle: Text(
                        '${_when(c['cancelled_at'])} · الزبون ${c['customer_name'] ?? ''}${(c['driver_name'] ?? '').toString().isEmpty ? '' : ' · السائق ${c['driver_name']}'}',
                        style: WText.small,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('رقم الرحلة: ${c['ride_id']}', style: WText.small),
                        Text('الحالة قبل الإلغاء: ${c['ride_status_before']}', style: WText.small),
                        Text('الانطلاق: ${c['pickup_text']}', style: WText.small),
                        Text('الوجهة: ${c['dropoff_text']}', style: WText.small),
                        Text('الزبون: ${c['customer_name']} · ${c['customer_phone']}', style: WText.small),
                        if ((c['driver_name'] ?? '').toString().isNotEmpty) Text('السائق: ${c['driver_name']} · ${c['driver_phone']}', style: WText.small),
                        if ((c['note'] ?? '').toString().isNotEmpty) Text('التوضيح: ${c['note']}', style: WText.small),
                      ],
                    ),
                ]),
              ),
            const SizedBox(height: 20),
            Center(child: TextButton.icon(onPressed: reload, icon: const Icon(Icons.refresh_rounded), label: const Text('تحديث'))),
          ]);
        },
      );

  Widget _stat(String label, String value) => SizedBox(
        width: 150,
        child: WCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: WText.h2),
            const SizedBox(height: 2),
            Text(label, style: WText.small),
          ]),
        ),
      );
}

class _RestrictionsTab extends StatefulWidget {
  const _RestrictionsTab();
  @override
  State<_RestrictionsTab> createState() => _RestrictionsTabState();
}

class _RestrictionsTabState extends State<_RestrictionsTab> {
  int _key = 0;
  bool _activeOnly = true;

  Future<void> _lift(Json r) async {
    final reason = await promptText(context, title: 'سبب رفع الإيقاف', hint: 'مثلاً: تم التحقق من الحالة', confirm: 'رفع الإيقاف');
    if (reason == null || !mounted) return;
    if (reason.trim().length < 5) return showError(context, 'اكتب السبب (5 أحرف على الأقل).');
    if (await runAction(context, () => adminApi.liftRestriction(r['id'] as String, reason), success: 'تم رفع الإيقاف') && mounted) {
      setState(() => _key++);
    }
  }

  @override
  Widget build(BuildContext context) => AsyncView<List<Json>>(
        key: ValueKey(_key),
        load: () => adminApi.restrictions(activeOnly: _activeOnly),
        builder: (context, rows, _) => ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('الإيقافات النشطة فقط'),
            value: _activeOnly,
            onChanged: (v) => setState(() {
              _activeOnly = v;
              _key++;
            }),
          ),
          if (rows.isEmpty)
            const EmptyView(icon: Icons.check_circle_outline_rounded, title: 'ما في إيقافات', message: 'كل الحسابات تشتغل بشكل طبيعي.')
          else
            WCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final r in rows)
                  ListTile(
                    isThreeLine: true,
                    title: Text('${r['full_name'] ?? ''} · ${r['phone'] ?? ''}', style: WText.bodyStrong),
                    subtitle: Text(
                      '${_kindLabels[r['kind']] ?? r['kind']}\n'
                      'من ${_when(r['starts_at'])} حتى ${_when(r['ends_at'])}'
                      '${r['lifted_at'] != null ? '\nمرفوع: ${r['lift_reason']}' : ''}',
                      style: WText.small,
                    ),
                    trailing: _isActive(r)
                        ? TextButton(onPressed: () => _lift(r), child: const Text('رفع'))
                        : Text(r['lifted_at'] != null ? 'مرفوع' : 'منتهٍ', style: WText.small),
                  ),
              ]),
            ),
        ]),
      );

  bool _isActive(Json r) => r['lifted_at'] == null && _at(r['ends_at']).isAfter(DateTime.now());
}

class _AuditTab extends StatelessWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context) => AsyncView<List<Json>>(
        load: () => adminApi.auditLog(),
        builder: (context, rows, reload) => ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          Text('كل إجراء يقوم به أحد المسؤولين يُسجَّل هنا.', style: WText.small),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const EmptyView(icon: Icons.history_rounded, title: 'السجل فاضي', message: 'ما صار أي إجراء بعد.')
          else
            WCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final a in rows)
                  ListTile(
                    title: Text(_actionLabels[a['action']] ?? '${a['action']}', style: WText.bodyStrong),
                    subtitle: Text(
                      '${_when(a['created_at'])} · ${a['actor_name'] ?? 'مسؤول'}\n'
                      'السبب: ${(a['details'] as Map?)?['reason'] ?? '-'}',
                      style: WText.small,
                    ),
                    isThreeLine: true,
                  ),
              ]),
            ),
          const SizedBox(height: 16),
          Center(child: TextButton.icon(onPressed: reload, icon: const Icon(Icons.refresh_rounded), label: const Text('تحديث'))),
        ]),
      );
}
