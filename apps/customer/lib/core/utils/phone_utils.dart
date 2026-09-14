abstract final class PhoneUtils {
  static String normalize(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63') && digits.length >= 12) {
      digits = '0${digits.substring(2)}';
    }
    return digits;
  }

  static bool looksLikeEmail(String input) => input.contains('@');

  /// Phone → `{mobile}@pasakay.commuter`; email stays as entered.
  static String toAuthEmail(String emailOrPhone) {
    final trimmed = emailOrPhone.trim();
    if (looksLikeEmail(trimmed)) return trimmed.toLowerCase();
    return '${normalize(trimmed)}@pasakay.commuter';
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
