import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import 'config.dart';

/// أي تطبيق تجي منه رسالة الدعم
enum SupportApp {
  customer('customer', 'مستهلك'),
  merchant('merchant', 'تاجر'),
  driver('driver', 'سائق');

  const SupportApp(this.value, this.label);
  final String value;
  final String label;
  static SupportApp parse(String? v) => values.firstWhere((e) => e.value == v, orElse: () => customer);
}

class SupportThread {
  SupportThread({
    required this.id,
    required this.userId,
    required this.app,
    required this.isOpen,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadForAdmin,
    required this.unreadForUser,
    this.userName,
    this.userPhone,
  });
  final String id;
  final String userId;
  final SupportApp app;
  final bool isOpen;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadForAdmin;
  final int unreadForUser;
  final String? userName;
  final String? userPhone;

  factory SupportThread.fromJson(Json j) {
    final u = j['users'] as Json?;
    return SupportThread(
      id: j['id'] as String,
      userId: j['user_id'] as String,
      app: SupportApp.parse(j['app'] as String?),
      isOpen: (j['status'] as String?) != 'closed',
      lastMessage: (j['last_message'] as String?) ?? '',
      lastMessageAt: DateTime.parse(j['last_message_at'] as String).toLocal(),
      unreadForAdmin: (j['unread_for_admin'] as num?)?.toInt() ?? 0,
      unreadForUser: (j['unread_for_user'] as num?)?.toInt() ?? 0,
      userName: u?['full_name'] as String?,
      userPhone: u?['phone'] as String?,
    );
  }
}

class SupportMessage {
  SupportMessage({required this.id, required this.threadId, required this.fromAdmin, required this.body, required this.createdAt, this.orderCode});
  final int id;
  final String threadId;
  final bool fromAdmin;
  final String body;
  final String? orderCode;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Json j) => SupportMessage(
        id: (j['id'] as num).toInt(),
        threadId: j['thread_id'] as String,
        fromAdmin: j['from_admin'] as bool? ?? false,
        body: j['body'] as String,
        orderCode: j['order_code'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

/// أرقام التواصل المضبوطة من تطبيق الإدارة (الإعداد support)
class SupportContacts {
  const SupportContacts({this.phone = '', this.whatsapp = ''});
  final String phone;
  final String whatsapp;
  bool get hasPhone => phone.trim().isNotEmpty;
  bool get hasWhatsapp => whatsappNumber != null;

  /// رقم واتساب بصيغة دولية بدون + (مثال 9647701234567). إذا ما مضبوط نستخدم رقم الهاتف.
  String? get whatsappNumber => whatsappIntl(whatsapp.trim().isNotEmpty ? whatsapp : phone);

  factory SupportContacts.fromJson(Object? v) {
    final m = v is Map ? v : const {};
    return SupportContacts(phone: '${m['phone'] ?? ''}', whatsapp: '${m['whatsapp'] ?? ''}');
  }
}

/// يحوّل رقم عراقي أو دولي لصيغة wa.me. يرجّع null إذا الرقم غير صالح.
String? whatsappIntl(String raw) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  var t = raw;
  for (var i = 0; i < 10; i++) {
    t = t.replaceAll(arabicDigits[i], '$i');
  }
  var d = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0') && d.length == 11) d = '964${d.substring(1)}';
  if (d.length == 10 && d.startsWith('7')) d = '964$d';
  if (d.length < 10 || d.length > 15) return null;
  return d;
}

Uri whatsappUri(String number, {String? text}) => Uri.parse('https://wa.me/$number${text == null || text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');

Future<bool> openWhatsapp(String number, {String? text}) => launchUrl(whatsappUri(number, text: text), mode: LaunchMode.externalApplication);

class SupportApi {
  const SupportApi();

  String get _uid => db.auth.currentUser!.id;
  static const _threadSelect = '*, users(full_name, phone)';

  Future<SupportContacts> contacts() async {
    final r = await db.from('app_settings').select('value').eq('key', 'support').maybeSingle();
    return SupportContacts.fromJson(r?['value']);
  }

  // ---------- المستخدم ----------
  Future<SupportThread?> myThread(SupportApp app) async {
    final r = await db.from('support_threads').select().eq('user_id', _uid).eq('app', app.value).maybeSingle();
    return r == null ? null : SupportThread.fromJson(r);
  }

  /// يراقب محادثة المستخدم (تتغير عند وصول رد أو تغيّر عداد غير المقروء)
  Stream<SupportThread?> watchMyThread(SupportApp app) =>
      db.from('support_threads').stream(primaryKey: ['id']).eq('user_id', _uid).map((rows) => rows.where((r) => r['app'] == app.value).map(SupportThread.fromJson).firstOrNull);

  Future<SupportMessage> send(SupportApp app, String body, {String? orderCode}) async {
    final r = await db.rpc('support_send', params: {'p_app': app.value, 'p_body': body, 'p_order_code': orderCode});
    return SupportMessage.fromJson(r as Json);
  }

  // ---------- مشترك ----------
  Stream<List<SupportMessage>> watchMessages(String threadId) =>
      db.from('support_messages').stream(primaryKey: ['id']).eq('thread_id', threadId).order('id', ascending: true).map((rows) => rows.map(SupportMessage.fromJson).toList());

  Future<void> markRead(String threadId) => db.rpc('support_mark_read', params: {'p_thread': threadId});

  // ---------- الإدارة ----------
  /// كل المحادثات، الأحدث أولاً. الـ stream ما يدعم join، لذلك نجيب الأسماء بطلب منفصل.
  Stream<List<SupportThread>> watchAllThreads() => db.from('support_threads').stream(primaryKey: ['id']).order('last_message_at').limit(200).asyncMap((rows) async {
        if (rows.isEmpty) return <SupportThread>[];
        final r = await db.from('support_threads').select(_threadSelect).inFilter('id', rows.map((e) => e['id']).toList()).order('last_message_at', ascending: false);
        return r.map(SupportThread.fromJson).toList();
      });

  Future<SupportMessage> reply(String threadId, String body) async {
    final r = await db.rpc('support_reply', params: {'p_thread': threadId, 'p_body': body});
    return SupportMessage.fromJson(r as Json);
  }

  Future<void> setStatus(String threadId, {required bool open}) => db.rpc('support_set_status', params: {'p_thread': threadId, 'p_status': open ? 'open' : 'closed'});
}

const supportApi = SupportApi();
