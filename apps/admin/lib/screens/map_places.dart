import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// نقاط الاستدلال: مسودات تنتظر المراجعة، ومعتمدة، ومرفوضة.
/// لا نقطة تُعتمد تلقائياً. كل اعتماد أو رفض يُسجَّل باسم المراجع.
class MapPlacesScreen extends StatefulWidget {
  const MapPlacesScreen({super.key});
  @override
  State<MapPlacesScreen> createState() => _MapPlacesScreenState();
}

class _MapPlacesScreenState extends State<MapPlacesScreen> {
  String _status = 'draft';
  late Future<List<MapPlace>> _list = adminApi.mapPlaces(_status);

  void _reload() => setState(() => _list = adminApi.mapPlaces(_status));

  Future<void> _edit([MapPlace? p]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => MapPlaceForm(place: p)));
    if (saved == true) _reload();
  }

  Future<void> _reject(MapPlace p) async {
    final reason = await promptText(context, title: 'سبب الرفض', hint: 'اكتب سبب الرفض (٥ أحرف على الأقل)', confirm: 'رفض');
    if (reason == null || !mounted) return;
    if (await runAction(context, () => adminApi.reviewMapPlace(p.id, approve: false, reason: reason), success: 'انرفضت النقطة')) _reload();
  }

  Future<void> _approve(MapPlace p) async {
    final ok = await confirmDialog(context, title: 'اعتماد النقطة؟', message: '«${p.name}» بتظهر للزبائن والسائقين.', confirm: 'اعتماد');
    if (!ok || !mounted) return;
    if (await runAction(context, () => adminApi.reviewMapPlace(p.id, approve: true), success: 'انعتمدت النقطة')) _reload();
  }

  Future<void> _delete(MapPlace p) async {
    final ok = await confirmDialog(context, title: 'حذف النقطة؟', message: '«${p.name}» ما راح ترجع.', confirm: 'حذف', danger: true);
    if (!ok || !mounted) return;
    if (await runAction(context, () => adminApi.deleteMapPlace(p.id), success: 'انحذفت')) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('نقاط الاستدلال'),
          actions: [IconButton(tooltip: 'إضافة نقطة', icon: const Icon(Icons.add_location_alt_outlined), onPressed: () => _edit())],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'draft', label: Text('مسودات')),
                ButtonSegment(value: 'approved', label: Text('معتمدة')),
                ButtonSegment(value: 'rejected', label: Text('مرفوضة')),
              ],
              selected: {_status},
              onSelectionChanged: (v) {
                _status = v.first;
                _reload();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MapPlace>>(
              future: _list,
              builder: (context, s) {
                if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
                if (!s.hasData) return const SkeletonList(count: 4);
                final rows = s.data!;
                if (rows.isEmpty) {
                  return EmptyView(
                    icon: Icons.place_outlined,
                    title: switch (_status) { 'draft' => 'ما في مسودات', 'approved' => 'ما في نقاط معتمدة بعد', _ => 'ما في نقاط مرفوضة' },
                    message: _status == 'approved' ? 'أضف نقطة من زر + وراجعها لتنعتمد.' : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32),
                    children: [
                      for (final p in rows) ...[
                        WCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(p.name, style: WText.h3, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              StatusPill(p.kindLabel, tone: PillTone.neutral),
                            ]),
                            const SizedBox(height: 4),
                            Text('${p.lat.toStringAsFixed(5)}، ${p.lng.toStringAsFixed(5)}', style: WText.caption),
                            if (p.description.isNotEmpty) Text(p.description, style: WText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (p.status == 'rejected' && p.rejectionReason.isNotEmpty)
                              Text('سبب الرفض: ${p.rejectionReason}', style: WText.small.copyWith(color: WColors.danger)),
                            const SizedBox(height: 10),
                            Row(children: [
                              if (p.status == 'draft') ...[
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _approve(p),
                                    icon: const Icon(Icons.check_rounded, size: 18),
                                    label: const Text('اعتماد'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: OutlinedButton(onPressed: () => _reject(p), child: const Text('رفض'))),
                                const SizedBox(width: 8),
                              ],
                              Expanded(child: OutlinedButton(onPressed: () => _edit(p), child: const Text('تعديل'))),
                              if (p.status != 'approved') ...[
                                const SizedBox(width: 4),
                                IconButton(tooltip: 'حذف', onPressed: () => _delete(p), icon: const Icon(Icons.delete_outline_rounded)),
                              ],
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      );
}

/// نموذج إضافة/تعديل نقطة. الموقع يُحدَّد من الخريطة نفسها (لا إدخال يدوي للإحداثيات).
class MapPlaceForm extends StatefulWidget {
  const MapPlaceForm({super.key, this.place});
  final MapPlace? place;
  @override
  State<MapPlaceForm> createState() => _MapPlaceFormState();
}

class _MapPlaceFormState extends State<MapPlaceForm> {
  late final _name = TextEditingController(text: widget.place?.name ?? '');
  late final _desc = TextEditingController(text: widget.place?.description ?? '');
  late String _kind = widget.place?.kind ?? 'landmark';
  late LatLng? _point = widget.place == null ? null : LatLng(widget.place!.lat, widget.place!.lng);
  String _label = '';

  Future<void> _pick() async {
    final r = await LocationPickerPage.openPlace(context, initial: _point ?? kDefaultCenter, title: 'حدّد مكان النقطة', confirmLabel: 'تأكيد المكان');
    if (r != null && mounted) {
      setState(() {
        _point = r.point;
        _label = r.label;
      });
    }
  }

  Future<void> _save() async {
    final p = _point;
    if (_name.text.trim().length < 2) return showError(context, 'اكتب اسم النقطة');
    if (p == null) return showError(context, 'حدّد المكان على الخريطة');
    final ok = await runAction(
      context,
      () => adminApi.saveMapPlace(id: widget.place?.id, name: _name.text.trim(), kind: _kind, lat: p.latitude, lng: p.longitude, description: _desc.text.trim()),
      success: widget.place == null ? 'انحفظت كمسودة، راجعها للاعتماد' : 'انحفظ التعديل، صار مسودة من جديد',
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.place == null ? 'نقطة جديدة' : 'تعديل النقطة')),
        body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'النوع'),
            items: [for (final e in kMapPlaceKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 12),
          TextField(controller: _desc, maxLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'وصف مختصر (اختياري)')),
          const SizedBox(height: 12),
          WCard(
            child: Row(children: [
              const Icon(Icons.place_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _point == null ? 'ما تم تحديد المكان بعد' : (_label.isNotEmpty ? _label : '${_point!.latitude.toStringAsFixed(5)}، ${_point!.longitude.toStringAsFixed(5)}'),
                  style: WText.small,
                ),
              ),
              TextButton(onPressed: _pick, child: Text(_point == null ? 'تحديد' : 'تغيير')),
            ]),
          ),
          const SizedBox(height: 16),
          WButton('حفظ كمسودة', onPressed: _save),
          const SizedBox(height: 8),
          Text('النقطة ما تظهر للزبائن والسائقين إلا بعد اعتمادها.', style: WText.caption, textAlign: TextAlign.center),
        ]),
      );
}
