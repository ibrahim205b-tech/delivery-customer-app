import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/errors.dart';
import '../theme/tokens.dart';

// =====================================================================
// الأزرار
// =====================================================================
enum WButtonKind {
  /// الفعل الرئيسي بالشاشة: ليموني + حبر
  primary,

  /// فعل قوي ثانوي أو على خلفية فاتحة جداً: حبر + أبيض
  dark,

  /// إطار حبر بدون تعبئة
  secondary,

  /// بدون خلفية (روابط/أفعال خفيفة)
  ghost,

  /// حذف/إلغاء
  danger,
}

/// زر واصل الموحّد. حالات: عادي، مضغوط (تصغير خفيف)، معطّل، تحميل، ونجاح (علامة صح لحظية).
class WButton extends StatefulWidget {
  const WButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = WButtonKind.primary,
    this.icon,
    this.loading = false,
    this.success = false,
    this.expand = true,
    this.trailing,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final WButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool success;
  final bool expand;
  final Widget? trailing;
  final bool compact;

  @override
  State<WButton> createState() => _WButtonState();
}

class _WButtonState extends State<WButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final (bg, fg, border) = switch (widget.kind) {
      WButtonKind.primary => (WColors.lime, WColors.ink, null),
      WButtonKind.dark => (WColors.night, WColors.white, null),
      WButtonKind.secondary => (Colors.transparent, WColors.fg, WColors.fg),
      WButtonKind.ghost => (Colors.transparent, WColors.fg, null),
      WButtonKind.danger => (WColors.dangerSoft, WColors.danger, null),
    };
    final disabled = !enabled && !widget.loading;
    final effBg = disabled && widget.kind != WButtonKind.ghost && widget.kind != WButtonKind.secondary ? WColors.surfaceAlt : bg;
    final effFg = disabled ? WColors.inkFaint : fg;
    final h = widget.compact ? 42.0 : 54.0;

    Widget content;
    if (widget.loading) {
      content = SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: effFg));
    } else if (widget.success) {
      content = Icon(Icons.check_rounded, color: effFg, size: 24);
    } else {
      final main = Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.icon != null) ...[Icon(widget.icon, size: 20, color: effFg), const SizedBox(width: 8)],
        Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis, style: WText.button.copyWith(color: effFg))),
      ]);
      content = widget.trailing == null
          ? main
          : Row(children: [Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: main)), widget.trailing!]);
    }

    final button = AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: WDurations.fast,
      curve: WDurations.curve,
      child: AnimatedContainer(
        duration: WDurations.base,
        curve: WDurations.curve,
        height: h,
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 20),
        decoration: BoxDecoration(
          color: widget.success && widget.kind == WButtonKind.primary ? WColors.success : effBg,
          borderRadius: WRadius.all(WRadius.md),
          border: border == null ? null : Border.all(color: disabled ? WColors.line : border, width: 1.5),
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: WDurations.base,
          child: KeyedSubtree(key: ValueKey('${widget.loading}${widget.success}'), child: IconTheme(data: IconThemeData(color: effFg), child: content)),
        ),
      ),
    );

    final interactive = Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      // excludeSemantics يحذف فعل النقر من GestureDetector؛ نعطيه هنا حتى يشتغل مع قارئ الشاشة
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onPressed!();
            }
          : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        child: button,
      ),
    );
    return widget.expand ? SizedBox(width: double.infinity, child: interactive) : interactive;
  }
}

/// زر أيقونة (مربع بزوايا ناعمة، مو دائرة)
class WIconButton extends StatelessWidget {
  const WIconButton(this.icon, {super.key, required this.onPressed, this.tooltip, this.background, this.color, this.size = 44, this.bordered = false});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? background;
  final Color? color;
  final double size;
  final bool bordered;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            color: background ?? WColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: WRadius.all(size * 0.32),
              side: bordered ? BorderSide(color: WColors.line) : BorderSide.none,
            ),
            child: InkWell(
              borderRadius: WRadius.all(size * 0.32),
              onTap: onPressed == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onPressed!();
                    },
              child: SizedBox(width: size, height: size, child: Icon(icon, color: color ?? WColors.fg, size: size * 0.48)),
            ),
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
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: WColors.surface, borderRadius: WRadius.all(22), border: Border.all(color: WColors.line)),
              child: Icon(icon, size: 30, color: WColors.fg),
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
void showSuccess(BuildContext context, String msg) => _snack(context, msg, Icons.check_circle_rounded, WColors.lime);
void showError(BuildContext context, Object error) =>
    _snack(context, error is String ? error : friendlyError(error), Icons.error_outline_rounded, const Color(0xFFFF8A78));
void showInfo(BuildContext context, String msg) => _snack(context, msg, Icons.notifications_active_outlined, WColors.lime);

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
          style: danger ? FilledButton.styleFrom(backgroundColor: WColors.danger, foregroundColor: WColors.white) : FilledButton.styleFrom(backgroundColor: WColors.night, foregroundColor: WColors.white),
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
                child: Text(action!, style: WText.label.copyWith(color: WColors.link, fontWeight: FontWeight.w600)),
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
      PillTone.info => (WColors.blueSoft, WColors.blue),
      PillTone.accent => (WColors.lime, WColors.ink),
      PillTone.dark => (WColors.ink, WColors.lime),
      PillTone.neutral => (WColors.surfaceAlt, WColors.inkMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: WRadius.all(WRadius.xs + 2)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Text(label, style: WText.label.copyWith(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

enum PillTone { neutral, success, warning, danger, info, accent, dark }

/// بطاقة بيضاء بحد ناعم
class WCard extends StatelessWidget {
  const WCard({super.key, required this.child, this.padding = const EdgeInsets.all(WSpace.lg), this.onTap, this.color, this.borderColor, this.radius = WRadius.lg});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
        color: color ?? WColors.surface,
        shape: RoundedRectangleBorder(borderRadius: WRadius.all(radius), side: BorderSide(color: borderColor ?? WColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

/// صورة من الشبكة مع بديل أنيق إذا ما موجودة أو فشل التحميل
class WImage extends StatelessWidget {
  const WImage(this.url, {super.key, this.width, this.height, this.radius = WRadius.md, this.fallbackIcon = Icons.image_outlined, this.fallbackColor, this.fit = BoxFit.cover});
  final String? url;
  final double? width;
  final double? height;
  final double radius;
  final IconData fallbackIcon;
  final Color? fallbackColor;
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

  // ألوان الهوية فقط
  static List<Color> get _palette => [WColors.ink, WColors.blue, WColors.graphite, WColors.lime];

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) return WImage(url, width: size, height: size, radius: size * 0.28);
    final c = _palette[name.runes.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: WRadius.all(size * 0.28)),
      child: Text(name.isEmpty ? '؟' : name.characters.first, style: WText.h2.copyWith(color: c == WColors.ink ? WColors.lime : (c == WColors.lime ? WColors.ink : WColors.white), fontSize: size * 0.42, height: 1, fontWeight: FontWeight.w700)),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: color ?? WColors.inkMuted),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: WText.small.copyWith(color: color ?? WColors.inkMuted))),
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
                  color: i <= current ? (onDark ? WColors.lime : WColors.fg) : (onDark ? WColors.white.withValues(alpha: 0.16) : WColors.line),
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
                  color: onDark ? WColors.white.withValues(alpha: i <= current ? 1 : 0.55) : (i <= current ? WColors.fg : WColors.inkFaint),
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
      Image.asset(onDark || WColors.isDark ? 'assets/brand/logo-ar-white.png' : 'assets/brand/logo-ar-ink.png', package: 'wasel_core', height: height);
}

/// العلامة مرسومة بالكود: مسار متموّج (W) ينتهي بحلقة وصول. نفس هندسة brand/tools/build_brand.py
class WaselMark extends StatelessWidget {
  const WaselMark({super.key, this.size = 48, this.route, this.ring});
  final double size;
  final Color? route;
  final Color? ring;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter(route ?? WColors.fg, ring ?? WColors.blue));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.route, this.ring);
  final Color route;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final p = Paint()
      ..color = route
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12.5 * s
      ..strokeCap = StrokeCap.round;
    // نفس هندسة brand/tools/build_brand.py (الإصدار 3): W كمسار، والطرف الأخير يلف ويصير حلقة الوصول
    final path = Path()
      ..moveTo(11.5 * s, 38.5 * s)
      ..cubicTo(17.5 * s, 60.5 * s, 21.5 * s, 78.5 * s, 29.5 * s, 78.5 * s)
      ..cubicTo(37.5 * s, 78.5 * s, 40.5 * s, 55.5 * s, 47.5 * s, 55.5 * s)
      ..cubicTo(54.5 * s, 55.5 * s, 57.5 * s, 78.5 * s, 65.5 * s, 78.5 * s)
      ..cubicTo(73.5 * s, 78.5 * s, 80.76 * s, 51.39 * s, 86.76 * s, 41 * s)
      ..arcToPoint(Offset(64.24 * s, 41 * s), radius: Radius.circular(13 * s), largeArc: true, clockwise: false);
    canvas.drawPath(path, p..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.route != route || old.ring != ring;
}
