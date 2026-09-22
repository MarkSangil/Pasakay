/// Shared client-side auth validation for the driver app.
abstract final class AuthValidators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phMobile = RegExp(r'^09\d{9}$');

  static String normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63') && digits.length >= 12) {
      digits = '0${digits.substring(2)}';
    }
    return digits;
  }

  static String? fullName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Full name is required';
    if (value.trim().length < 2) return 'Enter your full name';
    return null;
  }

  static String? mobile(String? value) {
    final n = normalizePhone(value ?? '');
    if (!_phMobile.hasMatch(n)) {
      return 'Enter a valid PH mobile (09XXXXXXXXX)';
    }
    return null;
  }

  /// Email is optional; validate format only when provided.
  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Include letters and a number';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value != password) return 'Passwords do not match';
    return null;
  }

  /// Canonical storage format: `D00-00-000000` (`D` + 10 digits).
  static String? license(String? value) {
    final v = _alnum(value);
    if (v.isEmpty) return 'License number is required';
    if (!RegExp(r'^[A-Z][0-9]{10}$').hasMatch(v)) {
      return "License format: D00-00-000000 (e.g. D12-34-567890)";
    }
    return null;
  }

  /// Canonical storage format: `ABC-1234` (3 letters + 4 digits).
  static String? plate(String? value) {
    final v = _alnum(value);
    if (v.isEmpty) return 'Plate number is required';
    if (!RegExp(r'^[A-Z]{3}[0-9]{4}$').hasMatch(v)) {
      return 'Plate format: ABC-1234 (3 letters, 4 digits)';
    }
    return null;
  }

  static String _alnum(String? value) =>
      (value ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  /// Pulls the human-readable message out of raw exception `toString()`s.
  ///
  /// Handles `AuthApiException: message: ... statusCode: ...` and
  /// `PostgrestException(message: ..., code: ...)` formats so users never see
  /// raw exception dumps.
  static String extractMessage(Object error) {
    final raw = error.toString();
    var text = raw.replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), '');

    // PostgrestException(message: ..., code: ..., ...)
    final pg = RegExp(r'^\w*\s*\(\s*message:\s*').firstMatch(text);
    if (pg != null) {
      text = text.substring(pg.end);
      final end = _nextKeyIndex(text);
      text = end == -1 ? text : text.substring(0, end);
    } else {
      // AuthApiException: message: ... statusCode: ...
      final msg = RegExp(r'^\s*message:\s*').firstMatch(text);
      if (msg != null) {
        text = text.substring(msg.end);
        final end = _nextKeyIndex(text);
        text = end == -1 ? text : text.substring(0, end);
      }
    }
    return text.replaceAll(RegExp(r'[),\s]+$'), '').trim();
  }

  static int _nextKeyIndex(String text) {
    final match = RegExp(
      r'\s+(?:statusCode|errorDescription|error|code|hint|details|'
      r'errorSummary|msg|error_code)\s*[:=]',
    ).firstMatch(text);
    return match?.start ?? -1;
  }

  static String friendlyAuthError(Object error) {
    final text = extractMessage(error);
    final lower = text.toLowerCase();
    if (lower.contains('invalid login') || lower.contains('invalid credentials')) {
      return 'Incorrect mobile number or password.';
    }
    if (lower.contains('banned') || lower.contains('not allowed')) {
      return text;
    }
    if (lower.contains('user already registered') ||
        lower.contains('already been registered') ||
        lower.contains('already exists')) {
      return 'An account with this mobile number already exists. Try logging in.';
    }
    if (lower.contains('email not confirmed') ||
        lower.contains('confirm your email') ||
        lower.contains('email_not_confirmed')) {
      return 'Confirm your email before signing in. Check your inbox for the verification link.';
    }
    return text;
  }

  /// Friendly message for non-auth failures (repository calls, etc.).
  static String friendlyError(Object error) {
    final text = extractMessage(error);
    if (text.isEmpty) return 'Something went wrong. Please try again.';
    return text;
  }
}

class AuthFlowException implements Exception {
  AuthFlowException(this.message, {this.isSuccessInfo = false});

  final String message;
  final bool isSuccessInfo;

  @override
  String toString() => message;
}
