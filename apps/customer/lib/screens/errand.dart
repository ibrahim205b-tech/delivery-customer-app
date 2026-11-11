import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';

/// قيمة نقطة على الخريطة + وصف نصي
class PointValue {
  PointValue({this.point, this.label = ''});
  LatLng? point;
  String label;
}

/// حقل اختيار نقطة: يفتح الخريطة، ويسمح بكتابة وصف، أو اختيار عنوان محفوظ
class PointField extends StatelessWidget {
  const PointField({super.key, required this.title, required this.value, required this.kind, required this.onChanged, this.trailing});
  final String title;
  final PointValue value;
  final WMarkerKind kind;
  final VoidCallback onChanged;
  final Widget? trailing;

  Future<void> _edit(BuildContext context) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.map_outlined), title: const Text('حدّد على الخريطة'), onTap: () => Navigator.pop(c, 'map')),
          for (final a in app.addresses)
            ListTile(leading: const Icon(Icons.bookmark_outline_rounded), title: Text(a.label), subtitle: Text(a.details), onTap: () => Navigator.pop(c, a)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice is Address) {
      value.point = LatLng(choice.lat, choice.lng);
      value.label = [choice.label, choice.details, if (choice.landmark.isNotEmpty) landmarkAr(choice.landmark)].join(' - ');
      onChanged();
      return;
    }
    final p = await LocationPickerPage.open(context, initial: value.point, title: title);
    if (p == null || !context.mounted) return;
    value.point = p;
    final t = await promptText(context, title: 'وصف المكان', hint: 'مثلاً: باب البيت، قرب الجامع', initial: value.label == 'موقعي الحالي' ? '' : value.label);
    if (t != null) value.label = t;
    onChanged();
  }

  @override
  Widget build(BuildContext context) => WCard(
        onTap: () => _edit(context),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(kind == WMarkerKind.dropoff ? Icons.flag_rounded : Icons.trip_origin_rounded, color: kind == WMarkerKind.dropoff ? WColors.coral : WColors.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: WText.caption),
              Text(
                value.point == null ? 'اضغط للتحديد' : (value.label.isEmpty ? 'نقطة على الخريطة' : value.label),
                style: value.point == null ? WText.body.copyWith(color: WColors.inkFaint) : WText.bodyStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          trailing ?? const Icon(Icons.chevron_left_rounded, color: WColors.inkMuted),
        ]),
      );
}

/// طلب مندوب (يشتري ويوصل) أو توصيل غرض من مكان لمكان
class ErrandRequestScreen extends StatefulWidget {
  const ErrandRequestScreen({super.key, required this.kind});
  final TaskKind kind;
  @override
  State<ErrandRequestScreen> createState() => _ErrandRequestScreenState();
}

class _ErrandRequestScreenState extends State<ErrandRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _pickup = PointValue();
  final _dropoff = PointValue();
  final _itemType = TextEditingController();
  final _desc = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  ({double distanceKm, int fare})? _estimate;
  bool _sending = false;

  bool get _courier => widget.kind == TaskKind.courier;

  @override
  void initState() {
    super.initState();
    final a = app.selectedAddress;
    if (a != null) {
      _dropoff
        ..point = LatLng(a.lat, a.lng)
        ..label = [a.label, a.details].join(' - ');
    }
    _phone.text = auth.profile?.phone ?? '';
  }

  Future<void> _estimateFare() async {
    final p = _pickup.point, d = _dropoff.point;
    setState(() => _estimate = null);
    if (p == null || d == null) return;
    try {
      final e = await customerApi.estimate('errand', p.latitude, p.longitude, d.latitude, d.longitude);
      if (mounted) setState(() => _estimate = e);
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_pickup.point == null || _dropoff.point == null) return showError(context, 'حدّد مكان الاستلام والتسليم.');
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final t = await customerApi.createErrand(
        kind: widget.kind,
        pickupText: _pickup.label,
        pLat: _pickup.point!.latitude,
        pLng: _pickup.point!.longitude,
        dropoffText: _dropoff.label,
        dLat: _dropoff.point!.latitude,
        dLng: _dropoff.point!.longitude,
        itemType: _itemType.text.trim(),
        description: _desc.text.trim(),
        recipientPhone: normalizeIraqiPhone(_phone.text) ?? _phone.text.trim(),
        notes: _notes.text.trim(),
      );
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ErrandTrackingScreen(taskId: t.id)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_courier ? 'الدلفري والمندوب' : 'توصيل الأغراض')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
            WCard(
              color: WColors.navy,
              borderColor: WColors.navy,
              child: Row(children: [
                Icon(_courier ? Icons.delivery_dining_rounded : Icons.inventory_2_rounded, color: WColors.coral, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _courier ? 'المندوب يروح يشتري اللي تحتاجه ويوصله إلك. تدفع ثمن الأغراض + الأجرة نقداً.' : 'نستلم غرضك من مكان ونسلّمه لمكان ثاني بأمان.',
                    style: WText.body.copyWith(color: WColors.white),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            PointField(title: _courier ? 'من وين يشتري؟' : 'مكان الاستلام', value: _pickup, kind: WMarkerKind.pickup, onChanged: () {
              setState(() {});
              _estimateFare();
            }),
            const SizedBox(height: 10),
            PointField(title: 'مكان التسليم', value: _dropoff, kind: WMarkerKind.dropoff, onChanged: () {
              setState(() {});
              _estimateFare();
            }),
            const SizedBox(height: 16),
            TextFormField(
              controller: _itemType,
              decoration: InputDecoration(labelText: _courier ? 'شنو يشتري؟' : 'نوع الغرض', hintText: _courier ? 'أدوية، أغراض بيت…' : 'أوراق، ملابس، جهاز…'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'الوصف', hintText: _courier ? 'اكتب القائمة بالتفصيل' : 'الحجم، هل قابل للكسر…'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'اكتب وصف واضح' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: const InputDecoration(labelText: 'رقم المستلم'),
              validator: (v) => normalizeIraqiPhone(v ?? '') == null ? 'رقم غير صحيح' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
            const SizedBox(height: 16),
            if (_estimate != null)
              WCard(
                child: Row(children: [
                  Expanded(child: Text('الأجرة التقديرية · ${kmAr(_estimate!.distanceKm)}', style: WText.body)),
                  Text(iqd(_estimate!.fare), style: WText.price.copyWith(fontSize: 18)),
                ]),
              ),
            const SizedBox(height: 16),
            WButton('أرسل الطلب', icon: Icons.send_rounded, onPressed: _send, loading: _sending),
            const SizedBox(height: 24),
          ]),
        ),
      );
}

/// متابعة طلب التوصيل لحظياً
class ErrandTrackingScreen extends StatelessWidget {
  const ErrandTrackingScreen({super.key, required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('طلب التوصيل')),
        body: StreamBuilder<DeliveryTask?>(
          stream: customerApi.watchTask(taskId),
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!);
            final t = s.data;
            if (t == null) return const LoadingView();
            final step = switch (t.status) {
              TaskStatus.requested => 0,
              TaskStatus.assigned => 1,
              TaskStatus.pickedUp || TaskStatus.onTheWay => 2,
              TaskStatus.delivered => 3,
              TaskStatus.cancelled => -1,
            };
            return ListView(padding: EdgeInsets.zero, children: [
              SizedBox(
                height: 230,
                child: WMap(markers: [
                  WMarker(LatLng(t.pickupLat, t.pickupLng), kind: WMarkerKind.pickup),
                  WMarker(LatLng(t.dropoffLat, t.dropoffLng), kind: WMarkerKind.dropoff),
                  if (t.driverLat != null && t.status.isActive) WMarker(LatLng(t.driverLat!, t.driverLng!), kind: WMarkerKind.driver),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(WSpace.page),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(t.status.label, style: WText.h1),
                  if (t.status == TaskStatus.requested) ...[const SizedBox(height: 10), const LinearProgressIndicator()],
                  if (t.status != TaskStatus.cancelled) ...[
                    const SizedBox(height: 14),
                    StepProgress(steps: const ['أُرسل', 'المندوب جاي', 'بالطريق', 'تم'], current: step),
                  ],
                  const SizedBox(height: 16),
                  if (t.driverName != null)
                    WCard(
                      child: Row(children: [
                        const CircleAvatar(backgroundColor: WColors.coralSoft, child: Icon(Icons.two_wheeler_rounded, color: WColors.coralDeep)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(t.driverName!, style: WText.bodyStrong)),
                        if ((t.driverPhone ?? '').isNotEmpty && t.status.isActive)
                          WIconButton(Icons.call_rounded, background: WColors.mintDeep, color: WColors.white, onPressed: () => callPhone(t.driverPhone!)),
                      ]),
                    ),
                  const SizedBox(height: 12),
                  WCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.itemType, style: WText.bodyStrong),
                      Text(t.description, style: WText.small),
                      const Divider(height: 22),
                      InfoRow(icon: Icons.trip_origin_rounded, text: t.pickupText.isEmpty ? 'مكان الاستلام' : t.pickupText, color: WColors.navy),
                      const SizedBox(height: 6),
                      InfoRow(icon: Icons.flag_rounded, text: t.dropoffText.isEmpty ? 'مكان التسليم' : t.dropoffText, color: WColors.coralDeep),
                      const SizedBox(height: 6),
                      InfoRow(icon: Icons.phone_outlined, text: 'المستلم: ${t.recipientPhone}'),
                      const Divider(height: 22),
                      Row(children: [Expanded(child: Text('الأجرة (نقداً)', style: WText.body)), Text(iqd(t.fee), style: WText.price)]),
                    ]),
                  ),
                  if (t.status == TaskStatus.requested || t.status == TaskStatus.assigned) ...[
                    const SizedBox(height: 16),
                    WButton('إلغاء الطلب', kind: WButtonKind.danger, onPressed: () async {
                      if (await confirmDialog(context, title: 'إلغاء الطلب؟', confirm: 'إلغاء', danger: true) && context.mounted) {
                        await runAction(context, () => customerApi.cancelErrand(t.id), success: 'انلغى الطلب');
                      }
                    }),
                  ],
                ]),
              ),
            ]);
          },
        ),
      );
}
