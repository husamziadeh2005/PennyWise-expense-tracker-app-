import 'dart:typed_data';

import 'package:expense_tracker/data/models/models.dart';
import 'package:expense_tracker/core/network/api_client.dart';

/// Typed wrappers for every endpoint of the Node.js API.
/// UI code calls these and never builds URLs or JSON by hand.
class ExpenseApi {
  ExpenseApi._();

  static final _c = ApiClient.instance;

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String dateString(DateTime d) => _date(d);
  static String monthString(DateTime d) => _date(d).substring(0, 7);

  // ---------------------------------------------------------------- auth

  static Future<({Profile? profile, bool canDeleteAccount})> me() async {
    final j = await _c.get('/auth/me') as Map<String, dynamic>;
    final p = j['profile'] as Map<String, dynamic>?;
    return (
      profile: p == null ? null : Profile.fromJson(p),
      canDeleteAccount: (j['features'] as Map?)?['accountDeletion'] == true,
    );
  }

  // ------------------------------------------------------------- profile

  static Future<Profile> updateProfile({
    String? fullName,
    String? country,
    String? gender,
    String? currency,
  }) async =>
      Profile.fromJson(await _c.patch('/profile', {
        'fullName': ?fullName,
        'country': ?country,
        'gender': ?gender,
        'currency': ?currency,
      }) as Map<String, dynamic>);

  static Future<Profile> uploadAvatar(Uint8List bytes, String filename) async =>
      Profile.fromJson(await _c.upload('/profile/avatar', bytes, filename) as Map<String, dynamic>);

  static Future<Profile> removeAvatar() async =>
      Profile.fromJson(await _c.delete('/profile/avatar') as Map<String, dynamic>);

  // ---------------------------------------------------------- categories

  static Future<List<Category>> categories() async {
    final j = await _c.get('/categories') as Map<String, dynamic>;
    return (j['items'] as List).map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Category> createCategory(
          {required String name, required TxType type, required String icon, required String color}) async =>
      Category.fromJson(await _c.post('/categories',
          {'name': name, 'type': type.name, 'icon': icon, 'color': color}) as Map<String, dynamic>);

  static Future<Category> updateCategory(String id,
          {required String name, required String icon, required String color}) async =>
      Category.fromJson(await _c.patch('/categories/$id', {'name': name, 'icon': icon, 'color': color})
          as Map<String, dynamic>);

  /// Returns how many transactions were moved / left without a category.
  static Future<int> deleteCategory(String id, {String? reassignTo}) async {
    final j = await _c.delete('/categories/$id', query: {'reassignTo': reassignTo}) as Map;
    return (j['affectedTransactions'] as num?)?.toInt() ?? 0;
  }

  // -------------------------------------------------------- transactions

  static Future<TransactionPage> transactions({
    DateTime? from,
    DateTime? to,
    TxType? type,
    String? categoryId,
    String? search,
    int limit = 30,
    int offset = 0,
  }) async =>
      TransactionPage.fromJson(await _c.get('/transactions', query: {
        'from': from == null ? null : _date(from),
        'to': to == null ? null : _date(to),
        'type': type?.name,
        'categoryId': categoryId,
        'q': search?.trim(),
        'limit': '$limit',
        'offset': '$offset',
      }) as Map<String, dynamic>);

  static Map<String, dynamic> _txBody(TxType type, double amount, String? categoryId, String? note,
          DateTime date) =>
      {
        'type': type.name,
        'amount': amount.toStringAsFixed(2),
        'categoryId': categoryId,
        'note': note?.trim(),
        'occurredOn': _date(date),
      };

  static Future<Transaction> createTransaction({
    required TxType type,
    required double amount,
    required DateTime date,
    String? categoryId,
    String? note,
  }) async =>
      Transaction.fromJson(await _c.post('/transactions', _txBody(type, amount, categoryId, note, date))
          as Map<String, dynamic>);

  static Future<Transaction> updateTransaction(
    String id, {
    required TxType type,
    required double amount,
    required DateTime date,
    String? categoryId,
    String? note,
  }) async =>
      Transaction.fromJson(await _c.patch('/transactions/$id', _txBody(type, amount, categoryId, note, date))
          as Map<String, dynamic>);

  static Future<void> deleteTransaction(String id) => _c.delete('/transactions/$id');

  static Future<Transaction> uploadReceipt(String id, Uint8List bytes, String filename) async =>
      Transaction.fromJson(await _c.upload('/transactions/$id/receipt', bytes, filename) as Map<String, dynamic>);

  static Future<String> receiptUrl(String id) async =>
      ((await _c.get('/transactions/$id/receipt')) as Map)['url'] as String;

  static Future<Transaction> removeReceipt(String id) async =>
      Transaction.fromJson(await _c.delete('/transactions/$id/receipt') as Map<String, dynamic>);

  // -------------------------------------------------------------- budgets

  static Future<List<Budget>> budgets() async {
    final j = await _c.get('/budgets') as Map<String, dynamic>;
    return (j['items'] as List).map((e) => Budget.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> createBudget({String? categoryId, required double amount}) =>
      _c.post('/budgets', {'categoryId': categoryId, 'amount': amount.toStringAsFixed(2)});

  static Future<void> updateBudget(String id, double amount) =>
      _c.patch('/budgets/$id', {'amount': amount.toStringAsFixed(2)});

  static Future<void> deleteBudget(String id) => _c.delete('/budgets/$id');

  // ---------------------------------------------------------------- stats

  static Future<MonthlySummary> summary(DateTime month) async => MonthlySummary.fromJson(
        await _c.get('/stats/summary', query: {
          'month': monthString(month),
          'today': _date(DateTime.now()), // the phone's local date
        }) as Map<String, dynamic>,
      );

  // -------------------------------------------------------------- account

  static Future<void> resetData() => _c.post('/account/reset');
  static Future<void> deleteAccount() => _c.delete('/account');
}
