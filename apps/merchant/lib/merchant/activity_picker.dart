import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// اختيار النشاط: يظهر لصاحب الحساب أول مرة، ويستطيع تغييره لاحقاً من إعدادات المحل.
/// الأنشطة مجمعة حتى لا يتعب صاحب الخدمة من القائمة الطويلة.
const _groups = <(String, List<String>)>[
  ('المحلات والمطاعم', ['store', 'restaurant']),
  ('الحجوزات والمواعيد', ['pitch_owner', 'clinic', 'venue', 'restaurant']),
  ('الخدمات المنزلية والصيانة', ['provider', 'technician', 'mobile_repair', 'cleaning_company', 'maintenance_center']),
  ('الخدمات المكتبية والتعليم', ['library', 'institute', 'print_shop', 'employer']),
  ('الإعلام والمناسبات', ['photographer', 'rental_center']),
  ('النقل والسفر', ['transport_company', 'travel_agency']),
];

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

  Future<void> _save() async {
    final t = _selected;
    if (t == null) return;
    setState(() => _saving = true);
    try {
      final m = await merchantApi.setBusinessType(widget.merchant.id, t);
      if (!mounted) return;
      showSuccess(context, 'تم حفظ نشاطك: ${kBusinessTypeLabels[m.businessType] ?? ''}');
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
            for (final g in _groups) ...[
              Text(g.$1, style: WText.h3),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in g.$2)
                  ChoiceChip(
                    label: Text(kBusinessTypeLabels[t] ?? t),
                    selected: _selected == t,
                    onSelected: (_) => setState(() => _selected = t),
                  ),
              ]),
              const SizedBox(height: 16),
            ],
            WButton(_saving ? 'جارٍ الحفظ…' : 'تأكيد النشاط', onPressed: (_selected == null || _saving) ? null : _save),
          ]),
        ),
      );
}
