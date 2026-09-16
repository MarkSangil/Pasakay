/// Shared client-side auth validation for the passenger app.
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

  static String friendlyAuthError(Object error) {
    final raw = error.toString();
    final text = raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^AuthApiException:\s*'), '')
        .replaceFirst(RegExp(r'^AuthException:\s*'), '')
        .replaceFirst(RegExp(r'^PostgrestException\([^)]*\):\s*'), '')
        .replaceFirst(RegExp(r'^PostgrestException:\s*'), '');
    final lower = text.toLowerCase();
    if (lower.contains('invalid login') || lower.contains('invalid credentials')) {
      return 'Incorrect mobile number or password.';
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
    if (lower.contains('confirm') ||
        lower.contains('confirmation') ||
        lower.contains('check your email') ||
        lower.contains('verify')) {
      return text;
    }
    if (lower.contains('password')) return text;
    if (lower.contains('suspended') ||
        lower.contains('deactivated') ||
        lower.contains('waiting for') ||
        lower.contains('not a passenger') ||
        lower.contains('not a driver') ||
        lower.contains('account created')) {
      return text;
    }
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
