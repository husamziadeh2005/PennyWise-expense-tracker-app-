// Plain data classes that mirror the API's JSON (camelCase).

double _num(dynamic v) => v == null ? 0 : (v as num).toDouble();
double? _numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();

enum TxType {
  income,
  expense;

  static TxType parse(String v) => v == 'income' ? income : expense;
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
  });

  final String id;
  final String name;
  final TxType type;
  final String icon;
  final String color;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        type: TxType.parse(j['type'] as String? ?? 'expense'),
        icon: j['icon'] as String? ?? 'category',
        color: j['color'] as String? ?? '#607D8B',
      );
}

class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.occurredOn,
    this.categoryId,
    this.category,
    this.note,
    this.hasReceipt = false,
  });

  final String id;
  final TxType type;
  final double amount;
  final String? categoryId;
  final Category? category;
  final String? note;

  /// Calendar date "YYYY-MM-DD" (no time zone).
  final String occurredOn;
  final bool hasReceipt;

  DateTime get date => DateTime.parse(occurredOn);

  factory Transaction.fromJson(Map<String, dynamic> j) {
    final cat = j['category'] as Map<String, dynamic>?;
    return Transaction(
      id: j['id'] as String,
      type: TxType.parse(j['type'] as String),
      amount: _num(j['amount']),
      categoryId: j['categoryId'] as String?,
      category: cat == null ? null : Category.fromJson({'type': j['type'], ...cat}),
      note: j['note'] as String?,
      occurredOn: j['occurredOn'] as String,
      hasReceipt: j['hasReceipt'] == true,
    );
  }
}

class TransactionPage {
  const TransactionPage(this.items, this.total, this.hasMore);
  final List<Transaction> items;
  final int total;
  final bool hasMore;

  factory TransactionPage.fromJson(Map<String, dynamic> j) => TransactionPage(
        (j['items'] as List).map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList(),
        (j['total'] as num).toInt(),
        j['hasMore'] == true,
      );
}

class Budget {
  const Budget({required this.id, required this.amount, this.categoryId, this.category});
  final String id;
  final double amount;
  final String? categoryId;
  final Category? category;

  factory Budget.fromJson(Map<String, dynamic> j) {
    final cat = j['category'] as Map<String, dynamic>?;
    return Budget(
      id: j['id'] as String,
      amount: _num(j['amount']),
      categoryId: j['categoryId'] as String?,
      category: cat == null ? null : Category.fromJson(cat),
    );
  }
}

class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.email,
    this.phone,
    this.country,
    this.gender,
    this.avatarUrl,
    this.currency = 'USD',
    this.provider,
  });

  final String id;
  final String? fullName;
  final String? email;
  final String? phone;
  final String? country;
  final String? gender;
  final String? avatarUrl;
  final String currency;
  final String? provider;

  String get displayName =>
      (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : (email ?? phone ?? 'You');

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        fullName: j['fullName'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        country: j['country'] as String?,
        gender: j['gender'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        currency: j['currency'] as String? ?? 'USD',
        provider: j['provider'] as String?,
      );
}

// ------------------------------------------------------------ stats summary

class CategoryShare {
  const CategoryShare(this.categoryId, this.name, this.icon, this.color, this.total, this.count,
      this.percent);
  final String? categoryId;
  final String name;
  final String icon;
  final String color;
  final double total;
  final int count;
  final double percent;

  factory CategoryShare.fromJson(Map<String, dynamic> j) => CategoryShare(
        j['categoryId'] as String?,
        j['name'] as String,
        j['icon'] as String? ?? 'category',
        j['color'] as String? ?? '#9E9E9E',
        _num(j['total']),
        (j['count'] as num).toInt(),
        _num(j['percent']),
      );
}

class BudgetStatus {
  const BudgetStatus(this.id, this.categoryId, this.name, this.icon, this.color, this.limit,
      this.spent, this.remaining, this.percent, this.status);
  final String id;
  final String? categoryId;
  final String name;
  final String icon;
  final String color;
  final double limit;
  final double spent;
  final double remaining;
  final double percent;
  final String status; // ok | warning | over

  factory BudgetStatus.fromJson(Map<String, dynamic> j) => BudgetStatus(
        j['id'] as String,
        j['categoryId'] as String?,
        j['name'] as String,
        j['icon'] as String? ?? 'wallet',
        j['color'] as String? ?? '#14213D',
        _num(j['limit']),
        _num(j['spent']),
        _num(j['remaining']),
        _num(j['percent']),
        j['status'] as String? ?? 'ok',
      );
}

class DailyTotal {
  const DailyTotal(this.date, this.income, this.expense);
  final String date;
  final double income;
  final double expense;
}

class MonthlySummary {
  const MonthlySummary({
    required this.month,
    required this.income,
    required this.expense,
    required this.balance,
    required this.transactionCount,
    required this.savingsRate,
    required this.previousExpense,
    required this.expenseChangePercent,
    required this.incomeChangePercent,
    required this.dailyAverage,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.daily,
    required this.budgets,
    required this.allTimeBalance,
    this.largestExpenseAmount,
    this.largestExpenseLabel,
  });

  final String month;
  final double income;
  final double expense;
  final double balance;
  final int transactionCount;
  final double? savingsRate;
  final double previousExpense;
  final double? expenseChangePercent;
  final double? incomeChangePercent;
  final double? dailyAverage;
  final List<CategoryShare> expenseByCategory;
  final List<CategoryShare> incomeByCategory;
  final List<DailyTotal> daily;
  final List<BudgetStatus> budgets;
  final double allTimeBalance;
  final double? largestExpenseAmount;
  final String? largestExpenseLabel;

  BudgetStatus? get overallBudget =>
      budgets.where((b) => b.categoryId == null).firstOrNull;

  factory MonthlySummary.fromJson(Map<String, dynamic> j) {
    final totals = j['totals'] as Map<String, dynamic>;
    final prev = j['previousMonth'] as Map<String, dynamic>;
    final largest = j['largestExpense'] as Map<String, dynamic>?;
    List<CategoryShare> shares(String key) => (j[key] as List)
        .map((e) => CategoryShare.fromJson(e as Map<String, dynamic>))
        .toList();
    return MonthlySummary(
      month: j['month'] as String,
      income: _num(totals['income']),
      expense: _num(totals['expense']),
      balance: _num(totals['balance']),
      transactionCount: (totals['transactionCount'] as num).toInt(),
      savingsRate: _numOrNull(totals['savingsRate']),
      previousExpense: _num(prev['expense']),
      expenseChangePercent: _numOrNull(prev['expenseChangePercent']),
      incomeChangePercent: _numOrNull(prev['incomeChangePercent']),
      dailyAverage: _numOrNull((j['averages'] as Map)['dailyExpense']),
      expenseByCategory: shares('expenseByCategory'),
      incomeByCategory: shares('incomeByCategory'),
      daily: (j['daily'] as List)
          .map((e) => DailyTotal(e['date'] as String, _num(e['income']), _num(e['expense'])))
          .toList(),
      budgets: (j['budgets'] as List)
          .map((e) => BudgetStatus.fromJson(e as Map<String, dynamic>))
          .toList(),
      allTimeBalance: _num((j['allTime'] as Map)['balance']),
      largestExpenseAmount: largest == null ? null : _num(largest['amount']),
      largestExpenseLabel: largest == null
          ? null
          : ((largest['note'] as String?)?.isNotEmpty ?? false)
              ? largest['note'] as String
              : largest['categoryName'] as String?,
    );
  }
}
