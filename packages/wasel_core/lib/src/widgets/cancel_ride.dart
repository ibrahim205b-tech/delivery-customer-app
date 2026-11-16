import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme/tokens.dart';
import 'basics.dart';

typedef CancelChoice = ({String reason, String note});

/// ورقة الإلغاء: سؤال التأكيد، ثم اختيار السبب (إلزامي)، ثم ملاحظة لـ"سبب آخر".
/// ترجع null إذا تراجع المستخدم. الإلغاء نفسه يتم في الخادم (cancel_ride).
Future<CancelChoice?> pickCancelReason(BuildContext context, {required String party}) =>
    showModalBottomSheet<CancelChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CancelSheet(party: party),
    );

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.party});
  final String party;
  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  late final Future<List<CancelReason>> _reasons = catalogApi.cancelReasons(widget.party);
  final _note = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(WSpace.page, 16, WSpace.page, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: FutureBuilder<List<CancelReason>>(
          future: _reasons,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!);
            if (!snap.hasData) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
            final list = snap.data!;
            final picked = list.where((r) => r.id == _selected).firstOrNull;
            final needsNote = picked?.needsNote ?? false;
            final canConfirm = picked != null && (!needsNote || _note.text.trim().length >= 5);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('هل أنت متأكد من إلغاء الرحلة؟', style: WText.h3),
                  const SizedBox(height: 4),
                  Text('اختار سبب الإلغاء. الإلغاء المتكرر يوقف الحساب مؤقتاً.', style: WText.small),
                  const SizedBox(height: 10),
                  for (final r in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.label),
                      leading: Icon(
                        _selected == r.id ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        color: _selected == r.id ? WColors.link : WColors.inkFaint,
                      ),
                      onTap: () => setState(() => _selected = r.id),
                    ),
                  if (needsNote)
                    TextField(
                      controller: _note,
                      maxLines: 2,
                      maxLength: 300,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'وضّح السبب (5 أحرف على الأقل)'),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: WButton('رجوع', kind: WButtonKind.ghost, onPressed: () => Navigator.pop(context))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WButton(
                        'تأكيد الإلغاء',
                        kind: WButtonKind.danger,
                        onPressed: canConfirm ? () => Navigator.pop(context, (reason: _selected!, note: _note.text.trim())) : null,
                      ),
                    ),
                  ]),
                ],
              ),
            );
          },
        ),
      );
}

/// إشعار الإيقاف: يوضح السبب ويعرض العدّ التنازلي حتى انتهاء المدة
class RestrictionNotice extends StatefulWidget {
  const RestrictionNotice({super.key, required this.restriction});
  final UserRestriction restriction;

  @override
  State<RestrictionNotice> createState() => _RestrictionNoticeState();
}

class _RestrictionNoticeState extends State<RestrictionNotice> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _countdown(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restriction;
    if (!r.isActive) return const SizedBox.shrink();
    final endsAt = r.endsAt;
    final hh = endsAt.hour.toString().padLeft(2, '0'), mm = endsAt.minute.toString().padLeft(2, '0');
    final title = r.isCustomer ? 'طلب الرحلات موقوف مؤقتاً' : 'استقبال الطلبات موقوف مؤقتاً';
    final explain = r.isCustomer
        ? 'تم تسجيل إلغاءات كثيرة خلال اليوم. يمكنك استخدام خدمة التكسي مجدداً بعد انتهاء مدة الإيقاف.'
        : 'تكرار إلغاء الرحلات أوقف استقبال الطلبات. سيعود حسابك لاستقبال الطلبات تلقائياً بعد انتهاء المدة.';
    return WCard(
      color: WColors.warningSoft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.pause_circle_outline_rounded, color: WColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: WText.bodyStrong)),
        ]),
        const SizedBox(height: 6),
        Text(explain, style: WText.small),
        const SizedBox(height: 8),
        Text('المتبقي ${_countdown(r.remaining)} · ينتهي الساعة $hh:$mm', style: WText.bodyStrong),
      ]),
    );
  }
}
