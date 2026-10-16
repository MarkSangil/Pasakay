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

  static String? plateNumber(String? value) {
    if (value == null || value.trim().isEmpty)
      return 'Plate number is required';
    return null;
  }

  /// TODA Plate Number: required on create and edit (completes legacy rows).
  /// Freeform (e.g. `SSLTODA No. 00876`); no strict format, no uniqueness
  /// check per business rules.
  static String? todaPlateNumber(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'TODA Plate Number is required';
    if (v.length < 2) return 'Enter a valid TODA Plate Number';
    return null;
  }

  /// Strict format check for NEW drivers: canonical `ABC-1234`
  /// (3 letters + 4 digits after normalization).
  static String? plateNumberFormat(String? value) {
    final required = plateNumber(value);
    if (required != null) return required;
    final v = _alnum(value).toUpperCase();
    if (!RegExp(r'^[A-Z]{3}[0-9]{4}$').hasMatch(v)) {
      return 'Format: ABC-1234 (3 letters, 4 digits)';
    }
    return null;
  }

  static String _alnum(String? value) =>
      (value ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

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
