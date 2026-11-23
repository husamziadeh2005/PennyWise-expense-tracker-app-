import 'dart:async';

import 'package:flutter/material.dart';

import 'package:expense_tracker/data/api/expense_api.dart';
import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:expense_tracker/core/widgets/common.dart';
import 'package:expense_tracker/features/transactions/transaction_form_page.dart';

/// All transactions of a month, grouped by day, with type filter, search
/// and "load more" paging. Swipe left to delete, tap to edit.
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  static const _pageSize = 30;

  final _state = AppState.instance;
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  TxType? _type;
  String _search = '';
  bool _searching = false;

  final List<Transaction> _items = [];
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _request = 0;
  int _seenVersion = -1;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _scroll.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onState() {
    if (_state.dataVersion != _seenVersion) {
      _reload();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<TransactionPage> _fetch(int offset) => ExpenseApi.transactions(
        from: _search.isEmpty ? _month : null,
        to: _search.isEmpty ? DateTime(_month.year, _month.month + 1, 0) : null,
        type: _type,
        search: _search,
        limit: _pageSize,
        offset: offset,
      );

  /// Starts again from the first page (filters changed or data changed).
  Future<void> _reload() async {
    _seenVersion = _state.dataVersion;
    final request = ++_request;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await _fetch(0);
      if (!mounted || request != _request) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = page.total;
        _hasMore = page.hasMore;
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

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_items.length);
      if (!mounted || request != _request) return;
      setState(() {
        // skip anything we already have (in case rows moved between pages)
        final known = _items.map((t) => t.id).toSet();
        _items.addAll(page.items.where((t) => !known.contains(t.id)));
        _total = page.total;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _applyFilters(VoidCallback change) {
    setState(() {
      change();
      _items.clear();
    });
    _reload();
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (text.trim() != _search) _applyFilters(() => _search = text.trim());
    });
  }

  Future<void> _edit(Transaction t) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => TransactionFormPage(transaction: t)));
    if (saved == true) _state.dataChanged();
  }

  Future<bool> _delete(Transaction t) async {
    final ok = await confirm(context,
        title: 'Delete transaction?',
        message: '${money(t.amount)} · ${t.category?.name ?? 'Uncategorized'}\nThis cannot be undone.');
    if (!ok || !mounted) return false;
    try {
      await ExpenseApi.deleteTransaction(t.id);
      if (!mounted) return true;
      setState(() {
        _items.removeWhere((x) => x.id == t.id);
        _total--;
      });
      showMessage(context, 'Transaction deleted.');
      _state.dataChanged();
      return true;
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search notes…', border: InputBorder.none),
                onChanged: _onSearchChanged,
              )
            : const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _searchController.clear();
                if (_search.isNotEmpty) _applyFilters(() => _search = '');
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        if (_search.isEmpty) MonthSwitcher(month: _month, onChanged: (m) => _applyFilters(() => _month = m)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              // scrolls sideways on narrow phones instead of overflowing
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (label, type) in [('All', null), ('Expenses', TxType.expense), ('Income', TxType.income)])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _type == type,
                        onSelected: (_) => _applyFilters(() => _type = type),
                      ),
                    ),
                ]),
              ),
            ),
            if (!_loading)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('$_total', style: TextStyle(color: Theme.of(context).hintColor)),
              ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorView(message: _error!, onRetry: _reload);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(children: [
          EmptyView(
            icon: Icons.receipt_long_outlined,
            title: _search.isNotEmpty ? 'No matches for "$_search"' : 'No transactions in ${monthLabel(_month)}',
            subtitle: _search.isNotEmpty ? null : 'Tap + to add one.',
          ),
        ]),
      );
    }

    // Build "day header, its rows, next day header…"
    final rows = <Widget>[];
    String? currentDay;
    for (final t in _items) {
      if (t.occurredOn != currentDay) {
        currentDay = t.occurredOn;
        final dayItems = _items.where((x) => x.occurredOn == currentDay);
        final net = dayItems.fold<double>(0, (s, x) => s + (x.type == TxType.income ? x.amount : -x.amount));
        rows.add(_DayHeader(date: t.date, net: net));
      }
      rows.add(Dismissible(
        key: ValueKey(t.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _delete(t),
        background: Container(
          color: Theme.of(context).colorScheme.error,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError),
        ),
        child: TransactionTile(transaction: t, onTap: () => _edit(t)),
      ));
    }
    if (_loadingMore) {
      rows.add(const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())));
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        children: rows,
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.net});
  final DateTime date;
  final double net;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).hintColor);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(children: [
        Expanded(child: Text(dayLabel(date), style: style)),
        Text(money(net, sign: true), style: style),
      ]),
    );
  }
}

/// One transaction row (used here and on the dashboard).
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction, this.onTap, this.dense = false});
  final Transaction transaction;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final isIncome = t.type == TxType.income;
    final subtitle = [
      if (dense) dayLabel(t.date),
      if (t.note?.isNotEmpty ?? false) t.note!,
    ].join(' · ');
    return ListTile(
      contentPadding: dense ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
      onTap: onTap,
      leading: CategoryAvatar(icon: t.category?.icon, color: t.category?.color),
      title: Row(children: [
        Flexible(child: Text(t.category?.name ?? 'Uncategorized', overflow: TextOverflow.ellipsis)),
        if (t.hasReceipt) ...[
          const SizedBox(width: 6),
          Icon(Icons.attach_file, size: 16, color: Theme.of(context).hintColor),
        ],
      ]),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        money(isIncome ? t.amount : -t.amount, sign: true),
        style: TextStyle(fontWeight: FontWeight.w600, color: isIncome ? incomeColor : expenseColor),
      ),
    );
  }
}
