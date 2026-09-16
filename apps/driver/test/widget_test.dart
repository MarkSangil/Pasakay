import 'package:flutter_test/flutter_test.dart';
import 'package:pasakay_driver/core/utils/phone_utils.dart';

void main() {
  test('normalizes Philippine mobile numbers', () {
    expect(PhoneUtils.normalize('0917 123 4567'), '09171234567');
    expect(PhoneUtils.normalize('+639171234567'), '09171234567');
    expect(PhoneUtils.toAuthEmail('09171234567'), '09171234567@pasakay.driver');
  });

  test('builds dialable tel and sms URIs', () {
    expect(PhoneUtils.toE164('0917 123 4567'), '+639171234567');
    expect(PhoneUtils.telUri('09171234567').toString(), 'tel:+639171234567');
    expect(
      PhoneUtils.smsUri('09171234567', body: 'hello').toString(),
      'sms:+639171234567?body=hello',
    );
  });
}
