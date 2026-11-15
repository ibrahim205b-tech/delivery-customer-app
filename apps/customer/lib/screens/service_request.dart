import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// اختيار مقدم الخدمة المعتمد المناسب، ثم تعبئة نموذج الخدمة وإرسال الطلب.
class ServiceProvidersScreen extends StatelessWidget {
  const ServiceProvidersScreen({super.key, required this.service});
  final ServiceItem service;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(service.name)),
        body: FutureBuilder<List<Merchant>>(
          future: catalogApi.providersForService(service.id),
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!);
            if (!snap.hasData) return const SkeletonList(count: 3);
            final ps = snap.data!;
            if (ps.isEmpty) return const EmptyView(icon: Icons.storefront_outlined, title: 'ما في مقدمين معتمدين بعد', message: 'تنضاف هنا أول ما يعتمد مقدم خدمة.');
            return ListView(padding: const EdgeInsets.all(WSpace.page), children: [
              if (service.description.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(service.description, style: WText.small)),
              for (final m in ps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: WCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceRequestScreen(service: service, provider: m))),
                    child: Row(children: [
                      Expanded(child: Text(m.name, style: WText.h3)),
                      const Icon(Icons.chevron_left_rounded),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}

/// نموذج الطلب: الحقول تأتي من kServiceForms، والمقدم يحدد السعر لاحقاً
class ServiceRequestScreen extends StatefulWidget {
  const ServiceRequestScreen({super.key, required this.service, required this.provider});
  final ServiceItem service;
  final Merchant provider;
  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  final _values = <String, String>{};
  bool _sending = false;

  List<ServiceFormField> get _fields => kServiceForms[widget.service.id] ?? const [];

  Future<void> _pickDate(ServiceFormField f) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: now.add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    setState(() => _values[f.key] = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  Future<void> _send() async {
    for (final f in _fields) {
      if (f.required && (_values[f.key] ?? '').trim().isEmpty) return showError(context, 'اكتب ${f.label}');
    }
    final payload = <String, dynamic>{};
    for (final f in _fields) {
      final v = (_values[f.key] ?? '').trim();
      if (v.isEmpty) continue;
      payload[f.key] = f.kind == ServiceFormKind.number ? (num.tryParse(v) ?? v) : v;
    }
    setState(() => _sending = true);
    try {
      await catalogApi.createServiceRequest(widget.service.id, widget.provider.id, payload);
      if (!mounted) return;
      showSuccess(context, 'وصل طلبك لـ ${widget.provider.name}. راح يحدد السعر ويرد عليك.');
      Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.service.name)),
        body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          Text(widget.provider.name, style: WText.h3),
          const SizedBox(height: 4),
          Text('السعر يحدده مقدم الخدمة بعد مراجعة طلبك.', style: WText.caption),
          const SizedBox(height: 14),
          for (final f in _fields) ...[
            _FieldInput(field: f, value: _values[f.key] ?? '', onChanged: (v) => setState(() => _values[f.key] = v), onPickDate: () => _pickDate(f)),
            const SizedBox(height: 12),
          ],
          WButton(_sending ? 'جارٍ الإرسال…' : 'أرسل الطلب', onPressed: _sending ? null : _send),
        ]),
      );
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({required this.field, required this.value, required this.onChanged, required this.onPickDate});
  final ServiceFormField field;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final label = field.required ? '${field.label} *' : field.label;
    return switch (field.kind) {
      ServiceFormKind.choice => DropdownButtonFormField<String>(
          initialValue: field.options.contains(value) ? value : null,
          decoration: InputDecoration(labelText: label),
          items: [for (final o in field.options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ServiceFormKind.date => InkWell(
          onTap: onPickDate,
          child: InputDecorator(
            decoration: InputDecoration(labelText: label),
            child: Text(value.isEmpty ? 'اختر التاريخ' : value),
          ),
        ),
      ServiceFormKind.number => TextFormField(
          key: ValueKey(field.key),
          initialValue: value,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          onChanged: onChanged,
        ),
      ServiceFormKind.text => TextFormField(
          key: ValueKey(field.key),
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          onChanged: onChanged,
        ),
    };
  }
}
