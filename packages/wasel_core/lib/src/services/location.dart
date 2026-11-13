import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// موقع افتراضي (وسط بغداد) يُستخدم فقط لتوسيط الخريطة إذا الموقع غير متاح.
const kDefaultCenter = LatLng(33.3152, 44.3661);

class LocationResult {
  final LatLng? position;
  final String? error;
  const LocationResult(this.position, this.error);
}

/// يطلب الصلاحية ويرجع الموقع الحالي، أو رسالة عربية توضح السبب.
Future<LocationResult> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult(null, 'خدمة الموقع مطفية. شغّل GPS وحاول مرة ثانية.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return const LocationResult(null, 'لازم تسمح للتطبيق يوصل لموقعك.');
    if (perm == LocationPermission.deniedForever) {
      return const LocationResult(null, 'صلاحية الموقع مرفوضة. فعّلها من إعدادات الموبايل.');
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return LocationResult(LatLng(p.latitude, p.longitude), null);
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return LocationResult(LatLng(last.latitude, last.longitude), null);
    return const LocationResult(null, 'تعذّر تحديد موقعك. حاول بمكان مفتوح.');
  }
}

/// المسافة بالكيلومتر (نفس معادلة الخادم).
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// يفتح تطبيق الخرائط بالموبايل على نقطة معينة (للسائق).
Future<void> openInMaps(double lat, double lng, {String? label}) async {
  final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label ?? 'الموقع')})');
  if (await canLaunchUrl(geo)) {
    await launchUrl(geo);
    return;
  }
  await launchUrl(Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng'),
      mode: LaunchMode.externalApplication);
}

Future<void> callPhone(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

/// يفتح واتساب برسالة جاهزة والمستخدم يختار لمن يرسلها
Future<bool> shareViaWhatsapp(String text) =>
    launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);

/// يفتح رابط ويب بالمتصفح
Future<bool> openWebLink(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// رابط موقع على الخريطة يفتح بأي جهاز
String mapLinkFor(double lat, double lng) => 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng';
