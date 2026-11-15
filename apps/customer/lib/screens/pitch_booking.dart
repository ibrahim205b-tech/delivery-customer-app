import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// حجز ملاعب الخماسي: اختيار الملعب، ثم اليوم والوقت والمدة، ثم طلب الحجز.
/// الحجز لا يُؤكَّد إلا عند قبول صاحب الملعب، والمواعيد المحجوزة تُقرأ من الخادم.
class PitchOwnersScreen extends StatelessWidget {
  const PitchOwnersScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حجز ملاعب الخماسي')),
        body: FutureBuilder<List<Merchant>>(
          future: catalogApi.pitchOwners(),
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!);
            if (!snap.hasData) return const SkeletonList(count: 3);
            final owners = snap.data!;
            if (owners.isEmpty) return const EmptyView(icon: Icons.sports_soccer_outlined, title: 'ما اكو ملاعب معتمدة بعد', message: 'تنضاف الملاعب هنا بعد اعتمادها.');
            return ListView(padding: const EdgeInsets.all(WSpace.page), children: [
              for (final m in owners)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: WCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PitchListScreen(owner: m))),
                    child: Row(children: [
                      Expanded(child: Text(m.name, style: WText.h3)),
                      const Icon(Icons.chevron_left_rounded),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}

class PitchListScreen extends StatelessWidget {
  const PitchListScreen({super.key, required this.owner});
  final Merchant owner;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(owner.name)),
        body: FutureBuilder<List<Pitch>>(
          future: catalogApi.pitchesOf(owner.id),
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!);
            if (!snap.hasData) return const SkeletonList(count: 3);
            final ps = snap.data!;
            if (ps.isEmpty) return const EmptyView(icon: Icons.sports_soccer_outlined, title: 'ما في ملاعب مفعّلة');
            return ListView(padding: const EdgeInsets.all(WSpace.page), children: [
              for (final p in ps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: WCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PitchBookScreen(pitch: p))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: WText.h3),
                      if (p.description.isNotEmpty) Text(p.description, style: WText.small),
                      const SizedBox(height: 6),
                      Text('${iqd(p.pricePerHour)} / ساعة · من ${p.openHour}:00 إلى ${p.closeHour == 24 ? '12:00 ص' : '${p.closeHour}:00'}', style: WText.caption),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}

class PitchBookScreen extends StatefulWidget {
  const PitchBookScreen({super.key, required this.pitch});
  final Pitch pitch;
  @override
  State<PitchBookScreen> createState() => _PitchBookScreenState();
}

class _PitchBookScreenState extends State<PitchBookScreen> {
  late DateTime _day = _today.add(const Duration(days: 1));
  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  int _minutes = 0;
  DateTime? _start;
  List<({DateTime start, DateTime end})> _busy = const [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _minutes = widget.pitch.minMinutes;
    _loadBusy();
  }

  Future<void> _loadBusy() async {
    setState(() {
      _start = null;
      _busy = const [];
    });
    try {
      final b = await catalogApi.pitchBusySlots(widget.pitch.id, _day);
      if (mounted) setState(() => _busy = b);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// الأوقات الممكنة لليوم (كل 30 دقيقة) مع المدة المختارة، بدون تعارض مع المحجوز
  List<DateTime> get _slots {
    final p = widget.pitch;
    final out = <DateTime>[];
    for (var m = p.openHour * 60; m + _minutes <= p.closeHour * 60; m += 30) {
      final s = DateTime(_day.year, _day.month, _day.day, m ~/ 60, m % 60);
      final e = s.add(Duration(minutes: _minutes));
      if (s.isBefore(DateTime.now())) continue;
      final clash = _busy.any((b) => s.isBefore(b.end) && e.isAfter(b.start));
      if (!clash) out.add(s);
    }
    return out;
  }

  Future<void> _send() async {
    final s = _start;
    if (s == null) return;
    setState(() => _sending = true);
    try {
      await catalogApi.bookPitch(widget.pitch.id, s, _minutes);
      if (!mounted) return;
      showSuccess(context, 'وصل طلبك لصاحب الملعب. نعلمك أول ما يرد.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pitch;
    final total = (p.pricePerHour * _minutes / 60).round();
    final durations = [for (var m = p.minMinutes; m <= 240; m += 30) m];
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
        Text('اختر اليوم', style: WText.h3),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 1; i <= 7; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(dateAr(_today.add(Duration(days: i)))),
                  selected: DateUtils.isSameDay(_day, _today.add(Duration(days: i))),
                  onSelected: (_) {
                    setState(() => _day = _today.add(Duration(days: i)));
                    _loadBusy();
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        Text('المدة', style: WText.h3),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in durations)
            ChoiceChip(
              label: Text(m % 60 == 0 ? '${m ~/ 60} ساعة' : '${m ~/ 60} س و30 د'),
              selected: _minutes == m,
              onSelected: (_) => setState(() {
                _minutes = m;
                _start = null;
              }),
            ),
        ]),
        const SizedBox(height: 14),
        Text('الوقت المتاح', style: WText.h3),
        const SizedBox(height: 8),
        if (_slots.isEmpty)
          Text('ما في وقت متاح بهذه المدة في هذا اليوم.', style: WText.small)
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in _slots)
              ChoiceChip(
                label: Text(timeAr(s)),
                selected: _start == s,
                onSelected: (_) => setState(() => _start = s),
              ),
          ]),
        const SizedBox(height: 18),
        WCard(
          child: Column(children: [
            Row(children: [Expanded(child: Text('السعر المتوقع', style: WText.small)), Text(iqd(total), style: WText.price)]),
            const SizedBox(height: 6),
            Text('الحجز يتأكد عند قبول صاحب الملعب فقط.', style: WText.caption),
            if (p.cancellationPolicy.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('سياسة الإلغاء: ${p.cancellationPolicy}', style: WText.caption),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        WButton(_sending ? 'جارٍ الإرسال…' : 'اطلب الحجز', onPressed: (_start == null || _sending) ? null : _send),
      ]),
    );
  }
}

/// حجوزات الزبون وطلباته: الحالة، والإلغاء، والتقييم بعد الإتمام
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});
  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  late Future<List<ServiceRequest>> _list = catalogApi.myServiceRequests();
  void _reload() => setState(() => _list = catalogApi.myServiceRequests());

  Future<void> _cancel(ServiceRequest r) async {
    final ok = await confirmDialog(context, title: 'إلغاء الحجز؟', message: 'تنطبق سياسة الإلغاء في الملعب.', confirm: 'إلغاء الحجز', danger: true);
    if (!ok || !mounted) return;
    final reason = await promptText(context, title: 'سبب الإلغاء', hint: 'اختياري', confirm: 'تأكيد') ?? '';
    if (!mounted) return;
    if (await runAction(context, () => catalogApi.cancelServiceRequest(r.id, reason), success: 'انلغى الحجز')) _reload();
  }

  Future<void> _rate(ServiceRequest r) async {
    final stars = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('قيّم الخدمة'),
        children: [for (var i = 5; i >= 1; i--) SimpleDialogOption(onPressed: () => Navigator.pop(c, i), child: Text('$i ⭐'))],
      ),
    );
    if (stars == null || !mounted) return;
    if (await runAction(context, () => catalogApi.rateServiceRequest(r.id, stars, ''), success: 'شكراً على التقييم')) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حجوزاتي')),
        body: FutureBuilder<List<ServiceRequest>>(
          future: _list,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            if (!snap.hasData) return const SkeletonList(count: 4);
            final rows = snap.data!;
            if (rows.isEmpty) return const EmptyView(icon: Icons.event_note_outlined, title: 'ما عندك حجوزات بعد');
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: WCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(r.placeName.isEmpty ? 'طلب خدمة' : r.placeName, style: WText.bodyStrong)),
                          StatusPill(r.statusLabel, tone: r.status == 'accepted' || r.status == 'completed' ? PillTone.info : PillTone.neutral),
                        ]),
                        if (r.startsAt != null) Text('${dateTimeAr(r.startsAt!)} · ${iqd(r.amount)}', style: WText.small),
                        if (r.rejectReason.isNotEmpty) Text('سبب الرفض: ${r.rejectReason}', style: WText.small.copyWith(color: WColors.danger)),
                        if (r.status == 'requested' || r.status == 'accepted')
                          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: () => _cancel(r), child: const Text('إلغاء'))),
                        if (r.status == 'completed')
                          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: () => _rate(r), child: const Text('قيّم'))),
                      ]),
                    ),
                  ),
              ]),
            );
          },
        ),
      );
}
