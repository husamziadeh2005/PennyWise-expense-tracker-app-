import 'package:flutter/material.dart';

import 'package:expense_tracker/data/api/expense_api.dart';
import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:expense_tracker/core/widgets/common.dart';
import 'package:expense_tracker/features/transactions/transaction_form_page.dart';
import 'package:expense_tracker/features/transactions/transactions_page.dart' show TransactionTile;

/// Dashboard: this month's numbers using simple math (totals, averages,
/// percentages) — all calculated by the API's /stats/summary endpoint.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.onSeeAll});
  final VoidCallback onSeeAll;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _state = AppState.instance;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  MonthlySummary? _summary;
  List<Transaction> _recent = const [];
  String? _error;
  bool _loading = true;
  int _seenVersion = -1;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
    _load();
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (_state.dataVersion != _seenVersion) {
      _load();
    } else if (mounted) {
      setState(() {}); // e.g. name or currency changed in Settings
    }
  }

  Future<void> _load() async {
    _seenVersion = _state.dataVersion;
    final request = ++_request; // ignore answers to older requests
    setState(() => _loading = _summary == null);
    try {
      final last = DateTime(_month.year, _month.month + 1, 0);
      final results = await Future.wait([
        ExpenseApi.summary(_month),
        ExpenseApi.transactions(from: _month, to: last, limit: 5),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _summary = results[0] as MonthlySummary;
        _recent = (results[1] as TransactionPage).items;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  void _changeMonth(DateTime m) {
    setState(() {
      _month = m;
      _summary = null;
    });
    _load();
  }

  Future<void> _edit(Transaction t) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => TransactionFormPage(transaction: t)));
    if (saved == true) _state.dataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _state.profile;
    final name = profile?.fullName?.split(' ').first;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          if (profile != null) ...[
            UserAvatar(name: profile.displayName, imageUrl: profile.avatarUrl, radius: 18),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(name == null || name.isEmpty ? 'Dashboard' : 'Hi, $name',
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            MonthSwitcher(month: _month, onChanged: _changeMonth),
            if (_loading)
              const Padding(padding: EdgeInsets.all(64), child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _summary == null)
              ErrorView(message: _error!, onRetry: _load)
            else if (_summary != null)
              ..._content(_summary!),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(MonthlySummary s) => [
        _BalanceCard(summary: s),
        _QuickStats(summary: s),
        if (s.overallBudget != null) _BudgetCard(budget: s.overallBudget!),
        SectionCard(
          title: 'Spending by category',
          child: s.expenseByCategory.isEmpty
              ? const Text('No expenses this month yet.')
              : Column(children: [for (final c in s.expenseByCategory.take(6)) _CategoryBar(share: c)]),
        ),
        SectionCard(title: 'Daily spending', child: _DailyBars(days: s.daily)),
        SectionCard(
          title: 'Recent transactions',
          trailing: TextButton(onPressed: widget.onSeeAll, child: const Text('See all')),
          child: _recent.isEmpty
              ? const Text('Tap + to add your first transaction.')
              : Column(children: [
                  for (final t in _recent) TransactionTile(transaction: t, onTap: () => _edit(t), dense: true),
                ]),
        ),
      ];
}

// ------------------------------------------------------------------ widgets

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});
  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = scheme.onPrimary;
    return Card(
      color: scheme.primary,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Balance this month', style: TextStyle(color: on.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          Text(money(summary.balance),
              style: TextStyle(color: on, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Total balance: ${money(summary.allTimeBalance)}',
              style: TextStyle(color: on.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _flow(Icons.arrow_downward, 'Income', summary.income, on)),
            Expanded(child: _flow(Icons.arrow_upward, 'Expenses', summary.expense, on)),
          ]),
        ]),
      ),
    );
  }

  Widget _flow(IconData icon, String label, double value, Color on) => Row(children: [
        CircleAvatar(
            radius: 16,
            backgroundColor: on.withValues(alpha: 0.15),
            child: Icon(icon, size: 16, color: on)),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: on.withValues(alpha: 0.8), fontSize: 12)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(money(value), style: TextStyle(color: on, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ]);
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.summary});
  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final change = summary.expenseChangePercent;
    final tiles = [
      _StatTile(
        icon: Icons.calendar_today,
        label: 'Daily average',
        value: summary.dailyAverage == null ? '—' : money(summary.dailyAverage!),
        hint: 'spent per day',
      ),
      _StatTile(
        icon: Icons.savings_outlined,
        label: 'Savings rate',
        value: percentLabel(summary.savingsRate),
        hint: 'of income kept',
      ),
      _StatTile(
        icon: change == null || change <= 0 ? Icons.trending_down : Icons.trending_up,
        label: 'vs last month',
        value: change == null ? '—' : '${change > 0 ? '+' : ''}${percentLabel(change)}',
        hint: 'expenses (${money(summary.previousExpense)})',
        color: change == null ? null : (change > 0 ? expenseColor : incomeColor),
      ),
      _StatTile(
        icon: Icons.local_fire_department_outlined,
        label: 'Biggest expense',
        value: summary.largestExpenseAmount == null ? '—' : money(summary.largestExpenseAmount!),
        hint: summary.largestExpenseLabel ?? '${summary.transactionCount} transactions',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(children: [
        Row(children: [Expanded(child: tiles[0]), Expanded(child: tiles[1])]),
        Row(children: [Expanded(child: tiles[2]), Expanded(child: tiles[3])]),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value, required this.hint, this.color});
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ),
          Text(hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ]),
      ),
    );
  }
}

/// Colour for a budget's progress: green < 80%, orange < 100%, red over.
Color budgetColor(String status) => switch (status) {
      'over' => expenseColor,
      'warning' => Colors.orange.shade700,
      _ => incomeColor,
    };

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget});
  final BudgetStatus budget;

  @override
  Widget build(BuildContext context) {
    final color = budgetColor(budget.status);
    return SectionCard(
      title: 'Monthly budget',
      trailing: Text('${percentLabel(budget.percent)} used', style: TextStyle(color: color)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (budget.percent / 100).clamp(0, 1).toDouble(),
            minHeight: 10,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          budget.remaining >= 0
              ? '${money(budget.spent)} of ${money(budget.limit)} · ${money(budget.remaining)} left'
              : '${money(budget.spent)} of ${money(budget.limit)} · ${money(-budget.remaining)} over budget',
        ),
      ]),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.share});
  final CategoryShare share;

  @override
  Widget build(BuildContext context) {
    final color = hexColor(share.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        CategoryAvatar(icon: share.icon, color: share.color, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(share.name, overflow: TextOverflow.ellipsis)),
              Text(money(share.total), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: share.percent / 100,
                    minHeight: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(percentLabel(share.percent),
                    textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// A plain bar per day of the month; bar height = that day's expenses
/// divided by the biggest day.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});
  final List<DailyTotal> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = days.fold<double>(0, (m, d) => d.expense > m ? d.expense : m);
    if (max == 0) return const Text('No expenses this month yet.');
    final today = ExpenseApi.dateString(DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Highest day: ${money(max)}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      SizedBox(
        height: 110,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in days)
              Expanded(
                child: Tooltip(
                  message: '${d.date.substring(8)}: ${money(d.expense)}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: d.expense == 0 ? 2 : (d.expense / max * 106).clamp(3, 106).toDouble(),
                      decoration: BoxDecoration(
                        color: d.date == today ? scheme.tertiary : scheme.primary.withValues(alpha: d.expense == 0 ? 0.15 : 0.75),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('1', style: Theme.of(context).textTheme.bodySmall),
        Text('${days.length ~/ 2}', style: Theme.of(context).textTheme.bodySmall),
        Text('${days.length}', style: Theme.of(context).textTheme.bodySmall),
      ]),
    ]);
  }
}
