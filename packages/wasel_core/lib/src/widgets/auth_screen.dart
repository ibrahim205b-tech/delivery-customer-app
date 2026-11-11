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
        backgroundColor: WColors.navy,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const WaselWordmark(height: 46, onDark: true),
                        const Spacer(),
                        if (widget.badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: WColors.coral.withValues(alpha: 0.16), borderRadius: WRadius.all(WRadius.pill)),
                            child: Text(widget.badge!, style: WText.caption.copyWith(color: WColors.coral, fontWeight: FontWeight.w600)),
                          ),
                      ]),
                      const SizedBox(height: 36),
                      Text(widget.headline, style: WText.display.copyWith(color: WColors.white)),
                      const SizedBox(height: 8),
                      Text(widget.subline, style: WText.body.copyWith(color: WColors.mint)),
                    ]),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(color: WColors.ivory, borderRadius: BorderRadius.vertical(top: Radius.circular(WRadius.xl))),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Form(
                      key: _form,
                      child: AutofillGroup(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(_signUp ? 'حساب جديد' : 'تسجيل الدخول', style: WText.h2),
                          const SizedBox(height: 18),
                          AnimatedSize(
                            duration: WDurations.base,
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
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.telephoneNumber],
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ٠-٩]'))],
                            decoration: const InputDecoration(labelText: 'رقم الهاتف', hintText: '07XX XXX XXXX', prefixIcon: Icon(Icons.phone_iphone_rounded)),
                            validator: (v) => normalizeIraqiPhone(v ?? '') == null ? 'رقم عراقي غير صحيح (مثال 07701234567)' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _pass,
                            obscureText: !_showPass,
                            textDirection: TextDirection.ltr,
                            autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                onPressed: () => setState(() => _showPass = !_showPass),
                              ),
                            ),
                            validator: (v) => (v ?? '').length < 6 ? '6 أحرف على الأقل' : null,
                          ),
                          const SizedBox(height: 22),
                          WButton(_signUp ? 'إنشاء الحساب' : 'دخول', onPressed: _submit, loading: _busy),
                          if (widget.allowSignUp) ...[
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                              child: Text(_signUp ? 'عندك حساب؟ سجّل دخول' : 'ما عندك حساب؟ سجّل هسه'),
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
      );
}

/// أيقونة القسم حسب المفتاح المخزن بقاعدة البيانات
IconData categoryIcon(String key) => switch (key) {
      'restaurant' || 'restaurants' => Icons.restaurant_rounded,
      'supermarket' => Icons.local_grocery_store_rounded,
      'home_repair' || 'home_services' => Icons.home_repair_service_rounded,
      'sweets' => Icons.cake_rounded,
      'mobile' || 'mobiles' => Icons.smartphone_rounded,
      'bakery' => Icons.bakery_dining_rounded,
      'produce' => Icons.eco_rounded,
      'taxi' => Icons.local_taxi_rounded,
      'tuktuk' => Icons.electric_rickshaw_rounded,
      'courier' => Icons.delivery_dining_rounded,
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
Color categoryTint(String key) => switch (key) {
      'restaurant' || 'restaurants' || 'sweets' => WColors.coralDeep,
      'supermarket' || 'produce' || 'bakery' => WColors.mintDeep,
      'mobile' || 'mobiles' => WColors.info,
      'home_repair' || 'home_services' => WColors.warning,
      _ => WColors.navy,
    };
