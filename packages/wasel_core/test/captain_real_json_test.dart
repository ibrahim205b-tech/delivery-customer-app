import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  test('شكل ردّ driver_account يتحول لنموذج بدون أخطاء (يطابق الخادم)', () {
    final j = <String, dynamic>{
      'ledger': [
        {'type': 'commission', 'at': '2026-11-14T23:16:26.627748+00:00', 'amount': 650, 'fare': 6500, 'percent': 10.00, 'ref': 'ride', 'ref_id': 'x', 'note': ''},
        {'type': 'payment', 'at': '2026-11-14T23:20:00+00:00', 'amount': -400, 'fare': null, 'percent': null, 'ref': null, 'ref_id': null, 'note': 'نقد'},
      ],
      'summary': {
        'owed': 250,
        'commission_total': 650,
        'commission_today': 650,
        'commission_week': 650,
        'commission_month': 650,
        'paid_total': 400,
        'adjust_total': 0,
        'fares_today': 6500,
        'fares_week': 6500,
        'fares_month': 6500,
        'trips_done': 1,
        'trips_done_today': 1,
        'trips_cancelled': 0,
        'cancel_rate': 0,
        'rating_avg': 0.00,
        'last_7_days': [
          {'day': '2026-11-14', 'trips': 1, 'fares': 6500},
        ],
      },
    };
    final st = CaptainStatement.fromJson(j);
    expect(st.summary.owed, 250);
    expect(st.summary.last7Days.single.fares, 6500);
    expect(st.ledger.first.percent, 10);
    expect(st.ledger[1].kind, LedgerKind.payment);
  });
}
