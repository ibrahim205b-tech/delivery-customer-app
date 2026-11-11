import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/errors.dart';
import '../theme/tokens.dart';

// =====================================================================
// الأزرار
// =====================================================================
enum WButtonKind { primary, secondary, dark, danger, ghost }

/// زر موحّد مع حالة تحميل. استخدمه بدل FilledButton مباشرة.
class WButton extends StatelessWidget {
  const WButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = WButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPressed;
  final WButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final (bg, fg, side) = switch (kind) {
      WButtonKind.primary => (primary, onPrimary, BorderSide.none),
      WButtonKind.dark => (WColors.navy, WColors.white, BorderSide.none),
      WButtonKind.danger => (WColors.dangerSoft, WColors.danger, BorderSide.none),
      WButtonKind.secondary => (WColors.white, WColors.ink, const BorderSide(color: WColors.line, width: 1.5)),
      WButtonKind.ghost => (Colors.transparent, WColors.ink, BorderSide.none),
    };
    final child = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: trailing == null ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ]),
              if (trailing != null) trailing!,
            ],
          );
    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: loading ? bg : WColors.line,
        disabledForegroundColor: loading ? fg : WColors.inkFaint,
        side: side,
        elevation: 0,
      ),
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// زر أيقونة دائري
class WIconButton extends StatelessWidget {
  const WIconButton(this.icon, {super.key, required this.onPressed, this.tooltip, this.background = WColors.white, this.color = WColors.ink, this.size = 44});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color background;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(width: size, height: size, child: Icon(icon, color: color, size: size * 0.5)),
          ),
        ),
      );
}

// =====================================================================
// الحالات: تحميل / فراغ / خطأ
// =====================================================================
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
          if (message != null) ...[const SizedBox(height: 14), Text(message!, style: WText.small)],
        ]),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(WSpace.xxxl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: WColors.surfaceAlt, shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: WColors.inkMuted),
            ),
            const SizedBox(height: 16),
            Text(title, style: WText.h3, textAlign: TextAlign.center),
            if (message != null) ...[const SizedBox(height: 6), Text(message!, style: WText.small, textAlign: TextAlign.center)],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.wifi_off_rounded,
        title: 'ما گدرنا نجيب البيانات',
        message: friendlyError(error),
        action: onRetry == null ? null : WButton('حاول مرة ثانية', onPressed: onRetry, kind: WButtonKind.secondary, expand: false, icon: Icons.refresh_rounded),
      );
}

/// يبني الواجهة من Future مع حالات التحميل والخطأ وإعادة المحاولة
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder, this.loading});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Widget? loading;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _future = f);
    await f.catchError((_) => null as T);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, s) {
          if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
          if (!s.hasData && s.connectionState != ConnectionState.done) return widget.loading ?? const LoadingView();
          return widget.builder(context, s.data as T, _reload);
        },
      );
}

/// هيكل تحميل (Skeleton) بدل الدوائر الدوّارة للقوائم
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 16, this.width, this.radius = WRadius.sm});
  final double height;
  final double? width;
  final double radius;
  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(color: WColors.surfaceAlt, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.itemHeight = 84});
  final int count;
  final double itemHeight;
  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(WSpace.page),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => SkeletonBox(height: itemHeight, radius: WRadius.lg),
      );
}

// =====================================================================
// رسائل
// =====================================================================
void showSuccess(BuildContext context, String msg) => _snack(context, msg, Icons.check_circle_rounded, WColors.mint);
void showError(BuildContext context, Object error) =>
    _snack(context, error is String ? error : friendlyError(error), Icons.error_outline_rounded, WColors.coral);
void showInfo(BuildContext context, String msg) => _snack(context, msg, Icons.info_outline_rounded, WColors.mint);

void _snack(BuildContext context, String msg, IconData icon, Color iconColor) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(icon, color: iconColor, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(msg)),
    ]),
  ));
}

/// ينفّذ عملية مع رسالة خطأ عربية تلقائياً. يرجّع true إذا نجحت.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showSuccess(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, String confirm = 'تأكيد', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message, style: WText.body.copyWith(color: WColors.inkMuted)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('تراجع')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: WColors.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, {required String title, String? hint, String? initial, String confirm = 'حفظ', int maxLines = 1, TextInputType? keyboard}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, maxLines: maxLines, keyboardType: keyboard, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(confirm)),
      ],
    ),
  );
  return (r == null || r.isEmpty) ? null : r;
}

// =====================================================================
// عناصر عرض
// =====================================================================
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction, this.padding});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(WSpace.page, WSpace.xxl, WSpace.page, WSpace.md),
        child: Row(children: [
          Expanded(child: Text(title, style: WText.h3)),
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: WRadius.all(WRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(action!, style: WText.caption.copyWith(color: WColors.coralDeep, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      );
}

/// شارة حالة ملوّنة
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = PillTone.neutral, this.icon});
  final String label;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.success => (WColors.successSoft, WColors.success),
      PillTone.warning => (WColors.warningSoft, WColors.warning),
      PillTone.danger => (WColors.dangerSoft, WColors.danger),
      PillTone.info => (WColors.infoSoft, WColors.info),
      PillTone.accent => (WColors.coralSoft, WColors.coralDeep),
      PillTone.neutral => (WColors.surfaceAlt, WColors.inkMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: WRadius.all(WRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Text(label, style: WText.caption.copyWith(color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

enum PillTone { neutral, success, warning, danger, info, accent }

/// بطاقة بيضاء بحد ناعم
class WCard extends StatelessWidget {
  const WCard({super.key, required this.child, this.padding = const EdgeInsets.all(WSpace.lg), this.onTap, this.color = WColors.white, this.borderColor = WColors.line, this.radius = WRadius.lg});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        shape: RoundedRectangleBorder(borderRadius: WRadius.all(radius), side: BorderSide(color: borderColor)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

/// صورة من الشبكة مع بديل أنيق إذا ما موجودة أو فشل التحميل
class WImage extends StatelessWidget {
  const WImage(this.url, {super.key, this.width, this.height, this.radius = WRadius.md, this.fallbackIcon = Icons.image_outlined, this.fallbackColor = WColors.surfaceAlt, this.fit = BoxFit.cover});
  final String? url;
  final double? width;
  final double? height;
  final double radius;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: width,
      height: height,
      color: fallbackColor,
      alignment: Alignment.center,
      child: Icon(fallbackIcon, color: WColors.inkFaint, size: ((height ?? 48) * 0.36).clamp(16, 40)),
    );
    return ClipRRect(
      borderRadius: WRadius.all(radius),
      child: url == null || url!.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: url!,
              width: width,
              height: height,
              fit: fit,
              fadeInDuration: WDurations.base,
              placeholder: (_, __) => SkeletonBox(height: height ?? 48, width: width, radius: 0),
              errorWidget: (_, __, ___) => fallback,
            ),
    );
  }
}

/// شعار محل: صورة إذا متوفرة، وإلا مربع بلون ثابت مشتق من الاسم وأول حرف
class MerchantLogo extends StatelessWidget {
  const MerchantLogo({super.key, required this.name, this.url, this.size = 52});
  final String name;
  final String? url;
  final double size;

  static const _palette = [WColors.navy, WColors.coralDeep, WColors.mintDeep, Color(0xFF8A5A44), Color(0xFF5B4B8A), Color(0xFF2F6A8A)];

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) return WImage(url, width: size, height: size, radius: size * 0.28);
    final c = _palette[name.runes.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: WRadius.all(size * 0.28)),
      child: Text(name.isEmpty ? '؟' : name.characters.first, style: WText.h2.copyWith(color: WColors.white, fontSize: size * 0.42, height: 1)),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.text, this.color = WColors.inkMuted});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: WText.small.copyWith(color: color))),
      ]);
}

/// خطوات تقدّم أفقية (للطلبات والرحلات)
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.steps, required this.current, this.onDark = false});
  final List<String> steps;
  final int current; // -1 = ملغي
  final bool onDark;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: WDurations.slow,
                height: 6,
                decoration: BoxDecoration(
                  color: i <= current ? WColors.coral : (onDark ? WColors.white.withValues(alpha: 0.18) : WColors.line),
                  borderRadius: WRadius.all(WRadius.pill),
                ),
              ),
            ),
            if (i < steps.length - 1) const SizedBox(width: 4),
          ],
        ]),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Text(
                steps[i],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WText.caption.copyWith(
                  fontSize: 11,
                  color: onDark ? WColors.white.withValues(alpha: i <= current ? 1 : 0.55) : (i <= current ? WColors.ink : WColors.inkFaint),
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ]),
      ]);
}

/// شعار واصل (صورة PNG من الهوية)
class WaselWordmark extends StatelessWidget {
  const WaselWordmark({super.key, this.height = 40, this.onDark = false});
  final double height;
  final bool onDark;
  @override
  Widget build(BuildContext context) =>
      Image.asset(onDark ? 'assets/brand/logo-ar-ivory.png' : 'assets/brand/logo-ar-navy.png', package: 'wasel_core', height: height);
}

/// العلامة مرسومة بالكود (حرف و كمسار) — حادة بأي حجم
class WaselMark extends StatelessWidget {
  const WaselMark({super.key, this.size = 48, this.stroke = WColors.coral, this.dot = WColors.mint});
  final double size;
  final Color stroke;
  final Color dot;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter(stroke, dot));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.stroke, this.dot);
  final Color stroke;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final p = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 * s
      ..strokeCap = StrokeCap.round;
    // الرسم بإحداثيات LTR ثابتة (العلامة صورة، ما تنقلب مع الاتجاه)
    canvas.drawCircle(Offset(60 * s, 34 * s), 15 * s, p);
    final path = Path()
      ..moveTo(75 * s, 34 * s)
      ..cubicTo(75 * s, 58 * s, 62 * s, 78 * s, 32 * s, 81 * s);
    canvas.drawPath(path, p);
    canvas.drawCircle(Offset(21 * s, 81.5 * s), 6.5 * s, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.stroke != stroke || old.dot != dot;
}
