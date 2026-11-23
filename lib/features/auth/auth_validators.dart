/// Pure validation / normalisation helpers for authentication input.
/// Kept free of Flutter and Supabase imports so they are easy to unit test.
class AuthValidators {
  AuthValidators._();

  static const minPasswordLength = 8;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  /// Dialling codes for the countries offered on the Sign Up page.
  static const dialCodes = {
    'Jordan': '+962',
    'Saudi Arabia': '+966',
    'United Arab Emirates': '+971',
    'United States': '+1',
  };

  /// Default currency for each country offered on the Sign Up page.
  static const currencies = {
    'Jordan': 'JOD',
    'Saudi Arabia': 'SAR',
    'United Arab Emirates': 'AED',
    'United States': 'USD',
  };

  static String? fullName(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Please enter your full name.';
    if (v.length < 2) return 'Your name looks too short.';
    if (v.length > 80) return 'Your name is too long.';
    return null;
  }

  static String? email(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Please enter your email address.';
    if (!_emailRegex.hasMatch(v)) return 'Please enter a valid email address.';
    return null;
  }

  /// Requires at least 8 characters with upper-case, lower-case and a digit.
  static String? password(String value) {
    if (value.isEmpty) return 'Please enter a password.';
    if (value.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters.';
    }
    if (value.length > 72) return 'Password must be 72 characters or fewer.';
    if (!RegExp(r'[a-z]').hasMatch(value) ||
        !RegExp(r'[A-Z]').hasMatch(value) ||
        !RegExp(r'\d').hasMatch(value)) {
      return 'Password must include an upper-case letter, a lower-case letter and a number.';
    }
    return null;
  }

  static String? otp(String value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) {
      return 'Please enter the 6-digit code.';
    }
    return null;
  }

  static String _strip(String p) => p.replaceAll(RegExp(r'[\s\-().]'), '');

  /// Normalises a phone number to E.164 (e.g. `0791234567` in Jordan ->
  /// `+962791234567`). Returns null when the number is not valid.
  ///
  /// Accepts `+…`, `00…`, or a local number for the selected [country].
  static String? toE164(String input, {String? country}) {
    var p = _strip(input.trim());
    if (p.isEmpty) return null;
    if (p.startsWith('00')) p = '+${p.substring(2)}';
    if (!p.startsWith('+')) {
      final code = dialCodes[country];
      if (code == null) return null;
      final local = p.replaceFirst(RegExp(r'^0+'), '');
      // Users sometimes type the country code without "+" (e.g. 962791234567).
      final codeDigits = code.substring(1);
      p = local.startsWith(codeDigits) && local.length > codeDigits.length + 7
          ? '+$local'
          : '$code$local';
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(p)) return null;
    // Jordanian mobiles: +962 7[789] XXXXXXX (9 digits after the code).
    if (p.startsWith('+962') && !RegExp(r'^\+9627[789]\d{7}$').hasMatch(p)) {
      return null;
    }
    return p;
  }

  static bool looksLikeEmail(String value) => value.trim().contains('@');
}
