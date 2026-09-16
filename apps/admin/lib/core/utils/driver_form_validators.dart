/// Client-side checks for admin driver forms.
/// Server RPCs remain authoritative.
abstract final class DriverFormValidators {
  static String? requiredName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Full name is required';
    return null;
  }

  static String? contactNumber(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    var normalized = digits;
    if (normalized.startsWith('63') && normalized.length >= 12) {
      normalized = '0${normalized.substring(2)}';
    }
    if (!RegExp(r'^09\d{9}$').hasMatch(normalized)) {
      return 'Enter a valid PH mobile (09XXXXXXXXX)';
    }
    return null;
  }

  static String? licenseNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'License number is required';
    return null;
  }

  static String? plateNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Plate number is required';
    return null;
  }

  static String? ssltodaNumber(String? value, {bool required = false}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return required ? 'SSLTODA number is required' : null;
    }
    if (v.length < 2) return 'Enter a valid SSLTODA number';
    return null;
  }

  static String? password(String? value, {required bool required}) {
    if (!required && (value == null || value.isEmpty)) return null;
    if (value == null || value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  static String? requiredSelection(String? value, String label) {
    if (value == null || value.isEmpty) return 'Select a $label';
    return null;
  }
}
