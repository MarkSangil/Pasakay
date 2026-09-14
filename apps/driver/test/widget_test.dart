import 'package:flutter_test/flutter_test.dart';
import 'package:pasakay_driver/core/utils/phone_utils.dart';

void main() {
  test('normalizes Philippine mobile numbers', () {
    expect(PhoneUtils.normalize('0917 123 4567'), '09171234567');
    expect(PhoneUtils.normalize('+639171234567'), '09171234567');
    expect(PhoneUtils.toAuthEmail('09171234567'), '09171234567@pasakay.driver');
  });
}
