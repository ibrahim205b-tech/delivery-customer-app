import 'package:flutter_test/flutter_test.dart';
import 'package:wasel_core/wasel_core.dart';

void main() {
  test('كشف الكابتن يُقرأ من ردّ الخادم', () {
    final st = CaptainStatement.fromJson({
      'summary': {
        'owed': 850,
        'commission_total': 1250,
        'commission_today': 300,
        'commission_week': 900,
        'commission_month': 1250,
        'paid_total': 400,
        'adjust_total': 0,
        'fares_today': 3000,
        'fares_week': 9000,
        'fares_month': 12500,
        'trips_done': 4,
        'trips_done_today': 2,
        'trips_cancelled': 1,
        'cancel_rate': 20.0,
        'rating_avg': 0,
        'last_7_days': [
          {'day': '2026-11-14', 'trips': 2, 'fares': 3000},
        ],
      },
      'ledger': [
        {'type': 'commission', 'at': '2026-11-14T10:00:00Z', 'amount': 300, 'fare': 3000, 'percent': 10, 'ref': 'ride', 'ref_id': 'x', 'note': ''},
        {'type': 'payment', 'at': '2026-11-14T12:00:00Z', 'amount': -400, 'fare': null, 'percent': null, 'ref': null, 'ref_id': null, 'note': 'نقد'},
        {'type': 'adjustment', 'at': '2026-11-14T13:00:00Z', 'amount': 50, 'fare': null, 'percent': null, 'ref': null, 'ref_id': null, 'note': 'تصحيح'},
      ],
    });
    expect(st.summary.owed, 850);
    expect(st.summary.cancelRate, 20.0);
    expect(st.summary.ratingAvg, 0);
    expect(st.summary.last7Days.single.fares, 3000);
    expect(st.ledger.map((e) => e.kind), [LedgerKind.commission, LedgerKind.payment, LedgerKind.adjustment]);
    expect(st.ledger[1].amount, -400);
  });

  test('نسبة الإلغاء تبقى فارغة إذا ما في رحلات', () {
    final s = CaptainSummary.fromJson({
      'owed': 0, 'commission_total': 0, 'commission_today': 0, 'commission_week': 0, 'commission_month': 0,
      'paid_total': 0, 'adjust_total': 0, 'fares_today': 0, 'fares_week': 0, 'fares_month': 0,
      'trips_done': 0, 'trips_done_today': 0, 'trips_cancelled': 0, 'cancel_rate': null, 'rating_avg': 0, 'last_7_days': [],
    });
    expect(s.cancelRate, isNull);
    expect(s.last7Days, isEmpty);
  });

  test('صف الكابتن في قائمة الإدارة', () {
    final r = DriverAccountRow.fromJson({
      'driver_id': 'd1', 'name': 'أحمد', 'phone': '07700000000', 'vehicle_type': 'taxi',
      'is_active': true, 'owed': 1200, 'trips_done': 7,
    });
    expect(r.vehicleType, VehicleType.taxi);
    expect(r.owed, 1200);
  });
}
