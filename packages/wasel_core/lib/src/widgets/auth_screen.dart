import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth.dart';
import '../theme/tokens.dart';
import 'basics.dart';

/// شاشة الدخول/التسجيل برقم الهاتف وكلمة المرور (مشتركة بين التطبيقات).
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key, required this.auth, required this.headline, required this.subline, this.allowSignUp = true, this.badge});
  final AuthController auth;
  final String headline;
  final String subline;
  final bool allowSignUp;
  final String? badge;

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _showPass = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_signUp) {
        await widget.auth.signUp(fullName: _name.text, phone: _phone.text, password: _pass.text);
      } else {
        await widget.auth.signIn(phone: _phone.text, password: _pass.text);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WColors.ink,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: Center(
                // على التابلت والشاشات العريضة: عمود بعرض مريح بدل ما يتمدد على كل الشاشة
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight, maxWidth: 520),
                  child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const WaselWordmark(height: 40, onDark: true),
                          const Spacer(),
                          if (widget.badge != null) StatusPill(widget.badge!, tone: PillTone.accent),
                        ]),
                        const SizedBox(height: 48),
                        // خط المسار: لمسة من العلامة بدل صورة زخرفية
                        SizedBox(
                          height: 46,
                          width: double.infinity,
                          child: CustomPaint(painter: _RouteLinePainter()),
                        ),
                        const SizedBox(height: 22),
                        Text(widget.headline, style: WText.display.copyWith(color: WColors.white)),
                        const SizedBox(height: 10),
                        Text(widget.subline, style: WText.body.copyWith(color: WColors.inkFaint)),
                      ]),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(color: WColors.paper, borderRadius: BorderRadius.vertical(top: Radius.circular(WRadius.xl))),
                      padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + MediaQuery.paddingOf(context).bottom),
                      child: Form(
                        key: _form,
                        child: AutofillGroup(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            AnimatedSwitcher(
                              duration: WDurations.base,
                              child: Text(_signUp ? 'حساب جديد' : 'أهلاً بيك', key: ValueKey(_signUp), style: WText.h1),
                            ),
                            const SizedBox(height: 4),
                            Text(_signUp ? 'رقمك هو اسم المستخدم' : 'سجّل دخولك برقم هاتفك', style: WText.small),
                            const SizedBox(height: 20),
                            AnimatedSize(
                              duration: WDurations.base,
                              curve: WDurations.curve,
                              child: _signUp
                                  ? Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: TextFormField(
                                        controller: _name,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [AutofillHints.name],
                                        decoration: const InputDecoration(labelText: 'الاسم الكامل', prefixIcon: Icon(Icons.person_outline_rounded)),
                                        validator: (v) => (v ?? '').trim().length < 3 ? 'اكتب اسمك' : null,
                                      ),
                                    )
                                  : const SizedBox(width: double.infinity),
                            ),
                            TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.right,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.telephoneNumber],
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ٠-٩]'))],
                              style: WText.number.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                              decoration: const InputDecoration(labelText: 'رقم الهاتف', hintText: '07XX XXX XXXX', prefixIcon: Icon(Icons.phone_iphone_rounded)),
                              validator: (v) => normalizeIraqiPhone(v ?? '') == null ? 'رقم عراقي غير صحيح (مثال 07701234567)' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _pass,
                              obscureText: !_showPass,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.right,
                              autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'كلمة المرور',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  tooltip: _showPass ? 'إخفاء' : 'إظهار',
                                  icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                  onPressed: () => setState(() => _showPass = !_showPass),
                                ),
                              ),
                              validator: (v) => (v ?? '').length < 6 ? '6 أحرف على الأقل' : null,
                            ),
                            const SizedBox(height: 22),
                            WButton(_signUp ? 'إنشاء الحساب' : 'دخول', onPressed: _submit, loading: _busy, icon: Icons.arrow_back_rounded),
                            if (widget.allowSignUp) ...[
                              const SizedBox(height: 8),
                              WButton(
                                _signUp ? 'عندي حساب، سجّل دخول' : 'ما عندي حساب، سجّل هسه',
                                kind: WButtonKind.ghost,
                                onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

/// خط مسار متموّج ينتهي بحلقة — نفس روح العلامة، بعرض الشاشة
class _RouteLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = WColors.lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(w - 4, h * 0.3);
    // RTL: يبدأ من اليمين وينتهي يسار
    final seg = (w - 40) / 4;
    var x = w - 4;
    for (var i = 0; i < 4; i++) {
      final nx = x - seg;
      final up = i.isEven;
      path.cubicTo(x - seg * 0.35, up ? h * 0.95 : h * 0.15, nx + seg * 0.35, up ? h * 0.95 : h * 0.15, nx, up ? h * 0.6 : h * 0.3);
      x = nx;
    }
    canvas.drawPath(path, p);
    canvas.drawCircle(
        Offset(x - 12, h * 0.3),
        9,
        Paint()
          ..color = WColors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawCircle(Offset(w - 4, h * 0.3), 4, Paint()..color = WColors.lime);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// أيقونة القسم حسب المفتاح المخزن بقاعدة البيانات
IconData categoryIcon(String key) => switch (key) {
      'restaurant' || 'restaurants' => Icons.ramen_dining_rounded,
      'supermarket' => Icons.local_grocery_store_rounded,
      'home_repair' || 'home_services' => Icons.home_repair_service_rounded,
      'sweets' => Icons.cake_rounded,
      'mobile' || 'mobiles' => Icons.smartphone_rounded,
      'bakery' => Icons.bakery_dining_rounded,
      'produce' => Icons.spa_rounded,
      'taxi' => Icons.local_taxi_rounded,
      'tuktuk' => Icons.electric_rickshaw_rounded,
      'courier' => Icons.directions_bike_rounded,
      'parcel' => Icons.inventory_2_rounded,
      _ => Icons.storefront_rounded,
    };

IconData homeServiceIcon(String key) => switch (key) {
      'plumbing' => Icons.plumbing_rounded,
      'electric' => Icons.electrical_services_rounded,
      'cleaning' => Icons.cleaning_services_rounded,
      'handyman' => Icons.handyman_rounded,
      _ => Icons.home_repair_service_rounded,
    };

/// لون مميز لكل قسم (من لوحة الهوية فقط)
/// كل الأقسام بلونين فقط (حبر/أزرق) حتى تبقى الواجهة هادئة؛ الليموني للتمييز اللحظي.
Color categoryTint(String key) => switch (key) {
      'mobile' || 'mobiles' || 'home_repair' || 'home_services' || 'taxi' || 'tuktuk' => WColors.blue,
      _ => WColors.ink,
    };
