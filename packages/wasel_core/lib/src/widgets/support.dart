import 'dart:async';

import 'package:flutter/material.dart';

import '../services/location.dart';
import '../services/notifier.dart';
import '../services/support.dart';
import '../theme/tokens.dart';
import 'basics.dart';
import 'format.dart';

/// نافذة "تواصل مع الدعم": مراسلة داخل التطبيق، واتساب، أو اتصال.
/// واتساب والاتصال يظهرون فقط إذا الإدارة ضابطة الرقم.
Future<void> showSupportSheet(BuildContext context, {required SupportApp app, String? orderCode}) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: WColors.paper,
      builder: (_) => _SupportSheet(app: app, orderCode: orderCode),
    );

class _SupportSheet extends StatelessWidget {
  const _SupportSheet({required this.app, this.orderCode});
  final SupportApp app;
  final String? orderCode;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, WSpace.page),
          child: FutureBuilder<SupportContacts>(
            future: supportApi.contacts(),
            builder: (context, s) {
              final c = s.data ?? const SupportContacts();
              final waText = orderCode == null ? 'مرحبا دعم واصل،' : 'مرحبا دعم واصل، استفسار عن الطلب $orderCode';
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('تواصل مع دعم واصل', style: WText.h2),
                const SizedBox(height: 4),
                Text(orderCode == null ? 'اختار الطريقة الأنسب إلك' : 'بخصوص الطلب $orderCode', style: WText.small),
                const SizedBox(height: 16),
                _option(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'مراسلة داخل التطبيق',
                  subtitle: 'الرد يوصلك هنا مع إشعار',
                  dark: true,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => SupportChatScreen(app: app, orderCode: orderCode)));
                  },
                ),
                if (s.connectionState != ConnectionState.done)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                else ...[
                  if (c.hasWhatsapp) ...[
                    const SizedBox(height: 10),
                    _option(
                      icon: Icons.forum_outlined,
                      title: 'واتساب',
                      subtitle: 'محادثة مباشرة مع الدعم',
                      onTap: () async {
                        Navigator.pop(context);
                        final ok = await openWhatsapp(c.whatsappNumber!, text: waText);
                        if (!ok && context.mounted) showError(context, 'ما گدرنا نفتح واتساب. تأكد إنه مثبّت.');
                      },
                    ),
                  ],
                  if (c.hasPhone) ...[
                    const SizedBox(height: 10),
                    _option(
                      icon: Icons.call_outlined,
                      title: 'اتصال',
                      subtitle: c.phone,
                      onTap: () {
                        Navigator.pop(context);
                        callPhone(c.phone);
                      },
                    ),
                  ],
                ],
              ]);
            },
          ),
        ),
      );

  Widget _option({required IconData icon, required String title, required String subtitle, required VoidCallback onTap, bool dark = false}) => WCard(
        onTap: onTap,
        color: dark ? WColors.night : WColors.surface,
        borderColor: dark ? WColors.night : WColors.line,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: dark ? WColors.lime : WColors.paper, borderRadius: WRadius.all(12)),
            child: Icon(icon, color: dark ? WColors.ink : WColors.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: WText.bodyStrong.copyWith(color: dark ? WColors.white : WColors.fg)),
              Text(subtitle, style: WText.caption.copyWith(color: dark ? WColors.inkFaint : WColors.inkMuted)),
            ]),
          ),
          Icon(Icons.chevron_left_rounded, color: dark ? WColors.white : WColors.inkMuted),
        ]),
      );
}

/// محادثة الدعم.
/// - للمستخدم: [SupportChatScreen] مع [app] (المحادثة تنخلق مع أول رسالة).
/// - للإدارة: [SupportChatScreen.admin] مع المحادثة.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key, required SupportApp this.app, this.orderCode}) : thread = null;
  const SupportChatScreen.admin({super.key, required SupportThread this.thread})
      : app = null,
        orderCode = null;

  final SupportApp? app;
  final SupportThread? thread;
  final String? orderCode;
  bool get isAdmin => thread != null;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _threadId;
  Stream<List<SupportMessage>>? _messages;
  StreamSubscription<SupportThread?>? _threadSub;
  bool _sending = false;
  String? _orderCode;
  Object? _error;
  int _lastCount = 0;
  late bool _open = widget.thread?.isOpen ?? true;

  @override
  void initState() {
    super.initState();
    _orderCode = widget.orderCode;
    if (widget.isAdmin) {
      _attach(widget.thread!.id);
    } else {
      // المحادثة ممكن ما تكون موجودة بعد؛ نراقبها وأول ما تنخلق نربط الرسائل
      _threadSub = supportApi.watchMyThread(widget.app!).listen((t) {
        if (t != null && _threadId != t.id) _attach(t.id);
        if (t != null && t.unreadForUser > 0) supportApi.markRead(t.id).ignore();
      }, onError: (Object e) {
        if (mounted) setState(() => _error = e);
      });
    }
  }

  void _attach(String id) {
    setState(() {
      _threadId = id;
      _messages = supportApi.watchMessages(id);
    });
    supportApi.markRead(id).ignore();
  }

  @override
  void dispose() {
    _threadSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (widget.isAdmin) {
        await supportApi.reply(widget.thread!.id, text);
      } else {
        await supportApi.send(widget.app!, text, orderCode: _orderCode);
        _orderCode = null; // رقم الطلب يُرفق بأول رسالة فقط
      }
      _input.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: WDurations.base, curve: WDurations.curve);
      });

  @override
  Widget build(BuildContext context) {
    final t = widget.thread;
    return Scaffold(
      backgroundColor: WColors.paper,
      appBar: AppBar(
        titleSpacing: 0,
        title: widget.isAdmin
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t!.userName?.isNotEmpty == true ? t.userName! : 'مستخدم', style: WText.h3),
                Text('${t.app.label}${t.userPhone == null ? '' : ' · ${t.userPhone}'}', style: WText.caption),
              ])
            : Row(children: [
                const WaselMark(size: 28),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('دعم واصل', style: WText.h3),
                  Text('نرد عليك بأقرب وقت', style: WText.caption),
                ]),
              ]),
        actions: [
          if (widget.isAdmin && t!.userPhone != null) IconButton(tooltip: 'اتصال', onPressed: () => callPhone(t.userPhone!), icon: const Icon(Icons.call_outlined)),
          if (widget.isAdmin && t!.userPhone != null && whatsappIntl(t.userPhone!) != null)
            IconButton(tooltip: 'واتساب', onPressed: () => openWhatsapp(whatsappIntl(t.userPhone!)!), icon: const Icon(Icons.forum_outlined)),
          if (widget.isAdmin)
            PopupMenuButton<bool>(
              tooltip: 'المزيد',
              onSelected: (open) async {
                if (await runAction(context, () => supportApi.setStatus(t!.id, open: open), success: open ? 'انفتحت المحادثة' : 'انغلقت المحادثة')) {
                  setState(() => _open = open);
                }
              },
              itemBuilder: (_) => [
                if (_open) const PopupMenuItem(value: false, child: Text('إغلاق المحادثة (تم الحل)')) else const PopupMenuItem(value: true, child: Text('إعادة فتح المحادثة')),
              ],
            ),
        ],
      ),
      body: Column(children: [
        Expanded(child: _body()),
        _composer(),
      ]),
    );
  }

  Widget _body() {
    if (_error != null) return ErrorView(error: _error!, onRetry: () => setState(() => _error = null));
    if (_messages == null) {
      return EmptyView(
        icon: Icons.support_agent_rounded,
        title: 'شلون نگدر نساعدك؟',
        message: _orderCode == null ? 'اكتب رسالتك وفريق واصل يرد عليك هنا.' : 'رسالتك راح توصل ويا رقم الطلب $_orderCode.',
      );
    }
    return StreamBuilder<List<SupportMessage>>(
      stream: _messages,
      builder: (context, s) {
        if (s.hasError) return ErrorView(error: s.error!, onRetry: () => _attach(_threadId!));
        if (!s.hasData) return const LoadingView();
        final list = s.data!;
        if (list.length != _lastCount) {
          _lastCount = list.length;
          _scrollToEnd();
          if (_threadId != null && list.isNotEmpty) supportApi.markRead(_threadId!).ignore();
        }
        if (list.isEmpty) return const EmptyView(icon: Icons.support_agent_rounded, title: 'ما اكو رسائل بعد');
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(WSpace.page, 12, WSpace.page, 12),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final m = list[i];
            final mine = m.fromAdmin == widget.isAdmin;
            final newDay = i == 0 || list[i - 1].createdAt.day != m.createdAt.day;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (newDay)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: Text(dateAr(m.createdAt), style: WText.caption)),
                ),
              _Bubble(message: m, mine: mine),
            ]);
          },
        );
      },
    );
  }

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(color: WColors.surface, border: Border(top: BorderSide(color: WColors.line))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_orderCode != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: StatusPill('بخصوص الطلب $_orderCode', tone: PillTone.info),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'اكتب رسالتك…', counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'إرسال',
                onTap: _send,
                excludeSemantics: true,
                child: Material(
                  color: WColors.lime,
                  borderRadius: WRadius.all(WRadius.md),
                  child: InkWell(
                    borderRadius: WRadius.all(WRadius.md),
                    onTap: _send,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: _sending
                          ? Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2, color: WColors.ink))
                          : const Icon(Icons.send_rounded, color: WColors.ink, textDirection: TextDirection.rtl),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final SupportMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return Align(
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: mine ? WColors.night : WColors.surface,
            border: mine ? null : Border.all(color: WColors.line),
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(16),
              topEnd: const Radius.circular(16),
              bottomStart: Radius.circular(mine ? 4 : 16),
              bottomEnd: Radius.circular(mine ? 16 : 4),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (!mine && m.fromAdmin) Text('دعم واصل', style: WText.label.copyWith(color: WColors.link)),
            if (m.orderCode != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('الطلب ${m.orderCode}', style: WText.label.copyWith(color: mine ? WColors.lime : WColors.link)),
              ),
            Text(m.body, style: WText.body.copyWith(color: mine ? WColors.white : WColors.fg)),
            const SizedBox(height: 2),
            Text(timeAr(m.createdAt), style: WText.caption.copyWith(fontSize: 11, color: mine ? WColors.inkFaint : WColors.inkMuted)),
          ]),
        ),
      ),
    );
  }
}

/// زر/بلاطة "الدعم" مع عداد الردود غير المقروءة
class SupportTile extends StatelessWidget {
  const SupportTile({super.key, required this.app});
  final SupportApp app;

  @override
  Widget build(BuildContext context) => StreamBuilder<SupportThread?>(
        stream: supportApi.watchMyThread(app),
        builder: (context, s) {
          final unread = s.data?.unreadForUser ?? 0;
          return ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('الدعم والمساعدة'),
            subtitle: Text(unread > 0 ? 'عندك $unread رد جديد' : 'مراسلة، واتساب، أو اتصال'),
            trailing: unread > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(8)),
                    child: Text('$unread', style: WText.label.copyWith(color: WColors.ink)),
                  )
                : const Icon(Icons.chevron_left_rounded),
            onTap: () => showSupportSheet(context, app: app),
          );
        },
      );
}

/// أزرار واتساب/اتصال مباشرة (لشاشة الحساب الموقوف، حيث المراسلة داخل التطبيق غير متاحة)
class SupportContactButtons extends StatelessWidget {
  const SupportContactButtons({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<SupportContacts>(
        future: supportApi.contacts(),
        builder: (context, s) {
          final c = s.data;
          if (c == null || (!c.hasWhatsapp && !c.hasPhone)) return const SizedBox.shrink();
          return Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
            if (c.hasWhatsapp)
              WButton('واتساب الدعم', icon: Icons.forum_outlined, expand: false, onPressed: () => openWhatsapp(c.whatsappNumber!, text: 'مرحبا دعم واصل، حسابي موقوف')),
            if (c.hasPhone) WButton('اتصال', icon: Icons.call_outlined, kind: WButtonKind.secondary, expand: false, onPressed: () => callPhone(c.phone)),
          ]);
        },
      );
}

/// زر الدعم بشريط العنوان مع شارة الردود غير المقروءة.
/// يشغّل إشعار بصوت عند وصول رد جديد من الدعم (للتاجر والسائق).
class SupportIconButton extends StatefulWidget {
  const SupportIconButton({super.key, required this.app, this.color});
  final SupportApp app;
  final Color? color;
  @override
  State<SupportIconButton> createState() => _SupportIconButtonState();
}

class _SupportIconButtonState extends State<SupportIconButton> {
  StreamSubscription<SupportThread?>? _sub;
  int _unread = 0;
  int? _last;

  @override
  void initState() {
    super.initState();
    _sub = supportApi.watchMyThread(widget.app).listen((t) {
      final n = t?.unreadForUser ?? 0;
      if (_last != null && n > _last!) notifier.show('رد من دعم واصل', t!.lastMessage, channel: WChannel.support);
      _last = n;
      if (mounted) setState(() => _unread = n);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'الدعم',
        onPressed: () => showSupportSheet(context, app: widget.app),
        icon: Badge(
          isLabelVisible: _unread > 0,
          label: Text('$_unread'),
          backgroundColor: WColors.lime,
          textColor: WColors.ink,
          child: Icon(Icons.support_agent_rounded, color: widget.color ?? WColors.fg),
        ),
      );
}
