import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth.dart';
import '../services/errors.dart';
import '../theme/tokens.dart';
import 'basics.dart';

/// شاشة إدخال رمز التحقق (6 أرقام) المرسل على الواتساب.
///
/// [onVerify] ترسل الرمز للخادم؛ نجاحها يعني أن الجلسة فُتحت، فترجع الشاشة لأول صفحة
/// (بوابة الدخول تنقل المستخدم تلقائياً للتطبيق).
/// [onResend] تطلب رمزاً جديداً وترجع ثواني الانتظار قبل الإعادة التالية.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
    required this.onVerify,
    required this.onResend,
    this.resendIn = 60,
    this.title = 'رمز التحقق',
  });

  /// الرقم بصيغة 07XXXXXXXXX للعرض
  final String phone;
  final Future<void> Function(String code) onVerify;
  final Future<int> Function() onResend;
  final int resendIn;
  final String title;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _len = 6;
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  late int _left = widget.resendIn;
  bool _busy = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer(widget.resendIn);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() => _left = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text;
    if (code.length != _len || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onVerify(code);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _error = friendlyError(e));
      _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_left > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final wait = await widget.onResend();
      if (!mounted) return;
      _code.clear();
      _startTimer(wait);
      showInfo(context, 'أرسلنا رمزاً جديداً على الواتساب.');
    } on AuthFlowException catch (e) {
      if (!mounted) return;
      if (e.code == 'otp_cooldown' && e.retryIn != null) _startTimer(e.retryIn!);
      setState(() => _error = friendlyError(e));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String get _mmss => '${(_left ~/ 60).toString().padLeft(1, '0')}:${(_left % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WColors.night,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: WColors.white,
          leading: IconButton(
            tooltip: 'رجوع',
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight, maxWidth: 520),
                  child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(color: WColors.lime, borderRadius: BorderRadius.circular(WRadius.lg)),
                          child: Icon(Icons.mark_chat_read_outlined, color: WColors.ink, size: 28),
                        ),
                        const SizedBox(height: 22),
                        Text(widget.title, style: WText.display.copyWith(color: WColors.white)),
                        const SizedBox(height: 10),
                        Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'أرسلنا رمزاً من 6 أرقام على الواتساب للرقم '),
                            TextSpan(
                              text: widget.phone,
                              style: WText.number.copyWith(color: WColors.white, fontSize: 14.5),
                            ),
                          ]),
                          style: WText.body.copyWith(color: WColors.inkFaint),
                          textDirection: TextDirection.rtl,
                        ),
                      ]),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: WColors.paper, borderRadius: BorderRadius.vertical(top: Radius.circular(WRadius.xl))),
                      padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + MediaQuery.paddingOf(context).bottom),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('اكتب الرمز', style: WText.h1),
                        const SizedBox(height: 4),
                        Text('صالح لمدة 5 دقائق', style: WText.small),
                        const SizedBox(height: 20),
                        _boxes(),
                        AnimatedSize(
                          duration: WDurations.base,
                          curve: WDurations.curve,
                          child: _error == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Row(children: [
                                    Icon(Icons.error_outline_rounded, color: WColors.danger, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(_error!, style: WText.small.copyWith(color: WColors.danger))),
                                  ]),
                                ),
                        ),
                        const SizedBox(height: 22),
                        WButton('تأكيد', onPressed: _code.text.length == _len ? _verify : null, loading: _busy, icon: Icons.check_rounded),
                        const SizedBox(height: 8),
                        _left > 0
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Text.rich(
                                  TextSpan(children: [
                                    const TextSpan(text: 'إعادة الإرسال بعد '),
                                    TextSpan(text: _mmss, style: WText.number.copyWith(fontSize: 13, color: WColors.fg)),
                                  ]),
                                  style: WText.small,
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : WButton(
                                'إعادة إرسال الرمز',
                                kind: WButtonKind.ghost,
                                loading: _resending,
                                icon: Icons.refresh_rounded,
                                onPressed: _busy ? null : _resend,
                              ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );

  /// 6 خانات مرسومة فوق حقل نص واحد مخفي (يدعم اللصق والتعبئة التلقائية)
  Widget _boxes() => SizedBox(
        height: 58,
        child: Stack(children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: List.generate(_len, (i) {
                final t = _code.text;
                final filled = i < t.length;
                final active = _focus.hasFocus && i == t.length.clamp(0, _len - 1) && !(t.length == _len && i < _len - 1);
                return Expanded(
                  child: AnimatedContainer(
                    duration: WDurations.fast,
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
                    decoration: BoxDecoration(
                      color: WColors.surface,
                      borderRadius: BorderRadius.circular(WRadius.md),
                      border: Border.all(
                        color: _error != null ? WColors.danger : (active ? WColors.ink : WColors.line),
                        width: active ? 2 : 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(filled ? t[i] : '', style: WText.number.copyWith(fontSize: 24, color: WColors.fg)),
                  ),
                );
              }),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _code,
                focusNode: _focus,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: _len,
                showCursor: false,
                enableInteractiveSelection: false,
                inputFormatters: [_DigitsFormatter(), LengthLimitingTextInputFormatter(_len)],
                decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                onChanged: (v) {
                  setState(() => _error = null);
                  if (v.length == _len) _verify();
                },
              ),
            ),
          ),
        ]),
      );
}

/// يقبل الأرقام فقط ويحوّل الأرقام العربية (٠-٩) إلى إنجليزية
class _DigitsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final b = StringBuffer();
    for (final ch in newValue.text.runes) {
      if (ch >= 0x30 && ch <= 0x39) {
        b.writeCharCode(ch);
      } else if (ch >= 0x660 && ch <= 0x669) {
        b.writeCharCode(ch - 0x660 + 0x30);
      } else if (ch >= 0x6F0 && ch <= 0x6F9) {
        b.writeCharCode(ch - 0x6F0 + 0x30);
      }
    }
    final s = b.toString();
    return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}
