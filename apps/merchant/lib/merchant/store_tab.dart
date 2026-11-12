import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import 'merchant_home.dart';

/// إعدادات المحل التي يتحكم بها التاجر: الإيقاف المؤقت، أوقات العمل، الشعار والغلاف، الوصف.
/// الاسم والموقع وأجور التوصيل والاعتماد بيد الإدارة.
class StoreTab extends StatefulWidget {
  const StoreTab({super.key, required this.merchant, required this.onUpdated});
  final Merchant merchant;
  final ValueChanged<Merchant> onUpdated;
  @override
  State<StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<StoreTab> {
  late Merchant m = widget.merchant;
  late Map<String, DayHours> _hours = {for (var d = 0; d < 7; d++) '$d': m.workingHours['$d'] ?? const DayHours()};
  bool _hoursDirty = false;
  bool _busy = false;

  Future<void> _refresh() async {
    final fresh = await catalogApi.merchant(m.id);
    if (fresh != null && mounted) {
      setState(() => m = fresh);
      widget.onUpdated(fresh);
    }
  }

  Future<void> _update({String? description, String? phone, bool? accepting, int? prep, String? logo, String? cover, bool hours = false}) async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => merchantApi.updateProfile(m.id, description: description, phone: phone, accepting: accepting, prepMinutes: prep, logoUrl: logo, coverUrl: cover, hours: hours ? _hours : null),
      success: 'انحفظت التغييرات',
    );
    if (ok) {
      _hoursDirty = false;
      await _refresh();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _uploadImage(bool logo) async {
    final img = await pickImage(context, maxSide: logo ? 600 : 1600);
    if (img == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final url = await mediaApi.upload('merchants/${m.id}', img.bytes, ext: img.ext);
      await _update(logo: logo ? url : null, cover: logo ? null : url);
    } catch (e) {
      if (mounted) showError(context, e);
      setState(() => _busy = false);
    }
  }

  Future<String?> _pickTime(String current) async {
    final p = current.split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          // الإيقاف المؤقت: أهم زر للتاجر
          WCard(
            color: m.isAcceptingOrders ? WColors.successSoft : WColors.dangerSoft,
            borderColor: Colors.transparent,
            child: Row(children: [
              Icon(m.isAcceptingOrders ? Icons.storefront_rounded : Icons.pause_circle_filled_rounded, color: m.isAcceptingOrders ? WColors.success : WColors.danger, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.isAcceptingOrders ? 'يستقبل طلبات' : 'الطلبات موقفة مؤقتاً', style: WText.h3),
                  Text(m.isAcceptingOrders ? 'أطفيه إذا المحل مزدحم أو مسكّر' : 'المحل يظهر مسكّر للزبائن', style: WText.small),
                ]),
              ),
              Switch(value: m.isAcceptingOrders, onChanged: _busy ? null : (v) => _update(accepting: v)),
            ]),
          ),
          if (m.status != MerchantStatus.approved) ...[
            const SizedBox(height: 10),
            StatusPill(m.status == MerchantStatus.pending ? 'المحل بانتظار اعتماد الإدارة، ما يظهر للزبائن بعد' : 'المحل موقوف من الإدارة',
                tone: PillTone.warning, icon: Icons.info_outline_rounded),
          ],
          const SectionTitle('الصور', padding: EdgeInsets.fromLTRB(0, 24, 0, 10)),
          Row(children: [
            Column(children: [
              InkWell(onTap: _busy ? null : () => _uploadImage(true), child: MerchantLogo(name: m.name, url: m.logoUrl, size: 84)),
              const SizedBox(height: 6),
              Text('الشعار', style: WText.caption),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(children: [
                InkWell(
                  onTap: _busy ? null : () => _uploadImage(false),
                  child: WImage(m.coverUrl, height: 84, radius: WRadius.md, fallbackIcon: Icons.add_photo_alternate_outlined),
                ),
                const SizedBox(height: 6),
                Text('صورة الغلاف', style: WText.caption),
              ]),
            ),
          ]),
          const SectionTitle('المعلومات', padding: EdgeInsets.fromLTRB(0, 24, 0, 6)),
          WCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                title: const Text('الوصف'),
                subtitle: Text(m.description.isEmpty ? 'اكتب وصف مختصر لمحلك' : m.description),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final t = await promptText(context, title: 'وصف المحل', initial: m.description, maxLines: 3);
                  if (t != null) _update(description: t);
                },
              ),
              const Divider(indent: 16),
              ListTile(
                title: const Text('رقم التواصل'),
                subtitle: Text(m.phone.isEmpty ? '—' : m.phone, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final t = await promptText(context, title: 'رقم التواصل', initial: m.phone, keyboard: TextInputType.phone);
                  if (t != null) _update(phone: t);
                },
              ),
              const Divider(indent: 16),
              ListTile(
                title: const Text('وقت التحضير'),
                subtitle: Text('${m.prepMinutes} دقيقة'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final t = await promptText(context, title: 'وقت التحضير بالدقائق', initial: '${m.prepMinutes}', keyboard: TextInputType.number);
                  final v = int.tryParse(t ?? '');
                  if (v != null && v >= 0 && v <= 300) _update(prep: v);
                },
              ),
              const Divider(indent: 16),
              ListTile(
                title: const Text('أجور التوصيل والموقع'),
                subtitle: Text('${iqd(m.deliveryFee)} · نطاق ${m.deliveryRadiusKm} كم — تعدّلها الإدارة'),
                leading: const Icon(Icons.lock_outline_rounded, size: 20),
              ),
            ]),
          ),
          const SectionTitle('أوقات العمل', padding: EdgeInsets.fromLTRB(0, 24, 0, 6)),
          WCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              for (var d = 0; d < 7; d++) _dayRow(d),
            ]),
          ),
          if (_hoursDirty) ...[
            const SizedBox(height: 12),
            WButton('حفظ أوقات العمل', onPressed: () => _update(hours: true), loading: _busy),
          ],
          const SizedBox(height: 24),
          WButton('تسجيل الخروج', kind: WButtonKind.ghost, icon: Icons.logout_rounded, onPressed: () => signOutFlow(context)),
          Center(child: Text(auth.profile?.phone ?? '', style: WText.caption, textDirection: TextDirection.ltr)),
        ]),
      );

  Widget _dayRow(int d) {
    final h = _hours['$d']!;
    void set(DayHours v) => setState(() {
          _hours = {..._hours, '$d': v};
          _hoursDirty = true;
        });
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(children: [
        SizedBox(width: 74, child: Text(weekdaysAr[d], style: WText.body)),
        Switch(value: !h.closed, onChanged: (v) => set(h.copyWith(closed: !v))),
        const SizedBox(width: 6),
        if (h.closed)
          Text('مسكّر', style: WText.small)
        else ...[
          TextButton(onPressed: () async => set(h.copyWith(open: await _pickTime(h.open) ?? h.open)), child: Text(h.open, textDirection: TextDirection.ltr)),
          const Text('—'),
          TextButton(onPressed: () async => set(h.copyWith(close: await _pickTime(h.close) ?? h.close)), child: Text(h.close, textDirection: TextDirection.ltr)),
        ],
      ]),
    );
  }
}
