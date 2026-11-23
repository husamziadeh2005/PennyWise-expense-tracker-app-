import 'dart:async';

import 'package:flutter/material.dart';

import 'package:expense_tracker/features/auth/auth_service.dart';
import 'package:expense_tracker/features/auth/auth_validators.dart';

/// Small screens needed by the auth flow, styled to match the Login and
/// Sign Up pages (same navy gradient, field colours and buttons).

const _navy = Color(0xFF14213D);
const _fieldFill = Color(0xFF182235);
const _resendSeconds = 60;

const _background = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_navy, Color(0xFF080B12)],
  ),
);

InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      suffixIcon: suffix,
      filled: true,
      fillColor: _fieldFill,
      border: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
    );

/// Spinner used inside the white primary buttons while loading.
const authButtonSpinner = SizedBox(
  height: 18,
  width: 18,
  child: CircularProgressIndicator(strokeWidth: 2, color: _navy),
);

Widget _primaryButton(String text, bool loading, VoidCallback onPressed) => FilledButton(
      onPressed: loading ? () {} : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: loading ? authButtonSpinner : Text(text),
    );

Widget _secondaryButton(String text, VoidCallback? onPressed) => OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(text),
    );

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _background,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 28),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Countdown helper for "Resend" buttons.
mixin _ResendCountdown<T extends StatefulWidget> on State<T> {
  int secondsLeft = 0;
  Timer? _timer;

  void startCountdown([int seconds = _resendSeconds]) {
    _timer?.cancel();
    setState(() => secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => secondsLeft--);
      if (secondsLeft <= 0) t.cancel();
    });
  }

  String resendLabel(String label) =>
      secondsLeft > 0 ? '$label in ${secondsLeft}s' : label;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ----------------------------------------------------------- Verify email

/// Shown after email sign-up (and if an unverified user somehow has a
/// session). Lets the user resend the verification email.
class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage>
    with _ResendCountdown<VerifyEmailPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => startCountdown());
  }

  Future<void> _resend() async {
    if (_loading || secondsLeft > 0) return;
    setState(() => _loading = true);
    final res = await AuthService.resendVerificationEmail(widget.email);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.message != null) showAuthMessage(context, res.message!, error: !res.success);
    if (res.success) startCountdown();
  }

  Future<void> _backToLogin() async {
    if (AuthService.isLoggedIn) {
      await AuthService.logout();
    } else if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Verify your email',
      subtitle: 'We sent a verification link to ${widget.email}.\n'
          'Open it on this phone to activate your account.',
      children: [
        const Icon(Icons.mark_email_unread_outlined, color: Colors.white, size: 64),
        const SizedBox(height: 28),
        _primaryButton(resendLabel('Resend email'), _loading,
            secondsLeft > 0 ? () {} : _resend),
        const SizedBox(height: 12),
        _secondaryButton('Back to login', _backToLogin),
      ],
    );
  }
}

// ----------------------------------------------------------- Verify phone

/// Shown after requesting an SMS code. Verifies the code, with a resend
/// countdown.
class VerifyPhonePage extends StatefulWidget {
  const VerifyPhonePage({
    super.key,
    required this.phone,
    this.password,
    this.fullName,
    this.country,
    this.gender,
  });

  final String phone;
  final String? password;
  final String? fullName;
  final String? country;
  final String? gender;

  @override
  State<VerifyPhonePage> createState() => _VerifyPhonePageState();
}

class _VerifyPhonePageState extends State<VerifyPhonePage>
    with _ResendCountdown<VerifyPhonePage> {
  final _code = TextEditingController();
  bool _loading = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => startCountdown());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final res = await AuthService.verifyPhoneOtp(widget.phone, _code.text,
        password: widget.password);
    if (mounted) setState(() => _loading = false);
    // On success the AuthGate navigates to the home screen.
    if (res.message != null) showAuthMessage(null, res.message!, error: !res.success);
  }

  Future<void> _resend() async {
    if (_resending || secondsLeft > 0) return;
    setState(() => _resending = true);
    final res = await AuthService.sendPhoneOtp(
      phone: widget.phone,
      fullName: widget.fullName,
      country: widget.country,
      gender: widget.gender,
    );
    if (!mounted) return;
    setState(() => _resending = false);
    showAuthMessage(context, res.success ? 'A new code has been sent.' : res.message!,
        error: !res.success);
    if (res.success) startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Verify phone',
      subtitle: 'Enter the 6-digit code sent to ${widget.phone}',
      children: [
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
          decoration: _decoration('Code', Icons.sms_outlined).copyWith(counterText: ''),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 24),
        _primaryButton('Verify', _loading, _verify),
        const SizedBox(height: 12),
        TextButton(
          onPressed: secondsLeft > 0 || _resending ? null : _resend,
          child: Text(resendLabel('Resend code'),
              style: TextStyle(color: secondsLeft > 0 ? Colors.white38 : Colors.white70)),
        ),
        _secondaryButton('Change number', () => Navigator.of(context).pop()),
      ],
    );
  }
}

// --------------------------------------------------------- Reset password

/// Opened automatically by the AuthGate after the user taps the password
/// reset link in their email.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _show = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final err = AuthValidators.password(_password.text);
    if (err != null) return showAuthMessage(context, err, error: true);
    if (_password.text != _confirm.text) {
      return showAuthMessage(context, 'Passwords do not match.', error: true);
    }
    setState(() => _loading = true);
    final res = await AuthService.updatePassword(_password.text);
    if (mounted) setState(() => _loading = false);
    if (res.message != null) showAuthMessage(null, res.message!, error: !res.success);
    if (res.code == 'session_expired') await AuthService.cancelPasswordRecovery();
  }

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      onPressed: () => setState(() => _show = !_show),
      icon: Icon(_show ? Icons.visibility_off : Icons.visibility, color: Colors.white),
    );
    return _AuthScaffold(
      title: 'New password',
      subtitle: 'Choose a new password for your account',
      children: [
        TextField(
          controller: _password,
          obscureText: !_show,
          autofillHints: const [AutofillHints.newPassword],
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('New password', Icons.lock_outline, suffix: toggle),
        ),
        const SizedBox(height: 8),
        const Text('At least 8 characters, with upper-case, lower-case and a number.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 16),
        TextField(
          controller: _confirm,
          obscureText: !_show,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration('Confirm password', Icons.lock_outline),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        _primaryButton('Update password', _loading, _submit),
        const SizedBox(height: 12),
        _secondaryButton('Cancel', AuthService.cancelPasswordRecovery),
      ],
    );
  }
}

// -------------------------------------------------------- Forgot password

/// Dialog asking for the registered email and sending the reset link.
Future<void> showForgotPasswordDialog(BuildContext context, {String initialEmail = ''}) {
  final controller = TextEditingController(
      text: AuthValidators.looksLikeEmail(initialEmail) ? initialEmail.trim() : '');
  var loading = false;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> send() async {
          if (loading) return;
          setState(() => loading = true);
          final res = await AuthService.sendPasswordReset(controller.text);
          if (!dialogContext.mounted) return;
          setState(() => loading = false);
          if (res.success) Navigator.of(dialogContext).pop();
          if (res.message != null) showAuthMessage(context, res.message!, error: !res.success);
        }

        return AlertDialog(
          backgroundColor: _navy,
          title: const Text('Reset password', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("Enter your account's email and we'll send you a reset link.",
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: const TextStyle(color: Colors.white),
                decoration: _decoration('Email', Icons.email_outlined),
                onSubmitted: (_) => send(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              onPressed: send,
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _navy),
              child: loading ? authButtonSpinner : const Text('Send link'),
            ),
          ],
        );
      },
    ),
  ).whenComplete(controller.dispose);
}
