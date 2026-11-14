import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasel_core/wasel_core.dart';

/// حسابات الكباتن: المستحق على كل كابتن، وتسجيل التسديدات النقدية والتصحيحات، ونسبة العمولة.
/// كل حركة مالية صف مستقل من الخادم؛ لا تعديل لأي حركة قديمة.
class DriverAccountsScreen extends StatefulWidget {
  const DriverAccountsScreen({super.key});
  @override
  State<DriverAccountsScreen> createState() => _DriverAccountsScreenState();
}

class _DriverAccountsScreenState extends State<DriverAccountsScreen> {
  late Future<List<DriverAccountRow>> _list = adminApi.driverAccounts();
  void _reload() => setState(() => _list = adminApi.driverAccounts());

  Future<void> _commissionDialog(Map<String, dynamic> current) async {
    var enabled = current['enabled'] == true;
    final percent = TextEditingController(text: '${(current['percent'] as num?) ?? 10}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('عمولة الكباتن'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('تفعيل احتساب العمولة'), value: enabled, onChanged: (v) => set(() => enabled = v)),
            TextField(
              controller: percent,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'النسبة', suffixText: '%', helperText: 'من 0 إلى 50. تنطبق على الرحلات المكتملة بعد الحفظ فقط.'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final p = double.tryParse(percent.text) ?? -1;
    if (await runAction(context, () => adminApi.setDriverCommission(enabled: enabled, percent: p), success: 'تم حفظ نسبة الكباتن')) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('حسابات الكباتن'),
          actions: [
            IconButton(
              tooltip: 'نسبة العمولة',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () async => _commissionDialog(await adminApi.driverCommissionSetting()),
            ),
          ],
        ),
        body: FutureBuilder<List<DriverAccountRow>>(
          future: _list,
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
            if (!s.hasData) return const SkeletonList(count: 4);
            final rows = s.data!;
            final totalOwed = rows.fold<int>(0, (a, r) => a + r.owed);
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32), children: [
                WCard(
                  color: WColors.night,
                  borderColor: WColors.night,
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Expanded(child: Text('المستحق على كل الكباتن', style: WText.small.copyWith(color: const Color(0xFF98A0A8)))),
                    Text(iqd(totalOwed), style: WText.number.copyWith(fontSize: 22, color: WColors.lime)),
                  ]),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty) const EmptyView(icon: Icons.badge_outlined, title: 'ما اكو كباتن بعد'),
                for (final r in rows) ...[
                  WCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => DriverAccountDetail(driver: r)));
                      _reload();
                    },
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.name.isEmpty ? 'كابتن بدون اسم' : r.name, style: WText.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${r.phone} · ${r.tripsDone} رحلة مكتملة${r.isActive ? '' : ' · موقوف'}', style: WText.caption),
                        ]),
                      ),
                      Text(iqd(r.owed), style: WText.price.copyWith(color: r.owed > 0 ? WColors.fg : WColors.inkMuted)),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_left_rounded),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
              ]),
            );
          },
        ),
      );
}

/// تفاصيل كابتن: ملخص، سجل حركات، وتسجيل تسديد أو تصحيح
class DriverAccountDetail extends StatefulWidget {
  const DriverAccountDetail({super.key, required this.driver});
  final DriverAccountRow driver;
  @override
  State<DriverAccountDetail> createState() => _DriverAccountDetailState();
}

class _DriverAccountDetailState extends State<DriverAccountDetail> {
  late Future<CaptainStatement> _st = adminApi.driverAccount(widget.driver.driverId);
  void _reload() => setState(() => _st = adminApi.driverAccount(widget.driver.driverId));

  Future<void> _payment(int owed) async {
    final amount = TextEditingController(text: owed > 0 ? '$owed' : '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('تسديد من ${widget.driver.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('المستحق الآن: ${iqd(owed)}', style: WText.small),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'المبلغ المستلم نقداً', suffixText: 'د.ع'),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تسجيل')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final v = int.tryParse(amount.text) ?? 0;
    if (await runAction(context, () => adminApi.addDriverPayment(widget.driver.driverId, v, note: note.text), success: 'انسجل التسديد')) _reload();
  }

  Future<void> _adjustment() async {
    final delta = TextEditingController();
    final reason = TextEditingController();
    var sign = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('تصحيح على الحساب'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 1, label: Text('يزيد المستحق')), ButtonSegment(value: -1, label: Text('ينقص المستحق'))],
              selected: {sign},
              onSelectionChanged: (v) => set(() => sign = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: delta,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'د.ع'),
            ),
            const SizedBox(height: 10),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'السبب (٥ أحرف على الأقل)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تسجيل')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final v = (int.tryParse(delta.text) ?? 0) * sign;
    if (await runAction(context, () => adminApi.addDriverAdjustment(widget.driver.driverId, v, reason.text), success: 'انسجل التصحيح كحركة مستقلة')) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.driver.name.isEmpty ? 'كابتن' : widget.driver.name)),
        body: FutureBuilder<CaptainStatement>(
          future: _st,
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
            if (!s.hasData) return const SkeletonList(count: 4);
            final st = s.data!;
            final sm = st.summary;
            return ListView(padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 32), children: [
              WCard(
                color: WColors.night,
                borderColor: WColors.night,
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('المستحق لواصل', style: WText.small.copyWith(color: const Color(0xFF98A0A8))),
                  Text(iqd(sm.owed), style: WText.number.copyWith(fontSize: 30, color: WColors.white)),
                  const SizedBox(height: 10),
                  Text('عمولات ${iqd(sm.commissionTotal)} · مسدَّد ${iqd(sm.paidTotal)} · تصحيحات ${iqd(sm.adjustTotal)}', style: WText.caption.copyWith(color: const Color(0xFF98A0A8))),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: WButton('تسديد نقدي', icon: Icons.payments_outlined, onPressed: sm.owed > 0 ? () => _payment(sm.owed) : null)),
                const SizedBox(width: 10),
                Expanded(child: WButton('تصحيح', kind: WButtonKind.secondary, icon: Icons.tune_rounded, onPressed: _adjustment)),
              ]),
              const SizedBox(height: 16),
              Text('الحركات', style: WText.h3),
              const SizedBox(height: 6),
              if (st.ledger.isEmpty) const EmptyView(icon: Icons.receipt_long_outlined, title: 'ما في حركات بعد'),
              for (final r in st.ledger)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(switch (r.kind) {
                    LedgerKind.commission => 'عمولة ${r.percent == null ? '' : '${r.percent!.toStringAsFixed(0)}٪'} على ${iqd(r.fare ?? 0)}',
                    LedgerKind.payment => 'تسديد نقدي',
                    LedgerKind.adjustment => 'تصحيح',
                  }),
                  subtitle: Text(
                    [dateTimeAr(r.at), if (r.note.isNotEmpty) r.note].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    switch (r.kind) {
                      LedgerKind.payment => iqd(-r.amount),
                      _ => '${r.amount >= 0 ? '+' : ''}${iqd(r.amount)}',
                    },
                    style: WText.bodyStrong,
                  ),
                ),
            ]);
          },
        ),
      );
}
