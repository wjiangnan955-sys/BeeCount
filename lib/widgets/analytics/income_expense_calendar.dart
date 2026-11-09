import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db.dart' as db;
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../biz/amount_text.dart';

typedef CalendarEntry = ({
  db.Transaction t,
  db.Category? category,
  db.Account? account,
  db.Account? toAccount
});
typedef CalendarQuery = ({
  int ledgerId,
  DateTime start,
  DateTime end,
  int refresh
});

final _calendarEntries = FutureProvider.autoDispose
    .family<List<CalendarEntry>, CalendarQuery>((ref, query) async {
  final rows = await ref
      .watch(repositoryProvider)
      .getTransactionsWithCategoryInRange(
          ledgerId: query.ledgerId, start: query.start, end: query.end);
  return rows
      .where((row) =>
          !row.t.excludeFromStats &&
          (row.t.type == 'income' || row.t.type == 'expense'))
      .toList();
});

/// Uses local dates and the same converted amounts/exclusions as analytics.
Map<DateTime, ({double income, double expense})> calendarDailyTotals(
    Iterable<db.Transaction> transactions) {
  final result = <DateTime, ({double income, double expense})>{};
  for (final t in transactions) {
    if (t.excludeFromStats || (t.type != 'income' && t.type != 'expense')) {
      continue;
    }
    final local = t.happenedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final previous = result[day] ?? (income: 0.0, expense: 0.0);
    final amount = t.nativeAmount ?? t.amount;
    result[day] = (
      income: previous.income + (t.type == 'income' ? amount : 0),
      expense: previous.expense + (t.type == 'expense' ? amount : 0)
    );
  }
  return result;
}

class IncomeExpenseCalendar extends ConsumerStatefulWidget {
  const IncomeExpenseCalendar(
      {super.key,
      required this.start,
      required this.end,
      required this.queryEnd,
      required this.onPrevious,
      required this.onNext});
  final DateTime start;
  final DateTime end;
  final DateTime queryEnd;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  ConsumerState<IncomeExpenseCalendar> createState() =>
      _IncomeExpenseCalendarState();
}

class _IncomeExpenseCalendarState extends ConsumerState<IncomeExpenseCalendar> {
  DateTime? _selected;

  @override
  void didUpdateWidget(covariant IncomeExpenseCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start || oldWidget.end != widget.end) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final tick = ref.watch(statsRefreshProvider);
    final query = (
      ledgerId: ledgerId,
      start: widget.start,
      end: widget.queryEnd,
      refresh: tick
    );
    final entries = ref.watch(_calendarEntries(query));
    final primary = Theme.of(context).colorScheme.primary;
    final incomeColor = BeeTokens.incomeColor(context, ref);
    final expenseColor = BeeTokens.expenseColor(context, ref);
    final now = DateUtils.dateOnly(DateTime.now());
    final selected = _selected ??
        (!now.isBefore(widget.start) && now.isBefore(widget.end)
            ? now
            : widget.start);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final materials = MaterialLocalizations.of(context);

    return entries.when(
      loading: () => const SizedBox(
          height: 260, child: Center(child: CircularProgressIndicator())),
      error: (error, stack) => TextButton.icon(
          onPressed: () => ref.invalidate(_calendarEntries(query)),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.commonError)),
      data: (rows) {
        final totals = calendarDailyTotals(rows.map((row) => row.t));
        final dates = <DateTime>[];
        for (var day = widget.start;
            day.isBefore(widget.end);
            day = DateTime(day.year, day.month, day.day + 1)) {
          dates.add(day);
        }
        final offset = widget.start.weekday - 1;
        final cells = ((offset + dates.length + 6) ~/ 7) * 7;
        final selectedRows = rows
            .where((row) =>
                DateUtils.isSameDay(row.t.happenedAt.toLocal(), selected))
            .toList()
          ..sort((a, b) => b.t.happenedAt.compareTo(a.t.happenedAt));
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text(zh ? '收支日历' : l10n.calendarTitle,
                        style: BeeTextTokens.title(context))),
                Text(zh ? '收 · 收入' : '+ ${l10n.homeIncome}',
                    style: TextStyle(fontSize: 11, color: incomeColor)),
                const SizedBox(width: 12),
                Text(zh ? '支 · 支出' : '− ${l10n.homeExpense}',
                    style: TextStyle(fontSize: 11, color: expenseColor)),
              ]),
              const SizedBox(height: 14),
              Row(
                  children: List.generate(
                      7,
                      (index) => Expanded(
                          child: Center(
                              child: Text(
                                  materials.narrowWeekdays[(index + 1) % 7],
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: BeeTokens.textSecondary(
                                          context))))))),
              const SizedBox(height: 8),
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
                    itemCount: cells,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisExtent: 72 * scale.clamp(1.0, 2.0),
                        mainAxisSpacing: 3,
                        crossAxisSpacing: 2),
                    itemBuilder: (context, index) {
                      final position = index - offset;
                      if (position < 0 || position >= dates.length) {
                        return const SizedBox.shrink();
                      }
                      final day = dates[position];
                      final total = totals[day] ?? (income: 0.0, expense: 0.0);
                      final isToday = DateUtils.isSameDay(day, now);
                      final isSelected = DateUtils.isSameDay(day, selected);
                      Widget money(double value, String prefix, Color color) =>
                          Flexible(
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                      '$prefix ${hide ? '***' : value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}',
                                      style: TextStyle(
                                          fontSize: 11, color: color))));
                      return Semantics(
                        selected: isSelected,
                        label: materials.formatFullDate(day),
                        child: Material(
                            color: isSelected
                                ? primary.withValues(alpha: .12)
                                : Colors.transparent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                    color: isSelected
                                        ? primary
                                        : Colors.transparent)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() => _selected = day),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 2, vertical: 5),
                                  child: Column(children: [
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5),
                                        decoration: BoxDecoration(
                                            color: isToday ? primary : null,
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: Text(
                                            day.month != widget.start.month &&
                                                    day.day == 1
                                                ? '${day.month}/1'
                                                : '${day.day}',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: isToday
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .onPrimary
                                                    : day.isAfter(now)
                                                        ? BeeTokens
                                                            .textSecondary(
                                                                context)
                                                        : null))),
                                    const SizedBox(height: 3),
                                    if (total.income != 0)
                                      money(total.income, zh ? '收' : '+',
                                          incomeColor),
                                    if (total.expense != 0)
                                      money(total.expense, zh ? '支' : '−',
                                          expenseColor),
                                  ])),
                            )),
                      );
                    },
                  );
                }),
              ),
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(14)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            '${materials.formatMediumDate(selected)}${DateUtils.isSameDay(selected, now) ? ' · ${l10n.calendarToday}' : ''}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        if (selectedRows.isEmpty)
                          Text(l10n.calendarNoTransactions,
                              style: TextStyle(
                                  color: BeeTokens.textSecondary(context),
                                  fontSize: 12)),
                        for (final row in selectedRows)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: Text(
                                            row.t.note?.trim().isNotEmpty ==
                                                    true
                                                ? row.t.note!
                                                : row.category?.name ??
                                                    l10n.commonUncategorized,
                                            style:
                                                const TextStyle(fontSize: 13))),
                                    const SizedBox(width: 10),
                                    AmountText(
                                        value: (row.t.nativeAmount ??
                                                row.t.amount) *
                                            (row.t.type == 'income' ? 1 : -1),
                                        hide: hide,
                                        signed: true,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: row.t.type == 'income'
                                                ? incomeColor
                                                : expenseColor)),
                                  ])),
                      ])),
            ]);
      },
    );
  }
}
