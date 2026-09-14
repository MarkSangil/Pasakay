import 'package:flutter_test/flutter_test.dart';
import 'package:pasakay_customer/core/utils/phone_utils.dart';

void main() {
  test('phone maps to commuter auth email', () {
    expect(
      PhoneUtils.toAuthEmail('09181234567'),
      '09181234567@pasakay.commuter',
    );
  });

  test('email stays email', () {
    expect(
      PhoneUtils.toAuthEmail('maria.santos@example.com'),
      'maria.santos@example.com',
    );
  });
}
