import 'package:flutter/foundation.dart';

/// Supabase project settings for PennyWise.
///
/// The publishable key is safe to ship inside the app; access to data is
/// controlled by Row Level Security policies on the database.
class SupabaseConfig {
  static const url = 'https://dwvqxftefejqxcopbvfz.supabase.co';
  static const publishableKey = 'sb_publishable_hpxBvj-iG0YeP8xO25Lezw_W0kdhLPP';

  /// Deep link the phone/desktop app listens on for email confirmation,
  /// password reset and Apple / Facebook / Google sign-in callbacks.
  static const appRedirectUrl = 'io.supabase.pennywise://login-callback/';

  /// Where Supabase sends the user back after sign-in / email links.
  ///
  /// * Phone & desktop: the [appRedirectUrl] deep link (reopens the app).
  /// * Web (Chrome): the page the app is running on, e.g.
  ///   http://localhost:5000/ — a browser can't open an app deep link.
  ///
  /// Every value must be allowed in Supabase Dashboard → Authentication →
  /// URL Configuration → Redirect URLs (see docs/SOCIAL_LOGIN.md).
  static String get redirectUrl => kIsWeb ? '${Uri.base.origin}/' : appRedirectUrl;
}
