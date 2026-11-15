import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import 'errand.dart';
import 'home.dart';

/// بوابة «اكتشف خدمات واصل»: كل الخدمات الإضافية منظمة بتصنيفات، مع بحث موحد.
/// تعرض الخدمات المفعّلة من الإدارة فقط، فلا يظهر للزبون أي خدمة بلا تنفيذ.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late Future<({List<ServiceGroup> groups, List<ServiceItem> services})> _catalog = catalogApi.servicesCatalog();
  final _q = TextEditingController();
  Timer? _debounce;
  Future<SearchResult>? _search;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _search = v.trim().length < 2 ? null : catalogApi.searchServices(v.trim()));
    });
  }

  /// كل خدمة مفعّلة لها مسار واحد واضح في التطبيق
  void _open(ServiceItem s) {
    final Widget? page = switch (s.id) {
      'parcel_delivery' => const ErrandRequestScreen(kind: TaskKind.parcel),
      'courier_errand' => const ErrandRequestScreen(kind: TaskKind.courier),
      'stores' => const ShopsHubScreen(),
      'restaurants' || 'home_services' => null,
      _ => null,
    };
    if (page != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      return;
    }
    final catId = s.id == 'restaurants' || s.id == 'home_services' ? s.id : null;
    final cat = catId == null ? null : app.categories.where((c) => c.id == catId).firstOrNull;
    if (cat != null) {
      openCategory(context, cat);
      return;
    }
    showInfo(context, '${s.name}: قريباً');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('اكتشف خدمات واصل')),
        body: RefreshIndicator(
          onRefresh: () async => setState(() => _catalog = catalogApi.servicesCatalog()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32),
            children: [
              TextField(
                controller: _q,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: 'ابحث عن خدمة أو محل أو مقدم خدمة', prefixIcon: Icon(Icons.search_rounded)),
              ),
              const SizedBox(height: 14),
              if (_search != null) _SearchResults(future: _search!, onOpenService: _openByMap) else _Catalog(future: _catalog, onOpen: _open),
            ],
          ),
        ),
      );

  void _openByMap(Map<String, dynamic> s) {
    final id = s['id'] as String;
    _open(ServiceItem(id: id, groupId: '', name: s['name'] as String? ?? '', description: '', engine: s['engine'] as String? ?? 'none', isActive: true, sortOrder: 0));
  }
}

class _Catalog extends StatelessWidget {
  const _Catalog({required this.future, required this.onOpen});
  final Future<({List<ServiceGroup> groups, List<ServiceItem> services})> future;
  final void Function(ServiceItem) onOpen;

  @override
  Widget build(BuildContext context) => FutureBuilder<({List<ServiceGroup> groups, List<ServiceItem> services})>(
        future: future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!);
          if (!snap.hasData) return const SkeletonList(count: 4);
          final c = snap.data!;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final g in c.groups) ...[
              Builder(builder: (_) {
                final active = c.services.where((s) => s.groupId == g.id && s.isActive).toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.name, style: WText.h3),
                    const SizedBox(height: 8),
                    if (active.isEmpty)
                      Text('قريباً', style: WText.small.copyWith(color: WColors.inkFaint))
                    else
                      for (final s in active)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: WCard(
                            padding: const EdgeInsets.all(14),
                            onTap: () => onOpen(s),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.name, style: WText.bodyStrong),
                                  if (s.description.isNotEmpty) Text(s.description, style: WText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
                                ]),
                              ),
                              const Icon(Icons.chevron_left_rounded),
                            ]),
                          ),
                        ),
                  ]),
                );
              }),
            ],
          ]);
        },
      );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.future, required this.onOpenService});
  final Future<SearchResult> future;
  final void Function(Map<String, dynamic>) onOpenService;

  @override
  Widget build(BuildContext context) => FutureBuilder<SearchResult>(
        future: future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!);
          if (!snap.hasData) return const SkeletonList(count: 3);
          final r = snap.data!;
          if (r.isEmpty) return const EmptyView(icon: Icons.search_off_rounded, title: 'ما لقينا نتيجة', message: 'جرّب كلمة ثانية.');
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (r.services.isNotEmpty) ...[
              Text('الخدمات', style: WText.h3),
              const SizedBox(height: 8),
              for (final s in r.services)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () => onOpenService(s),
                    child: Text(s['name'] as String? ?? '', style: WText.bodyStrong),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            if (r.merchants.isNotEmpty) ...[
              Text('المحلات ومقدمو الخدمات', style: WText.h3),
              const SizedBox(height: 8),
              for (final m in r.merchants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () => showInfo(context, 'افتح القسم من الرئيسية'),
                    child: Text(m['name'] as String? ?? '', style: WText.bodyStrong),
                  ),
                ),
            ],
          ]);
        },
      );
}

/// بطاقة مدخل من الرئيسية
class DiscoverEntry extends StatelessWidget {
  const DiscoverEntry({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.page, 14, WSpace.page, 0),
        child: WCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen())),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('اكتشف خدمات واصل', style: WText.h3),
                const SizedBox(height: 2),
                Text('حجوزات، وظائف، نقل، مشتريات، صيانة، معاملات، وأكثر', style: WText.small),
              ]),
            ),
            const Icon(Icons.explore_outlined),
          ]),
        ),
      );
}
