import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// اختيار النشاط: يظهر لصاحب الحساب أول مرة، ويستطيع تغييره لاحقاً من إعدادات المحل.
/// الأنشطة تُحمّل من الإدارة وتُجمع حسب المجموعة، ولو تعذّر التحميل تظهر القائمة الاحتياطية.

class ActivityPickerScreen extends StatefulWidget {
  const ActivityPickerScreen({super.key, required this.merchant, this.canCancel = false, this.onSaved});
  final Merchant merchant;
  /// يُستدعى بعد الحفظ بالمحل المحدّث (الصفحة الرئيسية تعرض التبويبات الجديدة)
  final void Function(Merchant)? onSaved;
  /// عند التغيير من الإعدادات يمكن الرجوع دون اختيار
  final bool canCancel;
  @override
  State<ActivityPickerScreen> createState() => _ActivityPickerScreenState();
}

class _ActivityPickerScreenState extends State<ActivityPickerScreen> {
  String? _selected;
  bool _saving = false;
  late final Future<List<BusinessActivity>> _activities = _load();

  Future<List<BusinessActivity>> _load() async {
    try {
      final list = await catalogApi.businessActivities();
      return list.isEmpty ? BusinessActivity.fallback() : list;
    } catch (_) {
      return BusinessActivity.fallback();
    }
  }

  /// المجموعات بترتيب ظهورها
  static Map<String, List<BusinessActivity>> _grouped(List<BusinessActivity> list) {
    final out = <String, List<BusinessActivity>>{};
    for (final a in list) {
      out.putIfAbsent(a.groupName, () => []).add(a);
    }
    return out;
  }

  Future<void> _save() async {
    final t = _selected;
    if (t == null) return;
    setState(() => _saving = true);
    try {
      final m = await merchantApi.setBusinessType(widget.merchant.id, t);
      if (!mounted) return;
      showSuccess(context, 'تم حفظ نشاطك');
      widget.onSaved?.call(m);
      if (widget.canCancel && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: widget.canCancel,
        child: Scaffold(
          appBar: AppBar(title: const Text('اختار نشاطك'), automaticallyImplyLeading: widget.canCancel),
          body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
            Text('هذا يحدد الشاشات والتبويبات التي تشوفها، ويعرّف الزبائن بخدمتك.', style: WText.small),
            const SizedBox(height: 14),
            FutureBuilder<List<BusinessActivity>>(
              future: _activities,
              builder: (context, snap) {
                if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final g in _grouped(snap.data!).entries) ...[
                    Text(g.key, style: WText.h3),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final a in g.value)
                        ChoiceChip(
                          label: Text(a.label),
                          selected: _selected == a.key,
                          onSelected: (_) => setState(() => _selected = a.key),
                        ),
                    ]),
                    const SizedBox(height: 16),
                  ],
                ]);
              },
            ),
            WButton(_saving ? 'جارٍ الحفظ…' : 'تأكيد النشاط', onPressed: (_selected == null || _saving) ? null : _save),
          ]),
        ),
      );
}
