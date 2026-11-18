import 'package:flutter/material.dart';
import 'package:wasel_core/wasel_core.dart';

/// محفظتي: واصل حالياً يعتمد الدفع نقداً عند الاستلام، فلا يوجد رصيد حقيقي لعرضه.
/// الشاشة تقول ذلك بوضوح بدل عرض رصيد أو حركات وهمية.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('محفظتي')),
        body: const EmptyView(
          icon: Icons.account_balance_wallet_outlined,
          title: 'المحفظة غير مفعّلة بعد',
          message: 'الدفع حالياً نقداً عند الاستلام. لما تتفعّل المحفظة يظهر رصيدك وحركاتك هنا.',
        ),
      );
}
