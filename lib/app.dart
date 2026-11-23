import 'package:flutter/material.dart';

import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/auth/auth_gate.dart';
import 'package:expense_tracker/features/auth/auth_service.dart';
import 'package:expense_tracker/features/auth/login_page.dart';
import 'package:expense_tracker/state/app_state.dart';

/// Root widget. [AuthGate] decides which screen to show
/// (login, verify email, reset password or the main app).
class PennyWiseApp extends StatelessWidget {
  const PennyWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) => MaterialApp(
        title: 'PennyWise',
        navigatorKey: AuthService.navigatorKey,
        scaffoldMessengerKey: AuthService.messengerKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Brightness.light),
        darkTheme: AppTheme.build(Brightness.dark),
        themeMode: mode,
        home: AuthGate(loginBuilder: (_) => const LoginPage()),
      ),
    );
  }
}
