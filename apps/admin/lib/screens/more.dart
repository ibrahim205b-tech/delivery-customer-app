import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import 'commissions.dart';
import 'growth.dart';
import 'support_inbox.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    Widget tile(IconData i, String t, String s, Widget page) => ListTile(
          leading: CircleAvatar(backgroundColor: WColors.surfaceAlt, child: Icon(i, color: WColors.fg)),
          title: Text(t),
          subtitle: Text(s),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => open(page),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
        WCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            tile(Icons.percent_rounded, 'العمولات', 'عمولة الفترة، المستحق على كل محل، وتسجيل الدفعات', const CommissionsScreen()),
            const Divider(indent: 72),
            tile(Icons.support_agent_rounded, 'رسائل الدعم', 'محادثات المستهلكين والتجار والسائقين', const SupportInboxScreen()),
            const Divider(indent: 72),
            tile(Icons.people_alt_outlined, 'المستخدمون', 'بحث، تعطيل، صلاحيات، الطلبات', const UsersScreen()),
            const Divider(indent: 72),
            tile(Icons.map_outlined, 'المناطق', 'مناطق التشغيل ونطاقها', const AreasScreen()),
            const Divider(indent: 72),
            tile(Icons.dashboard_customize_outlined, 'الصفحة الرئيسية', 'ترتيب الأقسام، البانرات، السلايدر، والكروت', const HomeLayoutScreen()),
            const Divider(indent: 72),
            tile(Icons.local_offer_outlined, 'العروض', 'عروض الصفحة الرئيسية', const PromotionsScreen()),
            const Divider(indent: 72),
            tile(Icons.confirmation_number_outlined, 'أكواد الخصم', 'إنشاء الأكواد ومتابعة استخدامها', const PromoCodesScreen()),
            const Divider(indent: 72),
            tile(Icons.stars_outlined, 'المكافآت', 'النقاط، رصيد المحافظ، ودعوة الأصدقاء', const RewardsSettingsScreen()),
            const Divider(indent: 72),
            tile(Icons.category_outlined, 'الأقسام والخدمات', 'تفعيل الأقسام وأنواع الخدمات المنزلية', const CatalogSettingsScreen()),
            const Divider(indent: 72),
            tile(Icons.tune_rounded, 'إعدادات المنصة', 'أجور التوصيل والرحلات، الحد الأدنى، العمولات', const PlatformSettingsScreen()),
          ]),
        ),
        const SizedBox(height: 12),
        const WCard(padding: EdgeInsets.zero, child: ThemeModeTile()),
        const SizedBox(height: 16),
        WButton('تسجيل الخروج', kind: WButtonKind.ghost, icon: Icons.logout_rounded, onPressed: () async {
          if (await confirmDialog(context, title: 'تسجيل الخروج؟', confirm: 'خروج')) await auth.signOut();
        }),
      ]),
    );
  }
}

// ============================== المستخدمون ==============================
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String _q = '';
  int _key = 0;

  String _roleLabel(AppRole r) => switch (r) { AppRole.customer => 'مستهلك', AppRole.merchant => 'تاجر', AppRole.driver => 'سائق', AppRole.admin => 'مدير' };

  Future<void> _manage(AppUser u, Set<AppRole> roles) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(u.fullName.isEmpty ? '—' : u.fullName, style: WText.h2),
              Text('${u.phone ?? ''} · سجّل ${dateTimeAr(u.createdAt)}', style: WText.small),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الحساب مفعّل'),
                value: u.isActive,
                onChanged: u.id == auth.userId
                    ? null
                    : (v) async {
                        if (await runAction(c, () => adminApi.setUserActive(u.id, v), success: v ? 'انفعّل' : 'انوقف')) {
                          if (c.mounted) Navigator.pop(c);
                          setState(() => _key++);
                        }
                      },
              ),
              Text('الصلاحيات', style: WText.caption),
              Wrap(spacing: 8, children: [
                for (final r in [AppRole.merchant, AppRole.driver, AppRole.admin])
                  FilterChip(
                    label: Text(_roleLabel(r)),
                    selected: roles.contains(r),
                    onSelected: (v) async {
                      if (r == AppRole.admin && v && !await confirmDialog(c, title: 'منح صلاحية مدير؟', message: 'المدير يتحكم بكل المنصة.', confirm: 'منح', danger: true)) return;
                      if (!c.mounted) return;
                      if (await runAction(c, () => adminApi.setRole(u.id, r, v))) set(() => v ? roles.add(r) : roles.remove(r));
                    },
                  ),
              ]),
              Text('تاجر: اربطه بمحل من شاشة المحلات. سائق: أضفه من شاشة السائقين.', style: WText.caption),
              const SizedBox(height: 12),
              WButton('رصيد المحفظة', kind: WButtonKind.secondary, icon: Icons.account_balance_wallet_outlined, onPressed: () {
                Navigator.pop(c);
                showWalletSheet(context, u);
              }),
              const SizedBox(height: 10),
              WButton('طلبات هذا المستخدم', kind: WButtonKind.secondary, icon: Icons.receipt_long_outlined, onPressed: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => _UserOrders(user: u)));
              }),
            ]),
          ),
        ),
      ),
    );
    setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المستخدمون')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, 8),
            child: TextField(
              onSubmitted: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'الاسم أو رقم الهاتف', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          Expanded(
            child: AsyncView<List<(AppUser, Set<AppRole>)>>(
              key: ValueKey('$_q-$_key'),
              load: () => adminApi.users(search: _q),
              loading: const SkeletonList(itemHeight: 60),
              builder: (context, list, reload) => list.isEmpty
                  ? const EmptyView(icon: Icons.person_search_outlined, title: 'ما لگينا مستخدمين')
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(indent: 72),
                      itemBuilder: (context, i) {
                        final (u, roles) = list[i];
                        return ListTile(
                          onTap: () => _manage(u, {...roles}),
                          leading: CircleAvatar(
                            backgroundColor: u.isActive ? WColors.surfaceAlt : WColors.dangerSoft,
                            child: Text(u.fullName.characters.firstOrNull ?? '؟', style: WText.bodyStrong),
                          ),
                          title: Text(u.fullName.isEmpty ? '—' : u.fullName),
                          subtitle: Text('${u.phone ?? ''}${u.isActive ? '' : ' · موقوف'}'),
                          trailing: Wrap(spacing: 4, children: [
                            for (final r in roles.where((r) => r != AppRole.customer))
                              StatusPill(_roleLabel(r), tone: r == AppRole.admin ? PillTone.danger : PillTone.info),
                          ]),
                        );
                      },
                    ),
            ),
          ),
        ]),
      );
}

class _UserOrders extends StatelessWidget {
  const _UserOrders({required this.user});
  final AppUser user;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('طلبات ${user.fullName}')),
        body: AsyncView<List<Order>>(
          load: () => adminApi.orders(customerId: user.id),
          builder: (context, list, _) => list.isEmpty
              ? const EmptyView(icon: Icons.receipt_long_outlined, title: 'ما عنده طلبات')
              : ListView.separated(
                  padding: const EdgeInsets.all(WSpace.page),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final o = list[i];
                    return WCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${o.code} · ${o.merchantName ?? ''}', style: WText.bodyStrong),
                            Text('${dateTimeAr(o.createdAt)} · ${iqd(o.total)}', style: WText.caption),
                          ]),
                        ),
                        StatusPill(o.status.label),
                      ]),
                    );
                  },
                ),
        ),
      );
}

// ============================== المناطق ==============================
class AreasScreen extends StatefulWidget {
  const AreasScreen({super.key});
  @override
  State<AreasScreen> createState() => _AreasScreenState();
}

class _AreasScreenState extends State<AreasScreen> {
  int _key = 0;

  Future<void> _edit([ServiceArea? a]) async {
    final name = TextEditingController(text: a?.name);
    final city = TextEditingController(text: a?.city ?? 'بغداد');
    final radius = TextEditingController(text: '${a?.radiusKm ?? 5}');
    LatLng? center = a == null ? null : LatLng(a.centerLat, a.centerLng);
    var active = a?.isActive ?? true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(a == null ? 'منطقة جديدة' : 'تعديل المنطقة', style: WText.h2),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المنطقة', hintText: 'الكرادة')),
                const SizedBox(height: 10),
                TextField(controller: city, decoration: const InputDecoration(labelText: 'المدينة')),
                const SizedBox(height: 10),
                TextField(controller: radius, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'نصف القطر', suffixText: 'كم')),
                const SizedBox(height: 10),
                WButton(center == null ? 'حدّد مركز المنطقة' : 'المركز محدّد ✓ (تغيير)', kind: WButtonKind.secondary, icon: Icons.map_outlined, onPressed: () async {
                  final p = await LocationPickerPage.open(c, initial: center, title: 'مركز المنطقة');
                  if (p != null) set(() => center = p);
                }),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => set(() => active = v), title: const Text('مفعّلة')),
                WButton('حفظ', onPressed: () async {
                  final r = double.tryParse(radius.text);
                  if (name.text.trim().isEmpty || center == null || r == null || r <= 0) return showError(c, 'أكمل الاسم والمركز ونصف القطر');
                  if (await runAction(c, () => adminApi.saveArea(a?.id, {
                        'name': name.text.trim(), 'city': city.text.trim(), 'center_lat': center!.latitude, 'center_lng': center!.longitude, 'radius_km': r, 'is_active': active,
                      })) && c.mounted) {
                    Navigator.pop(c, true);
                  }
                }),
                if (a != null)
                  TextButton(
                    onPressed: () async {
                      if (await confirmDialog(c, title: 'حذف المنطقة؟', message: 'المحلات تبقى بدون منطقة.', confirm: 'حذف', danger: true) && c.mounted) {
                        if (await runAction(c, () => adminApi.deleteArea(a.id)) && c.mounted) Navigator.pop(c, true);
                      }
                    },
                    child: Text('حذف', style: WText.button.copyWith(color: WColors.danger)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
    if (ok == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المناطق')),
        floatingActionButton: FloatingActionButton(backgroundColor: WColors.night, foregroundColor: WColors.white, onPressed: _edit, child: const Icon(Icons.add_rounded)),
        body: AsyncView<List<ServiceArea>>(
          key: ValueKey(_key),
          load: catalogApi.areas,
          builder: (context, list, _) => list.isEmpty
              ? const EmptyView(icon: Icons.map_outlined, title: 'ما اكو مناطق', message: 'ابدأ بمنطقة وحدة (مثلاً حيّك) وتوسّع لاحقاً.')
              : ListView(padding: const EdgeInsets.all(WSpace.page), children: [
                  SizedBox(
                    height: 220,
                    child: ClipRRect(
                      borderRadius: WRadius.all(WRadius.lg),
                      child: WMap(markers: [for (final a in list) WMarker(LatLng(a.centerLat, a.centerLng))]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final a in list)
                    ListTile(
                      onTap: () => _edit(a),
                      leading: Icon(Icons.place_rounded, color: a.isActive ? WColors.link : WColors.inkFaint),
                      title: Text('${a.name} · ${a.city}'),
                      subtitle: Text('نصف القطر ${a.radiusKm} كم${a.isActive ? '' : ' · معطّلة'}'),
                      trailing: const Icon(Icons.edit_outlined),
                    ),
                ]),
        ),
      );
}

// ============================== العروض ==============================
class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});
  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  int _key = 0;

  Future<void> _edit([Promotion? p]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _PromotionForm(promo: p)));
    if (ok == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('العروض')),
        floatingActionButton: FloatingActionButton(backgroundColor: WColors.night, foregroundColor: WColors.white, onPressed: _edit, child: const Icon(Icons.add_rounded)),
        body: AsyncView<List<Promotion>>(
          key: ValueKey(_key),
          load: adminApi.promotions,
          builder: (context, list, _) => list.isEmpty
              ? const EmptyView(icon: Icons.local_offer_outlined, title: 'ما اكو عروض')
              : ListView.separated(
                  padding: const EdgeInsets.all(WSpace.page),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final live = p.isActive && DateTime.now().isAfter(p.startsAt) && DateTime.now().isBefore(p.endsAt);
                    return WCard(
                      onTap: () => _edit(p),
                      child: Row(children: [
                        WImage(p.imageUrl, width: 64, height: 64, fallbackIcon: Icons.local_offer_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.title, style: WText.bodyStrong),
                            Text('${dateAr(p.startsAt)} ← ${dateAr(p.endsAt)}', style: WText.caption),
                          ]),
                        ),
                        StatusPill(live ? 'ظاهر' : (p.isActive ? 'مجدول/منتهي' : 'معطّل'), tone: live ? PillTone.success : PillTone.neutral),
                      ]),
                    );
                  },
                ),
        ),
      );
}

class _PromotionForm extends StatefulWidget {
  const _PromotionForm({this.promo});
  final Promotion? promo;
  @override
  State<_PromotionForm> createState() => _PromotionFormState();
}

class _PromotionFormState extends State<_PromotionForm> {
  late final _title = TextEditingController(text: widget.promo?.title);
  late final _desc = TextEditingController(text: widget.promo?.description);
  late String? _image = widget.promo?.imageUrl;
  late String? _merchant = widget.promo?.merchantId;
  late DateTime _start = widget.promo?.startsAt ?? DateTime.now();
  late DateTime _end = widget.promo?.endsAt ?? DateTime.now().add(const Duration(days: 7));
  late bool _active = widget.promo?.isActive ?? true;
  List<Merchant> _merchants = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    adminApi.merchants(status: 'approved').then((m) {
      if (mounted) setState(() => _merchants = m);
    }).catchError((_) {});
  }

  Future<DateTime?> _date(DateTime init) async {
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365)));
    return d;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.promo == null ? 'عرض جديد' : 'تعديل العرض'),
          actions: [
            if (widget.promo != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: WColors.danger),
                onPressed: () async {
                  if (await confirmDialog(context, title: 'حذف العرض؟', confirm: 'حذف', danger: true) && context.mounted) {
                    if (await runAction(context, () => adminApi.deletePromotion(widget.promo!.id)) && context.mounted) Navigator.pop(context, true);
                  }
                },
              ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          InkWell(
            onTap: _busy
                ? null
                : () async {
                    final img = await pickImage(context, maxSide: 1600);
                    if (img == null || !context.mounted) return;
                    setState(() => _busy = true);
                    await runAction(context, () async {
                      final url = await mediaApi.upload('promotions', img.bytes, ext: img.ext);
                      setState(() => _image = url);
                    });
                    if (mounted) setState(() => _busy = false);
                  },
            child: WImage(_image, height: 150, radius: WRadius.lg, fallbackIcon: Icons.add_photo_alternate_outlined),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 14),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'العنوان')),
          const SizedBox(height: 10),
          TextField(controller: _desc, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _merchants.any((m) => m.id == _merchant) ? _merchant : null,
            decoration: const InputDecoration(labelText: 'المحل (اختياري)'),
            items: [const DropdownMenuItem(value: null, child: Text('عرض عام')), for (final m in _merchants) DropdownMenuItem(value: m.id, child: Text(m.name))],
            onChanged: (v) => setState(() => _merchant = v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: WButton('من ${dateAr(_start)}', kind: WButtonKind.secondary, onPressed: () async {
              final d = await _date(_start);
              if (d != null) setState(() => _start = d);
            })),
            const SizedBox(width: 10),
            Expanded(child: WButton('إلى ${dateAr(_end)}', kind: WButtonKind.secondary, onPressed: () async {
              final d = await _date(_end);
              if (d != null) setState(() => _end = DateTime(d.year, d.month, d.day, 23, 59));
            })),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('مفعّل')),
          const SizedBox(height: 10),
          WButton('حفظ', onPressed: () async {
            if (_title.text.trim().isEmpty) return showError(context, 'اكتب العنوان');
            if (!_end.isAfter(_start)) return showError(context, 'تاريخ النهاية لازم بعد البداية');
            if (await runAction(context, () => adminApi.savePromotion(widget.promo?.id, {
                  'title': _title.text.trim(), 'description': _desc.text.trim(), 'image_url': _image, 'merchant_id': _merchant,
                  'starts_at': _start.toUtc().toIso8601String(), 'ends_at': _end.toUtc().toIso8601String(), 'is_active': _active,
                }), success: 'انحفظ العرض') && context.mounted) {
              Navigator.pop(context, true);
            }
          }),
        ]),
      );
}

// ============================== الأقسام والخدمات ==============================
class CatalogSettingsScreen extends StatefulWidget {
  const CatalogSettingsScreen({super.key});
  @override
  State<CatalogSettingsScreen> createState() => _CatalogSettingsScreenState();
}

class _CatalogSettingsScreenState extends State<CatalogSettingsScreen> {
  int _key = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الأقسام والخدمات')),
        body: AsyncView<(List<MerchantCategory>, List<HomeService>)>(
          key: ValueKey(_key),
          load: () async => (await adminApi.allCategories(), await adminApi.allHomeServices()),
          builder: (context, d, _) => ListView(padding: const EdgeInsets.all(WSpace.page), children: [
            Text('أقسام التطبيق', style: WText.h3),
            Text('القسم المعطّل يختفي من تطبيق المستهلك.', style: WText.small),
            const SizedBox(height: 8),
            WCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final c in d.$1)
                  SwitchListTile(
                    secondary: Icon(categoryIcon(c.icon), color: categoryTint(c.icon)),
                    title: Text(c.name),
                    value: c.isActive,
                    onChanged: (v) async {
                      if (await runAction(context, () => adminApi.setCategoryActive(c.id, v))) setState(() => _key++);
                    },
                  ),
              ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text('أنواع الخدمات المنزلية', style: WText.h3)),
              TextButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة'),
                onPressed: () async {
                  final n = await promptText(context, title: 'اسم الخدمة', hint: 'مثلاً: تبريد وتكييف');
                  if (n != null && context.mounted && await runAction(context, () => adminApi.saveHomeService(null, n, true))) setState(() => _key++);
                },
              ),
            ]),
            WCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final s in d.$2)
                  SwitchListTile(
                    secondary: Icon(homeServiceIcon(s.icon), color: WColors.warning),
                    title: Text(s.name),
                    value: s.isActive,
                    onChanged: (v) async {
                      if (await runAction(context, () => adminApi.saveHomeService(s.id, s.name, v))) setState(() => _key++);
                    },
                  ),
              ]),
            ),
          ]),
        ),
      );
}

// ============================== إعدادات المنصة ==============================
class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({super.key});
  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  Map<String, dynamic>? _s;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await catalogApi.settings();
      setState(() => _s = s.map((k, v) => MapEntry(k, v is Map ? Map<String, dynamic>.from(v.map((a, b) => MapEntry('$a', b is Map ? Map<String, dynamic>.from(b) : b))) : v)));
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Map<String, dynamic> _map(String key) => (_s![key] as Map<String, dynamic>?) ?? <String, dynamic>{};

  Future<void> _save(String key) async {
    setState(() => _saving = true);
    await runAction(context, () => adminApi.saveSetting(key, _s![key] as Object), success: 'انحفظ');
    if (mounted) setState(() => _saving = false);
  }

  Widget _pricing(String title, Map<String, dynamic> cfg, VoidCallback onSave) {
    Widget numField(String k, String label) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextFormField(
            initialValue: '${cfg[k] ?? 0}',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: k == 'max_km' ? 'كم' : 'د.ع', isDense: true),
            onChanged: (v) => cfg[k] = int.tryParse(v) ?? 0,
          ),
        );
    return StatefulBuilder(
      builder: (context, set) => WCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: WText.h3),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'distance', label: Text('حسب المسافة')), ButtonSegment(value: 'fixed', label: Text('أجرة ثابتة'))],
            selected: {(cfg['mode'] as String?) ?? 'distance'},
            onSelectionChanged: (v) => set(() => cfg['mode'] = v.first),
          ),
          if ((cfg['mode'] ?? 'distance') == 'distance') ...[numField('base', 'فتح العداد'), numField('per_km', 'لكل كيلومتر')] else numField('fixed', 'الأجرة الثابتة'),
          numField('min', 'أقل أجرة'),
          if (cfg.containsKey('max_km')) numField('max_km', 'أقصى مسافة'),
          const SizedBox(height: 12),
          WButton('حفظ', kind: WButtonKind.dark, loading: _saving, onPressed: onSave),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(), body: ErrorView(error: _error!, onRetry: _load));
    if (_s == null) return Scaffold(appBar: AppBar(), body: const LoadingView());
    final ride = _map('ride_pricing');
    ride['taxi'] ??= <String, dynamic>{};
    ride['tuktuk'] ??= <String, dynamic>{};
    final errand = _map('errand_pricing');
    final minOrder = _map('min_order');
    final outArea = _map('allow_out_of_area');
    final commission = _map('commission');
    final hours = _map('operating_hours');
    final support = _map('support');
    _s!['ride_pricing'] = ride;
    _s!['errand_pricing'] = errand;
    _s!['min_order'] = minOrder;
    _s!['allow_out_of_area'] = outArea;
    _s!['commission'] = commission;
    _s!['operating_hours'] = hours;
    _s!['support'] = support;

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات المنصة')),
      body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
        Text('أجور توصيل المحلات تُضبط لكل محل من شاشة المحلات.', style: WText.small),
        const SizedBox(height: 12),
        _pricing('تسعير التكسي', ride['taxi'] as Map<String, dynamic>, () => _save('ride_pricing')),
        const SizedBox(height: 12),
        _pricing('تسعير التكتك', ride['tuktuk'] as Map<String, dynamic>, () => _save('ride_pricing')),
        const SizedBox(height: 12),
        _pricing('المندوب وتوصيل الأغراض', errand, () => _save('errand_pricing')),
        const SizedBox(height: 12),
        StatefulBuilder(
          builder: (context, set) => WCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('الطلبات', style: WText.h3),
              TextFormField(
                initialValue: '${minOrder['amount'] ?? 0}',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'الحد الأدنى العام للطلب', suffixText: 'د.ع'),
                onChanged: (v) => minOrder['amount'] = int.tryParse(v) ?? 0,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('السماح بالطلب خارج نطاق توصيل المحل'),
                value: outArea['enabled'] == true,
                onChanged: (v) => set(() => outArea['enabled'] = v),
              ),
              WButton('حفظ', kind: WButtonKind.dark, loading: _saving, onPressed: () async {
                await _save('min_order');
                await _save('allow_out_of_area');
              }),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        StatefulBuilder(
          builder: (context, set) => WCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('العمولات', style: WText.h3),
              Text('النسبة العامة على كل المحلات (إلا اللي إلها نسبة خاصة). تُحسب على مبلغ المنتجات فقط وتُستحق عند التسليم. تغييرها ينطبق على الطلبات الجديدة فقط.', style: WText.small),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('تفعيل العمولة'), value: commission['enabled'] == true, onChanged: (v) => set(() => commission['enabled'] = v)),
              if (commission['enabled'] == true)
                TextFormField(
                  initialValue: '${commission['percent'] ?? 0}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'النسبة', suffixText: '%'),
                  onChanged: (v) => commission['percent'] = (int.tryParse(v) ?? 0).clamp(0, 50),
                ),
              const SizedBox(height: 8),
              WButton('حفظ', kind: WButtonKind.dark, loading: _saving, onPressed: () => _save('commission')),
              const SizedBox(height: 6),
              WButton('عرض العمولات والمستحقات', kind: WButtonKind.ghost, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommissionsScreen()))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        WCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('التشغيل والدعم', style: WText.h3),
            Row(children: [
              Expanded(child: TextFormField(initialValue: '${hours['open'] ?? '08:00'}', decoration: const InputDecoration(labelText: 'يبدأ'), onChanged: (v) => hours['open'] = v)),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(initialValue: '${hours['close'] ?? '02:00'}', decoration: const InputDecoration(labelText: 'ينتهي'), onChanged: (v) => hours['close'] = v)),
            ]),
            TextFormField(initialValue: '${support['phone'] ?? ''}', keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الدعم (للاتصال)', hintText: '07XXXXXXXXX'), onChanged: (v) => support['phone'] = v),
            TextFormField(
              initialValue: '${support['whatsapp'] ?? ''}',
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم واتساب الدعم', hintText: 'إذا فارغ يُستخدم رقم الدعم', helperText: 'يظهر زر واتساب للزبائن والتجار والسائقين'),
              onChanged: (v) => support['whatsapp'] = v,
            ),
            const SizedBox(height: 8),
            WButton('حفظ', kind: WButtonKind.dark, loading: _saving, onPressed: () async {
              await _save('operating_hours');
              await _save('support');
            }),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
