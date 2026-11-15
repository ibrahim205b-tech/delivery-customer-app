import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

const _modelLabel = {'free': 'مجانية', 'percent': 'نسبة من المبلغ', 'fixed': 'مبلغ ثابت'};
const _engineLabel = {
  'none': 'بانتظار التنفيذ',
  'order': 'طلبات متجر',
  'task': 'مهام مندوب',
  'ride': 'رحلات',
  'booking': 'حجوزات',
};

/// إدارة كتالوج «اكتشف خدمات واصل»: تشغيل/إيقاف، تعديل الاسم والوصف، والعمولة لكل خدمة.
/// الخدمة بلا تنفيذ لا تقبل التفعيل (الخادم يمنعه).
class ServicesAdminScreen extends StatefulWidget {
  const ServicesAdminScreen({super.key});
  @override
  State<ServicesAdminScreen> createState() => _ServicesAdminScreenState();
}

class _ServicesAdminScreenState extends State<ServicesAdminScreen> {
  late Future<({List<ServiceGroup> groups, List<ServiceItem> services})> _cat = catalogApi.servicesCatalog();
  late Future<Map<String, dynamic>> _com = adminApi.serviceCommissions();

  void _reload() => setState(() {
        _cat = catalogApi.servicesCatalog();
        _com = adminApi.serviceCommissions();
      });

  Future<void> _toggle(ServiceItem s, bool v) async {
    if (await runAction(context, () => adminApi.setServiceActive(s.id, v), success: v ? 'انفعّلت الخدمة' : 'انوقفت الخدمة')) _reload();
  }

  Future<void> _edit(ServiceItem s) async {
    final name = TextEditingController(text: s.name);
    final desc = TextEditingController(text: s.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تعديل الخدمة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 10),
          TextField(controller: desc, maxLines: 3, maxLength: 300, decoration: const InputDecoration(labelText: 'الوصف')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await runAction(context, () => adminApi.setServiceActive(s.id, s.isActive, name: name.text.trim(), description: desc.text.trim()), success: 'انحفظ')) _reload();
  }

  Future<void> _commission(ServiceItem s, Map<String, dynamic> current) async {
    var model = (current['model'] as String?) ?? 'free';
    final value = TextEditingController(text: '${(current['value'] as num?) ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('عمولة: ${s.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: model,
              decoration: const InputDecoration(labelText: 'النموذج'),
              items: [for (final e in _modelLabel.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => set(() => model = v ?? model),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: value,
              enabled: model != 'free',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: model == 'percent' ? 'النسبة' : 'المبلغ', suffixText: model == 'percent' ? '%' : 'د.ع', helperText: 'القيمة تُطبَّق على العمليات المكتملة بعد الحفظ.'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final v = model == 'free' ? 0.0 : (double.tryParse(value.text) ?? -1);
    if (await runAction(context, () => adminApi.setServiceCommission(s.id, model, v), success: 'انحفظت العمولة')) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('إدارة الخدمات')),
        body: FutureBuilder<({List<ServiceGroup> groups, List<ServiceItem> services})>(
          future: _cat,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            if (!snap.hasData) return const SkeletonList(count: 5);
            final c = snap.data!;
            return FutureBuilder<Map<String, dynamic>>(
              future: _com,
              builder: (context, cs) {
                final coms = cs.data ?? const <String, dynamic>{};
                return ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32), children: [
                  for (final g in c.groups) ...[
                    Padding(padding: const EdgeInsets.only(top: 10, bottom: 6), child: Text(g.name, style: WText.h3)),
                    for (final s in c.services.where((x) => x.groupId == g.id))
                      WCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(s.name, style: WText.bodyStrong)),
                            Switch(value: s.isActive, onChanged: s.engine == 'none' ? null : (v) => _toggle(s, v)),
                          ]),
                          Text('${_engineLabel[s.engine] ?? s.engine}${s.engine == 'none' ? ' · لا يظهر للزبون' : ''}', style: WText.caption),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                              child: Text(
                                'العمولة: ${_modelLabel[(coms[s.id] as Map?)?['model']] ?? 'مجانية'}'
                                '${((coms[s.id] as Map?)?['model'] ?? 'free') == 'free' ? '' : ' · ${(coms[s.id] as Map)['value']}'}',
                                style: WText.small,
                              ),
                            ),
                            TextButton(onPressed: () => _commission(s, (coms[s.id] as Map?)?.cast<String, dynamic>() ?? {}), child: const Text('العمولة')),
                            TextButton(onPressed: () => _edit(s), child: const Text('تعديل')),
                          ]),
                        ]),
                      ),
                    const SizedBox(height: 4),
                  ],
                ]);
              },
            );
          },
        ),
      );
}
