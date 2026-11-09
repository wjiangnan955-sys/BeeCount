import 'package:beecount/data/db.dart' as db;
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers.dart';
import 'package:beecount/widgets/analytics/year_income_expense_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  db.Transaction tx(int id, String type, double amount, DateTime at,
          {double? native, bool excluded = false}) =>
      db.Transaction(
          id: id,
          ledgerId: 1,
          type: type,
          amount: amount,
          happenedAt: at,
          nativeAmount: native,
          excludeFromStats: excluded,
          excludeFromBudget: false);

  test('monthly totals use ledger periods, converted amounts and exclusions',
      () {
    final totals = calendarMonthlyTotals([
      tx(1, 'expense', 12, DateTime(2026, 11, 9)),
      tx(2, 'expense', 10, DateTime(2026, 11, 10), native: 70),
      tx(3, 'income', 200, DateTime(2026, 11, 30)),
      tx(4, 'expense', 999, DateTime(2026, 11, 11), excluded: true),
      tx(5, 'transfer', 500, DateTime(2026, 11, 11)),
      tx(6, 'income', 20, DateTime(2027, 1, 9, 23, 59)),
      tx(7, 'income', 999, DateTime(2027, 1, 10)),
      tx(8, 'income', 999, DateTime(2026, 1, 9)),
    ], year: 2026, startDay: 10);
    expect(totals.length, 3);
    expect(totals[10], (income: 0.0, expense: 12.0, count: 1));
    expect(totals[11], (income: 200.0, expense: 70.0, count: 2));
    expect(totals[12], (income: 20.0, expense: 0.0, count: 1));
    expect(calendarMonthlyTotals([], year: 2026), isEmpty);
  });

  testWidgets(
      '12 months select real totals, hide amounts and reset across years',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    late ProviderContainer container;
    var previous = 0;
    Widget host(int year, {double scale = 1}) => ProviderScope(
          overrides: [
            currentLedgerProvider.overrideWith((ref) => Stream.value(null)),
            yearCalendarTotalsProvider.overrideWith((ref, query) async => {
                  2: (income: 8320.0, expense: 969.0, count: 24),
                }),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Builder(builder: (context) {
              container = ProviderScope.containerOf(context);
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: YearIncomeExpenseCalendar(
                    year: year,
                    startDay: 1,
                    queryEnd: DateTime(year + 1),
                    onPrevious: () => previous++,
                    onNext: () {},
                  ),
                )),
              );
            })),
          ),
        );
    String value(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    await tester.pumpWidget(host(now.year - 1));
    await tester.pumpAndSettle();
    for (var month = 1; month <= 12; month++) {
      expect(find.byKey(ValueKey('year_month_$month')), findsOneWidget);
    }
    expect(find.text('暂无收支记录'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('year_month_2')));
    await tester.pumpAndSettle();
    expect(value('year_selected_income'), '8,320');
    expect(value('year_selected_expense'), '969');
    expect(value('year_selected_balance'), '7,351');
    expect(find.text('24 笔记录'), findsOneWidget);
    container.read(hideAmountsProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(value('year_selected_income'), '****');
    expect(find.text('8,320'), findsNothing);
    await tester.pumpWidget(host(now.year - 2, scale: 1.8));
    await tester.pumpAndSettle();
    expect(value('year_selected_month'), '1月收支');
    expect(tester.takeException(), isNull);
    await tester.fling(
        find.byKey(const ValueKey('year_month_1')), const Offset(150, 0), 800);
    await tester.pumpAndSettle();
    expect(previous, 1);
  });
}
