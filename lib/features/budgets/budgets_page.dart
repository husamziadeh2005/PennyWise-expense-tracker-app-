import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:expense_tracker/data/api/expense_api.dart';
import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:expense_tracker/core/widgets/common.dart';
import 'package:expense_tracker/features/dashboard/dashboard_page.dart' show budgetColor;

/// Monthly spending limits: one overall budget plus optional budgets per
/// expense category, each showing how much of it this month has used.
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  final _state = AppState.instance;
  MonthlySummary? _summary;
  String? _error;
  int _seenVersion = -1;
  int _request = 0;

  DateTime get _thisMonth => DateTime(DateTime.now().year, DateTime.now().month);

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
      setState(() {});
    }
  }

  Future<void> _load() async {
    _seenVersion = _state.dataVersion;
    final request = ++_request;
    try {
      final s = await ExpenseApi.summary(_thisMonth);
      if (!mounted || request != _request) return;
      setState(() {
        _summary = s;
        _error = null;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _error = errorText(e));
    }
  }

  Future<void> _add() async {
    final used = _summary!.budgets.map((b) => b.categoryId).toSet();
    final options = <(String?, String)>[
      if (!used.contains(null)) (null, 'Overall (all expenses)'),
      for (final c in _state.categoriesOf(TxType.expense))
        if (!used.contains(c.id)) (c.id, c.name),
    ];
    if (options.isEmpty) {
      showMessage(context, 'Every category already has a budget.');
      return;
    }
    final result = await showDialog<(String?, double)>(
      context: context,
      builder: (_) => _BudgetDialog(options: options),
    );
    if (result == null) return;
    await _run(() => ExpenseApi.createBudget(categoryId: result.$1, amount: result.$2), 'Budget added.');
  }

  Future<void> _edit(BudgetStatus b) async {
    final result = await showDialog<(String?, double)>(
      context: context,
      builder: (_) => _BudgetDialog(existing: b),
    );
    if (result == null || !mounted) return;
    if (result.$2 <= 0) {
      final ok = await confirm(context, title: 'Delete budget?', message: 'Remove the "${b.name}" budget?');
      if (ok) await _run(() => ExpenseApi.deleteBudget(b.id), 'Budget deleted.');
      return;
    }
    await _run(() => ExpenseApi.updateBudget(b.id, result.$2), 'Budget updated.');
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      showMessage(context, done);
      _state.dataChanged();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          if (s != null) IconButton(tooltip: 'Add budget', icon: const Icon(Icons.add), onPressed: _add),
        ],
      ),
      body: s == null
          ? (_error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('${monthLabel(_thisMonth)} · budgets reset every month',
                      style: TextStyle(color: Theme.of(context).hintColor)),
                ),
                if (s.budgets.isEmpty)
                  EmptyView(
                    icon: Icons.savings_outlined,
                    title: 'No budgets yet',
                    subtitle: 'Set a monthly limit to see how much you can still spend.',
                  ),
                if (s.budgets.isEmpty)
                  Center(
                    child: FilledButton.icon(
                        onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add a budget')),
                  ),
                for (final b in s.budgets) _BudgetTile(budget: b, onTap: () => _edit(b)),
              ]),
            ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.budget, required this.onTap});
  final BudgetStatus budget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = budget;
    final color = budgetColor(b.status);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CategoryAvatar(icon: b.icon, color: b.color, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(b.name, style: Theme.of(context).textTheme.titleMedium)),
              Text(percentLabel(b.percent), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (b.percent / 100).clamp(0, 1).toDouble(),
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('${money(b.spent)} of ${money(b.limit)}')),
              Text(
                b.remaining >= 0 ? '${money(b.remaining)} left' : '${money(-b.remaining)} over',
                style: TextStyle(color: b.remaining >= 0 ? null : expenseColor),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Add (choose category + amount) or edit (amount, or delete) a budget.
/// Returns (categoryId, amount); amount 0 means "delete".
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({this.options = const [], this.existing});
  final List<(String?, String)> options;
  final BudgetStatus? existing;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _amount = TextEditingController(text: widget.existing?.limit.toStringAsFixed(2) ?? '');
  late String? _categoryId = widget.existing?.categoryId ?? widget.options.firstOrNull?.$1;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _amount.text.trim().replaceAll(',', '.');
    final value = double.tryParse(text);
    if (value == null || value <= 0 || !RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) {
      setState(() => _error = 'Enter an amount greater than 0 (max 2 decimals)');
      return;
    }
    Navigator.pop(context, (_categoryId, value));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? '${widget.existing!.name} budget' : 'New monthly budget'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!editing)
          DropdownButtonFormField<String?>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'For', border: OutlineInputBorder()),
            items: [
              for (final (id, name) in widget.options) DropdownMenuItem(value: id, child: Text(name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        if (!editing) const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Monthly limit',
            prefixText: '${AppState.instance.currency} ',
            border: const OutlineInputBorder(),
            errorText: _error,
            errorMaxLines: 2,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        if (editing)
          TextButton(
            onPressed: () => Navigator.pop(context, (widget.existing!.categoryId, 0.0)),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
