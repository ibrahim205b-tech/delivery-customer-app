import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import 'errand.dart';
import 'home_services.dart';
import 'order_tracking.dart';
import 'rides.dart';

/// "طلباتي": كل أنواع الطلبات بتبويبات
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('طلباتي'),
            bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              Tab(text: 'المحلات'),
              Tab(text: 'الرحلات'),
              Tab(text: 'التوصيل'),
              Tab(text: 'خدمات البيت'),
            ]),
          ),
          body: const TabBarView(children: [_StoreOrders(), _Rides(), _Errands(), _Bookings()]),
        ),
      );
}

PillTone _tone(bool active, bool cancelled) => cancelled ? PillTone.danger : (active ? PillTone.accent : PillTone.success);

class _StoreOrders extends StatelessWidget {
  const _StoreOrders();
  @override
  Widget build(BuildContext context) => AsyncView<List<Order>>(
        load: () => customerApi.myOrders(),
        loading: const SkeletonList(),
        builder: (context, list, reload) => RefreshIndicator(
          onRefresh: reload,
          child: list.isEmpty
              ? ListView(children: const [EmptyView(icon: Icons.receipt_long_outlined, title: 'ما عندك طلبات بعد', message: 'أول طلب تسويه من أي محل يطلع هنا.')])
              : ListView.separated(
                  padding: const EdgeInsets.all(WSpace.page),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final o = list[i];
                    return WCard(
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: o.id)));
                        reload();
                      },
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          MerchantLogo(name: o.merchantName ?? '', url: o.merchantLogo, size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(o.merchantName ?? '', style: WText.bodyStrong),
                              Text('${o.code} · ${dateTimeAr(o.createdAt)}', style: WText.caption),
                            ]),
                          ),
                          StatusPill(o.status.label, tone: _tone(o.status.isActive, o.status == OrderStatus.cancelled)),
                        ]),
                        const SizedBox(height: 10),
                        Text(o.itemsSummary, style: WText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Row(children: [
                          Text(iqd(o.total), style: WText.price),
                          const Spacer(),
                          Text(o.status.isActive ? 'تتبع الطلب' : 'التفاصيل', style: WText.caption.copyWith(color: WColors.coralDeep, fontWeight: FontWeight.w600)),
                          const Icon(Icons.chevron_left_rounded, size: 18, color: WColors.coralDeep),
                        ]),
                      ]),
                    );
                  },
                ),
        ),
      );
}

class _Rides extends StatelessWidget {
  const _Rides();
  @override
  Widget build(BuildContext context) => AsyncView<List<Ride>>(
        load: customerApi.myRides,
        loading: const SkeletonList(),
        builder: (context, list, reload) => RefreshIndicator(
          onRefresh: reload,
          child: list.isEmpty
              ? ListView(children: const [EmptyView(icon: Icons.local_taxi_outlined, title: 'ما عندك رحلات بعد')])
              : ListView.separated(
                  padding: const EdgeInsets.all(WSpace.page),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = list[i];
                    return WCard(
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: r.id)));
                        reload();
                      },
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: WColors.surfaceAlt,
                          child: Icon(r.vehicle == VehicleType.tuktuk ? Icons.electric_rickshaw_rounded : Icons.local_taxi_rounded, color: WColors.navy),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r.pickupText} ← ${r.dropoffText}', style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('${r.vehicle.label} · ${dateTimeAr(r.createdAt)} · ${iqd(r.fare)}', style: WText.caption),
                          ]),
                        ),
                        StatusPill(r.status.label, tone: _tone(r.status.isActive, r.status == RideStatus.cancelled)),
                      ]),
                    );
                  },
                ),
        ),
      );
}

class _Errands extends StatelessWidget {
  const _Errands();
  @override
  Widget build(BuildContext context) => AsyncView<List<DeliveryTask>>(
        load: customerApi.myErrands,
        loading: const SkeletonList(),
        builder: (context, list, reload) => RefreshIndicator(
          onRefresh: reload,
          child: list.isEmpty
              ? ListView(children: const [EmptyView(icon: Icons.inventory_2_outlined, title: 'ما عندك طلبات توصيل بعد')])
              : ListView.separated(
                  padding: const EdgeInsets.all(WSpace.page),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final t = list[i];
                    return WCard(
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => ErrandTrackingScreen(taskId: t.id)));
                        reload();
                      },
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: WColors.surfaceAlt,
                          child: Icon(t.kind == TaskKind.courier ? Icons.delivery_dining_rounded : Icons.inventory_2_rounded, color: WColors.navy),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.description, style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('${t.kind.label} · ${dateTimeAr(t.createdAt)} · ${iqd(t.fee)}', style: WText.caption),
                          ]),
                        ),
                        StatusPill(t.status.label, tone: _tone(t.status.isActive, t.status == TaskStatus.cancelled)),
                      ]),
                    );
                  },
                ),
        ),
      );
}

class _Bookings extends StatelessWidget {
  const _Bookings();
  @override
  Widget build(BuildContext context) => AsyncView<List<ServiceBooking>>(
        load: customerApi.myBookings,
        loading: const SkeletonList(),
        builder: (context, list, reload) => RefreshIndicator(
          onRefresh: reload,
          child: list.isEmpty
              ? ListView(children: const [EmptyView(icon: Icons.home_repair_service_outlined, title: 'ما عندك حجوزات خدمات بعد')])
              : ListView.separated(
                  padding: const EdgeInsets.all(WSpace.page),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => BookingCard(booking: list[i], onChanged: reload),
                ),
        ),
      );
}
