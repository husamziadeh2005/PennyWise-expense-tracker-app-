import 'package:flutter/material.dart';

import 'package:expense_tracker/features/auth/auth_pages.dart';
import 'package:expense_tracker/features/auth/auth_service.dart';
import 'package:expense_tracker/features/auth/auth_validators.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  bool _usePhone = false;
  String _country = 'Jordan';
  String _gender = 'Male';
  bool _loading = false;
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final AuthResult res;
    if (_usePhone) {
      final passwordError = AuthValidators.password(_passwordController.text);
      res = passwordError != null
          ? AuthResult.error(passwordError)
          : await AuthService.sendPhoneOtp(
              phone: _contactController.text,
              fullName: _nameController.text,
              country: _country,
              gender: _gender,
            );
    } else {
      res = await AuthService.signUpWithEmail(
        fullName: _nameController.text,
        email: _contactController.text,
        password: _passwordController.text,
        country: _country,
        gender: _gender,
      );
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (!res.success) {
      showAuthMessage(context, res.message!, error: true);
    } else if (_usePhone) {
      showAuthMessage(context, res.message!);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyPhonePage(
            phone: res.data!,
            password: _passwordController.text,
            fullName: _nameController.text,
            country: _country,
            gender: _gender,
          ),
        ),
      );
    } else if (res.data == 'verify_email') {
      // Email confirmation required: show the "verify your email" screen.
      showAuthMessage(context, res.message!);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VerifyEmailPage(email: _contactController.text.trim().toLowerCase()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF14213D);
    const fieldFill = Color(0xFF182235);
    const border = OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white24),
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [navy, Color(0xFF080B12)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Create account',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 28,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Enter your details to get started',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 28),
                    _textField('Full name', Icons.person_outline,
                        controller: _nameController,
                        fill: fieldFill, border: border),
                    const SizedBox(height: 16),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Email')),
                        ButtonSegment(value: true, label: Text('Phone number')),
                      ],
                      selected: {_usePhone},
                      onSelectionChanged: (value) =>
                          setState(() => _usePhone = value.first),
                      style: SegmentedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        selectedForegroundColor: navy,
                        selectedBackgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _textField(
                      _usePhone ? 'Phone number' : 'Email address',
                      _usePhone ? Icons.phone_outlined : Icons.email_outlined,
                      keyboardType: _usePhone
                          ? TextInputType.phone
                          : TextInputType.emailAddress,
                      controller: _contactController,
                      fill: fieldFill,
                      border: border,
                    ),
                    const SizedBox(height: 16),
                    _textField('Password', Icons.lock_outline,
                        controller: _passwordController,
                        obscureText: true,
                        fill: fieldFill, border: border),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _country,
                      dropdownColor: fieldFill,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration('Country', Icons.public,
                          fill: fieldFill, border: border),
                      items: const ['Jordan', 'Saudi Arabia', 'United Arab Emirates', 'United States', 'Other']
                          .map((country) => DropdownMenuItem(
                              value: country, child: Text(country)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _country = value ?? _country),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      dropdownColor: fieldFill,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration('Gender', Icons.person_search_outlined,
                          fill: fieldFill, border: border),
                      items: const ['Male', 'Female']
                          .map((gender) => DropdownMenuItem(
                              value: gender, child: Text(gender)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _gender = value ?? _gender),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _createAccount,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: navy,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _loading
                          ? authButtonSpinner
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Back to login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField(String label, IconData icon,
      {TextInputType keyboardType = TextInputType.text,
      TextEditingController? controller,
      bool obscureText = false,
      required Color fill,
      required OutlineInputBorder border}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(label, icon, fill: fill, border: border),
    );
  }

  InputDecoration _decoration(String label, IconData icon,
      {required Color fill, required OutlineInputBorder border}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      filled: true,
      fillColor: fill,
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
    );
  }
}
