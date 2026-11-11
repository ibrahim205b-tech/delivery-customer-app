import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// حجوزات الخدمات المنزلية لمقدّم الخدمة (لحظياً)
class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key, required this.merchant});
  final Merchant merchant;
  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  late Stream<List<ServiceBooking>> _stream = merchantApi.watchBookings(widget.merchant.id);
  bool _active = true;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ServiceBooking>>(
        stream: _stream,
        builder: (context, s) {
          if (s.hasError) return ErrorView(error: s.error!, onRetry: () => setState(() => _stream = merchantApi.watchBookings(widget.merchant.id)));
          if (!s.hasData) return const SkeletonList();
          final list = s.data!.where((b) => b.status.isActive == _active).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 8),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: true, label: Text('الحالية')), ButtonSegment(value: false, label: Text('السابقة'))],
                selected: {_active},
                onSelectionChanged: (v) => setState(() => _active = v.first),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyView(icon: Icons.event_available_outlined, title: 'ما اكو حجوزات هنا')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _BookingCard(b: list[i]),
                    ),
            ),
          ]);
        },
      );
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.b});
  final ServiceBooking b;

  Future<void> _set(BuildContext context, BookingStatus s, {bool askNote = false}) async {
    String? note;
    if (askNote) {
      note = await promptText(context,
          title: s == BookingStatus.rejected ? 'سبب الرفض' : 'رسالة للزبون (الموعد، السعر التقريبي…)',
          confirm: s == BookingStatus.rejected ? 'رفض' : 'قبول');
      if (s == BookingStatus.rejected && note == null) return;
    }
    if (context.mounted) await runAction(context, () => merchantApi.updateBooking(b.id, s, note: note));
  }

  @override
  Widget build(BuildContext context) => WCard(
        borderColor: b.status == BookingStatus.requested ? WColors.coral : WColors.line,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(b.customerName, style: WText.h3)),
            StatusPill(b.status.label, tone: b.status == BookingStatus.requested ? PillTone.accent : PillTone.info),
          ]),
          const SizedBox(height: 6),
          Text(b.description, style: WText.body),
          const SizedBox(height: 8),
          InfoRow(icon: Icons.event_outlined, text: 'الوقت المطلوب: ${dateAr(b.preferredTime)} · ${timeAr(b.preferredTime)}'),
          const SizedBox(height: 4),
          InfoRow(icon: Icons.place_outlined, text: b.addressText),
          if (b.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: b.photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => showDialog(context: context, builder: (_) => Dialog(child: WImage(b.photoUrls[i], fit: BoxFit.contain))),
                  child: WImage(b.photoUrls[i], width: 72, height: 72),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            WIconButton(Icons.call_outlined, background: WColors.surfaceAlt, onPressed: () => callPhone(b.customerPhone)),
            const SizedBox(width: 8),
            WIconButton(Icons.map_outlined, background: WColors.surfaceAlt, onPressed: () => openInMaps(b.lat, b.lng, label: b.customerName)),
            const SizedBox(width: 12),
            Expanded(
              child: switch (b.status) {
                BookingStatus.requested => Row(children: [
                    Expanded(flex: 2, child: WButton('قبول', kind: WButtonKind.dark, onPressed: () => _set(context, BookingStatus.accepted, askNote: true))),
                    const SizedBox(width: 8),
                    Expanded(child: WButton('رفض', kind: WButtonKind.danger, onPressed: () => _set(context, BookingStatus.rejected, askNote: true))),
                  ]),
                BookingStatus.accepted => WButton('بدء العمل', kind: WButtonKind.dark, onPressed: () => _set(context, BookingStatus.inProgress)),
                BookingStatus.inProgress => WButton('تم إنجاز العمل', onPressed: () => _set(context, BookingStatus.completed)),
                _ => const SizedBox.shrink(),
              },
            ),
          ]),
        ]),
      );
}
