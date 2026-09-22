import 'package:flutter/services.dart';

/// Input formatter for plate numbers stored as `ABC-1234`.
///
/// Uppercases alphanumerics, auto-inserts a dash after the first three
/// characters, and caps input at 3 letters + 4 digits (8 display chars).
class PlateNumberFormatter extends TextInputFormatter {
  const PlateNumberFormatter();

  static const int maxAlnum = 7;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final alnum = _alnumOf(newValue.text).toUpperCase();
    final capped = alnum.length > maxAlnum ? alnum.substring(0, maxAlnum) : alnum;
    final buffer = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 3) buffer.write('-');
      buffer.write(capped[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static String _alnumOf(String input) =>
      input.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
}

/// Input formatter for driver's license numbers stored as `D00-00-000000`.
///
/// Uppercases alphanumerics, auto-inserts dashes after the 2nd and 5th
/// characters, and caps input at 11 characters (13 display chars).
class DriverLicenseFormatter extends TextInputFormatter {
  const DriverLicenseFormatter();

  static const int maxAlnum = 11;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final alnum = _alnumOf(newValue.text).toUpperCase();
    final capped = alnum.length > maxAlnum ? alnum.substring(0, maxAlnum) : alnum;
    final buffer = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 2 || i == 5) buffer.write('-');
      buffer.write(capped[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static String _alnumOf(String input) =>
      input.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
}
