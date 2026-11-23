import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:expense_tracker/features/home/main_shell.dart';
import 'package:expense_tracker/features/auth/auth_pages.dart';
import 'package:expense_tracker/features/auth/auth_service.dart';

/// Decides which screen to show based on the authentication state.
///
/// * No session                 -> Login
/// * Opened a password-reset link -> New password
/// * Email not verified          -> Verify email
/// * Signed in                   -> Home
///
/// Sessions are restored automatically on launch, so returning users go
/// straight to Home. Errors from deep links (expired/invalid email links,
/// cancelled OAuth) are shown as messages.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.loginBuilder});

  final WidgetBuilder loginBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = AuthService.authStateChanges.listen(_onAuthState, onError: _onAuthError);
    AuthService.recoveryMode.addListener(_refresh);
  }

  @override
  void dispose() {
    _sub?.cancel();
    AuthService.recoveryMode.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _popToRoot() =>
      AuthService.navigatorKey.currentState?.popUntil((route) => route.isFirst);

  void _onAuthState(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        AuthService.recoveryMode.value = true;
        _popToRoot();
      case AuthChangeEvent.signedIn:
        _popToRoot();
      case AuthChangeEvent.signedOut:
        AuthService.recoveryMode.value = false;
        _popToRoot();
        if (!AuthService.consumeUserSignOut()) {
          showAuthMessage(null, 'Your session has expired. Please log in again.', error: true);
        }
      default:
        break;
    }
    _refresh();
  }

  void _onAuthError(Object error) {
    showAuthMessage(null, AuthService.friendlyError(error), error: true);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    if (AuthService.currentSession == null || user == null) {
      return widget.loginBuilder(context);
    }
    if (AuthService.recoveryMode.value) return const ResetPasswordPage();
    if (!AuthService.isEmailVerified) {
      return VerifyEmailPage(email: user.email ?? '');
    }
    return const MainShell();
  }
}
