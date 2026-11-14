import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// قنوات الإشعارات. كل قناة لها صوت واهتزاز، والمستخدم يگدر يتحكم بيها من إعدادات أندرويد.
enum WChannel {
  orders('wasel_orders', 'الطلبات الجديدة', 'تنبيه بصوت عند وصول طلب أو مهمة جديدة'),
  updates('wasel_updates', 'تحديثات الطلب', 'حالة طلبك ووصول المندوب'),
  support('wasel_support', 'رسائل الدعم', 'رسائل الدعم والردود');

  const WChannel(this.id, this.title, this.description);
  final String id;
  final String title;
  final String description;
}

/// إشعارات النظام مع صوت (تظهر بشريط الإشعارات حتى لو التطبيق بالخلفية ما دام شغّال).
///
/// حدود: إذا انسكر التطبيق بالكامل ما توصل إشعارات؛ هذا يحتاج Firebase Cloud Messaging.
class WaselNotifier {
  WaselNotifier._();
  static final instance = WaselNotifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 1;

  /// يُستدعى مرة وحدة عند تشغيل التطبيق. ما يرمي أخطاء (الإشعارات ميزة إضافية).
  Future<void> init() async {
    if (_ready || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_wasel')));
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      for (final c in WChannel.values) {
        await android?.createNotificationChannel(AndroidNotificationChannel(
          c.id,
          c.title,
          description: c.description,
          importance: c == WChannel.updates ? Importance.defaultImportance : Importance.max,
        ));
      }
      _ready = true;
    } catch (e) {
      debugPrint('notifier init failed: $e');
    }
  }

  /// طلب إذن الإشعارات (أندرويد 13+). يُستدعى بعد تسجيل الدخول حتى يفهم المستخدم السبب.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// يعرض إشعار بصوت. على الويب/الاختبار يكتفي باهتزاز خفيف.
  Future<void> show(String title, String body, {WChannel channel = WChannel.orders}) async {
    HapticFeedback.heavyImpact();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.title,
            channelDescription: channel.description,
            icon: 'ic_stat_wasel',
            importance: channel == WChannel.updates ? Importance.defaultImportance : Importance.max,
            priority: channel == WChannel.updates ? Priority.defaultPriority : Priority.high,
            color: const Color(0xFF17191B),
            category: AndroidNotificationCategory.message,
          ),
        ),
      );
    } catch (e) {
      debugPrint('notify failed: $e');
    }
  }
}

final notifier = WaselNotifier.instance;
