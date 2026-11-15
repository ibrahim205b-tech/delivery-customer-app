import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// هل نتتبع موقع السائق الآن؟ فقط عندما يكون متاحاً للطلبات، أو عنده مهمة/رحلة جارية.
/// خارج العمل وبدون مهمة = لا تتبع ولا إرسال، حتى لو التطبيق مفتوح.
bool shouldTrack({required bool available, required bool hasJob}) => available || hasJob;

/// نرسل الموقع كحد أدنى كل 15 ثانية، حتى لو الستريم يعطي قيم أسرع (حماية للبطارية والشبكة).
bool shouldSend(DateTime? last, DateTime now, {Duration every = const Duration(seconds: 15)}) => last == null || now.difference(last) >= every;

/// يرسل قيمة كحد أدنى كل [every]. القيمة الممنوعة تُحفظ، وتُرسل آخر قيمة عند انتهاء الفترة.
/// هكذا آخر موقع يصل حتى لو توقف السائق بعد حركة قصيرة.
class ThrottledSender<T> {
  ThrottledSender({required this.send, this.every = const Duration(seconds: 15)});
  final Future<void> Function(T value) send;
  final Duration every;
  Timer? _timer;
  DateTime? _lastSent;
  T? _pending;

  bool get hasPending => _pending != null;

  void offer(T value) {
    final now = DateTime.now();
    if (shouldSend(_lastSent, now, every: every)) {
      _timer?.cancel();
      _timer = null;
      _pending = null;
      unawaited(_fire(value));
      return;
    }
    _pending = value;
    _timer ??= Timer(every - now.difference(_lastSent!), () {
      _timer = null;
      final p = _pending;
      _pending = null;
      if (p != null) unawaited(_fire(p));
    });
  }

  Future<void> _fire(T value) async {
    _lastSent = DateTime.now();
    try {
      await send(value);
    } catch (_) {
      // انقطع النت أو فشل الإرسال: الموقع الجاي يحاول من جديد
      _lastSent = null;
    }
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _lastSent = null;
  }
}

/// تتبع موقع السائق أثناء العمل، ومنه الخلفية.
/// على أندرويد يعمل كخدمة مقدمة (Foreground Service) بإشعار دائم يوضح أن الموقع يُرسل،
/// وتتوقف الخدمة عند stop(). لا يبدأ أبداً بدون استدعاء start() من شاشة السائق بعد الشرح.
class DriverTracker {
  StreamSubscription<Position>? _sub;
  ThrottledSender<LatLng>? _sender;
  LatLng? lastPosition;

  bool get running => _sub != null;

  /// يبدأ التتبع. يرجع رسالة خطأ عربية إذا الصلاحية غير متاحة، أو null عند النجاح.
  Future<String?> start({required Future<void> Function(LatLng p) onSend, void Function(LatLng p)? onPosition}) async {
    if (_sub != null) return null;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return 'لازم تسمح للتطبيق بالموقع حتى تستلم مهام.';
    }
    _sender = ThrottledSender<LatLng>(send: onSend);
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: const Duration(seconds: 15),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'واصل شريك',
        notificationText: 'نرسل موقعك للزبون أثناء العمل',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) {
        final ll = LatLng(p.latitude, p.longitude);
        lastPosition = ll;
        onPosition?.call(ll);
        _sender?.offer(ll);
      },
      onError: (_) {},
    );
    return null;
  }

  Future<void> stop() async {
    _sender?.cancel();
    _sender = null;
    await _sub?.cancel();
    _sub = null;
  }
}

/// يطلب صلاحية الموقع الكاملة (طوال الوقت) لاستمرار التتبع بالخلفية.
/// يرجع true إذا صارت الصلاحية "طوال الوقت". أندرويد يفرض أن تُطلب الخلفية بعد الاستخدام الفعلي.
Future<bool> requestAlwaysLocation() async {
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.whileInUse) p = await Geolocator.requestPermission();
  return p == LocationPermission.always;
}

/// هل صلاحية الموقع الكاملة مفعّلة الآن؟
Future<bool> hasAlwaysLocation() async => (await Geolocator.checkPermission()) == LocationPermission.always;
