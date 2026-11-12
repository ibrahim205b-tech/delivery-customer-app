import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// يراقب رسائل الدعم الجديدة على مستوى التطبيق كله: صوت + عداد.
class SupportInboxWatcher extends ChangeNotifier {
  SupportInboxWatcher._();
  static final instance = SupportInboxWatcher._();

  StreamSubscription<List<SupportThread>>? _sub;
  int _lastUnread = -1;
  int unread = 0;
  List<SupportThread> threads = const [];
  Object? error;

  /// [onNew] يُستدعى عند وصول رسالة جديدة (لإظهار تنبيه داخل التطبيق)
  void start(void Function(SupportThread latest) onNew) {
    _sub?.cancel();
    _lastUnread = -1;
    _sub = supportApi.watchAllThreads().listen((list) {
      threads = list;
      error = null;
      unread = list.fold(0, (a, t) => a + t.unreadForAdmin);
      if (_lastUnread >= 0 && unread > _lastUnread) {
        final latest = list.where((t) => t.unreadForAdmin > 0).firstOrNull;
        if (latest != null) {
          notifier.show('رسالة دعم من ${latest.userName?.isNotEmpty == true ? latest.userName : latest.app.label}', latest.lastMessage, channel: WChannel.support);
          onNew(latest);
        }
      }
      _lastUnread = unread;
      notifyListeners();
    }, onError: (Object e) {
      error = e;
      notifyListeners();
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}

final supportInbox = SupportInboxWatcher.instance;

/// زر الدعم مع العداد (لشريط عنوان اللوحة)
class SupportInboxButton extends StatelessWidget {
  const SupportInboxButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: supportInbox,
        builder: (context, _) => IconButton(
          tooltip: 'رسائل الدعم',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportInboxScreen())),
          icon: Badge(
            isLabelVisible: supportInbox.unread > 0,
            label: Text('${supportInbox.unread}'),
            backgroundColor: WColors.lime,
            textColor: WColors.ink,
            child: const Icon(Icons.support_agent_rounded),
          ),
        ),
      );
}

enum _Filter { open, unread, closed }

class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen({super.key});
  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  _Filter _filter = _Filter.open;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('رسائل الدعم')),
        body: ListenableBuilder(
          listenable: supportInbox,
          builder: (context, _) {
            if (supportInbox.error != null && supportInbox.threads.isEmpty) {
              return ErrorView(error: supportInbox.error!, onRetry: () => supportInbox.start((_) {}));
            }
            final all = supportInbox.threads;
            final list = switch (_filter) {
              _Filter.open => all.where((t) => t.isOpen).toList(),
              _Filter.unread => all.where((t) => t.unreadForAdmin > 0).toList(),
              _Filter.closed => all.where((t) => !t.isOpen).toList(),
            };
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(WSpace.page, 4, WSpace.page, 8),
                child: SegmentedButton<_Filter>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: _Filter.open, label: Text('المفتوحة (${all.where((t) => t.isOpen).length})')),
                    ButtonSegment(value: _Filter.unread, label: Text('غير مقروءة (${all.where((t) => t.unreadForAdmin > 0).length})')),
                    const ButtonSegment(value: _Filter.closed, label: Text('المغلقة')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (v) => setState(() => _filter = v.first),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyView(icon: Icons.support_agent_rounded, title: 'ما اكو رسائل هنا', message: 'رسائل المستهلكين والتجار والسائقين تظهر هنا فوراً مع تنبيه.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(WSpace.page, 0, WSpace.page, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _ThreadCard(thread: list[i]),
                      ),
              ),
            ]);
          },
        ),
      );
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread});
  final SupportThread thread;

  @override
  Widget build(BuildContext context) {
    final t = thread;
    final unread = t.unreadForAdmin > 0;
    return WCard(
      padding: const EdgeInsets.all(14),
      borderColor: unread ? WColors.fg : WColors.line,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _AdminChat(thread: t))),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: unread ? WColors.night : WColors.paper, borderRadius: WRadius.all(12)),
          child: Icon(
            switch (t.app) { SupportApp.customer => Icons.person_outline_rounded, SupportApp.merchant => Icons.storefront_outlined, SupportApp.driver => Icons.two_wheeler_outlined },
            color: unread ? WColors.lime : WColors.fg,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(t.userName?.isNotEmpty == true ? t.userName! : (t.userPhone ?? 'مستخدم'), style: WText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(relativeAr(t.lastMessageAt), style: WText.caption),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              StatusPill(t.app.label, tone: t.app == SupportApp.customer ? PillTone.info : PillTone.neutral),
              const SizedBox(width: 8),
              Expanded(child: Text(t.lastMessage, style: WText.small.copyWith(color: unread ? WColors.fg : WColors.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: WColors.lime, borderRadius: WRadius.all(8)),
                  child: Text('${t.unreadForAdmin}', style: WText.label.copyWith(color: WColors.ink)),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// محادثة الإدارة (الإغلاق/إعادة الفتح من قائمة شريط العنوان)
class _AdminChat extends StatelessWidget {
  const _AdminChat({required this.thread});
  final SupportThread thread;
  @override
  Widget build(BuildContext context) => SupportChatScreen.admin(thread: thread);
}
