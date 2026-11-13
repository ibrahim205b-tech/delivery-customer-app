import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import '../widgets.dart';
import 'home.dart';
import 'rewards.dart';
import 'rides.dart';
import 'search.dart';

/// ينفّذ وجهة عنصر من الرئيسية. الروابط الفارغة أو غير المفهومة ما تسوي شي (العنصر للعرض فقط).
Future<void> openHomeLink(BuildContext context, String raw) async {
  final link = HomeLink.parse(raw);
  void push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  switch (link) {
    case null:
      return;
    case HomeLinkCategory(:final categoryId):
      final c = app.categories.where((c) => c.id == categoryId).firstOrNull;
      if (c != null) openCategory(context, c);
    case HomeLinkMerchant(:final merchantId):
      try {
        final m = await catalogApi.merchant(merchantId);
        if (m != null && context.mounted) openMerchant(context, m);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    case HomeLinkRide(:final vehicle):
      push(RideRequestScreen(vehicle: vehicle));
    case HomeLinkRewards():
      push(const RewardsScreen());
    case HomeLinkInvite():
      push(const InviteScreen());
    case HomeLinkSearch():
      push(const SearchScreen());
    case HomeLinkWeb(:final uri):
      await openWebLink(uri);
  }
}

/// ألوان البطاقة حسب النغمة: (الخلفية، النص، النص الثانوي، الإطار)
({Color bg, Color fg, Color sub, Color? border}) toneColors(HomeTone t) => switch (t) {
      HomeTone.lime => (bg: WColors.lime, fg: WColors.ink, sub: WColors.graphite, border: null),
      HomeTone.ink => (bg: WColors.night, fg: WColors.white, sub: WColors.inkFaint, border: null),
      HomeTone.blue => (bg: WColors.blue, fg: WColors.white, sub: WColors.white.withValues(alpha: 0.78), border: null),
      HomeTone.plain => (bg: WColors.surface, fg: WColors.fg, sub: WColors.inkMuted, border: WColors.line),
    };

/// بطاقة بانر: صورة تغطي البطاقة مع تدرّج تحت النص، أو لون الهوية مع علامة واصل إذا ما اكو صورة.
class HomeBannerCard extends StatelessWidget {
  const HomeBannerCard(this.item, {super.key, this.height = 148});
  final HomeItem item;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hasImage = item.imageUrl != null;
    final c = hasImage ? toneColors(HomeTone.ink) : toneColors(item.tone);
    final tappable = HomeLink.parse(item.link) != null;
    final card = Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.bg, borderRadius: WRadius.all(WRadius.lg), border: c.border == null ? null : Border.all(color: c.border!)),
      child: Stack(fit: StackFit.expand, children: [
        if (hasImage) ...[
          WImage(item.imageUrl, radius: 0, fallbackColor: WColors.night),
          // النص دائماً فوق تدرّج داكن حتى يبقى مقروء على أي صورة
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00111923), Color(0xD9111923)], stops: [0.25, 1]),
            ),
          ),
        ] else
          PositionedDirectional(
            end: -14,
            bottom: -18,
            child: Opacity(
              opacity: item.tone == HomeTone.plain ? 0.08 : 0.16,
              child: WaselMark(size: height * 0.95, route: c.fg, ring: c.fg),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            if (item.badge.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: hasImage || item.tone == HomeTone.ink || item.tone == HomeTone.blue ? WColors.lime : WColors.ink,
                  borderRadius: WRadius.all(WRadius.xs + 2),
                ),
                child: Text(item.badge,
                    style: WText.label.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: hasImage || item.tone == HomeTone.ink || item.tone == HomeTone.blue ? WColors.ink : WColors.lime)),
              ),
              const Spacer(),
            ],
            if (item.title.isNotEmpty) Text(item.title, style: WText.h2.copyWith(color: c.fg, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (item.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(item.subtitle, style: WText.small.copyWith(color: c.sub), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ]),
    );
    if (!tappable) return Semantics(label: '${item.title} ${item.subtitle}'.trim(), excludeSemantics: true, child: card);
    return Semantics(
      button: true,
      label: '${item.title} ${item.subtitle}'.trim(),
      onTap: () => openHomeLink(context, item.link),
      excludeSemantics: true,
      child: Pressable(onTap: () => openHomeLink(context, item.link), child: card),
    );
  }
}

/// سلايدر بانرات: يتقلّب تلقائياً كل 5 ثواني ويتوقف إذا المستخدم لمسه أو مفعّل "تقليل الحركة".
class HomeSlider extends StatefulWidget {
  const HomeSlider(this.items, {super.key});
  final List<HomeItem> items;
  @override
  State<HomeSlider> createState() => _HomeSliderState();
}

class _HomeSliderState extends State<HomeSlider> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;
  bool _touched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (widget.items.length < 2 || MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _touched || !_page.hasClients) return;
      _page.animateToPage((_index + 1) % widget.items.length, duration: WDurations.slow, curve: WDurations.curve);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 156,
          child: Listener(
            onPointerDown: (_) => _touched = true,
            child: PageView.builder(
              controller: _page,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
                child: HomeBannerCard(widget.items[i], height: 156),
              ),
            ),
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.items.length; i++)
              AnimatedContainer(
                duration: WDurations.base,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(color: i == _index ? WColors.fg : WColors.line, borderRadius: WRadius.all(3)),
              ),
          ]),
        ],
      ]);
}

/// صف كروت أفقي. كرت واحد يأخذ العرض كله، كرتين يتقاسمان الشاشة، وأكثر يتمرّر.
class HomeCards extends StatelessWidget {
  const HomeCards(this.items, {super.key});
  final List<HomeItem> items;

  @override
  Widget build(BuildContext context) {
    Widget card(HomeItem it, {double? width}) {
      final c = toneColors(it.tone);
      final tappable = HomeLink.parse(it.link) != null;
      final body = Container(
        width: width,
        height: 132,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.bg, borderRadius: WRadius.all(WRadius.lg), border: c.border == null ? null : Border.all(color: c.border!)),
        child: Stack(children: [
          if (it.imageUrl != null)
            PositionedDirectional(end: 0, top: 0, bottom: 0, child: WImage(it.imageUrl, width: 76, radius: 0))
          else
            PositionedDirectional(end: -10, bottom: -12, child: Opacity(opacity: it.tone == HomeTone.plain ? 0.08 : 0.16, child: WaselMark(size: 84, route: c.fg, ring: c.fg))),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(14, 14, it.imageUrl != null ? 86 : 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (it.badge.isNotEmpty)
                Text(it.badge, style: WText.overline.copyWith(color: c.sub))
              else
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: c.fg.withValues(alpha: 0.1), borderRadius: WRadius.all(9)),
                  child: Icon(Icons.arrow_back_rounded, size: 16, color: c.fg),
                ),
              const Spacer(),
              Text(it.title, style: WText.h3.copyWith(color: c.fg, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (it.subtitle.isNotEmpty) Text(it.subtitle, style: WText.caption.copyWith(color: c.sub), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
      if (!tappable) return body;
      return Semantics(
        button: true,
        label: '${it.title} ${it.subtitle}'.trim(),
        onTap: () => openHomeLink(context, it.link),
        excludeSemantics: true,
        child: Pressable(onTap: () => openHomeLink(context, it.link), child: body),
      );
    }

    if (items.length <= 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
        child: Row(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: card(items[i])),
          ],
        ]),
      );
    }
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => card(items[i], width: 172),
      ),
    );
  }
}

/// وجهات الزبون المتكررة: ضغطة وحدة تفتح طلب الرحلة والوجهة معبّأة.
class HomeDestinations extends StatelessWidget {
  const HomeDestinations(this.items, {super.key});
  final List<RideDestination> items;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 60,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: WSpace.page),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final d = items[i];
            void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => RideRequestScreen(vehicle: d.vehicle, destination: d)));
            return Semantics(
              button: true,
              label: 'رحلة إلى ${d.text}',
              onTap: open,
              excludeSemantics: true,
              child: WCard(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 14, 8),
                radius: WRadius.md,
                onTap: open,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: WColors.blueSoft, borderRadius: WRadius.all(12)),
                    child: Icon(d.vehicle == VehicleType.tuktuk ? Icons.electric_rickshaw_rounded : Icons.local_taxi_rounded, size: 20, color: WColors.link),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(d.text, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(d.count > 1 ? '${d.count} رحلات' : d.vehicle.label, style: WText.caption, maxLines: 1),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      );
}

/// بطاقة الرحلة الشغّالة بالرئيسية
class ActiveRideCard extends StatelessWidget {
  const ActiveRideCard(this.ride, {super.key, required this.onClosed});
  final Ride ride;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    final step = switch (ride.status) {
      RideStatus.requested => 0,
      RideStatus.accepted || RideStatus.arrived => 1,
      _ => 2,
    };
    Future<void> open() async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: ride.id)));
      onClosed();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(WSpace.page, 16, WSpace.page, 0),
      child: Semantics(
        button: true,
        label: 'رحلتك الحالية، ${ride.status.label}',
        onTap: open,
        excludeSemantics: true,
        child: Pressable(
          onTap: open,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: WColors.blue, borderRadius: WRadius.all(WRadius.lg)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(ride.vehicle == VehicleType.tuktuk ? Icons.electric_rickshaw_rounded : Icons.local_taxi_rounded, color: WColors.lime, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('رحلتك الحالية · ${ride.dropoffText}', style: WText.label.copyWith(color: WColors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.arrow_back_rounded, color: WColors.white, size: 20),
              ]),
              const SizedBox(height: 8),
              Text(ride.status.label, style: WText.h2.copyWith(color: WColors.white)),
              if (ride.driverName != null)
                Text('${ride.driverName}${(ride.driverVehicle ?? '').isEmpty ? '' : ' · ${ride.driverVehicle}'}', style: WText.small.copyWith(color: WColors.white.withValues(alpha: 0.8))),
              const SizedBox(height: 12),
              Row(children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: WDurations.slow,
                      height: 5,
                      decoration: BoxDecoration(color: i <= step ? WColors.lime : WColors.white.withValues(alpha: 0.22), borderRadius: WRadius.all(3)),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// شريحة الرصيد والنقاط بأعلى الرئيسية
class RewardsChip extends StatelessWidget {
  const RewardsChip(this.rewards, {super.key});
  final Rewards rewards;

  @override
  Widget build(BuildContext context) {
    void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => const RewardsScreen()));
    return Semantics(
      button: true,
      label: 'رصيدك ${iqd(rewards.wallet)} و${rewards.points} نقطة',
      onTap: open,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: WRadius.all(WRadius.md),
        onTap: open,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: WColors.inkSurface, borderRadius: WRadius.all(WRadius.md)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.stars_rounded, color: WColors.lime, size: 18),
            const SizedBox(width: 6),
            Text(rewards.wallet > 0 ? iqd(rewards.wallet) : '${rewards.points} نقطة', style: WText.number.copyWith(fontSize: 12.5, color: WColors.white)),
          ]),
        ),
      ),
    );
  }
}
