import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

/// إدارة المحلات: الإضافة والاعتماد والتعطيل. لا يظهر أي محل للمستهلك قبل الاعتماد.
class MerchantsScreen extends StatefulWidget {
  const MerchantsScreen({super.key});
  @override
  State<MerchantsScreen> createState() => _MerchantsScreenState();
}

class _MerchantsScreenState extends State<MerchantsScreen> {
  String? _status = 'pending';
  String _q = '';
  int _key = 0;

  Future<void> _open([Merchant? m]) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => MerchantFormScreen(merchant: m)));
    if (changed == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المحلات ومقدّمو الخدمات')),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: WColors.ink,
          foregroundColor: WColors.white,
          onPressed: () => _open(),
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('إضافة محل'),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, 8),
            child: TextField(
              onSubmitted: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'ابحث باسم المحل', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: WSpace.page), children: [
              for (final s in [('pending', 'بانتظار الاعتماد'), ('approved', 'معتمدة'), ('suspended', 'موقوفة'), (null, 'الكل')])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) => setState(() => _status = s.$1)),
                ),
            ]),
          ),
          Expanded(
            child: AsyncView<List<Merchant>>(
              key: ValueKey('$_status-$_q-$_key'),
              load: () => adminApi.merchants(status: _status, search: _q),
              loading: const SkeletonList(),
              builder: (context, list, reload) => RefreshIndicator(
                onRefresh: reload,
                child: list.isEmpty
                    ? ListView(children: const [EmptyView(icon: Icons.storefront_outlined, title: 'ما اكو محلات هنا')])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(WSpace.page, 6, WSpace.page, 100),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final m = list[i];
                          return WCard(
                            onTap: () => _open(m),
                            child: Row(children: [
                              MerchantLogo(name: m.name, url: m.logoUrl, size: 50),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(m.name, style: WText.bodyStrong),
                                  Text('${m.categoryId} · ${m.ownerId == null ? 'بدون حساب تاجر' : 'مربوط بتاجر'}', style: WText.caption),
                                ]),
                              ),
                              StatusPill(switch (m.status) { MerchantStatus.pending => 'بانتظار', MerchantStatus.approved => 'معتمد', MerchantStatus.suspended => 'موقوف' },
                                  tone: switch (m.status) { MerchantStatus.pending => PillTone.warning, MerchantStatus.approved => PillTone.success, MerchantStatus.suspended => PillTone.danger }),
                            ]),
                          );
                        },
                      ),
              ),
            ),
          ),
        ]),
      );
}

class MerchantFormScreen extends StatefulWidget {
  const MerchantFormScreen({super.key, this.merchant});
  final Merchant? merchant;
  @override
  State<MerchantFormScreen> createState() => _MerchantFormScreenState();
}

class _MerchantFormScreenState extends State<MerchantFormScreen> {
  final _form = GlobalKey<FormState>();
  late Merchant? m = widget.merchant;
  late final _name = TextEditingController(text: m?.name);
  late final _desc = TextEditingController(text: m?.description);
  late final _address = TextEditingController(text: m?.addressText);
  late final _phone = TextEditingController(text: m?.phone);
  late final _fee = TextEditingController(text: '${m?.deliveryFee ?? 1500}');
  late final _min = TextEditingController(text: '${m?.minOrder ?? 0}');
  late final _radius = TextEditingController(text: '${m?.deliveryRadiusKm ?? 5}');
  late final _prep = TextEditingController(text: '${m?.prepMinutes ?? 20}');
  late final _ownerPhone = TextEditingController();
  late String? _category = m?.categoryId;
  late String? _area = m?.areaId;
  late LatLng? _point = m == null ? null : LatLng(m!.lat, m!.lng);
  late MerchantStatus _status = m?.status ?? MerchantStatus.pending;
  String? _ownerLabel;
  List<MerchantCategory> _cats = [];
  List<ServiceArea> _areas = [];
  List<HomeService> _services = [];
  Set<String> _serviceIds = {};
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    try {
      final r = await Future.wait([adminApi.allCategories(), catalogApi.areas(), adminApi.allHomeServices()]);
      final ids = m == null ? <String>{} : await adminApi.merchantServiceIds(m!.id);
      String? ownerLabel;
      if (m?.ownerId != null) {
        final u = (await adminApi.users(search: null, limit: 500)).where((x) => x.$1.id == m!.ownerId).firstOrNull;
        ownerLabel = u == null ? 'حساب مربوط' : '${u.$1.fullName} · ${u.$1.phone}';
      }
      if (!mounted) return;
      setState(() {
        _cats = (r[0] as List<MerchantCategory>).where((c) => c.kind == CategoryKind.store || c.kind == CategoryKind.homeService).toList();
        _areas = r[1] as List<ServiceArea>;
        _services = r[2] as List<HomeService>;
        _serviceIds = ids;
        _ownerLabel = ownerLabel;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  bool get _isProvider => _category == 'home_services';

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_point == null) return showError(context, 'حدّد موقع المحل على الخريطة.');
    setState(() => _saving = true);
    final data = {
      'name': _name.text.trim(),
      'category_id': _category,
      'area_id': _area,
      'description': _desc.text.trim(),
      'address_text': _address.text.trim(),
      'phone': _phone.text.trim(),
      'lat': _point!.latitude,
      'lng': _point!.longitude,
      'delivery_fee': int.parse(_fee.text),
      'min_order': int.parse(_min.text),
      'delivery_radius_km': double.parse(_radius.text),
      'prep_minutes': int.parse(_prep.text),
      'status': _status.name,
    };
    final ok = await runAction(context, () async {
      final saved = await adminApi.saveMerchant(m?.id, data);
      if (_isProvider) await adminApi.setMerchantServices(saved.id, _serviceIds);
      setState(() => m = saved);
    }, success: widget.merchant == null ? 'انضاف المحل. هسه تگدر تربط التاجر وترفع الصور.' : 'انحفظت التغييرات');
    if (mounted) setState(() => _saving = false);
    if (ok && widget.merchant != null && mounted) Navigator.pop(context, true);
  }

  Future<void> _linkOwner() async {
    final p = normalizeIraqiPhone(_ownerPhone.text);
    if (p == null) return showError(context, 'رقم غير صحيح');
    await runAction(context, () async {
      final u = await adminApi.userByPhone(p);
      if (u == null) throw 'ما اكو حساب بهذا الرقم. خلي التاجر يسجّل بتطبيق "واصل للأعمال" أولاً.';
      await adminApi.linkOwner(m!.id, u.id);
      setState(() => _ownerLabel = '${u.fullName} · ${u.phone}');
      _ownerPhone.clear();
    }, success: 'انربط الحساب بالمحل');
  }

  Future<void> _upload(bool logo) async {
    final img = await pickImage(context, maxSide: logo ? 600 : 1600);
    if (img == null || !mounted) return;
    setState(() => _uploading = true);
    await runAction(context, () async {
      final url = await mediaApi.upload('merchants/${m!.id}', img.bytes, ext: img.ext);
      final saved = await adminApi.saveMerchant(m!.id, {logo ? 'logo_url' : 'cover_url': url});
      setState(() => m = saved);
    });
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, title: 'حذف المحل نهائياً؟', message: 'إذا عنده طلبات سابقة الأفضل "إيقاف" بدل الحذف.', confirm: 'حذف', danger: true)) return;
    if (!mounted) return;
    if (await runAction(context, () => adminApi.deleteMerchant(m!.id), success: 'انحذف') && mounted) Navigator.pop(context, true);
  }

  String? _num(String? v) => int.tryParse(v ?? '') == null ? 'رقم' : null;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {},
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.merchant == null && m == null ? 'محل جديد' : (m?.name ?? '')),
            leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context, m != null)),
            actions: [if (m != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded, color: WColors.danger))],
          ),
          body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
              Text('حالة الاعتماد', style: WText.caption),
              const SizedBox(height: 6),
              SegmentedButton<MerchantStatus>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: MerchantStatus.pending, label: Text('بانتظار')),
                  ButtonSegment(value: MerchantStatus.approved, label: Text('معتمد')),
                  ButtonSegment(value: MerchantStatus.suspended, label: Text('موقوف')),
                ],
                selected: {_status},
                onSelectionChanged: (v) => setState(() => _status = v.first),
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'اسم المحل'), validator: (v) => (v ?? '').trim().length < 2 ? 'مطلوب' : null),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _cats.any((c) => c.id == _category) ? _category : null,
                decoration: const InputDecoration(labelText: 'التصنيف'),
                items: [for (final c in _cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => _category = v),
                validator: (v) => v == null ? 'اختار التصنيف' : null,
              ),
              if (_isProvider) ...[
                const SizedBox(height: 10),
                Text('الخدمات اللي يقدّمها', style: WText.caption),
                Wrap(spacing: 8, children: [
                  for (final s in _services)
                    FilterChip(
                      label: Text(s.name),
                      selected: _serviceIds.contains(s.id),
                      onSelected: (v) => setState(() => v ? _serviceIds.add(s.id) : _serviceIds.remove(s.id)),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              TextFormField(controller: _desc, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _areas.any((a) => a.id == _area) ? _area : null,
                decoration: const InputDecoration(labelText: 'المنطقة'),
                items: [const DropdownMenuItem(value: null, child: Text('بدون منطقة')), for (final a in _areas) DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.city}'))],
                onChanged: (v) => setState(() => _area = v),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'العنوان', hintText: 'المنطقة، الشارع، أقرب نقطة دالة')),
              const SizedBox(height: 12),
              WCard(
                onTap: () async {
                  final p = await LocationPickerPage.open(context, initial: _point, title: 'موقع المحل');
                  if (p != null) setState(() => _point = p);
                },
                child: Row(children: [
                  const Icon(Icons.place_outlined, color: WColors.blue),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_point == null ? 'حدّد الموقع على الخريطة' : '${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)}', style: WText.bodyStrong, textDirection: TextDirection.ltr, textAlign: TextAlign.right)),
                  const Icon(Icons.map_outlined),
                ]),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الاتصال')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextFormField(controller: _fee, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'أجرة التوصيل', suffixText: 'د.ع'), validator: _num)),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: _min, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'أقل طلب', suffixText: 'د.ع'), validator: _num)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _radius,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'نطاق التوصيل', suffixText: 'كم'),
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'رقم' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: _prep, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'وقت التحضير', suffixText: 'دقيقة'), validator: _num)),
              ]),
              const SizedBox(height: 20),
              WButton(m == null ? 'إضافة المحل' : 'حفظ', onPressed: _save, loading: _saving),
              if (m != null) ...[
                const SectionTitle('حساب التاجر', padding: EdgeInsets.fromLTRB(0, 28, 0, 8)),
                if (_ownerLabel != null)
                  WCard(
                    child: Row(children: [
                      const Icon(Icons.verified_user_outlined, color: WColors.success),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_ownerLabel!, style: WText.bodyStrong)),
                      TextButton(
                        onPressed: () async {
                          if (await runAction(context, () => adminApi.linkOwner(m!.id, null), success: 'انفك الربط')) setState(() => _ownerLabel = null);
                        },
                        child: const Text('فك الربط'),
                      ),
                    ]),
                  )
                else
                  Row(children: [
                    Expanded(child: TextField(controller: _ownerPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم هاتف التاجر', hintText: '07XXXXXXXXX'))),
                    const SizedBox(width: 10),
                    WButton('ربط', onPressed: _linkOwner, expand: false, kind: WButtonKind.dark),
                  ]),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('التاجر يسجّل برقمه بتطبيق "واصل للأعمال"، وبعدها تربطه هنا.', style: WText.caption),
                ),
                const SectionTitle('الصور', padding: EdgeInsets.fromLTRB(0, 24, 0, 8)),
                Row(children: [
                  InkWell(onTap: _uploading ? null : () => _upload(true), child: MerchantLogo(name: m!.name, url: m!.logoUrl, size: 84)),
                  const SizedBox(width: 12),
                  Expanded(child: InkWell(onTap: _uploading ? null : () => _upload(false), child: WImage(m!.coverUrl, height: 84, fallbackIcon: Icons.add_photo_alternate_outlined))),
                ]),
                if (_uploading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              ],
              const SizedBox(height: 32),
            ]),
          ),
        ),
      );
}
