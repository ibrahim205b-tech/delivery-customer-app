import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import 'errand.dart';
import 'home_services.dart';
import 'order_tracking.dart';
import 'rides.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void dispose() {
    customerApi.markAllRead().catchError((_) {});
    super.dispose();
  }

  void _open(AppNotification n) {
    final id = n.data['id'] as String?;
    if (id == null) return;
    final Widget? page = switch (n.data['type']) {
      'order' => OrderTrackingScreen(orderId: id),
      'ride' => RideTrackingScreen(rideId: id),
      'task' => ErrandTrackingScreen(taskId: id),
      'booking' => const MyBookingsScreen(),
      _ => null,
    };
    if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الإشعارات')),
        body: StreamBuilder<List<AppNotification>>(
          stream: customerApi.watchNotifications(),
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!);
            if (!s.hasData) return const SkeletonList(itemHeight: 64);
            final list = s.data!;
            if (list.isEmpty) return const EmptyView(icon: Icons.notifications_none_rounded, title: 'ما اكو إشعارات بعد');
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(indent: 72),
              itemBuilder: (context, i) {
                final n = list[i];
                return ListTile(
                  onTap: () => _open(n),
                  leading: CircleAvatar(
                    backgroundColor: n.isRead ? WColors.surfaceAlt : WColors.limeSoft,
                    child: Icon(switch (n.data['type']) {
                      'ride' => Icons.local_taxi_rounded,
                      'task' => Icons.inventory_2_rounded,
                      'booking' => Icons.home_repair_service_rounded,
                      _ => Icons.receipt_long_rounded,
                    }, color: n.isRead ? WColors.inkMuted : WColors.blue, size: 20),
                  ),
                  title: Text(n.title, style: n.isRead ? WText.body : WText.bodyStrong),
                  subtitle: Text([if (n.body.isNotEmpty) n.body, relativeAr(n.createdAt)].join(' · ')),
                );
              },
            );
          },
        ),
      );
}
