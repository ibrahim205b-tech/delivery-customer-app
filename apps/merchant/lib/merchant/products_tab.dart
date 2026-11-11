import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

/// إدارة المنتجات: بسيطة جداً لصاحب المحل
class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key, required this.merchant});
  final Merchant merchant;
  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  late Future<(List<ProductCategory>, List<Product>)> _data = _load();
  String _q = '';

  Future<(List<ProductCategory>, List<Product>)> _load() async {
    final r = await Future.wait([catalogApi.productCategories(widget.merchant.id), catalogApi.products(widget.merchant.id)]);
    return (r[0] as List<ProductCategory>, r[1] as List<Product>);
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _data = f);
    await f.then((_) {}, onError: (_) {});
  }

  Future<void> _openForm(List<ProductCategory> cats, [Product? p]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProductFormScreen(merchant: widget.merchant, categories: cats, product: p)));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _data,
        builder: (context, s) {
          if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
          if (!s.hasData) return const SkeletonList();
          final (cats, products) = s.data!;
          final filtered = products.where((p) => _q.isEmpty || p.name.contains(_q)).toList();
          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              backgroundColor: WColors.coral,
              foregroundColor: WColors.white,
              onPressed: () => _openForm(cats),
              icon: const Icon(Icons.add_rounded),
              label: const Text('منتج جديد'),
            ),
            body: RefreshIndicator(
              onRefresh: _reload,
              child: ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 100), children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v.trim()),
                      decoration: const InputDecoration(hintText: 'ابحث بمنتجاتك', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  WIconButton(Icons.category_outlined, tooltip: 'الأقسام', onPressed: () => _manageCategories(cats)),
                ]),
                const SizedBox(height: 12),
                if (products.isEmpty)
                  EmptyView(
                    icon: Icons.add_business_outlined,
                    title: 'ضيف أول منتج',
                    message: 'اكتب الاسم والسعر وصوّره بموبايلك. يظهر للزبائن فوراً.',
                    action: WButton('إضافة منتج', onPressed: () => _openForm(cats), expand: false, icon: Icons.add_rounded),
                  ),
                for (final p in filtered) ...[
                  _ProductRow(product: p, category: cats.where((c) => c.id == p.categoryId).firstOrNull, onEdit: () => _openForm(cats, p), onChanged: _reload),
                  const SizedBox(height: 10),
                ],
              ]),
            ),
          );
        },
      );

  Future<void> _manageCategories(List<ProductCategory> cats) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('أقسام المنيو', style: WText.h2),
              Text('مثل: مشويات، مقبلات، مشروبات', style: WText.small),
              const SizedBox(height: 8),
              for (final x in cats)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(x.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: WColors.danger),
                    onPressed: () async {
                      if (await runAction(c, () => merchantApi.deleteCategory(x.id))) set(() => cats.remove(x));
                    },
                  ),
                ),
              const SizedBox(height: 8),
              WButton('إضافة قسم', kind: WButtonKind.secondary, icon: Icons.add_rounded, onPressed: () async {
                final n = await promptText(c, title: 'اسم القسم');
                if (n == null || !c.mounted) return;
                await runAction(c, () async {
                  final created = await merchantApi.addCategory(widget.merchant.id, n);
                  set(() => cats.add(created));
                });
              }),
            ]),
          ),
        ),
      ),
    );
    _reload();
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.category, required this.onEdit, required this.onChanged});
  final Product product;
  final ProductCategory? category;
  final VoidCallback onEdit;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return WCard(
      onTap: onEdit,
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        WImage(p.imageUrl, width: 64, height: 64, fallbackIcon: Icons.photo_camera_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text([iqd(p.price), if (category != null) category!.name, if (p.stock != null) 'المخزون ${p.stock}'].join(' · '), style: WText.small),
          ]),
        ),
        Column(children: [
          Switch(
            value: p.isAvailable,
            onChanged: (v) async {
              if (await runAction(context, () => merchantApi.setAvailability(p.id, v), success: v ? 'المنتج متوفر' : 'المنتج مخفي مؤقتاً')) onChanged();
            },
          ),
          Text(p.isAvailable ? 'متوفر' : 'غير متوفر', style: WText.caption),
        ]),
      ]),
    );
  }
}

/// إضافة/تعديل منتج
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.merchant, required this.categories, this.product});
  final Merchant merchant;
  final List<ProductCategory> categories;
  final Product? product;
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _price = TextEditingController(text: widget.product?.price.toString());
  late final _desc = TextEditingController(text: widget.product?.description);
  late final _stock = TextEditingController(text: widget.product?.stock?.toString());
  late String? _categoryId = widget.product?.categoryId;
  late bool _available = widget.product?.isAvailable ?? true;
  late bool _trackStock = widget.product?.stock != null;
  late String? _image = widget.product?.imageUrl;
  late final List<ProductCategory> _cats = [...widget.categories];
  bool _uploading = false;
  bool _saving = false;

  Future<void> _pickPhoto() async {
    final img = await pickImage(context);
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      final url = await mediaApi.upload('merchants/${widget.merchant.id}', img.bytes, ext: img.ext);
      setState(() => _image = url);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => merchantApi.saveProduct(
        id: widget.product?.id,
        merchantId: widget.merchant.id,
        categoryId: _categoryId,
        name: _name.text,
        description: _desc.text,
        price: int.parse(_price.text.replaceAll(',', '')),
        isAvailable: _available,
        stock: _trackStock ? int.tryParse(_stock.text) ?? 0 : null,
        imageUrl: _image != widget.product?.imageUrl ? _image : null,
      ),
      success: 'انحفظ المنتج',
    );
    if (mounted) setState(() => _saving = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, title: 'حذف المنتج؟', message: 'الطلبات السابقة تبقى محفوظة.', confirm: 'حذف', danger: true)) return;
    if (!mounted) return;
    if (await runAction(context, () => merchantApi.deleteProduct(widget.product!.id), success: 'انحذف المنتج') && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.product == null ? 'منتج جديد' : 'تعديل المنتج'),
          actions: [if (widget.product != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded, color: WColors.danger))],
        ),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
            Center(
              child: InkWell(
                onTap: _uploading ? null : _pickPhoto,
                borderRadius: WRadius.all(WRadius.lg),
                child: Stack(alignment: Alignment.center, children: [
                  WImage(_image, width: 180, height: 150, radius: WRadius.lg, fallbackIcon: Icons.add_a_photo_outlined),
                  if (_uploading) const CircularProgressIndicator(),
                  if (_image == null && !_uploading)
                    Positioned(bottom: 14, child: Text('صوّر المنتج', style: WText.caption.copyWith(color: WColors.inkMuted))),
                ]),
              ),
            ),
            if (_image != null)
              Center(child: TextButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.photo_camera_outlined), label: const Text('تغيير الصورة'))),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم المنتج'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب اسم المنتج' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'السعر', suffixText: 'د.ع'),
              validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'اكتب سعر صحيح' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _cats.any((c) => c.id == _categoryId) ? _categoryId : null,
              decoration: const InputDecoration(labelText: 'القسم'),
              items: [
                const DropdownMenuItem(value: null, child: Text('بدون قسم')),
                for (final c in _cats) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('قسم جديد'),
                onPressed: () async {
                  final n = await promptText(context, title: 'اسم القسم');
                  if (n == null || !context.mounted) return;
                  await runAction(context, () async {
                    final c = await merchantApi.addCategory(widget.merchant.id, n);
                    setState(() {
                      _cats.add(c);
                      _categoryId = c.id;
                    });
                  });
                },
              ),
            ),
            TextFormField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'الوصف (اختياري)', hintText: 'المكونات، الحجم، الوزن…')),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _available, onChanged: (v) => setState(() => _available = v), title: const Text('متوفر للطلب')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _trackStock, onChanged: (v) => setState(() => _trackStock = v), title: const Text('تحديد الكمية المتوفرة'), subtitle: const Text('ينطفي المنتج تلقائياً لما تخلص')),
            if (_trackStock)
              TextFormField(
                controller: _stock,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'الكمية'),
                validator: (v) => _trackStock && int.tryParse(v ?? '') == null ? 'اكتب رقم' : null,
              ),
            const SizedBox(height: 20),
            WButton('حفظ', onPressed: _uploading ? null : _save, loading: _saving),
          ]),
        ),
      );
}
