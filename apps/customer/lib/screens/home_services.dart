import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import '../main.dart';
import 'errand.dart';

/// الخدمات المنزلية: اختيار الخدمة ← مقدّم الخدمة ← تفاصيل الحجز
class HomeServicesScreen extends StatelessWidget {
  const HomeServicesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الأعمال المنزلية'),
          actions: [TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen())), child: const Text('حجوزاتي'))],
        ),
        body: AsyncView<List<HomeService>>(
          load: catalogApi.homeServices,
          builder: (context, services, _) => services.isEmpty
              ? const EmptyView(icon: Icons.home_repair_service_outlined, title: 'ما اكو خدمات مفعّلة حالياً')
              : GridView.builder(
                  padding: const EdgeInsets.all(WSpace.page),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.25),
                  itemCount: services.length,
                  itemBuilder: (context, i) {
                    final s = services[i];
                    return WCard(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ProvidersScreen(service: s))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: WColors.warningSoft, borderRadius: WRadius.all(14)),
                          child: Icon(homeServiceIcon(s.icon), color: WColors.warning),
                        ),
                        Text(s.name, style: WText.h3),
                      ]),
                    );
                  },
                ),
        ),
      );
}

class _ProvidersScreen extends StatelessWidget {
  const _ProvidersScreen({required this.service});
  final HomeService service;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(service.name)),
        body: AsyncView<List<Merchant>>(
          load: () => catalogApi.providersFor(service.id),
          loading: const SkeletonList(),
          builder: (context, list, _) => list.isEmpty
              ? const EmptyView(icon: Icons.engineering_outlined, title: 'ما اكو مقدّمين لهذه الخدمة بعد', message: 'الإدارة تضيف الفنيين المعتمدين تباعاً.')
              : ListView.separated(
                  padding: const EdgeInsets.all(WSpace.page),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final m = list[i];
                    return WCard(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceBookingScreen(service: service, provider: m))),
                      child: Row(children: [
                        MerchantLogo(name: m.name, url: m.logoUrl, size: 54),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.name, style: WText.bodyStrong),
                            if (m.description.isNotEmpty) Text(m.description, style: WText.small, maxLines: 2),
                            if (m.ratingCount > 0)
                              Row(children: [
                                const Icon(Icons.star_rounded, size: 15, color: WColors.coral),
                                Text(' ${m.ratingAvg.toStringAsFixed(1)}', style: WText.caption),
                              ]),
                          ]),
                        ),
                        const Icon(Icons.chevron_left_rounded),
                      ]),
                    );
                  },
                ),
        ),
      );
}

class ServiceBookingScreen extends StatefulWidget {
  const ServiceBookingScreen({super.key, required this.service, required this.provider});
  final HomeService service;
  final Merchant provider;
  @override
  State<ServiceBookingScreen> createState() => _ServiceBookingScreenState();
}

class _ServiceBookingScreenState extends State<ServiceBookingScreen> {
  final _desc = TextEditingController();
  final _place = PointValue();
  final List<String> _photos = [];
  DateTime _when = DateTime.now().add(const Duration(hours: 2));
  bool _uploading = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final a = app.selectedAddress;
    if (a != null) {
      _place
        ..point = LatLng(a.lat, a.lng)
        ..label = [a.label, a.details, if (a.landmark.isNotEmpty) 'قرب ${a.landmark}'].join(' - ');
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 5) return showError(context, 'الحد الأقصى 5 صور.');
    final img = await pickImage(context);
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      final url = await mediaApi.upload('bookings/${auth.userId}', img.bytes, ext: img.ext);
      setState(() => _photos.add(url));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(context: context, initialDate: _when, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (t == null) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _send() async {
    if (_place.point == null) return showError(context, 'حدّد مكان الخدمة.');
    if (_desc.text.trim().length < 5) return showError(context, 'اكتب وصف للمشكلة أو العمل المطلوب.');
    setState(() => _sending = true);
    final ok = await runAction(
      context,
      () => customerApi.bookService(
        serviceId: widget.service.id,
        providerId: widget.provider.id,
        addressText: _place.label,
        lat: _place.point!.latitude,
        lng: _place.point!.longitude,
        description: _desc.text.trim(),
        photoUrls: _photos,
        preferredTime: _when,
      ),
      success: 'انرسل طلبك لـ ${widget.provider.name}',
    );
    if (mounted) setState(() => _sending = false);
    if (ok && mounted) {
      Navigator.of(context)
        ..pop()
        ..pop();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${widget.service.name} · ${widget.provider.name}')),
        body: ListView(padding: const EdgeInsets.all(WSpace.page), children: [
          TextField(
            controller: _desc,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'شنو المشكلة أو العمل المطلوب؟', hintText: 'مثلاً: تسريب مي تحت مغسلة المطبخ'),
          ),
          PointField(title: 'مكان الخدمة', value: _place, kind: WMarkerKind.home, onChanged: () => setState(() {})),
          const SizedBox(height: 12),
          WCard(
            onTap: _pickTime,
            child: Row(children: [
              const Icon(Icons.event_rounded, color: WColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('الوقت المناسب', style: WText.caption),
                  Text('${dateAr(_when)} · ${timeAr(_when)}', style: WText.bodyStrong),
                ]),
              ),
              const Icon(Icons.chevron_left_rounded),
            ]),
          ),
          const SizedBox(height: 16),
          Text('صور (اختياري، حتى 5)', style: WText.caption),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final p in _photos)
              Stack(children: [
                WImage(p, width: 84, height: 84),
                PositionedDirectional(
                  top: 2,
                  end: 2,
                  child: InkWell(onTap: () => setState(() => _photos.remove(p)), child: const CircleAvatar(radius: 12, backgroundColor: WColors.navy, child: Icon(Icons.close, size: 14, color: WColors.white))),
                ),
              ]),
            InkWell(
              onTap: _uploading ? null : _addPhoto,
              borderRadius: WRadius.all(WRadius.md),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(borderRadius: WRadius.all(WRadius.md), border: Border.all(color: WColors.line, width: 1.5), color: WColors.white),
                child: _uploading ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.add_a_photo_outlined, color: WColors.inkMuted),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          Text('السعر يتفق عليه مع الفني بعد المعاينة، والدفع نقداً.', style: WText.small),
          const SizedBox(height: 12),
          WButton('أرسل الطلب', icon: Icons.send_rounded, onPressed: _uploading ? null : _send, loading: _sending),
        ]),
      );
}

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حجوزات الخدمات')),
        body: AsyncView<List<ServiceBooking>>(
          load: customerApi.myBookings,
          loading: const SkeletonList(),
          builder: (context, list, reload) => list.isEmpty
              ? const EmptyView(icon: Icons.home_repair_service_outlined, title: 'ما عندك حجوزات بعد')
              : RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(WSpace.page),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => BookingCard(booking: list[i], onChanged: reload),
                  ),
                ),
        ),
      );
}

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, required this.onChanged});
  final ServiceBooking booking;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final tone = switch (b.status) {
      BookingStatus.rejected || BookingStatus.cancelled => PillTone.danger,
      BookingStatus.completed => PillTone.success,
      _ => PillTone.accent,
    };
    return WCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${b.serviceName ?? 'خدمة'} · ${b.providerName ?? ''}', style: WText.bodyStrong)),
          StatusPill(b.status.label, tone: tone),
        ]),
        const SizedBox(height: 6),
        Text(b.description, style: WText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        InfoRow(icon: Icons.event_outlined, text: '${dateAr(b.preferredTime)} · ${timeAr(b.preferredTime)}'),
        if ((b.providerNote ?? '').isNotEmpty) ...[const SizedBox(height: 4), InfoRow(icon: Icons.chat_bubble_outline_rounded, text: b.providerNote!)],
        if (b.status == BookingStatus.accepted && (b.providerPhone ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          WButton('اتصل بالفني', kind: WButtonKind.secondary, icon: Icons.call_outlined, onPressed: () => callPhone(b.providerPhone!)),
        ],
        if (b.status == BookingStatus.requested || b.status == BookingStatus.accepted)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () async {
                if (await confirmDialog(context, title: 'إلغاء الحجز؟', confirm: 'إلغاء', danger: true) && context.mounted) {
                  if (await runAction(context, () => customerApi.cancelBooking(b.id), success: 'انلغى الحجز')) onChanged();
                }
              },
              child: Text('إلغاء', style: WText.button.copyWith(color: WColors.danger)),
            ),
          ),
      ]),
    );
  }
}
