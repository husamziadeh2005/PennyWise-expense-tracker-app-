import 'package:expense_tracker/features/auth/auth_service.dart';
import 'package:expense_tracker/features/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fakes Supabase's /auth/v1/settings answer: which social providers are on.
void fakeProviders(Set<String>? on) {
  AuthService.settingsOverride = () async => on == null
      ? null // settings could not be loaded
      : {'external': {for (final p in AuthService.socialProviderNames) p: on.contains(p), 'email': true}};
}

Widget app() => MaterialApp(scaffoldMessengerKey: AuthService.messengerKey, home: const LoginPage());

void main() {
  setUp(() {
    AuthService.socialProviders.value = null;
    LoginPage.showDisabledProviders = true; // default in debug builds
    fakeProviders(null);
  });
  tearDown(() {
    AuthService.settingsOverride = null;
    AuthService.socialProviders.value = null;
  });

  testWidgets('Login page renders fields and every auth button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('PennyWise'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('f'), findsOneWidget); // Facebook
    expect(find.text('G'), findsOneWidget); // Google
    expect(find.byType(OutlinedButton), findsNWidgets(3)); // Apple, Facebook, Google
  });

  testWidgets('Forgot password opens the reset dialog', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'user@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Send link'), findsOneWidget);
    // Pre-filled with the email typed on the login page.
    expect(find.text('user@example.com'), findsNWidgets(2));
  });

  testWidgets('Sign up page has a password field', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
  });

  group('social login buttons follow the Supabase settings', () {
    Finder button(String mark) => find.widgetWithText(OutlinedButton, mark);
    double opacityOf(WidgetTester tester, String mark) => tester
        .widget<Opacity>(find.ancestor(of: button(mark), matching: find.byType(Opacity)).first)
        .opacity;

    testWidgets('only enabled providers are active, others are dimmed in debug', (tester) async {
      fakeProviders({'google'});
      await tester.pumpWidget(app());
      await tester.pump();

      expect(opacityOf(tester, 'G'), 1.0);
      expect(opacityOf(tester, 'f'), lessThan(1.0));

      // Tapping a switched-off provider explains what to enable, no browser.
      await tester.tap(button('f'));
      await tester.pump();
      expect(find.textContaining('Facebook sign-in is turned off in Supabase'), findsOneWidget);
    });

    testWidgets('release build: switched-off providers are hidden', (tester) async {
      LoginPage.showDisabledProviders = false;
      fakeProviders({'apple', 'google'});
      await tester.pumpWidget(app());
      await tester.pump();

      expect(button('G'), findsOneWidget);
      expect(button('\uF8FF'), findsOneWidget);
      expect(button('f'), findsNothing);
    });

    testWidgets('release build with nothing enabled: whole section is hidden', (tester) async {
      LoginPage.showDisabledProviders = false;
      fakeProviders({});
      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text('OR CONTINUE WITH'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('a provider switched on while the app is in the background appears on resume',
        (tester) async {
      LoginPage.showDisabledProviders = false;
      fakeProviders({});
      await tester.pumpWidget(app());
      await tester.pump();
      expect(button('G'), findsNothing);

      fakeProviders({'google'}); // you enable Google in the dashboard...
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
          AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump();
      expect(button('G'), findsOneWidget); // ...and the button shows up
    });
  });
}

