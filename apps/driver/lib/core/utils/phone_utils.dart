abstract final class PhoneUtils {
  /// Normalize PH mobiles to digits only (e.g. 09171234567).
  static String normalize(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63') && digits.length >= 12) {
      digits = '0${digits.substring(2)}';
    }
    return digits;
  }

  static String toAuthEmail(String mobile) {
    final n = normalize(mobile);
    return '$n@${'pasakay.driver'}';
  }

  static String display(String? mobile) {
    if (mobile == null || mobile.isEmpty) return '—';
    final n = normalize(mobile);
    if (n.length == 11) {
      return '${n.substring(0, 4)} ${n.substring(4, 7)} ${n.substring(7)}';
    }
    return mobile;
  }
}
