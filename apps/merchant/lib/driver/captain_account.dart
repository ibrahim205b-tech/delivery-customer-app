import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

/// تبويب "الحساب" للكابتن: المستحق لواصل، الأرباح حسب الفترة، الأداء، آخر 7 أيام، وكشف الحركات.
/// كل الأرقام من الخادم (driver_account). لا توجد أرقام تقديرية.
class CaptainAccountTab extends StatefulWidget {
  const CaptainAccountTab({super.key, required this.future, required this.onRefresh});
  final Future<CaptainStatement>? future;
  final VoidCallback onRefresh;

  @override
  State<CaptainAccountTab> createState() => _CaptainAccountTabState();
}

class _CaptainAccountTabState extends State<CaptainAccountTab> {
  int _period = 0; // 0 اليوم · 1 الأسبوع · 2 الشهر
  String _filter = 'all'; // all · commission · payment · adjustment

  Future<void> _copyStatement(CaptainStatement st) async {
    final s = st.summary;
    final b = StringBuffer()
      ..writeln('كشف حساب كابتن واصل')
      ..writeln('المستحق لواصل: ${iqd(s.owed)}')
      ..writeln('────────────')
      ..writeln('إجمالي العمولات: ${iqd(s.commissionTotal)}')
      ..writeln('إجمالي المسدَّد: ${iqd(s.paidTotal)}')
      ..writeln('التصحيحات: ${iqd(s.adjustTotal)}')
      ..writeln('────────────');
    for (final r in st.ledger) {
      final label = switch (r.kind) {
        LedgerKind.commission => 'عمولة ${r.fare == null ? '' : 'على ${iqd(r.fare!)}'}',
        LedgerKind.payment => 'تسديد',
        LedgerKind.adjustment => 'تصحيح${r.note.isEmpty ? '' : ' · ${r.note}'}',
      };
      final v = r.kind == LedgerKind.payment ? -r.amount : r.amount;
      b.writeln('${dateTimeAr(r.at)} · $label · ${v >= 0 ? '+' : ''}${iqd(v)}');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) showSuccess(context, 'تم نسخ كشف الحساب');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.future == null) return const SkeletonList();
    return FutureBuilder<CaptainStatement>(
      future: widget.future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: widget.onRefresh);
        if (!snap.hasData) return const SkeletonList();
        final st = snap.data!;
        final s = st.summary;
        final fares = switch (_period) { 0 => s.faresToday, 1 => s.faresWeek, _ => s.faresMonth };
        final comm = switch (_period) { 0 => s.commissionToday, 1 => s.commissionWeek, _ => s.commissionMonth };
        final rows = st.ledger.where((r) => switch (_filter) {
              'commission' => r.kind == LedgerKind.commission,
              'payment' => r.kind == LedgerKind.payment,
              'adjustment' => r.kind == LedgerKind.adjustment,
              _ => true,
            }).toList();

        return RefreshIndicator(
          onRefresh: () async => widget.onRefresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(WSpace.lg, 0, WSpace.lg, 24),
            children: [
              // المستحق لواصل: أهم رقم في الشاشة
              WCard(
                color: s.owed > 0 ? WColors.night : WColors.successSoft,
                borderColor: Colors.transparent,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('المستحق لواصل', style: WText.small.copyWith(color: s.owed > 0 ? WColors.white : WColors.fg)),
                  const SizedBox(height: 4),
                  Text(iqd(s.owed), style: WText.price.copyWith(fontSize: 30, color: s.owed > 0 ? WColors.white : WColors.fg)),
                  const SizedBox(height: 6),
                  Text(
                    s.owed > 0 ? 'يُسدَّد نقداً عند مكتب واصل. الرصيد يتحدّث بعد كل رحلة مكتملة.' : 'ما عليك أي مستحقات حالياً.',
                    style: WText.caption.copyWith(color: s.owed > 0 ? WColors.white : WColors.fg),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _Stat(label: 'رحلات اليوم', value: '${s.tripsDoneToday}')),
                const SizedBox(width: 10),
                Expanded(child: _Stat(label: 'إجمالي الرحلات', value: '${s.tripsDone}')),
                const SizedBox(width: 10),
                Expanded(child: _Stat(label: 'التقييم', value: s.ratingAvg > 0 ? s.ratingAvg.toStringAsFixed(1) : 'لا يوجد')),
              ]),
              const SizedBox(height: 16),

              // الأرباح حسب الفترة
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('اليوم')),
                  ButtonSegment(value: 1, label: Text('الأسبوع')),
                  ButtonSegment(value: 2, label: Text('الشهر')),
                ],
                selected: {_period},
                onSelectionChanged: (v) => setState(() => _period = v.first),
              ),
              const SizedBox(height: 10),
              WCard(
                child: Column(children: [
                  _Line(label: 'أجور الرحلات', value: iqd(fares)),
                  const Divider(height: 18),
                  _Line(label: 'عمولة واصل', value: iqd(comm), strong: true),
                  const Divider(height: 18),
                  _Line(label: 'صافيك قبل المصاريف', value: iqd(fares - comm)),
                ]),
              ),
              const SizedBox(height: 16),

              // أداء آخر 7 أيام
              Text('آخر 7 أيام', style: WText.h3),
              const SizedBox(height: 10),
              WCard(child: _WeekBars(days: s.last7Days)),
              const SizedBox(height: 10),
              WCard(
                child: Column(children: [
                  _Line(label: 'نسبة الإلغاء', value: s.cancelRate == null ? 'لا توجد رحلات بعد' : '${s.cancelRate!.toStringAsFixed(1)}٪'),
                  const Divider(height: 18),
                  _Line(label: 'الرحلات الملغاة', value: '${s.tripsCancelled}'),
                ]),
              ),
              const SizedBox(height: 16),

              // كشف الحساب
              Row(children: [
                Expanded(child: Text('كشف الحساب', style: WText.h3)),
                TextButton.icon(
                  onPressed: () => _copyStatement(st),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ'),
                ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final f in const [('all', 'الكل'), ('commission', 'عمولات'), ('payment', 'تسديدات'), ('adjustment', 'تصحيحات')])
                  ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
              ]),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const EmptyView(icon: Icons.receipt_long_outlined, title: 'ما في حركات بعد', message: 'العمولات تنسجل تلقائياً بعد كل رحلة مكتملة.')
              else
                for (final r in rows) _LedgerTile(row: r),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => WCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: WText.bodyStrong.copyWith(fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, style: WText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: strong ? WText.bodyStrong : WText.body)),
        Text(value, style: strong ? WText.bodyStrong : WText.body),
      ]);
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});
  final List<CaptainDay> days;
  @override
  Widget build(BuildContext context) {
    if (days.isEmpty || days.every((d) => d.fares == 0)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('ما في رحلات مكتملة خلال هذا الأسبوع', style: WText.small, textAlign: TextAlign.center),
      );
    }
    final max = days.map((d) => d.fares).reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 130,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in days)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(d.trips > 0 ? '${d.trips}' : '', style: WText.caption),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                height: max == 0 ? 4 : 4 + 80 * (d.fares / max),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: d.fares > 0 ? WColors.night : WColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(child: Text(_weekdayAr(d.day), style: WText.caption)),
            ]),
          ),
      ]),
    );
  }

  static String _weekdayAr(DateTime d) => const ['اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد'][d.weekday - 1];
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.row});
  final LedgerRow row;
  @override
  Widget build(BuildContext context) {
    final r = row;
    final (icon, color, title) = switch (r.kind) {
      LedgerKind.commission => (Icons.percent_rounded, WColors.blue, 'عمولة ${r.percent == null ? '' : '${r.percent!.toStringAsFixed(0)}٪'}${r.fare == null ? '' : ' على ${iqd(r.fare!)}'}'),
      LedgerKind.payment => (Icons.payments_outlined, WColors.success, 'تسديد لواصل'),
      LedgerKind.adjustment => (Icons.tune_rounded, WColors.warning, 'تصحيح من الإدارة'),
    };
    final v = r.kind == LedgerKind.payment ? -r.amount : r.amount;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        r.note.isNotEmpty ? '${dateTimeAr(r.at)} · ${r.note}' : dateTimeAr(r.at),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${v >= 0 ? '+' : ''}${iqd(v)}', style: WText.bodyStrong.copyWith(color: r.kind == LedgerKind.payment ? WColors.success : WColors.fg)),
    );
  }
}

/// عدّاد قبول الطلب: يبدأ من أول ظهور، وعند انتهائه يختفي الطلب من شاشتك فقط.
/// ملاحظة: الخادم لا يُلغي الطلب تلقائياً؛ الطلب يبقى متاحاً للكباتن الآخرين.
class OfferCountdown extends StatefulWidget {
  const OfferCountdown({super.key, required this.startedAt, required this.total, required this.onExpire});
  final DateTime startedAt;
  final Duration total;
  final VoidCallback onExpire;
  @override
  State<OfferCountdown> createState() => _OfferCountdownState();
}

class _OfferCountdownState extends State<OfferCountdown> {
  late Duration _left;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _recalc();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_recalc);
    });
  }

  void _recalc() {
    _left = widget.total - DateTime.now().difference(widget.startedAt);
    if (_left <= Duration.zero) {
      _left = Duration.zero;
      _timer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpire();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frac = widget.total.inMilliseconds == 0 ? 0.0 : _left.inMilliseconds / widget.total.inMilliseconds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: frac.clamp(0.0, 1.0), minHeight: 5, color: WColors.lime, backgroundColor: WColors.surfaceAlt),
      ),
      const SizedBox(height: 4),
      Text('ينتهي وقت القبول خلال ${_left.inSeconds} ثانية', style: WText.caption),
    ]);
  }
}
