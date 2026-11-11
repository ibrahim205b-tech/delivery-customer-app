import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// إدارة السائقين والمندوبين: إضافة، مركبة، نوع، تفعيل/إيقاف
class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});
  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  int _key = 0;
  VehicleType? _filter;

  Future<void> _open([Driver? d]) async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _DriverForm(driver: d));
    if (ok == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('السائقون والمندوبون')),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: WColors.navy,
          foregroundColor: WColors.white,
          onPressed: () => _open(),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('إضافة سائق'),
        ),
        body: AsyncView<List<Driver>>(
          key: ValueKey(_key),
          load: adminApi.drivers,
          loading: const SkeletonList(),
          builder: (context, all, reload) {
            final list = all.where((d) => _filter == null || d.vehicleType == _filter).toList();
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, 100), children: [
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: Text('الكل (${all.length})'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                  for (final v in VehicleType.values)
                    ChoiceChip(label: Text('${v.label} (${all.where((d) => d.vehicleType == v).length})'), selected: _filter == v, onSelected: (_) => setState(() => _filter = v)),
                ]),
                const SizedBox(height: 10),
                if (list.isEmpty) const EmptyView(icon: Icons.no_transfer_outlined, title: 'ما اكو سائقين بعد'),
                for (final d in list) ...[
                  WCard(
                    onTap: () => _open(d),
                    child: Row(children: [
                      Stack(children: [
                        CircleAvatar(
                          backgroundColor: WColors.surfaceAlt,
                          child: Icon(switch (d.vehicleType) { VehicleType.taxi => Icons.local_taxi_rounded, VehicleType.tuktuk => Icons.electric_rickshaw_rounded, VehicleType.courier => Icons.two_wheeler_rounded }, color: WColors.navy),
                        ),
                        if (d.isAvailable && d.isActive) const PositionedDirectional(end: 0, bottom: 0, child: CircleAvatar(radius: 6, backgroundColor: WColors.mintDeep)),
                      ]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.fullName ?? '', style: WText.bodyStrong),
                          Text([d.phone ?? '', d.vehicleType.label, if ((d.model ?? '').isNotEmpty) d.model!, if ((d.plate ?? '').isNotEmpty) d.plate!].join(' · '), style: WText.caption),
                          if (d.lastSeenAt != null) Text('آخر ظهور ${relativeAr(d.lastSeenAt!)}', style: WText.caption),
                        ]),
                      ),
                      if (!d.isActive) const StatusPill('موقوف', tone: PillTone.danger) else if (d.isAvailable) const StatusPill('متاح', tone: PillTone.success),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
              ]),
            );
          },
        ),
      );
}

class _DriverForm extends StatefulWidget {
  const _DriverForm({this.driver});
  final Driver? driver;
  @override
  State<_DriverForm> createState() => _DriverFormState();
}

class _DriverFormState extends State<_DriverForm> {
  late final _phone = TextEditingController(text: widget.driver?.phone);
  late final _plate = TextEditingController(text: widget.driver?.plate);
  late final _model = TextEditingController(text: widget.driver?.model);
  late final _color = TextEditingController(text: widget.driver?.color);
  late VehicleType _vehicle = widget.driver?.vehicleType ?? VehicleType.courier;
  late bool _active = widget.driver?.isActive ?? true;
  late String? _area = widget.driver?.areaId;
  List<ServiceArea> _areas = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    catalogApi.areas().then((a) {
      if (mounted) setState(() => _areas = a);
    }).catchError((_) {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      var userId = widget.driver?.id;
      if (userId == null) {
        final p = normalizeIraqiPhone(_phone.text);
        if (p == null) throw 'رقم غير صحيح';
        final u = await adminApi.userByPhone(p);
        if (u == null) throw 'ما اكو حساب بهذا الرقم. خلي السائق يسجّل بتطبيق "واصل للأعمال" أولاً.';
        userId = u.id;
      }
      await adminApi.upsertDriver(userId: userId, vehicle: _vehicle, areaId: _area, plate: _plate.text.trim(), model: _model.text.trim(), color: _color.text.trim(), active: _active);
    }, success: 'انحفظ السائق');
    if (mounted) setState(() => _saving = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.driver == null ? 'إضافة سائق / مندوب' : (widget.driver!.fullName ?? ''), style: WText.h2),
              const SizedBox(height: 14),
              if (widget.driver == null) ...[
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم هاتف السائق', hintText: 'سجّل بتطبيق واصل للأعمال')),
                const SizedBox(height: 12),
              ],
              SegmentedButton<VehicleType>(
                segments: const [
                  ButtonSegment(value: VehicleType.courier, label: Text('مندوب'), icon: Icon(Icons.two_wheeler_rounded)),
                  ButtonSegment(value: VehicleType.taxi, label: Text('تكسي'), icon: Icon(Icons.local_taxi_rounded)),
                  ButtonSegment(value: VehicleType.tuktuk, label: Text('تكتك'), icon: Icon(Icons.electric_rickshaw_rounded)),
                ],
                selected: {_vehicle},
                onSelectionChanged: (v) => setState(() => _vehicle = v.first),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _model, decoration: const InputDecoration(labelText: 'المركبة', hintText: 'كيا، دراجة…'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _color, decoration: const InputDecoration(labelText: 'اللون'))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _plate, decoration: const InputDecoration(labelText: 'رقم اللوحة')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _areas.any((a) => a.id == _area) ? _area : null,
                decoration: const InputDecoration(labelText: 'المنطقة'),
                items: [const DropdownMenuItem(value: null, child: Text('كل المناطق')), for (final a in _areas) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _area = v),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('الحساب مفعّل')),
              const SizedBox(height: 8),
              WButton('حفظ', onPressed: _save, loading: _saving),
            ]),
          ),
        ),
      );
}
