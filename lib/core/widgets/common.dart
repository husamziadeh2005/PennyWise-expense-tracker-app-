import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:expense_tracker/core/network/api_client.dart';
import 'package:expense_tracker/state/app_state.dart';

// ------------------------------------------------------------------ formats

/// Formats money in the user's currency, always with 2 decimals.
String money(num value, {String? currency, bool sign = false}) {
  final code = currency ?? AppState.instance.currency;
  final f = NumberFormat.simpleCurrency(name: code, decimalDigits: 2);
  final text = f.format(value.abs());
  if (value < 0) return '-$text';
  if (sign && value > 0) return '+$text';
  return text;
}

String monthLabel(DateTime d) => DateFormat.yMMMM().format(d);

String dayLabel(DateTime d) {
  final today = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.dateOnly(d);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat.yMMMEd().format(d);
}

String percentLabel(double? v) => v == null ? '—' : '${v.toStringAsFixed(v.abs() >= 10 ? 0 : 1)}%';

// ------------------------------------------------------------------- colors

const incomeColor = Color(0xFF2E7D32);
const expenseColor = Color(0xFFC62828);

Color hexColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return v == null ? Colors.blueGrey : Color(0xFF000000 | v);
}

String colorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

const categoryColors = [
  '#E57373', '#F06292', '#BA68C8', '#9575CD', '#7986CB', '#64B5F6',
  '#4FC3F7', '#4DB6AC', '#81C784', '#AED581', '#FFD54F', '#FFB74D',
  '#FF8A65', '#A1887F', '#90A4AE', '#66BB6A', '#26A69A', '#8D6E63',
];

// -------------------------------------------------------------------- icons

/// Icon names stored in the database -> Flutter icons.
/// (A fixed map keeps icon tree-shaking working in release builds.)
const categoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'local_grocery_store': Icons.local_grocery_store,
  'coffee': Icons.coffee,
  'directions_car': Icons.directions_car,
  'local_gas_station': Icons.local_gas_station,
  'flight': Icons.flight,
  'shopping_bag': Icons.shopping_bag,
  'receipt': Icons.receipt_long,
  'home': Icons.home,
  'phone_android': Icons.phone_android,
  'wifi': Icons.wifi,
  'movie': Icons.movie,
  'sports_esports': Icons.sports_esports,
  'fitness_center': Icons.fitness_center,
  'health': Icons.local_hospital,
  'school': Icons.school,
  'child_care': Icons.child_care,
  'pets': Icons.pets,
  'checkroom': Icons.checkroom,
  'build': Icons.build,
  'category': Icons.category,
  'payments': Icons.payments,
  'work': Icons.work,
  'gift': Icons.card_giftcard,
  'savings': Icons.savings,
  'trending_up': Icons.trending_up,
  'wallet': Icons.account_balance_wallet,
  'attach_money': Icons.attach_money,
};

IconData iconFor(String? name) => categoryIcons[name] ?? Icons.category;

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.icon, required this.color, this.size = 40});
  final String? icon;
  final String? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = hexColor(color ?? '#9E9E9E');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Icon(iconFor(icon), color: c, size: size * 0.5),
    );
  }
}

// --------------------------------------------------------- simple messages

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? const Color(0xFFB3261E) : null,
    ));
}

String errorText(Object e) => e is ApiException ? e.message : 'Something went wrong. Please try again.';

Future<bool> confirm(BuildContext context,
    {required String title, required String message, String action = 'Delete', bool danger = true}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Full-screen error with a "Try again" button.
///
/// [autoRetrying] adds a small "Retrying automatically…" line.
/// [debugDetails] is shown only in debug builds, to tell the developer
/// what to fix (e.g. "start the API with npm run dev").
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.autoRetrying = false,
    this.debugDetails,
  });
  final String message;
  final VoidCallback onRetry;
  final bool autoRetrying;
  final String? debugDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          if (autoRetrying) ...[
            const SizedBox(height: 8),
            Text('Retrying automatically…',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ],
          if (kDebugMode && debugDetails != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(debugDetails!,
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
            ),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ]),
      );
}

/// "< November 2026 >" selector used by Dashboard and Transactions.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(
        tooltip: 'Previous month',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
      ),
      SizedBox(
        width: 150,
        child: Text(monthLabel(month),
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
      ),
      IconButton(
        tooltip: 'Next month',
        icon: const Icon(Icons.chevron_right),
        onPressed: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
      ),
    ]);
  }
}

/// Simple card with a title used across the app.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ?trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

// ------------------------------------------------------------- user avatar

/// Round profile photo. Falls back to the user's initials when there is no
/// photo, while it is loading, or if it fails to load (e.g. offline).
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.imageUrl, this.radius = 20});

  final String name;
  final String? imageUrl;
  final double radius;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((s) => s.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(initials(name),
          style: TextStyle(
              color: scheme.onPrimaryContainer, fontSize: radius * 0.8, fontWeight: FontWeight.w600)),
    );
    final url = imageUrl;
    return SizedBox.square(
      dimension: radius * 2,
      child: ClipOval(
        child: url == null || url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
              ),
      ),
    );
  }
}
