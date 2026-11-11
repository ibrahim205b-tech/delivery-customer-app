import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../widgets.dart';
import 'home.dart';

/// البحث الشامل: محلات + منتجات
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Timer? _debounce;
  String _q = '';
  Future<({List<Merchant> merchants, List<(Product, Merchant)> products})>? _results;

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() {
        _q = v.trim();
        _results = _q.length < 2 ? null : catalogApi.search(_q);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: TextField(
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(hintText: 'شتريد؟ مثلاً: بيتزا، صمون، شاحنة…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
        ),
        bottomNavigationBar: const CartBar(),
        body: _results == null
            ? EmptyView(icon: Icons.manage_search_rounded, title: 'ابحث بكل واصل', message: _q.isEmpty ? 'اكتب اسم محل أو منتج' : 'اكتب حرفين على الأقل')
            : FutureBuilder(
                future: _results,
                builder: (context, s) {
                  if (s.hasError) return ErrorView(error: s.error!, onRetry: () => setState(() => _results = catalogApi.search(_q)));
                  if (!s.hasData) return const SkeletonList();
                  final r = s.data!;
                  if (r.merchants.isEmpty && r.products.isEmpty) {
                    return EmptyView(icon: Icons.search_off_rounded, title: 'ما لگينا "$_q"', message: 'جرّب كلمة ثانية أو استخدم "الدلفري والمندوب" نجيبه إلك.');
                  }
                  return ListView(children: [
                    if (r.merchants.isNotEmpty) ...[
                      const SectionTitle('المحلات'),
                      for (final m in r.merchants) MerchantRow(m, onTap: () => openMerchant(context, m)),
                    ],
                    if (r.products.isNotEmpty) ...[
                      const SectionTitle('المنتجات'),
                      for (final (p, m) in r.products)
                        ListTile(
                          leading: WImage(p.imageUrl, width: 52, height: 52, fallbackIcon: categoryIcon(m.categoryId)),
                          title: Text(p.name),
                          subtitle: Text('${m.name} · ${iqd(p.price)}'),
                          trailing: const Icon(Icons.chevron_left_rounded),
                          onTap: () => openMerchant(context, m),
                        ),
                    ],
                    const SizedBox(height: 24),
                  ]);
                },
              ),
      );
}
