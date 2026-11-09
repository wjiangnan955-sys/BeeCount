import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/month_range.dart';
import '../biz/format_money.dart';

typedef MonthIncomeExpense = ({double income, double expense, int count});
typedef YearCalendarQuery = ({
  int ledgerId,
  int year,
  int startDay,
  DateTime queryEnd,
  int refresh,
});

/// Keep month labels consistent with the ledger's custom accounting periods.
Map<int, MonthIncomeExpense> calendarMonthlyTotals(
    Iterable<db.Transaction> transactions,
    {required int year,
    int startDay = 1}) {
  final result = <int, MonthIncomeExpense>{};
  for (final transaction in transactions) {
    if (transaction.excludeFromStats ||
        (transaction.type != 'income' && transaction.type != 'expense')) {
      continue;
    }
    final month = labelForDate(transaction.happenedAt.toLocal(), startDay);
    if (month.year != year) continue;
    final previous =
        result[month.month] ?? (income: 0.0, expense: 0.0, count: 0);
    final amount = transaction.nativeAmount ?? transaction.amount;
    result[month.month] = (
      income: previous.income + (transaction.type == 'income' ? amount : 0),
      expense: previous.expense + (transaction.type == 'expense' ? amount : 0),
      count: previous.count + 1,
    );
  }
  return result;
}

final yearCalendarTotalsProvider = FutureProvider.autoDispose
    .family<Map<int, MonthIncomeExpense>, YearCalendarQuery>(
        (ref, query) async {
  final rows = await ref
      .watch(repositoryProvider)
      .getTransactionsWithCategoryInRange(
          ledgerId: query.ledgerId,
          start: yearRangeFor(query.year, query.startDay).start,
          end: query.queryEnd);
  return calendarMonthlyTotals(rows.map((row) => row.t),
      year: query.year, startDay: query.startDay);
});

class YearIncomeExpenseCalendar extends ConsumerStatefulWidget {
  const YearIncomeExpenseCalendar({
    super.key,
    required this.year,
    required this.startDay,
    required this.queryEnd,
    required this.onPrevious,
    required this.onNext,
  });

  final int year;
  final int startDay;
  final DateTime queryEnd;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  ConsumerState<YearIncomeExpenseCalendar> createState() =>
      _YearIncomeExpenseCalendarState();
}

class _YearIncomeExpenseCalendarState
    extends ConsumerState<YearIncomeExpenseCalendar> {
  int? _selected;

  @override
  void didUpdateWidget(covariant YearIncomeExpenseCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year ||
        oldWidget.startDay != widget.startDay) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final hide = ref.watch(hideAmountsProvider);
    final currency = ref.watch(currentLedgerProvider).asData?.value?.currency;
    final primary = Theme.of(context).colorScheme.primary;
    final muted = BeeTokens.textSecondary(context);
    final incomeColor = BeeTokens.incomeColor(context, ref);
    final expenseColor = BeeTokens.expenseColor(context, ref);
    final nowLabel = labelForDate(DateTime.now(), widget.startDay);
    final selected =
        _selected ?? (nowLabel.year == widget.year ? nowLabel.month : 1);
    final query = (
      ledgerId: ref.watch(currentLedgerIdProvider),
      year: widget.year,
      startDay: widget.startDay,
      queryEnd: widget.queryEnd,
      refresh: ref.watch(statsRefreshProvider),
    );
    final totals = ref.watch(yearCalendarTotalsProvider(query));
    String monthLabel(int month) => l10n.homeMonth(month.toString());
    String money(double amount, bool future) => hide
        ? '****'
        : future
            ? '—'
            : formatMoneyCompact(amount);

    return totals.when(
      loading: () => const SizedBox(
          height: 300, child: Center(child: CircularProgressIndicator())),
      error: (error, stack) => TextButton.icon(
          onPressed: () => ref.invalidate(yearCalendarTotalsProvider(query)),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.commonError)),
      data: (months) {
        final total = months[selected] ?? (income: 0.0, expense: 0.0, count: 0);
        final selectedFuture =
            DateTime(widget.year, selected).isAfter(nowLabel);
        Widget summaryAmount(
                String label, double amount, Color color, String key) =>
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label, style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 4),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(money(amount, selectedFuture),
                          key: ValueKey(key),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: color))),
                ]));
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text(zh ? '年度收支' : 'Yearly income & expense',
                        style: BeeTextTokens.title(context))),
                if (currency != null)
                  Text('${zh ? '单位' : 'Currency'}：$currency',
                      style: TextStyle(fontSize: 11, color: muted)),
              ]),
              const SizedBox(height: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity > 0) widget.onPrevious();
                  if (velocity < 0) widget.onNext();
                },
                child: LayoutBuilder(builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: 12,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            constraints.maxWidth < 280 || scale > 1.4 ? 2 : 3,
                        mainAxisExtent: 104 * scale.clamp(1.0, 3.0),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8),
                    itemBuilder: (context, index) {
                      final month = index + 1;
                      final value = months[month] ??
                          (income: 0.0, expense: 0.0, count: 0);
                      final label = DateTime(widget.year, month);
                      final future = label.isAfter(nowLabel);
                      final current = label == nowLabel;
                      final isSelected = selected == month;
                      Widget amountRow(
                              String prefix, double amount, Color color) =>
                          Row(children: [
                            Text(prefix,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: amount == 0 ? muted : color)),
                            const SizedBox(width: 4),
                            Expanded(
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(money(amount, future),
                                        style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                amount == 0 ? muted : color)))),
                          ]);
                      return Semantics(
                          selected: isSelected,
                          child: Material(
                            color: isSelected
                                ? primary.withValues(alpha: .12)
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: .03),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                                side: BorderSide(
                                    color: isSelected
                                        ? primary
                                        : Colors.transparent)),
                            child: InkWell(
                              key: ValueKey('year_month_$month'),
                              borderRadius: BorderRadius.circular(11),
                              onTap: () => setState(() => _selected = month),
                              child: Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                              child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(monthLabel(month),
                                                      style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight: FontWeight
                                                              .w600)))),
                                          if (current || future)
                                            Flexible(
                                                child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 3,
                                                            vertical: 1),
                                                    decoration: BoxDecoration(
                                                        color: current
                                                            ? primary
                                                            : null,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4)),
                                                    child: Text(
                                                        current
                                                            ? (zh
                                                                ? '本月'
                                                                : 'Now')
                                                            : (zh
                                                                ? '未到'
                                                                : 'Later'),
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: current
                                                                ? Theme.of(context)
                                                                    .colorScheme
                                                                    .onPrimary
                                                                : muted)))),
                                        ]),
                                        amountRow(zh ? '支' : '−', value.expense,
                                            expenseColor),
                                        amountRow(zh ? '收' : '+', value.income,
                                            incomeColor),
                                      ])),
                            ),
                          ));
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              Semantics(
                  liveRegion: true,
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: Text(
                              '${monthLabel(selected)}${zh ? '收支' : ' totals'}',
                              key: const ValueKey('year_selected_month'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      Text(
                          selectedFuture
                              ? (zh ? '尚未到来' : 'Upcoming')
                              : total.count == 0
                                  ? (zh ? '暂无收支记录' : 'No transactions')
                                  : '${total.count} ${zh ? '笔记录' : 'transactions'}',
                          style: TextStyle(fontSize: 11, color: muted)),
                    ]),
                    if (periodRangeText(widget.year, selected, widget.startDay)
                        case final String range)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text(range,
                              style: TextStyle(fontSize: 11, color: muted))),
                    const SizedBox(height: 10),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          summaryAmount(l10n.homeExpense, total.expense,
                              expenseColor, 'year_selected_expense'),
                          const SizedBox(width: 8),
                          summaryAmount(l10n.homeIncome, total.income,
                              incomeColor, 'year_selected_income'),
                          const SizedBox(width: 8),
                          summaryAmount(
                              l10n.homeBalance,
                              total.income - total.expense,
                              BeeTokens.textPrimary(context),
                              'year_selected_balance'),
                        ]),
                  ])),
              const SizedBox(height: 10),
              const Divider(),
            ]);
      },
    );
  }
}
