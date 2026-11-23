import 'package:expense_tracker/core/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initials', () {
    expect(UserAvatar.initials('Hussam Example'), 'HE');
    expect(UserAvatar.initials('  hussam  '), 'H');
    expect(UserAvatar.initials(''), '?');
  });

  testWidgets('shows initials when there is no photo', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(name: 'Hussam Example'))));
    expect(find.text('HE'), findsOneWidget);
  });

  testWidgets('falls back to initials when the photo fails to load', (tester) async {
    // Network images always fail in widget tests -> errorBuilder.
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(name: 'Hussam Example', imageUrl: 'https://x.invalid/a.jpg'))));
    await tester.pumpAndSettle();
    expect(find.text('HE'), findsOneWidget);
  });
}
