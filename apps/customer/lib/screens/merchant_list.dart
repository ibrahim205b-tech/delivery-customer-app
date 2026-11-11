import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../widgets.dart';
import 'home.dart';

enum _Sort { nearest, popular, rating, fee }

class MerchantListScreen extends StatefulWidget {
  const MerchantListScreen({super.key, required this.category});
  final MerchantCategory category;
  @override
  State<MerchantListScreen> createState() => _MerchantListScreenState();
}

class _MerchantListScreenState extends State<MerchantListScreen> {
  _Sort _sort = _Sort.nearest;
  bool _openOnly = false;

  List<Merchant> _apply(List<Merchant> list) {
    var r = list.where((m) => !_openOnly || m.isOpenNow).toList();
    final ref = app.referencePoint;
    switch (_sort) {
      case _Sort.nearest:
        if (ref != null) {
          r.sort((a, b) => distanceKm(ref.latitude, ref.longitude, a.lat, a.lng).compareTo(distanceKm(ref.latitude, ref.longitude, b.lat, b.lng)));
        }
      case _Sort.popular:
        r.sort((a, b) => b.orderCount.compareTo(a.orderCount));
      case _Sort.rating:
        r.sort((a, b) => b.ratingAvg.compareTo(a.ratingAvg));
      case _Sort.fee:
        r.sort((a, b) => a.deliveryFee.compareTo(b.deliveryFee));
    }
    // المفتوح أولاً دائماً
    r.sort((a, b) => (b.isOpenNow ? 1 : 0) - (a.isOpenNow ? 1 : 0));
    return r;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.category.name)),
        bottomNavigationBar: const CartBar(),
        body: AsyncView<List<Merchant>>(
          load: () => catalogApi.merchants(categoryId: widget.category.id, areaId: app.selectedAreaId),
          loading: const SkeletonList(),
          builder: (context, all, reload) {
            final list = _apply(all);
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(children: [
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
                    children: [
                      FilterChip(label: const Text('المفتوح هسه'), selected: _openOnly, onSelected: (v) => setState(() => _openOnly = v)),
                      const SizedBox(width: 8),
                      for (final s in _Sort.values)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(switch (s) { _Sort.nearest => 'الأقرب', _Sort.popular => 'الأكثر طلباً', _Sort.rating => 'الأعلى تقييماً', _Sort.fee => 'أقل توصيل' }),
                            selected: _sort == s,
                            onSelected: (_) => setState(() => _sort = s),
                          ),
                        ),
                    ],
                  ),
                ),
                if (list.isEmpty)
                  EmptyView(
                    icon: categoryIcon(widget.category.icon),
                    title: all.isEmpty ? 'ما اكو محلات بهذا القسم بعد' : 'ما اكو محلات مفتوحة هسه',
                    message: all.isEmpty ? 'راح تظهر هنا أول ما تعتمدها الإدارة.' : 'جرّب بعد شوية أو شيل فلتر "المفتوح هسه".',
                  ),
                for (final m in list) MerchantRow(m, onTap: () => openMerchant(context, m)),
                const SizedBox(height: 24),
              ]),
            );
          },
        ),
      );
}
