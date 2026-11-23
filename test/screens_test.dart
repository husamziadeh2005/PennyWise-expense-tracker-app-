import 'dart:convert';

import 'package:expense_tracker/core/network/api_client.dart';
import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:expense_tracker/features/budgets/budgets_page.dart';
import 'package:expense_tracker/features/dashboard/dashboard_page.dart';
import 'package:expense_tracker/features/settings/settings_page.dart';
import 'package:expense_tracker/features/transactions/transaction_form_page.dart';
import 'package:expense_tracker/features/transactions/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Renders every main screen with a fake API (no network, no Supabase)
/// at a normal and a small phone size, failing on any layout overflow.

const food = {'id': 'c1', 'name': 'Food & Dining', 'type': 'expense', 'icon': 'restaurant', 'color': '#E57373'};
const salary = {'id': 'c2', 'name': 'Salary', 'type': 'income', 'icon': 'payments', 'color': '#66BB6A'};

final today = DateTime.now();
String day(int d) =>
    '${today.year}-${today.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

final transactions = [
  {'id': 't1', 'type': 'expense', 'amount': 42.75, 'categoryId': 'c1', 'category': food, 'note': 'Dinner with a very long note that should be cut off nicely', 'occurredOn': day(1), 'hasReceipt': true},
  {'id': 't2', 'type': 'income', 'amount': 2500, 'categoryId': 'c2', 'category': salary, 'note': null, 'occurredOn': day(1), 'hasReceipt': false},
  {'id': 't3', 'type': 'expense', 'amount': 9.99, 'categoryId': null, 'category': null, 'note': 'Parking', 'occurredOn': day(1), 'hasReceipt': false},
];

Map<String, dynamic> summary() => {
      'month': day(1).substring(0, 7),
      'totals': {'income': 2500, 'expense': 52.74, 'balance': 2447.26, 'transactionCount': 3, 'savingsRate': 97.9},
      'previousMonth': {'month': 'x', 'income': 2400, 'expense': 1890.5, 'incomeChangePercent': 4.2, 'expenseChangePercent': -97.2},
      'averages': {'daysCounted': 1, 'dailyExpense': 52.74},
      'topCategory': null,
      'largestExpense': {'id': 't1', 'amount': 42.75, 'note': 'Dinner', 'occurredOn': day(1), 'categoryName': 'Food & Dining'},
      'expenseByCategory': [
        {'categoryId': 'c1', 'name': 'Food & Dining', 'icon': 'restaurant', 'color': '#E57373', 'total': 42.75, 'count': 1, 'percent': 81.1},
        {'categoryId': null, 'name': 'Uncategorized', 'icon': 'category', 'color': '#9E9E9E', 'total': 9.99, 'count': 1, 'percent': 18.9},
      ],
      'incomeByCategory': [],
      'daily': [
        for (var d = 1; d <= DateUtils.getDaysInMonth(today.year, today.month); d++)
          {'date': day(d), 'income': 0, 'expense': d == 1 ? 52.74 : (d % 3 == 0 ? 12.5 * d : 0)}
      ],
      'budgets': [
        {'id': 'b1', 'categoryId': null, 'name': 'Overall', 'icon': 'wallet', 'color': '#14213D', 'limit': 1500, 'spent': 1252.74, 'remaining': 247.26, 'percent': 83.5, 'status': 'warning'},
        {'id': 'b2', 'categoryId': 'c1', 'name': 'Food & Dining', 'icon': 'restaurant', 'color': '#E57373', 'limit': 40, 'spent': 42.75, 'remaining': -2.75, 'percent': 106.9, 'status': 'over'},
      ],
      'allTime': {'income': 10000, 'expense': 4321.09, 'balance': 5678.91},
    };

http.Response json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  setUp(() {
    ApiClient.instance.tokenOverride = ({bool forceRefresh = false}) async => 'test-token';
    ApiClient.instance.httpClient = MockClient((req) async {
      expect(req.headers['Authorization'], 'Bearer test-token');
      final path = req.url.path;
      if (path == '/api/stats/summary') return json(summary());
      if (path == '/api/transactions') {
        return json({'items': transactions, 'total': 3, 'limit': 30, 'offset': 0, 'hasMore': false});
      }
      return http.Response('{"error":{"code":"not_found","message":"Not found."}}', 404);
    });
    final state = AppState.instance;
    state.profile = Profile.fromJson({
      'id': 'u1', 'fullName': 'Hussam Example', 'email': 'h@example.com',
      'currency': 'JOD', 'provider': 'email', 'country': 'Jordan', 'gender': 'Male',
    });
    state.categories = [Category.fromJson(food), Category.fromJson(salary)];
  });

  Future<void> pumpScreen(WidgetTester tester, Widget page, Size size, {Brightness b = Brightness.light}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFF14213D), brightness: b),
      home: page,
    ));
    await tester.pumpAndSettle();
  }

  final screens = <String, Widget Function()>{
    'dashboard': () => DashboardPage(onSeeAll: () {}),
    'transactions': () => const TransactionsPage(),
    'budgets': () => const BudgetsPage(),
    'settings': () => const SettingsPage(),
    'form': () => const TransactionFormPage(),
  };

  for (final size in const [Size(390, 844), Size(320, 600)]) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} renders at ${size.width.toInt()}px wide', (tester) async {
        await pumpScreen(tester, entry.value(), size);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('dashboard shows the summary numbers', (tester) async {
    await pumpScreen(tester, DashboardPage(onSeeAll: () {}), const Size(390, 844));
    expect(find.text('Hi, Hussam'), findsOneWidget);
    expect(find.textContaining('2,447.26'), findsOneWidget); // balance
    expect(find.textContaining('84%'), findsOneWidget); // overall budget used (83.5 -> 84)
    expect(find.text('Food & Dining'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Recent transactions'), 200);
    expect(find.text('Parking'), findsNothing); // dense tile shows "Today · Parking"
  });

  testWidgets('transactions are grouped by day with a net total', (tester) async {
    await pumpScreen(tester, const TransactionsPage(), const Size(390, 844));
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget); // t1 has a receipt
    expect(find.textContaining('2,447.26'), findsOneWidget); // 2500 - 42.75 - 9.99
  });

  testWidgets('form validates the amount', (tester) async {
    await pumpScreen(tester, const TransactionFormPage(), const Size(390, 844));
    await tester.tap(find.text('Add transaction'));
    await tester.pump();
    expect(find.text('Enter an amount'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '12.345');
    await tester.tap(find.text('Add transaction'));
    await tester.pump();
    expect(find.text('Use a number with up to 2 decimals'), findsOneWidget);
  });
}
