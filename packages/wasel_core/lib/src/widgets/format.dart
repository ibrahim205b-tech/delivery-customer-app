import 'package:intl/intl.dart';

final _num = NumberFormat('#,##0', 'en');

/// 12500 -> "12,500 د.ع"
String iqd(int amount) => '${_num.format(amount)} د.ع';

const iraqiMonths = [
  'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
  'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
];

const weekdaysAr = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

String timeAr(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'ص' : 'م'}';
}

/// "اليوم 3:20 م" / "أمس ..." / "12 تشرين الثاني · 3:20 م"
String dateTimeAr(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  if (d == today) return 'اليوم ${timeAr(t)}';
  if (d == today.subtract(const Duration(days: 1))) return 'أمس ${timeAr(t)}';
  final y = t.year == now.year ? '' : ' ${t.year}';
  return '${t.day} ${iraqiMonths[t.month - 1]}$y · ${timeAr(t)}';
}

String dateAr(DateTime t) => '${weekdaysAr[t.weekday % 7]} ${t.day} ${iraqiMonths[t.month - 1]}';

String relativeAr(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'هسه';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
  return dateTimeAr(t);
}

String kmAr(double km) => km < 1 ? '${(km * 1000).round()} م' : '${km.toStringAsFixed(1)} كم';
