import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';

/// رصيد واصل والنقاط: الرصيد، التقدم نحو التحويل القادم، وسجل الحركات.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});
  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  late Future<Rewards> _future = _load();
  bool _redeeming = false;
  bool _showPoints = false;

  Future<Rewards> _load() async {
    final r = await customerApi.rewards();
    app.setRewards(r);
    return r;
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f.then((_) {}, onError: (_) {});
  }

  Future<void> _redeem(Rewards r) async {
    final ok = await confirmDialog(context,
        title: 'تحويل النقاط إلى رصيد؟', message: 'راح تتحول ${r.points - r.points % r.redeemPoints} نقطة إلى ${iqd(r.redeemableValue)} تستخدمها بطلباتك الجاية.', confirm: 'حوّل');
    if (!ok || !mounted) return;
    setState(() => _redeeming = true);
    try {
      final updated = await customerApi.redeemPoints();
      app.setRewards(updated);
      if (!mounted) return;
      setState(() => _future = Future.value(updated));
      showSuccess(context, 'انضاف الرصيد لمحفظتك');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('رصيدي ونقاطي')),
        body: FutureBuilder<Rewards>(
          future: _future,
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!, onRetry: _refresh);
            final r = s.data;
            if (r == null) return const SkeletonList();
            if (!r.enabled) {
              return const EmptyView(icon: Icons.stars_outlined, title: 'المكافآت متوقفة حالياً', message: 'رصيدك ونقاطك محفوظة وترجع تشتغل أول ما تتفعّل.');
            }
            final history = _showPoints ? r.pointsHistory : r.walletHistory;
            return RefreshIndicator(
              color: WColors.fg,
              onRefresh: _refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 8, WSpace.page, 32), children: [
                _walletCard(r),
                const SizedBox(height: 12),
                _pointsCard(r),
                const SizedBox(height: 12),
                WCard(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const InviteScreen()));
                    _refresh();
                  },
                  color: WColors.lime,
                  borderColor: WColors.lime,
                  child: Row(children: [
                    const Icon(Icons.group_add_rounded, color: WColors.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('ادعُ صديق', style: WText.bodyStrong.copyWith(color: WColors.ink, fontWeight: FontWeight.w600)),
                        Text('إلك ${iqd(r.referralInviter)} وإله ${iqd(r.referralInvitee)} بعد أول طلب', style: WText.caption.copyWith(color: WColors.graphite)),
                      ]),
                    ),
                    const Icon(Icons.chevron_left_rounded, color: WColors.ink),
                  ]),
                ),
                const SizedBox(height: 24),
                Text('شلون تشتغل', style: WText.h3),
                const SizedBox(height: 10),
                _how(Icons.shopping_bag_outlined, 'اطلب أو اركب', '${r.pointsPer1000} نقطة عن كل 1,000 د.ع بعد التسليم أو نهاية الرحلة.'),
                _how(Icons.autorenew_rounded, 'حوّل نقاطك', 'كل ${r.redeemPoints} نقطة تتحول إلى ${iqd(r.redeemValue)} رصيد.'),
                _how(Icons.payments_outlined, 'ادفع من رصيدك', 'الرصيد يغطي لحد ${r.walletMaxPercent}% من قيمة المنتجات بطلبات المحلات.'),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: Text('السجل', style: WText.h3)),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [ButtonSegment(value: false, label: Text('الرصيد')), ButtonSegment(value: true, label: Text('النقاط'))],
                    selected: {_showPoints},
                    onSelectionChanged: (v) => setState(() => _showPoints = v.first),
                  ),
                ]),
                const SizedBox(height: 10),
                if (history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(_showPoints ? 'ما عندك نقاط بعد. أول طلب مُسلَّم يبدي يجمعلك.' : 'ما اكو حركات على رصيدك بعد.', style: WText.small, textAlign: TextAlign.center),
                  )
                else
                  WCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < history.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        _entry(history[i], points: _showPoints),
                      ],
                    ]),
                  ),
              ]),
            );
          },
        ),
      );

  Widget _walletCard(Rewards r) => Container(
        padding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: WColors.night, borderRadius: WRadius.all(WRadius.xl)),
        child: Stack(clipBehavior: Clip.none, children: [
          // العلامة بالزاوية الفارغة فوق، بعيد عن النص
          PositionedDirectional(end: -26, top: -34, child: Opacity(opacity: 0.12, child: WaselMark(size: 120, route: WColors.white, ring: WColors.lime))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('رصيد واصل', style: WText.overline.copyWith(color: WColors.inkFaint)),
            const SizedBox(height: 6),
            Text(iqd(r.wallet), style: WText.display.copyWith(color: WColors.lime, fontSize: 36, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 4),
            Text(r.wallet > 0 ? 'فعّل "استخدم رصيدي" بالسلة وينخصم من طلبك.' : 'اجمع نقاط أو ادعُ صديق حتى يصير عندك رصيد.', style: WText.small.copyWith(color: WColors.white.withValues(alpha: 0.75))),
          ]),
        ]),
      );

  Widget _pointsCard(Rewards r) {
    final can = r.redeemableValue > 0;
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${r.points}', style: WText.number.copyWith(fontSize: 30, height: 1)),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('نقطة', style: WText.small)),
          const Spacer(),
          const Icon(Icons.stars_rounded, color: WColors.limeDeep, size: 28),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: WRadius.all(WRadius.pill),
          child: LinearProgressIndicator(value: can && r.points % r.redeemPoints == 0 ? 1 : r.progress, minHeight: 8, backgroundColor: WColors.surfaceAlt, color: WColors.fg),
        ),
        const SizedBox(height: 8),
        Text(
          can ? 'تگدر تحوّل هسه وتاخذ ${iqd(r.redeemableValue)}.' : 'باقي ${r.pointsToNext} نقطة وتاخذ ${iqd(r.redeemValue)} رصيد.',
          style: WText.small,
        ),
        if (can) ...[
          const SizedBox(height: 14),
          WButton('حوّل إلى ${iqd(r.redeemableValue)}', icon: Icons.autorenew_rounded, loading: _redeeming, onPressed: () => _redeem(r)),
        ],
      ]),
    );
  }

  Widget _how(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: WColors.surfaceAlt, borderRadius: WRadius.all(12)),
            child: Icon(icon, size: 20, color: WColors.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: WText.bodyStrong),
              Text(body, style: WText.small),
            ]),
          ),
        ]),
      );

  Widget _entry(LedgerEntry e, {required bool points}) {
    final plus = e.amount > 0;
    final value = points ? '${plus ? '+' : '−'}${e.amount.abs()}' : '${plus ? '+' : '−'}${iqd(e.amount.abs())}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: plus ? WColors.successSoft : WColors.surfaceAlt, borderRadius: WRadius.all(11)),
          child: Icon(plus ? Icons.south_west_rounded : Icons.north_east_rounded, size: 17, color: plus ? WColors.success : WColors.inkMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.label, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(e.note.isEmpty ? dateTimeAr(e.createdAt) : '${e.note} · ${dateTimeAr(e.createdAt)}', style: WText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        Text(value, style: WText.price.copyWith(color: plus ? WColors.success : WColors.fg)),
      ]),
    );
  }
}

/// دعوة صديق: كود الزبون للمشاركة + إدخال كود صديق للزبون الجديد.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});
  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late Future<Rewards> _future = _load();
  final _code = TextEditingController();
  bool _applying = false;

  Future<Rewards> _load() async {
    final r = await customerApi.rewards();
    app.setRewards(r);
    return r;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _message(Rewards r) =>
      'جرّب تطبيق واصل للتوصيل والتكسي. سجّل ودخّل كودي ${r.referralCode} من "ادعُ صديق" وتاخذ رصيد ${iqd(r.referralInvitee)} بعد أول طلب.';

  Future<void> _copyCode(Rewards r) async {
    await Clipboard.setData(ClipboardData(text: r.referralCode));
    if (mounted) showSuccess(context, 'تم نسخ الكود');
  }

  Future<void> _apply() async {
    final code = _code.text.trim();
    if (code.isEmpty) return showError(context, 'اكتب كود الدعوة.');
    setState(() => _applying = true);
    try {
      final r = await customerApi.applyReferralCode(code);
      app.setRewards(r);
      if (!mounted) return;
      setState(() => _future = Future.value(r));
      showSuccess(context, 'تم. رصيدك يوصل بعد أول طلب مُسلَّم');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ادعُ صديق')),
        body: FutureBuilder<Rewards>(
          future: _future,
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!, onRetry: () => setState(() => _future = _load()));
            final r = s.data;
            if (r == null) return const SkeletonList();
            if (!r.enabled) return const EmptyView(icon: Icons.group_add_outlined, title: 'الدعوات متوقفة حالياً');
            return ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 8, WSpace.page, 32), children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(WRadius.xl)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('إنت وصديقك تربحون', style: WText.h1.copyWith(color: WColors.ink)),
                  const SizedBox(height: 6),
                  Text('صديقك يدخّل كودك بعد التسجيل. أول ما يكمّل أول طلب، إنت تاخذ ${iqd(r.referralInviter)} وهو ياخذ ${iqd(r.referralInvitee)}.',
                      style: WText.body.copyWith(color: WColors.graphite)),
                  const SizedBox(height: 18),
                  Semantics(
                    button: true,
                    label: 'كودك ${r.referralCode}. اضغط للنسخ',
                    onTap: () => _copyCode(r),
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: WRadius.all(WRadius.md),
                      onTap: () => _copyCode(r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: WColors.ink, borderRadius: WRadius.all(WRadius.md)),
                        child: Row(children: [
                          Expanded(
                            child: Text(r.referralCode,
                                textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: WText.number.copyWith(fontSize: 24, color: WColors.lime, letterSpacing: 4)),
                          ),
                          const Icon(Icons.copy_rounded, color: WColors.white, size: 20),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  WButton('شارك بالواتساب', kind: WButtonKind.dark, icon: Icons.send_rounded, onPressed: () async {
                    final ok = await shareViaWhatsapp(_message(r));
                    if (!ok && context.mounted) {
                      await Clipboard.setData(ClipboardData(text: _message(r)));
                      if (context.mounted) showInfo(context, 'ما انفتح واتساب، فنسخنا الرسالة. الصقها وين ما تريد');
                    }
                  }),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _stat('${r.invited}', 'دخّلوا كودك')),
                const SizedBox(width: 10),
                Expanded(child: _stat('${r.invitedRewarded}', 'كمّلوا أول طلب')),
                const SizedBox(width: 10),
                Expanded(child: _stat(iqd(r.invitedRewarded * r.referralInviter), 'ربحت')),
              ]),
              if (r.canEnterCode) ...[
                const SizedBox(height: 24),
                Text('عندك كود من صديق؟', style: WText.h3),
                const SizedBox(height: 4),
                Text('دخّله قبل أول طلب وتاخذ ${iqd(r.referralInvitee)} رصيد.', style: WText.small),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      textDirection: TextDirection.ltr,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      maxLength: 12,
                      onSubmitted: (_) => _apply(),
                      decoration: const InputDecoration(labelText: 'كود الدعوة', hintText: 'WXXXXXX', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(padding: const EdgeInsets.only(top: 4), child: WButton('تأكيد', kind: WButtonKind.dark, expand: false, loading: _applying, onPressed: _apply)),
                ]),
              ],
            ]);
          },
        ),
      );

  Widget _stat(String value, String label) => WCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: WText.number.copyWith(fontSize: 18))),
          const SizedBox(height: 2),
          Text(label, style: WText.caption, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}
