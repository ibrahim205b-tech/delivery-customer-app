import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// تبويب صاحب الملعب: إدارة الملاعب (السعر والساعات والمدة وسياسة الإلغاء)،
/// وطلبات الحجز (قبول أو رفض بسبب، وبدء وإتمام).
class PitchOwnerTab extends StatefulWidget {
  const PitchOwnerTab({super.key, required this.merchant});
  final Merchant merchant;
  @override
  State<PitchOwnerTab> createState() => _PitchOwnerTabState();
}

class _PitchOwnerTabState extends State<PitchOwnerTab> {
  int _section = 0; // 0 الطلبات · 1 الملاعب
  late Future<List<ServiceRequest>> _requests = merchantApi.providerRequests(widget.merchant.id);
  late Future<List<Pitch>> _pitches = merchantApi.myPitches(widget.merchant.id);

  void _reload() => setState(() {
        _requests = merchantApi.providerRequests(widget.merchant.id);
        _pitches = merchantApi.myPitches(widget.merchant.id);
      });

  Future<void> _respond(ServiceRequest r, bool accept) async {
    var reason = '';
    if (!accept) {
      final v = await promptText(context, title: 'سبب الرفض', hint: 'مثال: الملعب مغلق لصيانة', confirm: 'رفض');
      if (v == null || v.trim().length < 3 || !mounted) return;
      reason = v.trim();
    }
    if (await runAction(context, () => merchantApi.respondServiceRequest(r.id, accept: accept, reason: reason), success: accept ? 'تم القبول' : 'تم الرفض')) _reload();
  }

  Future<void> _advance(ServiceRequest r, String to) async {
    if (await runAction(context, () => merchantApi.setServiceRequestStatus(r.id, to), success: to == 'completed' ? 'انتهى الحجز' : 'بدأ الحجز')) _reload();
  }

  Future<void> _editPitch([Pitch? p]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _PitchForm(merchant: widget.merchant, pitch: p)));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الملاعب والحجوزات'),
          actions: [if (_section == 1) IconButton(tooltip: 'ملعب جديد', icon: const Icon(Icons.add_rounded), onPressed: () => _editPitch())],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 8),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 0, label: Text('الطلبات')), ButtonSegment(value: 1, label: Text('الملاعب'))],
              selected: {_section},
              onSelectionChanged: (v) => setState(() => _section = v.first),
            ),
          ),
          Expanded(child: _section == 0 ? _requestsView() : _pitchesView()),
        ]),
      );

  Widget _requestsView() => FutureBuilder<List<ServiceRequest>>(
        future: _requests,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const SkeletonList(count: 4);
          final rows = snap.data!;
          if (rows.isEmpty) return const EmptyView(icon: Icons.event_available_outlined, title: 'ما في طلبات حجز', message: 'أول ما يطلب زبون حجز يظهر هنا.');
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: WCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(r.placeName.isEmpty ? 'حجز' : r.placeName, style: WText.bodyStrong)),
                        StatusPill(r.statusLabel, tone: r.status == 'requested' ? PillTone.accent : PillTone.neutral),
                      ]),
                      if (r.startsAt != null) Text('${dateTimeAr(r.startsAt!)} · ${iqd(r.amount)}', style: WText.small),
                      const SizedBox(height: 8),
                      if (r.status == 'requested')
                        Row(children: [
                          Expanded(child: WButton('قبول', kind: WButtonKind.dark, compact: true, onPressed: () => _respond(r, true))),
                          const SizedBox(width: 8),
                          Expanded(child: WButton('رفض', kind: WButtonKind.ghost, compact: true, onPressed: () => _respond(r, false))),
                        ]),
                      if (r.status == 'accepted')
                        WButton('بدأ الحجز', kind: WButtonKind.secondary, compact: true, onPressed: () => _advance(r, 'in_progress')),
                      if (r.status == 'accepted' || r.status == 'in_progress')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: WButton('انتهى الحجز', compact: true, onPressed: () => _advance(r, 'completed')),
                        ),
                    ]),
                  ),
                ),
            ]),
          );
        },
      );

  Widget _pitchesView() => FutureBuilder<List<Pitch>>(
        future: _pitches,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const SkeletonList(count: 3);
          final ps = snap.data!;
          if (ps.isEmpty) return const EmptyView(icon: Icons.sports_soccer_outlined, title: 'ما عندك ملاعب بعد', message: 'اضغط + وأضف ملعبك وحدد السعر والساعات.');
          return ListView(padding: const EdgeInsets.all(WSpace.page), children: [
            for (final p in ps)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: WCard(
                  onTap: () => _editPitch(p),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(p.name, style: WText.h3)),
                      StatusPill(p.isActive ? 'مفعّل' : 'موقوف', tone: p.isActive ? PillTone.info : PillTone.neutral),
                    ]),
                    Text('${iqd(p.pricePerHour)} / ساعة · ${p.openHour}:00 إلى ${p.closeHour == 24 ? '12:00 ص' : '${p.closeHour}:00'}', style: WText.small),
                  ]),
                ),
              ),
          ]);
        },
      );
}

class _PitchForm extends StatefulWidget {
  const _PitchForm({required this.merchant, this.pitch});
  final Merchant merchant;
  final Pitch? pitch;
  @override
  State<_PitchForm> createState() => _PitchFormState();
}

class _PitchFormState extends State<_PitchForm> {
  late final _name = TextEditingController(text: widget.pitch?.name ?? '');
  late final _desc = TextEditingController(text: widget.pitch?.description ?? '');
  late final _price = TextEditingController(text: widget.pitch == null ? '' : '${widget.pitch!.pricePerHour}');
  late final _policy = TextEditingController(text: widget.pitch?.cancellationPolicy ?? '');
  late int _minMinutes = widget.pitch?.minMinutes ?? 60;
  late int _open = widget.pitch?.openHour ?? 8;
  late int _close = widget.pitch?.closeHour ?? 23;
  late int _cancelHours = widget.pitch?.cancelBeforeHours ?? 2;
  late bool _active = widget.pitch?.isActive ?? false;
  bool _saving = false;

  Future<void> _save() async {
    final price = int.tryParse(_price.text.trim()) ?? 0;
    if (_name.text.trim().length < 2) return showError(context, 'اكتب اسم الملعب');
    if (_active && price <= 0) return showError(context, 'حدد سعر الساعة قبل التفعيل');
    if (_open >= _close) return showError(context, 'وقت الإغلاق لازم يكون بعد الفتح');
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => merchantApi.savePitch(
        id: widget.pitch?.id,
        merchantId: widget.merchant.id,
        name: _name.text.trim(),
        description: _desc.text.trim(),
        pricePerHour: price,
        minMinutes: _minMinutes,
        openHour: _open,
        closeHour: _close,
        cancelBeforeHours: _cancelHours,
        cancellationPolicy: _policy.text.trim(),
        isActive: _active,
      ),
      success: 'انحفظ الملعب',
    );
    if (mounted) setState(() => _saving = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.pitch == null ? 'ملعب جديد' : 'تعديل الملعب')),
        body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الملعب')),
          const SizedBox(height: 10),
          TextField(controller: _desc, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف (عشب، إضاءة، مواقف…)')),
          const SizedBox(height: 10),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'سعر الساعة', suffixText: 'د.ع', helperText: 'تحدده أنت، ولا تفعّل الملعب بدون سعر.'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _minMinutes,
            decoration: const InputDecoration(labelText: 'أقل مدة حجز'),
            items: [for (final m in [30, 60, 90, 120]) DropdownMenuItem(value: m, child: Text("$m دقيقة"))],
            onChanged: (v) => setState(() => _minMinutes = v ?? _minMinutes),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _open,
                decoration: const InputDecoration(labelText: 'يفتح'),
                items: [for (var h = 0; h <= 23; h++) DropdownMenuItem(value: h, child: Text('$h:00'))],
                onChanged: (v) => setState(() => _open = v ?? _open),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _close,
                decoration: const InputDecoration(labelText: 'يغلق'),
                items: [for (var h = 1; h <= 24; h++) DropdownMenuItem(value: h, child: Text(h == 24 ? '12:00 ص' : '$h:00'))],
                onChanged: (v) => setState(() => _close = v ?? _close),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _cancelHours,
            decoration: const InputDecoration(labelText: 'الإلغاء من الزبون قبل الموعد بـ'),
            items: [for (final h in [0, 1, 2, 6, 12, 24, 48]) DropdownMenuItem(value: h, child: Text(h == 0 ? "في أي وقت" : "$h ساعة"))],
            onChanged: (v) => setState(() => _cancelHours = v ?? _cancelHours),
          ),
          const SizedBox(height: 10),
          TextField(controller: _policy, maxLines: 2, decoration: const InputDecoration(labelText: 'سياسة الإلغاء (تظهر للزبون)')),
          const SizedBox(height: 6),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('الملعب مفعّل للحجز'), value: _active, onChanged: (v) => setState(() => _active = v)),
          const SizedBox(height: 14),
          WButton(_saving ? 'جارٍ الحفظ…' : 'حفظ', onPressed: _saving ? null : _save),
        ]),
      );
}
