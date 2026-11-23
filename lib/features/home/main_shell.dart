import 'package:flutter/material.dart';

import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:expense_tracker/features/budgets/budgets_page.dart';
import 'package:expense_tracker/core/widgets/common.dart';
import 'package:expense_tracker/features/dashboard/dashboard_page.dart';
import 'package:expense_tracker/features/settings/settings_page.dart';
import 'package:expense_tracker/features/transactions/transaction_form_page.dart';
import 'package:expense_tracker/features/transactions/transactions_page.dart';

/// The signed-in app: four tabs with a navigation bar at the bottom.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  final _state = AppState.instance;

  @override
  void initState() {
    super.initState();
    _state.start();
  }

  @override
  void dispose() {
    _state.stop();
    super.dispose();
  }

  Future<void> _addTransaction() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TransactionFormPage()),
    );
    if (saved == true) _state.dataChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        // First load (profile + categories) must succeed before showing tabs.
        if (_state.profile == null && _state.categories.isEmpty) {
          return Scaffold(
            body: _state.loadError != null
                ? ErrorView(
                    message: _state.loadError!,
                    onRetry: _state.load,
                    autoRetrying: _state.loadErrorIsNetwork,
                    debugDetails: _state.loadErrorIsNetwork ? ApiConfig.debugHint : null,
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          body: IndexedStack(
            index: _tab,
            children: [
              DashboardPage(onSeeAll: () => setState(() => _tab = 1)),
              const TransactionsPage(),
              const BudgetsPage(),
              const SettingsPage(),
            ],
          ),
          floatingActionButton: _tab <= 1
              ? FloatingActionButton(
                  tooltip: 'Add transaction',
                  onPressed: _addTransaction,
                  child: const Icon(Icons.add),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
              NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transactions'),
              NavigationDestination(
                  icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Budgets'),
              NavigationDestination(
                  icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}
