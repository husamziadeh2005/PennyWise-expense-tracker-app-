import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:expense_tracker/features/auth/auth_pages.dart';
import 'package:expense_tracker/features/auth/auth_service.dart';
import 'package:expense_tracker/features/auth/sign_up_page.dart';

/// The first screen a signed-out user sees: email / phone + password,
/// "forgot password", "sign up" and the Apple / Facebook / Google buttons.
/// All real work is done by [AuthService]; this widget only shows results.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  /// Show switched-off social providers as dimmed buttons (debug builds only
  /// by default, so you can see what is still missing in Supabase).
  @visibleForTesting
  static bool showDisabledProviders = kDebugMode;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _showPassword = false;
  bool _loading = false;
  bool _loginLoading = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Ask Supabase which social logins are switched on, now and every time
    // the app comes back to the foreground (e.g. after you change it in the
    // dashboard), so the buttons always match the real configuration.
    AuthService.refreshSocialProviders();
    _lifecycle = AppLifecycleListener(onResume: AuthService.refreshSocialProviders);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handle(Future<AuthResult> Function() action,
      {bool isLogin = false}) async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _loginLoading = isLogin;
    });
    final res = await action();
    if (mounted) {
      setState(() {
        _loading = false;
        _loginLoading = false;
      });
    }
    if (res.message == null) return;
    if (res.code == 'email_not_confirmed') {
      final email = _emailController.text;
      showAuthMessage(null, res.message!,
          error: true,
          actionLabel: 'Resend',
          onAction: () => _handle(() => AuthService.resendVerificationEmail(email)));
    } else {
      showAuthMessage(null, res.message!, error: !res.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF14213D);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [navy, Color(0xFF080B12)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/animations/login_pulse.gif', width: 64, height: 64),
                const SizedBox(height: 20),
                const Text('PennyWise',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 28,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Log in to your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(color: Colors.white),
                    prefixIcon: Icon(Icons.email_outlined),
                    prefixIconColor: Colors.white,
                    hintStyle: TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Color(0xFF182235),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white),
                    prefixIcon: Icon(Icons.lock_outline),
                    prefixIconColor: Colors.white,
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white,
                      ),
                    ),
                    filled: true,
                    fillColor: Color(0xFF182235),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ), 
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => _handle(() => AuthService.login(
                      _emailController.text, _passwordController.text),
                      isLogin: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: navy,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loginLoading ? authButtonSpinner : const Text('Log in'),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => showForgotPasswordDialog(context,
                          initialEmail: _emailController.text),
                      child: const Text('Forgot password?',
                          style: TextStyle(color: Colors.white70)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SignUpPage(),
                        ),
                      ),
                      child: const Text('Sign up',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
                ValueListenableBuilder<Set<String>?>(
                  valueListenable: AuthService.socialProviders,
                  builder: (context, enabled, _) => _socialSection(enabled),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The three social buttons. Order = order on screen.
final _socialButtons = <_SocialSpec>[
  _SocialSpec('apple', 'Apple', '\uF8FF', Colors.white, AuthService.signInWithApple),
  _SocialSpec('facebook', 'Facebook', 'f', const Color(0xFF7EA6FF), AuthService.signInWithFacebook),
  _SocialSpec('google', 'Google', 'G', const Color(0xFFFF8A80), AuthService.signInWithGoogle),
];

class _SocialSpec {
  const _SocialSpec(this.provider, this.label, this.mark, this.color, this.signIn);
  final String provider;
  final String label;
  final String mark;
  final Color color;
  final Future<AuthResult> Function() signIn;
}

extension on _LoginPageState {
  /// "OR CONTINUE WITH" + one button per provider that is switched on.
  ///
  /// * enabled == null (not known yet / offline): show all; the tap checks again.
  /// * Release builds: switched-off providers are simply not shown.
  /// * Debug builds: they are shown dimmed, and tapping says what to enable,
  ///   so you can see at a glance what is still missing in Supabase.
  Widget _socialSection(Set<String>? enabled) {
    bool isOn(_SocialSpec s) => enabled == null || enabled.contains(s.provider);
    final visible = _socialButtons
        .where((s) => isOn(s) || LoginPage.showDisabledProviders)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(children: [
      const SizedBox(height: 18),
      const Row(
        children: [
          Expanded(child: Divider(color: Colors.white24)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('OR CONTINUE WITH', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Expanded(child: Divider(color: Colors.white24)),
        ],
      ),
      const SizedBox(height: 18),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 10,
        children: [
          for (final s in visible)
            _SocialButton(
              spec: s,
              enabled: isOn(s),
              onPressed: isOn(s)
                  ? () => _handle(s.signIn)
                  : () {
                      final res = AuthService.providerDisabled(s.provider);
                      showAuthMessage(null, res.message!, error: true);
                    },
            ),
        ],
      ),
    ]);
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.spec, required this.enabled, required this.onPressed});

  final _SocialSpec spec;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled ? 'Continue with ${spec.label}' : '${spec.label} sign-in is turned off in Supabase',
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(spec.mark,
              semanticsLabel: spec.label,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: spec.color)),
        ),
      ),
    );
  }
}
