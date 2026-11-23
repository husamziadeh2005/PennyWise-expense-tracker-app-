import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/core/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Transaction parses the API shape', () {
    final t = Transaction.fromJson({
      'id': 't1',
      'type': 'expense',
      'amount': 12.5,
      'categoryId': 'c1',
      'category': {'id': 'c1', 'name': 'Food', 'icon': 'restaurant', 'color': '#E57373'},
      'note': null,
      'occurredOn': '2026-11-19',
      'hasReceipt': true,
    });
    expect(t.type, TxType.expense);
    expect(t.amount, 12.5);
    expect(t.category!.name, 'Food');
    expect(t.category!.type, TxType.expense);
    expect(t.date, DateTime(2026, 11, 19));
    expect(t.hasReceipt, isTrue);
  });

  test('Transaction without category', () {
    final t = Transaction.fromJson(
        {'id': 't', 'type': 'income', 'amount': 3, 'occurredOn': '2026-01-01', 'category': null});
    expect(t.category, isNull);
    expect(t.amount, 3.0);
  });

  test('MonthlySummary parses totals, budgets and nullable numbers', () {
    final s = MonthlySummary.fromJson({
      'month': '2026-11',
      'totals': {'income': 1000, 'expense': 150.3, 'balance': 849.7, 'transactionCount': 5, 'savingsRate': 85},
      'previousMonth': {'month': '2026-10', 'income': 0, 'expense': 0, 'incomeChangePercent': null, 'expenseChangePercent': null},
      'averages': {'daysCounted': 0, 'dailyExpense': null},
      'topCategory': null,
      'largestExpense': {'id': 'x', 'amount': 99.7, 'note': '', 'occurredOn': '2026-11-05', 'categoryName': 'Fun'},
      'expenseByCategory': [
        {'categoryId': null, 'name': 'Uncategorized', 'icon': 'category', 'color': '#9E9E9E', 'total': 50, 'count': 1, 'percent': 33.3}
      ],
      'incomeByCategory': [],
      'daily': [
        {'date': '2026-11-01', 'income': 1000, 'expense': 0}
      ],
      'budgets': [
        {'id': 'b', 'categoryId': null, 'name': 'Overall', 'icon': 'wallet', 'color': '#14213D', 'limit': 200, 'spent': 150.3, 'remaining': 49.7, 'percent': 75.2, 'status': 'ok'}
      ],
      'allTime': {'income': 1000, 'expense': 150.3, 'balance': 849.7},
    });
    expect(s.expense, 150.3);
    expect(s.dailyAverage, isNull);
    expect(s.expenseChangePercent, isNull);
    expect(s.overallBudget!.remaining, 49.7);
    expect(s.largestExpenseLabel, 'Fun'); // empty note falls back to category
    expect(s.expenseByCategory.single.categoryId, isNull);
  });

  test('money formatting always shows 2 decimals', () {
    expect(money(1234.5, currency: 'USD'), r'$1,234.50');
    expect(money(-3, currency: 'USD'), r'-$3.00');
    expect(money(3, currency: 'USD', sign: true), r'+$3.00');
    expect(money(0.1 + 0.2, currency: 'USD'), r'$0.30');
  });

  test('colour helpers round-trip', () {
    expect(colorHex(hexColor('#E57373')), '#E57373');
    expect(hexColor('nonsense'), Colors.blueGrey);
    expect(iconFor('unknown_icon'), Icons.category);
  });
}
