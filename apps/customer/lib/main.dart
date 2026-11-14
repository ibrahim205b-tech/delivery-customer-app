import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

import 'shell.dart';
import 'state.dart';

late final AuthController auth;
late final CustomerState app;

Future<void> main() async {
  // هوية تطبيق الزبون (نيلي واصل + أصفر التكسي). تطبيقا التاجر والإدارة يبقون على الهوية الأصلية.
  WColors.palette = WPalette.customer;
  final ready = await bootstrapWasel();
  if (ready) {
    auth = AuthController();
    app = CustomerState();
  }
  runApp(WaselApp(title: 'واصل', home: ready ? const Root() : const NotConfiguredScreen()));
}

/// يبدّل بين الدخول والتطبيق حسب حالة الجلسة
class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          if (!auth.isSignedIn) {
            return PhoneAuthScreen(
              auth: auth,
              headline: 'كل احتياجاتك أقرب.',
              subline: 'أكل، ماركت، تكسي، توصيل، وخدمات للبيت… من تطبيق واحد.',
            );
          }
          if (auth.profile == null) {
            if (auth.loadError != null) {
              return Scaffold(body: ErrorView(error: auth.loadError!, onRetry: auth.refresh));
            }
            return const SplashView();
          }
          if (!auth.profile!.isActive) {
            return Scaffold(
              body: EmptyView(
                icon: Icons.block_rounded,
                title: 'حسابك موقوف',
                message: 'تواصل مع دعم واصل لإعادة التفعيل.',
                action: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SupportContactButtons(),
                  const SizedBox(height: 10),
                  WButton('تسجيل الخروج', onPressed: auth.signOut, kind: WButtonKind.ghost, expand: false),
                ]),
              ),
            );
          }
          return const CustomerShell();
        },
      );
}
