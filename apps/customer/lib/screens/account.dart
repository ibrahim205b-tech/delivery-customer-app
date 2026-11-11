import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import 'notifications.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final p = auth.profile;
            return ListView(padding: EdgeInsets.zero, children: [
              Container(
                color: WColors.navy,
                padding: EdgeInsets.fromLTRB(WSpace.page, MediaQuery.paddingOf(context).top + 24, WSpace.page, 28),
                child: Row(children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: WColors.coral,
                    child: Text((p?.fullName ?? '؟').characters.firstOrNull ?? '؟', style: WText.h1.copyWith(color: WColors.white)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p?.fullName ?? '', style: WText.h2.copyWith(color: WColors.white)),
                      Text(p?.phone ?? '', style: WText.body.copyWith(color: WColors.mint), textDirection: TextDirection.ltr),
                    ]),
                  ),
                  WIconButton(Icons.edit_outlined, background: WColors.navySoft, color: WColors.white, tooltip: 'تعديل الاسم', onPressed: () async {
                    final n = await promptText(context, title: 'الاسم', initial: p?.fullName);
                    if (n != null && context.mounted) await runAction(context, () => auth.updateName(n), success: 'تم الحفظ');
                  }),
                ]),
              ),
              const SizedBox(height: 12),
              _group([
                _tile(context, Icons.location_on_outlined, 'عناويني', '${app.addresses.length} عنوان محفوظ', () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressesScreen()));
                }),
                _tile(context, Icons.notifications_none_rounded, 'الإشعارات', 'تحديثات طلباتك ورحلاتك', () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                }),
              ]),
              _group([
                _tile(context, Icons.lock_outline_rounded, 'تغيير كلمة المرور', null, () async {
                  final pw = await promptText(context, title: 'كلمة مرور جديدة', hint: '6 أحرف على الأقل');
                  if (pw == null || !context.mounted) return;
                  if (pw.length < 6) return showError(context, 'كلمة المرور لازم تكون 6 أحرف على الأقل.');
                  await runAction(context, () => auth.changePassword(pw), success: 'تم تغيير كلمة المرور');
                }),
                _tile(context, Icons.info_outline_rounded, 'عن واصل', 'كل احتياجاتك أقرب · نسخة تجريبية', () {
                  showAboutDialog(context: context, applicationName: 'واصل', applicationVersion: '1.0.0', applicationIcon: const WaselMark(size: 40));
                }),
              ]),
              _group([
                _tile(context, Icons.logout_rounded, 'تسجيل الخروج', null, () async {
                  if (await confirmDialog(context, title: 'تسجيل الخروج؟', confirm: 'خروج')) {
                    app.clearCart();
                    await auth.signOut();
                  }
                }, danger: true),
              ]),
              const SizedBox(height: 24),
            ]);
          },
        ),
      );

  Widget _group(List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.page, 8, WSpace.page, 8),
        child: WCard(padding: EdgeInsets.zero, child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[children[i], if (i < children.length - 1) const Divider(indent: 60)],
        ])),
      );

  Widget _tile(BuildContext context, IconData icon, String title, String? sub, VoidCallback onTap, {bool danger = false}) => ListTile(
        onTap: onTap,
        leading: Icon(icon, color: danger ? WColors.danger : WColors.navy),
        title: Text(title, style: WText.bodyStrong.copyWith(color: danger ? WColors.danger : WColors.ink)),
        subtitle: sub == null ? null : Text(sub),
        trailing: danger ? null : const Icon(Icons.chevron_left_rounded),
      );
}

class AddressesScreen extends StatelessWidget {
  const AddressesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('عناويني')),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: WColors.navy,
          foregroundColor: WColors.white,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressFormScreen())),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('عنوان جديد'),
        ),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) => app.addresses.isEmpty
              ? const EmptyView(icon: Icons.location_off_outlined, title: 'ما عندك عناوين', message: 'أضف عنوانك حتى نوصلك بسرعة.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(WSpace.page, 8, WSpace.page, 100),
                  itemCount: app.addresses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final a = app.addresses[i];
                    return WCard(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddressFormScreen(existing: a))),
                      child: Row(children: [
                        Icon(a.label == 'الدوام' ? Icons.work_outline_rounded : Icons.home_outlined, color: WColors.navy),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(a.label, style: WText.bodyStrong),
                              if (a.isDefault) ...[const SizedBox(width: 8), const StatusPill('الافتراضي', tone: PillTone.success)],
                            ]),
                            Text(a.details, style: WText.small),
                            if (a.landmark.isNotEmpty) Text('قرب ${a.landmark}', style: WText.caption),
                          ]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: WColors.danger),
                          onPressed: () async {
                            if (!await confirmDialog(context, title: 'حذف العنوان؟', confirm: 'حذف', danger: true)) return;
                            if (context.mounted) {
                              await runAction(context, () async {
                                await customerApi.deleteAddress(a.id);
                                await app.reloadAddresses();
                              });
                            }
                          },
                        ),
                      ]),
                    );
                  },
                ),
        ),
      );
}

/// إضافة/تعديل عنوان: موقع من الخريطة + تفاصيل + أقرب نقطة دالة
class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, this.existing});
  final Address? existing;
  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _details = TextEditingController(text: widget.existing?.details);
  late final _landmark = TextEditingController(text: widget.existing?.landmark);
  late final _customLabel = TextEditingController(text: widget.existing?.label);
  late String _label = widget.existing?.label ?? 'البيت';
  late LatLng? _point = widget.existing == null ? null : LatLng(widget.existing!.lat, widget.existing!.lng);
  late bool _default = widget.existing?.isDefault ?? app.addresses.isEmpty;
  bool _saving = false;

  Future<void> _pick() async {
    final p = await LocationPickerPage.open(context, initial: _point, title: 'وين بالضبط؟');
    if (p != null) setState(() => _point = p);
  }

  Future<void> _save() async {
    if (_point == null) return showError(context, 'حدّد الموقع على الخريطة.');
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final label = _label == 'غيره' ? _customLabel.text.trim() : _label;
    final ok = await runAction(context, () async {
      final a = await customerApi.saveAddress(
        id: widget.existing?.id,
        label: label,
        details: _details.text.trim(),
        landmark: _landmark.text.trim(),
        lat: _point!.latitude,
        lng: _point!.longitude,
        isDefault: _default,
      );
      await app.reloadAddresses();
      app.selectAddress(a.id);
    }, success: 'انحفظ العنوان');
    if (mounted) setState(() => _saving = false);
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.existing == null ? 'عنوان جديد' : 'تعديل العنوان')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
            GestureDetector(
              onTap: _pick,
              child: ClipRRect(
                borderRadius: WRadius.all(WRadius.lg),
                child: SizedBox(
                  height: 170,
                  child: _point == null
                      ? Container(
                          color: WColors.surfaceAlt,
                          alignment: Alignment.center,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.add_location_alt_rounded, size: 36, color: WColors.coral),
                            const SizedBox(height: 8),
                            Text('اضغط وحدّد الموقع على الخريطة', style: WText.bodyStrong),
                          ]),
                        )
                      : Stack(children: [
                          IgnorePointer(child: WMap(markers: [WMarker(_point!, kind: WMarkerKind.home)], zoom: 16, interactive: false)),
                          PositionedDirectional(
                            end: 10,
                            bottom: 10,
                            child: StatusPill('تغيير الموقع', icon: Icons.edit_location_alt_outlined, tone: PillTone.accent),
                          ),
                        ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('اسم العنوان', style: WText.caption),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final l in ['البيت', 'الدوام', 'بيت الأهل', 'غيره'])
                ChoiceChip(label: Text(l), selected: _label == l, onSelected: (_) => setState(() => _label = l)),
            ]),
            if (_label == 'غيره') ...[
              const SizedBox(height: 10),
              TextFormField(controller: _customLabel, decoration: const InputDecoration(labelText: 'سمّي العنوان'), validator: (v) => (v ?? '').trim().isEmpty ? 'مطلوب' : null),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _details,
              decoration: const InputDecoration(labelText: 'التفاصيل', hintText: 'المنطقة، الشارع، الزقاق، رقم الدار'),
              validator: (v) => (v ?? '').trim().length < 4 ? 'اكتب تفاصيل كافية للمندوب' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _landmark, decoration: const InputDecoration(labelText: 'أقرب نقطة دالة (اختياري)', hintText: 'مثلاً: قرب جامع، مقابل صيدلية')),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _default,
              onChanged: (v) => setState(() => _default = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('العنوان الافتراضي'),
            ),
            const SizedBox(height: 12),
            WButton('حفظ العنوان', onPressed: _save, loading: _saving),
          ]),
        ),
      );
}
