import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

/// العمولات: النسبة، عمولة الفترة، والمستحق على كل محل مع تسجيل الدفعات النقدية.
class CommissionsScreen extends StatefulWidget {
  const CommissionsScreen({super.key});
  @override
  State<CommissionsScreen> createState() => _CommissionsScreenState();
}

class _CommissionsScreenState extends State<CommissionsScreen> {
  int _days = 30;
  late Future<Map<String, dynamic>> _data = adminApi.commissionSummary(days: _days);

  void _reload() => setState(() => _data = adminApi.commissionSummary(days: _days));

  String _pct(num v) => v == v.roundToDouble() ? '${v.toInt()}%' : '${v.toStringAsFixed(1)}%';

  Future<void> _settle(Map<String, dynamic> m) async {
    final due = (m['due'] as num).toInt();
    final amount = TextEditingController(text: due > 0 ? '$due' : '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('تسجيل دفعة من ${m['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('المتبقي عليه: ${iqd(due)}', style: WText.small),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'المبلغ المستلم نقداً', suffixText: 'د.ع'),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تسجيل')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final v = int.tryParse(amount.text) ?? 0;
    if (await runAction(context, () => adminApi.addSettlement(m['id'] as String, v, note: note.text), success: 'انسجلت الدفعة')) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('العمولات')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
            if (!s.hasData) return const SkeletonList(count: 4);
            final d = s.data!;
            final g = (d['global'] as Map?)?.cast<String, dynamic>() ?? const {};
            final globalOn = g['enabled'] == true;
            final list = ((d['merchants'] as List?) ?? const []).cast<Map<String, dynamic>>();
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32), children: [
                WCard(
                  color: WColors.night,
                  borderColor: WColors.night,
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('عمولة آخر $_days يوم', style: WText.label.copyWith(color: const Color(0xFF98A0A8)))),
                      StatusPill(globalOn ? 'النسبة العامة ${_pct((g['percent'] as num?) ?? 0)}' : 'النسبة العامة معطّلة', tone: globalOn ? PillTone.accent : PillTone.neutral),
                    ]),
                    const SizedBox(height: 8),
                    Text(iqd((d['period_commission'] as num).toInt()), style: WText.number.copyWith(fontSize: 34, color: WColors.white)),
                    Text('من مبيعات مسلّمة ${iqd((d['period_sales'] as num).toInt())}', style: WText.small.copyWith(color: const Color(0xFF98A0A8))),
                    const SizedBox(height: 14),
                    Row(children: [
                      Text('المتبقي على كل المحلات', style: WText.small.copyWith(color: const Color(0xFF98A0A8))),
                      const Spacer(),
                      Text(iqd((d['due_total'] as num).toInt()), style: WText.number.copyWith(fontSize: 18, color: WColors.lime)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 10),
                Text('العمولة على مبلغ المنتجات فقط (بدون أجرة التوصيل)، وتُستحق عند تسليم الطلب. الزبون ما يدفع أي إضافة. النسبة العامة من "إعدادات المنصة"، والخاصة من صفحة كل محل.',
                    style: WText.caption),
                const SizedBox(height: 14),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 7, label: Text('7 أيام')), ButtonSegment(value: 30, label: Text('30 يوم')), ButtonSegment(value: 90, label: Text('90 يوم'))],
                  selected: {_days},
                  onSelectionChanged: (v) {
                    _days = v.first;
                    _reload();
                  },
                ),
                const SizedBox(height: 14),
                if (list.isEmpty) const EmptyView(icon: Icons.percent_rounded, title: 'ما اكو محلات بعد'),
                for (final m in list) ...[
                  WCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(m['name'] as String, style: WText.h3, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        StatusPill(
                          m['custom_percent'] == null ? 'عامة ${_pct(m['percent'] as num)}' : 'خاصة ${_pct(m['custom_percent'] as num)}',
                          tone: m['custom_percent'] == null ? PillTone.neutral : PillTone.info,
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _fig('طلبات الفترة', '${m['period_orders']}'),
                        _fig('عمولة الفترة', iqd((m['period_commission'] as num).toInt())),
                        _fig('المدفوع', iqd((m['settled_total'] as num).toInt())),
                      ]),
                      const Divider(height: 22),
                      Row(children: [
                        Text((m['due'] as num) < 0 ? 'إله على واصل' : 'المتبقي عليه', style: WText.small),
                        const SizedBox(width: 8),
                        Text(iqd((m['due'] as num).toInt().abs()), style: WText.price.copyWith(color: (m['due'] as num) > 0 ? WColors.fg : ((m['due'] as num) < 0 ? WColors.warning : WColors.inkMuted))),
                        const Spacer(),
                        WButton('تسجيل دفعة', kind: WButtonKind.secondary, compact: true, expand: false, onPressed: () => _settle(m)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
              ]),
            );
          },
        ),
      );

  Widget _fig(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: WText.bodyStrong),
          Text(label, style: WText.caption),
        ]),
      );
}
