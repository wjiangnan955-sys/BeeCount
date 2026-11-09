import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/data/db.dart' as db;
import 'package:beecount/widgets/analytics/income_expense_calendar.dart';

void main() {
  db.Transaction tx(int id, String type, double amount, DateTime at,
          {double? native, bool excluded = false}) =>
      db.Transaction(
          id: id,
          ledgerId: 1,
          type: type,
          amount: amount,
          happenedAt: at,
          excludeFromStats: excluded,
          excludeFromBudget: false,
          nativeAmount: native);

  test(
      'groups local days, uses converted values, excludes transfers and hidden statistics',
      () {
    final totals = calendarDailyTotals([
      tx(1, 'income', 200, DateTime(2026, 11, 9, 9)),
      tx(2, 'expense', 12, DateTime(2026, 11, 9, 8)),
      tx(3, 'expense', 10, DateTime(2026, 11, 9, 10), native: 70),
      tx(4, 'expense', 999, DateTime(2026, 11, 9), excluded: true),
      tx(5, 'transfer', 500, DateTime(2026, 11, 9)),
      tx(6, 'expense', 28, DateTime(2026, 11, 8, 23, 59)),
    ]);
    expect(totals.length, 2);
    expect(totals[DateTime(2026, 11, 9)], (income: 200.0, expense: 82.0));
    expect(totals[DateTime(2026, 11, 8)], (income: 0.0, expense: 28.0));
  });

  test('UTC timestamps use the device local date and empty months remain empty',
      () {
    final utc = DateTime.utc(2026, 11, 9, 23, 30);
    final local = utc.toLocal();
    expect(calendarDailyTotals([tx(1, 'income', 1, utc)]).keys.single,
        DateTime(local.year, local.month, local.day));
    expect(calendarDailyTotals([]), isEmpty);
  });
}
