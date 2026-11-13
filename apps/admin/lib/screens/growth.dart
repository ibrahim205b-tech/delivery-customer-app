import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

// =====================================================================
// الرئيسية: ترتيب الأقسام ومحتواها (migration 0009)
// =====================================================================
class HomeLayoutScreen extends StatefulWidget {
  const HomeLayoutScreen({super.key});
  @override
  State<HomeLayoutScreen> createState() => _HomeLayoutScreenState();
}

class _HomeLayoutScreenState extends State<HomeLayoutScreen> {
  List<HomeSection>? _list;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await adminApi.homeSections();
      if (mounted) {
        setState(() {
          _list = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _add() async {
    final type = await showModalBottomSheet<HomeSectionType>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('نوع القسم', style: WText.h2)),
          for (final t in HomeSectionType.values.where((t) => t != HomeSectionType.unknown))
            ListTile(
              leading: Icon(_icon(t)),
              title: Text(t.label),
              subtitle: Text(t.hasItems ? 'إنت تضيف محتواه (صور، نصوص، وجهات)' : 'جاهز: التطبيق يعبّيه تلقائياً'),
              onTap: () => Navigator.pop(c, t),
            ),
        ]),
      ),
    );
    if (type == null || !mounted) return;
    final ok = await runAction(context, () => adminApi.saveHomeSection(null, {'type': type.name, 'sort': ((_list?.length ?? 0) + 1) * 10, 'is_active': !type.hasItems}));
    if (!ok) return;
    await _load();
    // القسم اللي يحتاج محتوى ينضاف موقوف وينفتح مباشرة حتى تضيف عناصره ثم تفعّله
    final created = _list?.lastOrNull;
    if (type.hasItems && created != null && mounted) await _open(created);
  }

  Future<void> _open(HomeSection s) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _SectionEditor(section: s)));
    _load();
  }

  static IconData _icon(HomeSectionType t) => switch (t) {
        HomeSectionType.categories => Icons.grid_view_rounded,
        HomeSectionType.promotions => Icons.local_offer_outlined,
        HomeSectionType.destinations => Icons.flag_outlined,
        HomeSectionType.nearby => Icons.near_me_outlined,
        HomeSectionType.popular => Icons.trending_up_rounded,
        HomeSectionType.reorder => Icons.replay_rounded,
        HomeSectionType.slider => Icons.view_carousel_outlined,
        HomeSectionType.banner => Icons.image_outlined,
        HomeSectionType.cards => Icons.view_agenda_outlined,
        HomeSectionType.unknown => Icons.help_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('الصفحة الرئيسية')),
      floatingActionButton: FloatingActionButton.extended(backgroundColor: WColors.night, foregroundColor: WColors.white, onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('قسم جديد')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : list == null
              ? const SkeletonList(itemHeight: 64)
              : list.isEmpty
                  ? const EmptyView(icon: Icons.dashboard_customize_outlined, title: 'ما اكو أقسام', message: 'بدون أقسام، تطبيق المستهلك يعرض الترتيب الافتراضي.')
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, 8),
                        child: Text('اسحب لتغيير الترتيب. التغيير يظهر للزبائن عند فتح التطبيق أو السحب للتحديث، بدون تنزيل نسخة جديدة.', style: WText.small),
                      ),
                      Expanded(
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, 96),
                          itemCount: list.length,
                          onReorder: (from, to) async {
                            if (to > from) to--;
                            setState(() => list.insert(to, list.removeAt(from)));
                            await runAction(context, () => adminApi.reorderHomeSections(list.map((s) => s.id).toList()));
                          },
                          itemBuilder: (context, i) {
                            final s = list[i];
                            final empty = s.type.hasItems && s.items.where((it) => it.isActive).isEmpty;
                            return Padding(
                              key: ValueKey(s.id),
                              padding: const EdgeInsets.only(bottom: 10),
                              child: WCard(
                                padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
                                onTap: () => _open(s),
                                child: Row(children: [
                                  CircleAvatar(backgroundColor: WColors.surfaceAlt, child: Icon(_icon(s.type), color: WColors.fg, size: 20)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(s.title.isEmpty ? s.type.label : s.title, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(
                                        s.type.hasItems
                                            ? '${s.type.label} · ${s.items.length} عنصر${empty ? ' · ما يظهر بدون عناصر' : ''}'
                                            : (s.title.isEmpty ? 'جاهز · يتعبّى تلقائياً' : '${s.type.label} · جاهز'),
                                        style: WText.caption.copyWith(color: empty ? WColors.warning : null),
                                      ),
                                    ]),
                                  ),
                                  Switch(
                                    value: s.isActive,
                                    onChanged: (v) async {
                                      if (await runAction(context, () => adminApi.saveHomeSection(s.id, {'is_active': v}))) _load();
                                    },
                                  ),
                                  ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded, color: WColors.inkFaint))),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                    ]),
    );
  }
}

class _SectionEditor extends StatefulWidget {
  const _SectionEditor({required this.section});
  final HomeSection section;
  @override
  State<_SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<_SectionEditor> {
  late final _title = TextEditingController(text: widget.section.title);
  late bool _active = widget.section.isActive;
  late List<HomeItem> _items = widget.section.items;
  bool _saving = false;

  HomeSection get s => widget.section;

  Future<void> _reloadItems() async {
    final all = await adminApi.homeSections();
    final me = all.where((x) => x.id == s.id).firstOrNull;
    if (me != null && mounted) setState(() => _items = me.items);
  }

  Future<void> _editItem([HomeItem? it]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _ItemForm(sectionId: s.id, item: it, nextSort: _items.length + 1)));
    if (ok == true) await _reloadItems();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(s.type.label),
          actions: [
            IconButton(
              tooltip: 'حذف القسم',
              icon: const Icon(Icons.delete_outline_rounded, color: WColors.danger),
              onPressed: () async {
                if (await confirmDialog(context, title: 'حذف القسم؟', message: s.type.hasItems ? 'تنحذف عناصره وياه.' : null, confirm: 'حذف', danger: true) && context.mounted) {
                  if (await runAction(context, () => adminApi.deleteHomeSection(s.id)) && context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          TextField(controller: _title, maxLength: 40, decoration: InputDecoration(labelText: 'عنوان القسم (اختياري)', hintText: s.type.hasItems ? 'بدون عنوان يظهر المحتوى فقط' : 'فارغ = العنوان الافتراضي', counterText: '')),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('ظاهر للزبائن')),
          WButton('حفظ', kind: WButtonKind.dark, loading: _saving, onPressed: () async {
            setState(() => _saving = true);
            await runAction(context, () => adminApi.saveHomeSection(s.id, {'title': _title.text.trim(), 'is_active': _active}), success: 'انحفظ');
            if (mounted) setState(() => _saving = false);
          }),
          if (s.type.hasItems) ...[
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: Text('العناصر', style: WText.h3)),
              WButton('إضافة', icon: Icons.add_rounded, kind: WButtonKind.secondary, expand: false, compact: true, onPressed: _editItem),
            ]),
            if (s.type == HomeSectionType.banner) Padding(padding: const EdgeInsets.only(top: 4), child: Text('البانر المفرد يعرض أول عنصر مفعّل فقط.', style: WText.small)),
            const SizedBox(height: 10),
            if (_items.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('ضيف عنصر واحد على الأقل حتى يظهر القسم.', style: WText.small, textAlign: TextAlign.center))
            else
              for (final it in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: WCard(
                    onTap: () => _editItem(it),
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      WImage(it.imageUrl, width: 56, height: 56, fallbackIcon: Icons.image_outlined, fallbackColor: _toneColor(it.tone)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.title.isEmpty ? '(بدون عنوان)' : it.title, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(it.link.isEmpty ? 'بدون وجهة' : it.link, style: WText.caption, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                        ]),
                      ),
                      if (!it.isActive) const StatusPill('موقوف'),
                    ]),
                  ),
                ),
          ],
        ]),
      );
}

Color _toneColor(HomeTone t) => switch (t) { HomeTone.lime => WColors.lime, HomeTone.ink => WColors.night, HomeTone.blue => WColors.blue, HomeTone.plain => WColors.surfaceAlt };

enum _LinkKind { none, category, merchant, taxi, tuktuk, rewards, invite, search, web }

class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.sectionId, this.item, required this.nextSort});
  final String sectionId;
  final HomeItem? item;
  final int nextSort;
  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late final _title = TextEditingController(text: widget.item?.title);
  late final _subtitle = TextEditingController(text: widget.item?.subtitle);
  late final _badge = TextEditingController(text: widget.item?.badge);
  late final _sort = TextEditingController(text: '${widget.item?.sort ?? widget.nextSort}');
  final _web = TextEditingController();
  late String? _image = widget.item?.imageUrl;
  late HomeTone _tone = widget.item?.tone ?? HomeTone.lime;
  late bool _active = widget.item?.isActive ?? true;
  _LinkKind _kind = _LinkKind.none;
  String? _categoryId;
  String? _merchantId;
  List<MerchantCategory> _categories = [];
  List<Merchant> _merchants = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    switch (HomeLink.parse(widget.item?.link ?? '')) {
      case HomeLinkCategory(:final categoryId):
        _kind = _LinkKind.category;
        _categoryId = categoryId;
      case HomeLinkMerchant(:final merchantId):
        _kind = _LinkKind.merchant;
        _merchantId = merchantId;
      case HomeLinkRide(:final vehicle):
        _kind = vehicle == VehicleType.tuktuk ? _LinkKind.tuktuk : _LinkKind.taxi;
      case HomeLinkRewards():
        _kind = _LinkKind.rewards;
      case HomeLinkInvite():
        _kind = _LinkKind.invite;
      case HomeLinkSearch():
        _kind = _LinkKind.search;
      case HomeLinkWeb(:final uri):
        _kind = _LinkKind.web;
        _web.text = uri.toString();
      case null:
        _kind = _LinkKind.none;
    }
    adminApi.allCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
    adminApi.merchants(status: 'approved').then((m) {
      if (mounted) setState(() => _merchants = m);
    }).catchError((_) {});
  }

  /// يرجّع الرابط، أو null إذا الاختيار ناقص
  String? _link() => switch (_kind) {
        _LinkKind.none => '',
        _LinkKind.category => _categoryId == null ? null : 'wasel://category/$_categoryId',
        _LinkKind.merchant => _merchantId == null ? null : 'wasel://merchant/$_merchantId',
        _LinkKind.taxi => 'wasel://ride/taxi',
        _LinkKind.tuktuk => 'wasel://ride/tuktuk',
        _LinkKind.rewards => 'wasel://rewards',
        _LinkKind.invite => 'wasel://invite',
        _LinkKind.search => 'wasel://search',
        _LinkKind.web => RegExp(r'^https://\S+\.\S+').hasMatch(_web.text.trim()) ? _web.text.trim() : null,
      };

  static const _kindLabels = {
    _LinkKind.none: 'بدون (للعرض فقط)',
    _LinkKind.category: 'قسم',
    _LinkKind.merchant: 'محل معيّن',
    _LinkKind.taxi: 'طلب تكسي',
    _LinkKind.tuktuk: 'طلب تكتك',
    _LinkKind.rewards: 'الرصيد والنقاط',
    _LinkKind.invite: 'دعوة صديق',
    _LinkKind.search: 'البحث',
    _LinkKind.web: 'رابط ويب',
  };

  Future<void> _save() async {
    final link = _link();
    if (link == null) {
      return showError(context, switch (_kind) { _LinkKind.category => 'اختار القسم.', _LinkKind.merchant => 'اختار المحل.', _ => 'اكتب رابط يبدأ بـ https://' });
    }
    if (_title.text.trim().isEmpty && _image == null) return showError(context, 'ضيف عنوان أو صورة.');
    final ok = await runAction(
        context,
        () => adminApi.saveHomeItem(widget.item?.id, {
              'section_id': widget.sectionId,
              'title': _title.text.trim(),
              'subtitle': _subtitle.text.trim(),
              'badge': _badge.text.trim(),
              'image_url': _image,
              'tone': _tone.name,
              'link': link,
              'sort': int.tryParse(_sort.text) ?? widget.nextSort,
              'is_active': _active,
            }),
        success: 'انحفظ');
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.item == null ? 'عنصر جديد' : 'تعديل العنصر'),
          actions: [
            if (widget.item != null)
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline_rounded, color: WColors.danger),
                onPressed: () async {
                  if (await confirmDialog(context, title: 'حذف العنصر؟', confirm: 'حذف', danger: true) && context.mounted) {
                    if (await runAction(context, () => adminApi.deleteHomeItem(widget.item!.id)) && context.mounted) Navigator.pop(context, true);
                  }
                },
              ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          InkWell(
            borderRadius: WRadius.all(WRadius.lg),
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
            child: WImage(_image, height: 150, radius: WRadius.lg, fallbackIcon: Icons.add_photo_alternate_outlined, fallbackColor: _toneColor(_tone)),
          ),
          if (_busy) const LinearProgressIndicator(),
          Row(children: [
            Expanded(child: Text(_image == null ? 'الصورة اختيارية. بدونها تنعرض البطاقة بلون الهوية.' : 'الصورة تغطي البطاقة والنص فوقها.', style: WText.caption)),
            if (_image != null) TextButton(onPressed: () => setState(() => _image = null), child: const Text('إزالة الصورة')),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _title, maxLength: 40, decoration: const InputDecoration(labelText: 'العنوان', counterText: '')),
          const SizedBox(height: 10),
          TextField(controller: _subtitle, maxLength: 80, decoration: const InputDecoration(labelText: 'نص فرعي (اختياري)', counterText: '')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _badge, maxLength: 16, decoration: const InputDecoration(labelText: 'شارة (اختياري)', hintText: 'جديد', counterText: ''))),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: TextField(controller: _sort, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'الترتيب')),
            ),
          ]),
          const SizedBox(height: 14),
          Text('اللون (بدون صورة)', style: WText.caption),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final (t, label) in const [(HomeTone.lime, 'ليموني'), (HomeTone.ink, 'داكن'), (HomeTone.blue, 'أزرق'), (HomeTone.plain, 'فاتح')])
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: _toneColor(t), radius: 8),
                label: Text(label),
                selected: _tone == t,
                onSelected: (_) => setState(() => _tone = t),
              ),
          ]),
          const SizedBox(height: 14),
          DropdownButtonFormField<_LinkKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'عند الضغط يفتح'),
            items: [for (final k in _LinkKind.values) DropdownMenuItem(value: k, child: Text(_kindLabels[k]!))],
            onChanged: (v) => setState(() => _kind = v ?? _LinkKind.none),
          ),
          if (_kind == _LinkKind.category) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _categories.any((c) => c.id == _categoryId) ? _categoryId : null,
              decoration: const InputDecoration(labelText: 'القسم'),
              items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ],
          if (_kind == _LinkKind.merchant) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _merchants.any((m) => m.id == _merchantId) ? _merchantId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'المحل'),
              items: [for (final m in _merchants) DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _merchantId = v),
            ),
          ],
          if (_kind == _LinkKind.web) ...[
            const SizedBox(height: 10),
            TextField(controller: _web, textDirection: TextDirection.ltr, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'الرابط', hintText: 'https://')),
          ],
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('مفعّل')),
          const SizedBox(height: 10),
          WButton('حفظ', onPressed: _busy ? null : _save),
        ]),
      );
}

// =====================================================================
// أكواد الخصم
// =====================================================================
class PromoCodesScreen extends StatefulWidget {
  const PromoCodesScreen({super.key});
  @override
  State<PromoCodesScreen> createState() => _PromoCodesScreenState();
}

class _PromoCodesScreenState extends State<PromoCodesScreen> {
  int _key = 0;

  Future<void> _edit([PromoCode? p]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _PromoCodeForm(promo: p)));
    if (ok == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('أكواد الخصم')),
        floatingActionButton: FloatingActionButton(backgroundColor: WColors.night, foregroundColor: WColors.white, tooltip: 'كود جديد', onPressed: _edit, child: const Icon(Icons.add_rounded)),
        body: AsyncView<List<PromoCode>>(
          key: ValueKey(_key),
          load: adminApi.promoCodes,
          loading: const SkeletonList(itemHeight: 64),
          builder: (context, list, _) => list.isEmpty
              ? const EmptyView(icon: Icons.confirmation_number_outlined, title: 'ما اكو أكواد خصم', message: 'واصل هي اللي تتحمل الخصم: ينحسب للمحل وينطرح من عمولته.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final (label, tone) = !p.isActive
                        ? ('موقوف', PillTone.neutral)
                        : p.isExpired
                            ? ('منتهي', PillTone.neutral)
                            : p.isExhausted
                                ? ('خلص', PillTone.warning)
                                : p.startsAt.isAfter(DateTime.now())
                                    ? ('مجدول', PillTone.info)
                                    : ('شغّال', PillTone.success);
                    return WCard(
                      onTap: () => _edit(p),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.code, style: WText.number.copyWith(fontSize: 16, letterSpacing: 1), textDirection: TextDirection.ltr),
                            Text(
                              '${p.isPercent ? '${p.value}%${p.maxDiscount != null ? ' لحد ${iqd(p.maxDiscount!)}' : ''}' : iqd(p.value)}'
                              ' · استُخدم ${p.usedCount}${p.usageLimit != null ? ' من ${p.usageLimit}' : ''}',
                              style: WText.caption,
                            ),
                          ]),
                        ),
                        StatusPill(label, tone: tone),
                      ]),
                    );
                  },
                ),
        ),
      );
}

class _PromoCodeForm extends StatefulWidget {
  const _PromoCodeForm({this.promo});
  final PromoCode? promo;
  @override
  State<_PromoCodeForm> createState() => _PromoCodeFormState();
}

class _PromoCodeFormState extends State<_PromoCodeForm> {
  PromoCode? get p => widget.promo;
  late final _code = TextEditingController(text: p?.code);
  late final _desc = TextEditingController(text: p?.description);
  late final _value = TextEditingController(text: p == null ? '' : '${p!.value}');
  late final _max = TextEditingController(text: p?.maxDiscount?.toString() ?? '');
  late final _min = TextEditingController(text: p == null || p!.minSubtotal == 0 ? '' : '${p!.minSubtotal}');
  late final _limit = TextEditingController(text: p?.usageLimit?.toString() ?? '');
  late final _perUser = TextEditingController(text: '${p?.perUserLimit ?? 1}');
  late bool _percent = p?.isPercent ?? true;
  late bool _firstOnly = p?.firstOrderOnly ?? false;
  late bool _active = p?.isActive ?? true;
  late String? _merchant = p?.merchantId;
  late DateTime? _end = p?.endsAt;
  List<Merchant> _merchants = [];

  @override
  void initState() {
    super.initState();
    adminApi.merchants(status: 'approved').then((m) {
      if (mounted) setState(() => _merchants = m);
    }).catchError((_) {});
  }

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase();
    final value = int.tryParse(_value.text) ?? 0;
    if (!RegExp(r'^[A-Z0-9]{3,24}$').hasMatch(code)) return showError(context, 'الكود حروف إنگليزية وأرقام فقط، من 3 إلى 24.');
    if (value <= 0 || (_percent && value > 100)) return showError(context, _percent ? 'النسبة من 1 إلى 100.' : 'اكتب مبلغ الخصم.');
    if (_end != null && !_end!.isAfter(DateTime.now()) && p == null) return showError(context, 'تاريخ الانتهاء لازم يكون قادم.');
    final ok = await runAction(
        context,
        () => adminApi.savePromoCode(p?.id, {
              'code': code,
              'description': _desc.text.trim(),
              'kind': _percent ? 'percent' : 'fixed',
              'value': value,
              'max_discount': _percent ? int.tryParse(_max.text) : null,
              'min_subtotal': int.tryParse(_min.text) ?? 0,
              'merchant_id': _merchant,
              'usage_limit': int.tryParse(_limit.text),
              'per_user_limit': (int.tryParse(_perUser.text) ?? 1).clamp(1, 1000),
              'first_order_only': _firstOnly,
              'ends_at': _end?.toUtc().toIso8601String(),
              'is_active': _active,
            }),
        success: 'انحفظ الكود');
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _num(TextEditingController c, String label, {String? suffix, String? hint}) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, suffixText: suffix, hintText: hint),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(p == null ? 'كود جديد' : 'تعديل الكود'),
          actions: [
            if (p != null)
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline_rounded, color: WColors.danger),
                onPressed: () async {
                  if (await confirmDialog(context, title: 'حذف الكود؟', message: p!.usedCount > 0 ? 'استُخدم ${p!.usedCount} مرة. الطلبات السابقة تبقى بخصمها.' : null, confirm: 'حذف', danger: true) && context.mounted) {
                    if (await runAction(context, () => adminApi.deletePromoCode(p!.id)) && context.mounted) Navigator.pop(context, true);
                  }
                },
              ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          TextField(
            controller: _code,
            textDirection: TextDirection.ltr,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            maxLength: 24,
            decoration: const InputDecoration(labelText: 'الكود', hintText: 'WASEL20', counterText: ''),
          ),
          const SizedBox(height: 10),
          TextField(controller: _desc, maxLength: 120, decoration: const InputDecoration(labelText: 'ملاحظة داخلية (اختياري)', counterText: '')),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: true, label: Text('نسبة %')), ButtonSegment(value: false, label: Text('مبلغ ثابت'))],
            selected: {_percent},
            onSelectionChanged: (v) => setState(() => _percent = v.first),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _num(_value, _percent ? 'النسبة' : 'مبلغ الخصم', suffix: _percent ? '%' : 'د.ع')),
            if (_percent) ...[const SizedBox(width: 10), Expanded(child: _num(_max, 'سقف الخصم', suffix: 'د.ع', hint: 'بدون سقف'))],
          ]),
          const SizedBox(height: 4),
          Text('الخصم على مبلغ المنتجات فقط ويتقرّب نزولاً لأقرب 250 د.ع. أجرة التوصيل ما تتأثر.', style: WText.caption),
          const SizedBox(height: 10),
          _num(_min, 'أقل مبلغ منتجات للطلب', suffix: 'د.ع', hint: 'بدون حد'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _num(_limit, 'مجموع الاستخدامات', hint: 'بدون حد')),
            const SizedBox(width: 10),
            Expanded(child: _num(_perUser, 'لكل زبون')),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _merchants.any((m) => m.id == _merchant) ? _merchant : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ينطبق على'),
            items: [const DropdownMenuItem(value: null, child: Text('كل المحلات')), for (final m in _merchants) DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _merchant = v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: WButton(_end == null ? 'بدون تاريخ انتهاء' : 'ينتهي ${dateAr(_end!)}', kind: WButtonKind.secondary, icon: Icons.event_outlined, onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _end ?? DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 730)));
                if (d != null) setState(() => _end = DateTime(d.year, d.month, d.day, 23, 59));
              }),
            ),
            if (_end != null) IconButton(tooltip: 'إزالة التاريخ', onPressed: () => setState(() => _end = null), icon: const Icon(Icons.close_rounded)),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _firstOnly, onChanged: (v) => setState(() => _firstOnly = v), title: const Text('لأول طلب فقط'), subtitle: const Text('للزبائن اللي ما عندهم طلبات سابقة')),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('مفعّل')),
          const SizedBox(height: 10),
          WButton('حفظ', onPressed: _save),
        ]),
      );
}

// =====================================================================
// المكافآت: النقاط، الرصيد، الدعوات
// =====================================================================
class RewardsSettingsScreen extends StatefulWidget {
  const RewardsSettingsScreen({super.key});
  @override
  State<RewardsSettingsScreen> createState() => _RewardsSettingsScreenState();
}

class _RewardsSettingsScreenState extends State<RewardsSettingsScreen> {
  Map<String, dynamic>? _cfg;
  Map<String, dynamic>? _stats;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([catalogApi.settings(), adminApi.growthStats()]);
      if (!mounted) return;
      setState(() {
        _cfg = Map<String, dynamic>.from((r[0]['rewards'] as Map?) ?? const {});
        _stats = r[1];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  int _v(String k) => ((_cfg![k] ?? 0) as num).toInt();

  Widget _field(String k, String label, String suffix) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          initialValue: '${_v(k)}',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
          onChanged: (v) => _cfg![k] = int.tryParse(v) ?? 0,
        ),
      );

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [Expanded(child: Text(label, style: WText.body.copyWith(color: WColors.inkMuted))), Text(value, style: WText.price)]),
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('المكافآت')), body: ErrorView(error: _error!, onRetry: _load));
    if (_cfg == null) return Scaffold(appBar: AppBar(title: const Text('المكافآت')), body: const LoadingView());
    final s = _stats!;
    int n(String k) => ((s[k] ?? 0) as num).toInt();
    return Scaffold(
      appBar: AppBar(title: const Text('المكافآت')),
      body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
        WCard(
          color: WColors.night,
          borderColor: WColors.night,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('التزامات واصل', style: WText.overline.copyWith(color: WColors.inkFaint)),
            const SizedBox(height: 4),
            Text(iqd(n('wallet_outstanding')), style: WText.number.copyWith(fontSize: 28, color: WColors.lime)),
            Text('رصيد بمحافظ الزبائن ما انصرف بعد · ${n('points_outstanding')} نقطة غير محوّلة', style: WText.small.copyWith(color: WColors.white.withValues(alpha: 0.75))),
          ]),
        ),
        const SizedBox(height: 12),
        WCard(
          child: Column(children: [
            _stat('خصومات الأكواد (طلبات مسلّمة)', iqd(n('promo_discounts'))),
            _stat('مدفوع من المحافظ', iqd(n('wallet_spent'))),
            _stat('محسوب للمحلات على واصل', iqd(n('merchant_credit'))),
            _stat('دعوات مسجّلة / مكتملة', '${n('referrals')} / ${n('referrals_rewarded')}'),
          ]),
        ),
        const SizedBox(height: 12),
        WCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('الإعدادات', style: WText.h3),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تفعيل المكافآت'),
              subtitle: const Text('عند الإيقاف: ما تنمنح نقاط ولا ينصرف رصيد، والأرصدة تبقى محفوظة'),
              value: _cfg!['enabled'] == true,
              onChanged: (v) => setState(() => _cfg!['enabled'] = v),
            ),
            _field('points_per_1000', 'نقاط لكل 1,000 د.ع', 'نقطة'),
            _field('points_max_order', 'سقف النقاط للطلب الواحد (0 = بدون)', 'نقطة'),
            _field('points_max_ride', 'سقف النقاط للرحلة الوحدة (0 = بدون)', 'نقطة'),
            _field('redeem_points', 'عدد النقاط للتحويل', 'نقطة'),
            _field('redeem_value', 'تتحول إلى', 'د.ع'),
            _field('wallet_max_percent', 'أقصى تغطية من الرصيد لقيمة المنتجات', '%'),
            _field('referral_inviter', 'مكافأة صاحب الدعوة', 'د.ع'),
            _field('referral_invitee', 'هدية الزبون الجديد', 'د.ع'),
            const SizedBox(height: 8),
            Text('واصل هي اللي تتحمل كلفة الرصيد والخصومات: المبلغ ينحسب للمحل وينطرح من عمولته المستحقة. السقف يحد من تجميع النقاط بطلبات أو رحلات وهمية، لأن الدفع نقدي وما يمر بالمنصة.', style: WText.caption),
            const SizedBox(height: 12),
            WButton('حفظ', kind: WButtonKind.dark, loading: _saving, onPressed: () async {
              if (_v('wallet_max_percent') > 100) return showError(context, 'نسبة التغطية أقصاها 100.');
              setState(() => _saving = true);
              await runAction(context, () => adminApi.saveSetting('rewards', _cfg!), success: 'انحفظ');
              if (mounted) setState(() => _saving = false);
            }),
          ]),
        ),
      ]),
    );
  }
}

/// ورقة سفلية: رصيد محفظة زبون مع إضافة أو خصم
Future<void> showWalletSheet(BuildContext context, AppUser u) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => _WalletSheet(user: u),
    );

class _WalletSheet extends StatefulWidget {
  const _WalletSheet({required this.user});
  final AppUser user;
  @override
  State<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<_WalletSheet> {
  int? _balance;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    adminApi.walletBalance(widget.user.id).then((b) {
      if (mounted) setState(() => _balance = b);
    }).catchError((_) {});
  }

  Future<void> _apply(int sign) async {
    final amount = int.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return showError(context, 'اكتب مبلغ صحيح.');
    setState(() => _busy = true);
    try {
      final b = await adminApi.walletAdjust(widget.user.id, sign * amount, _note.text.trim());
      if (!mounted) return;
      setState(() => _balance = b);
      _amount.clear();
      showSuccess(context, sign > 0 ? 'انضاف الرصيد' : 'انخصم الرصيد');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('محفظة ${widget.user.fullName.isEmpty ? 'الزبون' : widget.user.fullName}', style: WText.h2),
            const SizedBox(height: 4),
            Text(_balance == null ? 'نحمّل الرصيد…' : 'الرصيد الحالي ${iqd(_balance!)}', style: WText.body.copyWith(color: WColors.inkMuted)),
            const SizedBox(height: 14),
            TextField(controller: _amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'د.ع')),
            const SizedBox(height: 10),
            TextField(controller: _note, maxLength: 120, decoration: const InputDecoration(labelText: 'السبب (يظهر للزبون)', hintText: 'تعويض عن طلب متأخر', counterText: '')),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: WButton('خصم', kind: WButtonKind.secondary, icon: Icons.remove_rounded, onPressed: _busy ? null : () => _apply(-1))),
              const SizedBox(width: 10),
              Expanded(child: WButton('إضافة', icon: Icons.add_rounded, loading: _busy, onPressed: () => _apply(1))),
            ]),
          ]),
        ),
      );
}
