import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/basics.dart';

/// مستودع النسخ: كل بناء يُنشر كإصدار باسم build-<رقم التشغيل> وفيه ملفات APK.
const kReleasesRepo = 'ibrahim205b-tech/delivery-customer-app';

/// تحديث متاح: رقم البناء الجديد ورابط التنزيل
class AppUpdate {
  const AppUpdate({required this.build, required this.url});
  final int build;
  final String url;
}

/// يقارن رقم البناء الحالي بآخر إصدار منشور، ويرجع التحديث إذا كان أحدث.
/// يرجع null إذا كان التطبيق محدثاً أو تعذّر الفحص (لا يزعج الزبون بسبب خطأ شبكة).
Future<AppUpdate?> checkForUpdate(String apkName) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;
    final resp = await http
        .get(
          Uri.parse('https://api.github.com/repos/$kReleasesRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final match = RegExp(r'build-(\d+)').firstMatch(j['tag_name'] as String? ?? '');
    if (match == null) return null;
    final latest = int.parse(match.group(1)!);
    if (latest <= current) return null;
    final assets = (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
    final asset = assets.where((a) => a['name'] == apkName).firstOrNull;
    if (asset == null) return null;
    return AppUpdate(build: latest, url: asset['browser_download_url'] as String);
  } catch (_) {
    return null;
  }
}

/// ينزّل ملف التحديث إلى مجلد مؤقت، ويبلّغ بالنسبة (0..1) أثناء التنزيل.
Future<File> downloadUpdate(AppUpdate u, void Function(double) onProgress) async {
  final client = http.Client();
  try {
    final resp = await client.send(http.Request('GET', Uri.parse(u.url)));
    if (resp.statusCode != 200) throw Exception('تعذّر تنزيل التحديث (${resp.statusCode})');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/wasel-update.apk');
    final sink = file.openWrite();
    final total = resp.contentLength ?? 0;
    var got = 0;
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got / total);
    }
    await sink.close();
    return file;
  } finally {
    client.close();
  }
}

/// يفتح ملف APK بمثبّت أندرويد. قد يطلب الجهاز إذن "التثبيت من مصدر غير معروف" مرة واحدة.
Future<void> installUpdate(File apk) async {
  final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
  if (r.type != ResultType.done) throw Exception('تعذّر فتح المثبّت: ${r.message}');
}

/// بوابة التحديث: عند فتح التطبيق تفحص وجود نسخة أحدث، وتعرض رسالة "تحديث" تنزّل وتثبّت.
/// تعمل مرة واحدة لكل تشغيل للتطبيق، وعلى أندرويد فقط.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.apkName, required this.child});
  /// اسم ملف APK لهذا التطبيق في الإصدار، مثل wasel-customer.apk
  final String apkName;
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

bool _updateChecked = false;

class _UpdateGateState extends State<UpdateGate> {
  @override
  void initState() {
    super.initState();
    if (_updateChecked || kIsWeb || !Platform.isAndroid) return;
    _updateChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final u = await checkForUpdate(widget.apkName);
    if (u == null || !mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('يتوفر تحديث'),
        content: Text('نسخة ${u.build} جاهزة. حدّث الآن للحصول على آخر التحسينات والإصلاحات.\n\nقد يطلب الجهاز إذن التثبيت من مصدر خارجي مرة واحدة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لاحقاً')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تحديث')),
        ],
      ),
    );
    if (accept != true || !mounted) return;
    final progress = ValueNotifier<double?>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('جارٍ تنزيل التحديث'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, __) => LinearProgressIndicator(value: v),
        ),
      ),
    );
    try {
      final file = await downloadUpdate(u, (p) => progress.value = p);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await installUpdate(file);
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        showError(context, e);
      }
    } finally {
      progress.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
