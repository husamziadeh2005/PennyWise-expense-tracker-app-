import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:expense_tracker/features/auth/auth_validators.dart';
import 'package:expense_tracker/core/config/supabase_config.dart';

/// Result of an auth action.
///
/// [message] is a user-friendly text to show (null = nothing to show).
/// [code] is a machine-readable reason the UI can react to
/// (e.g. `email_not_confirmed`). [data] carries extra values such as the
/// normalised phone number.
class AuthResult {
  const AuthResult.ok([this.message, this.data])
      : success = true,
        code = null;
  const AuthResult.error(this.message, {this.code})
      : success = false,
        data = null;

  final bool success;
  final String? message;
  final String? code;
  final String? data;
}

/// All Supabase authentication logic for PennyWise lives here.
/// UI code only calls these methods and shows the returned messages.
class AuthService {
  AuthService._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// True while the user is setting a new password after opening a
  /// password-recovery link.
  static final recoveryMode = ValueNotifier<bool>(false);

  static SupabaseClient get _client => Supabase.instance.client;
  static GoTrueClient get _auth => _client.auth;

  static bool _userRequestedSignOut = false;

  // ------------------------------------------------------------------ Setup

  /// Initialises Supabase. Sessions are persisted on the device and refreshed
  /// automatically by the SDK, so users stay logged in between app launches.
  static Future<void> init() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
    );
  }

  static Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;
  static Session? get currentSession => _auth.currentSession;
  static User? get currentUser => _auth.currentUser;
  static bool get isLoggedIn => currentSession != null;

  /// Email/password users must confirm their email. Phone and social
  /// (Apple / Google / Facebook) users are verified by their provider.
  static bool get isEmailVerified {
    final user = currentUser;
    if (user == null) return false;
    final provider = user.appMetadata['provider'];
    if (provider != 'email') return true;
    return user.emailConfirmedAt != null;
  }

  /// Returns true (once) if the last sign-out was requested by the user,
  /// so the gate can tell a normal logout from an expired session.
  static bool consumeUserSignOut() {
    final value = _userRequestedSignOut;
    _userRequestedSignOut = false;
    return value;
  }

  // ------------------------------------------------------------------ Login

  /// The login "Email" field accepts an email, or a phone number for users
  /// who registered by phone (e.g. 0791234567 or +962791234567).
  static Future<AuthResult> login(String identifier, String password) async {
    final id = identifier.trim();
    if (id.isEmpty) return const AuthResult.error('Please enter your email.');
    if (password.isEmpty) {
      return const AuthResult.error('Please enter your password.');
    }

    String? email;
    String? phone;
    if (AuthValidators.looksLikeEmail(id)) {
      final err = AuthValidators.email(id);
      if (err != null) return AuthResult.error(err);
      email = id;
    } else {
      phone = AuthValidators.toE164(id, country: 'Jordan');
      if (phone == null) {
        return const AuthResult.error(
            'Please enter a valid email address or phone number.');
      }
    }

    return _run(() async {
      await _auth.signInWithPassword(email: email, phone: phone, password: password);
      return const AuthResult.ok();
    });
  }

  // ------------------------------------------------------- Email sign up

  /// Registers with email + password. Supabase stores the password hashed in
  /// `auth.users`; it is never written to the app's own tables.
  static Future<AuthResult> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
    required String country,
    required String gender,
  }) async {
    final error = AuthValidators.fullName(fullName) ??
        AuthValidators.email(email) ??
        AuthValidators.password(password);
    if (error != null) return AuthResult.error(error);
    final mail = email.trim().toLowerCase();

    return _run(() async {
      final res = await _auth.signUp(
        email: mail,
        password: password,
        emailRedirectTo: SupabaseConfig.redirectUrl,
        data: _profileMetadata(fullName, country, gender),
      );
      // With email confirmation on, Supabase hides whether an email is taken
      // by returning a user with no identities.
      final identities = res.user?.identities;
      if (res.user != null && identities != null && identities.isEmpty) {
        return const AuthResult.error(
            'An account with this email already exists. Try logging in instead.',
            code: 'user_already_exists');
      }
      if (res.session == null) {
        return const AuthResult.ok(
            'Account created! We sent a verification link to your email.',
            'verify_email');
      }
      return const AuthResult.ok();
    });
  }

  static Future<AuthResult> resendVerificationEmail(String email) async {
    final err = AuthValidators.email(email);
    if (err != null) return AuthResult.error(err);
    return _run(() async {
      await _auth.resend(
        type: OtpType.signup,
        email: email.trim().toLowerCase(),
        emailRedirectTo: SupabaseConfig.redirectUrl,
      );
      return const AuthResult.ok('Verification email sent. Check your inbox.');
    });
  }

  /// Re-reads the user from the server (e.g. after verifying in a browser).
  static Future<void> refreshUser() async {
    try {
      await _auth.refreshSession();
    } catch (_) {/* ignore, gate re-checks state */}
  }

  // ------------------------------------------------------- Phone (SMS OTP)

  /// Sends an SMS code with `signInWithOtp`. Creates the account when the
  /// number is new. On success [AuthResult.data] holds the E.164 number.
  static Future<AuthResult> sendPhoneOtp({
    required String phone,
    String? fullName,
    String? country,
    String? gender,
  }) async {
    if (fullName != null) {
      final err = AuthValidators.fullName(fullName);
      if (err != null) return AuthResult.error(err);
    }
    final e164 = AuthValidators.toE164(phone, country: country);
    if (e164 == null) {
      return const AuthResult.error(
          'Please enter a valid mobile number, e.g. 07X XXX XXXX or +9627XXXXXXXX.');
    }
    return _run(() async {
      await _auth.signInWithOtp(
        phone: e164,
        shouldCreateUser: true,
        channel: OtpChannel.sms,
        data: fullName == null
            ? null
            : _profileMetadata(fullName, country ?? '', gender ?? ''),
      );
      return AuthResult.ok('We sent a 6-digit code to $e164.', e164);
    });
  }

  /// Verifies the SMS code (creates the session). If [password] is given it
  /// is set afterwards so the user can also log in with phone + password.
  static Future<AuthResult> verifyPhoneOtp(String phone, String code,
      {String? password}) async {
    final err = AuthValidators.otp(code);
    if (err != null) return AuthResult.error(err);
    return _run(() async {
      await _auth.verifyOTP(phone: phone, token: code.trim(), type: OtpType.sms);
      if (password != null && password.isNotEmpty) {
        try {
          await _auth.updateUser(UserAttributes(password: password));
        } on AuthException catch (e) {
          return AuthResult.ok(
              'Phone verified, but the password could not be saved (${friendlyError(e)}). '
              'You can still sign in with an SMS code.');
        }
      }
      return const AuthResult.ok('Phone number verified.');
    });
  }

  // ------------------------------------------------- Forgot / reset password

  static Future<AuthResult> sendPasswordReset(String email) async {
    final err = AuthValidators.email(email);
    if (err != null) return AuthResult.error(err);
    return _run(() async {
      await _auth.resetPasswordForEmail(email.trim().toLowerCase(),
          redirectTo: SupabaseConfig.redirectUrl);
      // Same message whether or not the account exists (prevents probing).
      return const AuthResult.ok(
          'If an account exists for this email, a reset link is on its way.');
    });
  }

  static Future<AuthResult> updatePassword(String newPassword) async {
    final err = AuthValidators.password(newPassword);
    if (err != null) return AuthResult.error(err);
    if (currentSession == null) {
      return const AuthResult.error(
          'Your reset link has expired. Please request a new one.',
          code: 'session_expired');
    }
    return _run(() async {
      await _auth.updateUser(UserAttributes(password: newPassword));
      recoveryMode.value = false;
      return const AuthResult.ok('Your password has been updated.');
    });
  }

  static Future<void> cancelPasswordRecovery() async {
    recoveryMode.value = false;
    await logout();
  }

  // ---------------------------------------------------------- Social logins

  /// Native Sign in with Apple on iOS (identity token + nonce); browser OAuth
  /// on other platforms.
  static Future<AuthResult> signInWithApple() {
    if (!kIsWeb && Platform.isIOS) return _signInWithAppleNative();
    return _oauth(OAuthProvider.apple);
  }

  static Future<AuthResult> signInWithFacebook() => _oauth(OAuthProvider.facebook);
  static Future<AuthResult> signInWithGoogle() => _oauth(OAuthProvider.google);

  /// The social providers this app has buttons for.
  static const socialProviderNames = ['apple', 'facebook', 'google'];

  /// Which of [socialProviderNames] are switched on in the Supabase
  /// dashboard right now. `null` = not known yet (offline, or not loaded).
  ///
  /// This makes the login page dynamic: switch a provider on or off in
  /// Supabase and the button appears or disappears the next time the app is
  /// opened or comes back to the foreground. No code change, no rebuild.
  static final socialProviders = ValueNotifier<Set<String>?>(null);

  /// Tests replace this to fake the Supabase answer.
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function()? settingsOverride;

  /// Reads Supabase's public Auth settings (`/auth/v1/settings`) and updates
  /// [socialProviders]. Uses package:http so it works on web too.
  /// On failure the last known value is kept.
  static Future<Set<String>?> refreshSocialProviders() async {
    try {
      final body = settingsOverride != null ? await settingsOverride!() : await _fetchSettings();
      final external = body?['external'];
      if (external is Map) {
        socialProviders.value = {
          for (final p in socialProviderNames)
            if (external[p] == true) p,
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Could not read Supabase auth settings: $e');
    }
    return socialProviders.value;
  }

  static Future<Map<String, dynamic>?> _fetchSettings() async {
    final response = await http
        .get(Uri.parse('${SupabaseConfig.url}/auth/v1/settings'),
            headers: {'apikey': SupabaseConfig.publishableKey})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Checked again right before every social sign-in, so we never send the
  /// user to a browser error page for a provider that is switched off.
  static Future<bool> _isProviderEnabled(String provider) async {
    final enabled = await refreshSocialProviders();
    return enabled == null || enabled.contains(provider); // unknown -> let the real call decide
  }

  /// Message for a provider that is switched off (public, so the login page
  /// can show it when a dimmed debug-only button is tapped).
  static AuthResult providerDisabled(String provider) => _notEnabled(provider);

  /// Shown when the provider is switched off in Supabase.
  /// Debug builds also say exactly where to switch it on.
  static AuthResult _notEnabled(String provider) {
    final name = provider[0].toUpperCase() + provider.substring(1);
    return AuthResult.error(
      kDebugMode
          ? '$name sign-in is turned off in Supabase. Enable it in Dashboard → '
              'Authentication → Sign In / Providers → $name (see docs/SOCIAL_LOGIN.md).'
          : '$name sign-in is not available yet. Please use email instead.',
      code: 'provider_disabled',
    );
  }

  static Future<AuthResult> _signInWithAppleNative() async {
    if (!await _isProviderEnabled('apple')) return _notEnabled('apple');
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        return const AuthResult.error('Apple did not return a sign-in token. Please try again.');
      }
      await _auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      // Apple shares the user's name only on the very first sign-in.
      final name = [credential.givenName, credential.familyName]
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(' ');
      if (name.isNotEmpty && currentUser?.userMetadata?['full_name'] == null) {
        try {
          await _auth.updateUser(UserAttributes(data: {'full_name': name}));
        } catch (_) {/* name is optional */}
      }
      return const AuthResult.ok();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthResult.error('Sign in with Apple was cancelled.', code: 'cancelled');
      }
      return const AuthResult.error('Sign in with Apple failed. Please try again.');
    } on SignInWithAppleNotSupportedException {
      return const AuthResult.error('Sign in with Apple is not available on this device.');
    } on AuthException catch (e) {
      return AuthResult.error(friendlyError(e), code: e.code);
    } catch (e) {
      return AuthResult.error(friendlyError(e));
    }
  }

  /// Browser-based OAuth. The provider redirects to
  /// [SupabaseConfig.redirectUrl]; the SDK exchanges the code for a session.
  /// If the user comes back to the app without finishing, we report a
  /// cancellation.
  static Future<AuthResult> _oauth(OAuthProvider provider) async {
    if (!await _isProviderEnabled(provider.name)) return _notEnabled(provider.name);
    final completer = Completer<AuthResult>();
    var launched = false;
    Timer? cancelTimer;

    final sub = _auth.onAuthStateChange.listen(
      (state) {
        if (launched && state.event == AuthChangeEvent.signedIn && !completer.isCompleted) {
          completer.complete(const AuthResult.ok());
        }
      },
      onError: (Object e) {
        // The AuthGate already shows stream errors; complete silently.
        if (launched && !completer.isCompleted) completer.complete(const AuthResult.error(null));
      },
    );
    final lifecycle = AppLifecycleListener(onResume: () {
      cancelTimer?.cancel();
      cancelTimer = Timer(const Duration(seconds: 8), () {
        if (!completer.isCompleted) {
          completer.complete(const AuthResult.error('Sign-in was cancelled.', code: 'cancelled'));
        }
      });
    });

    try {
      final opened = await _auth.signInWithOAuth(
        provider,
        redirectTo: SupabaseConfig.redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
        scopes: provider == OAuthProvider.facebook ? 'email,public_profile' : null,
        // Google: always show the account picker, so after logging out you
        // can choose a different Gmail instead of being signed straight back in.
        queryParams: provider == OAuthProvider.google ? const {'prompt': 'select_account'} : null,
      );
      if (!opened) return const AuthResult.error('Could not open the sign-in page.');
      // Web: this tab now navigates to the provider. When it comes back, the
      // SDK reads the code from the URL and the AuthGate shows the app.
      if (kIsWeb) return const AuthResult.ok();
      launched = true;
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => const AuthResult.error('Sign-in timed out. Please try again.'),
      );
    } on AuthException catch (e) {
      return AuthResult.error(friendlyError(e), code: e.code);
    } catch (e) {
      return AuthResult.error(friendlyError(e));
    } finally {
      cancelTimer?.cancel();
      lifecycle.dispose();
      await sub.cancel();
    }
  }

  // ---------------------------------------------------------------- Profile

  static Future<Map<String, dynamic>?> fetchProfile() async {
    final user = currentUser;
    if (user == null) return null;
    return _client.from('profiles').select().eq('id', user.id).maybeSingle();
  }

  /// Updates only the fields that are passed. Row Level Security limits the
  /// update to the signed-in user's own row (auth.uid()).
  static Future<AuthResult> updateProfile({
    String? fullName,
    String? country,
    String? gender,
    String? avatarUrl,
    String? currency,
  }) async {
    final user = currentUser;
    if (user == null) return const AuthResult.error('Please log in again.');
    final changes = <String, dynamic>{
      'full_name': ?fullName?.trim(),
      'country': ?country,
      'gender': ?gender,
      'avatar_url': ?avatarUrl,
      'currency': ?currency?.toUpperCase(),
    };
    if (changes.isEmpty) return const AuthResult.ok();
    return _run(() async {
      await _client.from('profiles').update(changes).eq('id', user.id);
      return const AuthResult.ok('Profile updated.');
    });
  }

  // ----------------------------------------------------------------- Logout

  static Future<void> logout() async {
    _userRequestedSignOut = true;
    recoveryMode.value = false;
    try {
      await _auth.signOut();
    } catch (_) {
      // Even if the network call fails the local session is cleared.
    }
  }

  // ---------------------------------------------------------------- Helpers

  static Map<String, dynamic> _profileMetadata(
          String fullName, String country, String gender) =>
      {
        'full_name': fullName.trim(),
        if (country.isNotEmpty) 'country': country,
        if (gender.isNotEmpty) 'gender': gender,
        if (AuthValidators.currencies[country] != null)
          'currency': AuthValidators.currencies[country],
      };

  static String _generateNonce([int length = 32]) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static Future<AuthResult> _run(Future<AuthResult> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      return AuthResult.error(friendlyError(e), code: e.code ?? e.statusCode);
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('Postgrest error: ${e.message}');
      return const AuthResult.error('Could not save your data. Please try again.');
    } catch (e) {
      return AuthResult.error(friendlyError(e));
    }
  }

  /// Converts any auth error into a short, safe message for the user.
  /// Raw server messages are only printed in debug builds.
  static String friendlyError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return 'No internet connection. Please check your connection and try again.';
    }
    if (error is! AuthException) {
      if (kDebugMode) debugPrint('Auth error: $error');
      return 'Something went wrong. Please try again.';
    }
    if (kDebugMode) {
      debugPrint('AuthException(code: ${error.code}, status: ${error.statusCode}): ${error.message}');
    }
    final codes = {error.code, error.statusCode};
    final m = error.message.toLowerCase();
    bool has(String c) => codes.contains(c);

    if (has('invalid_credentials') || m.contains('invalid login credentials')) {
      return 'Incorrect email/phone or password.';
    }
    if (has('email_not_confirmed')) return 'Please verify your email before logging in.';
    if (has('phone_not_confirmed')) return 'Please verify your phone number first.';
    if (has('user_already_exists') || has('email_exists') || m.contains('already registered')) {
      return 'An account with this email already exists. Try logging in instead.';
    }
    if (has('phone_exists')) return 'An account with this phone number already exists.';
    if (has('weak_password')) {
      return 'This password is too weak. Use at least 8 characters with upper-case, lower-case and numbers.';
    }
    if (has('same_password')) return 'Your new password must be different from your old one.';
    if (has('otp_expired') || m.contains('token has expired') || m.contains('link is invalid or has expired')) {
      return 'This code or link is invalid or has expired. Please request a new one.';
    }
    if (has('flow_state_expired') || has('flow_state_not_found') || has('bad_code_verifier') ||
        m.contains('code verifier')) {
      return 'This link has expired or was opened on another device. Please request a new one on this phone.';
    }
    if (has('over_email_send_rate_limit')) {
      return 'Too many emails sent. Please wait a few minutes and try again.';
    }
    if (has('over_sms_send_rate_limit')) {
      return 'Too many SMS codes requested. Please wait a minute and try again.';
    }
    if (has('over_request_rate_limit') || has('429') || m.contains('rate limit')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (has('sms_send_failed') || m.contains('error sending sms')) {
      return "We couldn't send the SMS. Check the number and try again later.";
    }
    if (has('phone_provider_disabled') || m.contains('unsupported phone provider')) {
      return 'Phone sign-in is not available yet. Please use email for now.';
    }
    if (has('email_address_not_authorized') || m.contains('error sending confirmation') ||
        m.contains('error sending recovery') || m.contains('error sending')) {
      return "We couldn't send the email right now. Please try again later.";
    }
    if (has('email_address_invalid')) return 'Please use a different email address.';
    if (has('provider_disabled') || has('oauth_provider_not_supported') ||
        m.contains('provider is not enabled') || m.contains('unsupported provider')) {
      return 'This sign-in method is not enabled yet.';
    }
    if (has('signup_disabled') || has('email_provider_disabled')) {
      return 'New sign-ups are currently disabled.';
    }
    if (has('access_denied')) return 'Sign-in was cancelled or denied.';
    if (has('user_banned')) return 'This account has been suspended.';
    if (has('session_expired') || has('session_not_found') || has('refresh_token_not_found') ||
        has('refresh_token_already_used')) {
      return 'Your session has expired. Please log in again.';
    }
    if (has('validation_failed')) return 'Please check your details and try again.';
    return 'Something went wrong. Please try again.';
  }
}

/// Shows a short message at the bottom of the screen. Uses the app-wide
/// messenger so messages survive navigation (e.g. after a deep link).
void showAuthMessage(BuildContext? context, String message,
    {bool error = false, String? actionLabel, VoidCallback? onAction}) {
  final messenger = AuthService.messengerKey.currentState ??
      (context != null ? ScaffoldMessenger.maybeOf(context) : null);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFB3261E) : const Color(0xFF2E7D32),
      duration: Duration(seconds: actionLabel != null ? 8 : 4),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, textColor: Colors.white, onPressed: onAction ?? () {}),
    ));
}
