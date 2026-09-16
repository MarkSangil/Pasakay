import 'package:flutter/services.dart';

abstract final class PhoneUtils {
  static const int localDigitCount = 11;

  /// Digits-only PH mobile, max 11. Converts `+639…` / `63…` → `09…`.
  static String normalize(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63') && digits.length >= 12) {
      digits = '0${digits.substring(2)}';
    }
    if (digits.length > localDigitCount) {
      digits = digits.substring(0, localDigitCount);
    }
    return digits;
  }

  /// Input formatter: digits only, max 11, normalizes `+639` / `63` prefixes.
  static List<TextInputFormatter> mobileInputFormatters() => [
        _PhMobileInputFormatter(),
      ];

  /// E.164 for dialers (+639171234567). Local 09… → +63….
  static String toE164(String input) {
    final n = normalize(input);
    if (n.startsWith('0') && n.length >= 10) {
      return '+63${n.substring(1)}';
    }
    if (n.startsWith('63') && n.length >= 12) {
      return '+$n';
    }
    return n;
  }

  /// System Phone dialer only (`tel:+639…`). Never chat app deep links.
  static Uri telUri(String mobile) => Uri.parse('tel:${toE164(mobile)}');

  /// System Messages / SMS app only (`sms:+639…`). Never WhatsApp or other chat apps.
  static Uri smsUri(String mobile, {String? body}) {
    final number = toE164(mobile);
    if (body == null || body.isEmpty) {
      return Uri.parse('sms:$number');
    }
    return Uri.parse('sms:$number?body=${Uri.encodeComponent(body)}');
  }

  static String toAuthEmail(String mobile) {
    final n = normalize(mobile);
    return '$n@pasakay.driver';
  }

  static String display(String? mobile) {
    if (mobile == null || mobile.isEmpty) return '—';
    final n = normalize(mobile);
    if (n.length == localDigitCount) {
      return '${n.substring(0, 4)} ${n.substring(4, 7)} ${n.substring(7)}';
    }
    return mobile;
  }
}

class _PhMobileInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = PhoneUtils.normalize(newValue.text);
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}
