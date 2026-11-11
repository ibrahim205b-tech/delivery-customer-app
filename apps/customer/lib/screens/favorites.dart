import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../widgets.dart';
import 'home.dart';

/// المفضلة مقسّمة حسب القسم
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  String? _cat;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المفضلة')),
        body: ListenableBuilder(
          listenable: app,
          // نعيد التحميل كل ما تتغير مجموعة المفضلة
          builder: (context, _) => AsyncView<List<Merchant>>(
            key: ValueKey(app.favorites.length),
            load: customerApi.favoriteMerchants,
            loading: const SkeletonList(),
            builder: (context, all, reload) {
              if (all.isEmpty) {
                return const EmptyView(icon: Icons.favorite_outline_rounded, title: 'ما عندك مفضلات بعد', message: 'اضغط على القلب بأي محل حتى تلقاه هنا بسرعة.');
              }
              final cats = app.categories.where((c) => all.any((m) => m.categoryId == c.id)).toList();
              final list = all.where((m) => _cat == null || m.categoryId == _cat).toList();
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView(children: [
                  if (cats.length > 1)
                    SizedBox(
                      height: 46,
                      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: WSpace.page), children: [
                        Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: const Text('الكل'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null))),
                        for (final c in cats)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: ChoiceChip(
                              avatar: Icon(categoryIcon(c.icon), size: 16),
                              label: Text(c.name),
                              selected: _cat == c.id,
                              onSelected: (_) => setState(() => _cat = c.id),
                            ),
                          ),
                      ]),
                    ),
                  for (final m in list) MerchantRow(m, onTap: () => openMerchant(context, m)),
                ]),
              );
            },
          ),
        ),
      );
}
