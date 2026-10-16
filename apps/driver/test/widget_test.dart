import 'package:flutter_test/flutter_test.dart';
import 'package:pasakay_driver/core/utils/auth_validators.dart';
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

  group('AuthValidators.todaPlate', () {
    test('rejects empty and whitespace-only values', () {
      expect(AuthValidators.todaPlate(null), isNotNull);
      expect(AuthValidators.todaPlate(''), isNotNull);
      expect(AuthValidators.todaPlate('   '), isNotNull);
    });

    test('accepts freeform TODA plate numbers', () {
      expect(AuthValidators.todaPlate('SSLTODA No. 00876'), isNull);
      expect(AuthValidators.todaPlate('TODA-123'), isNull);
    });

    test('normalizes surrounding and repeated whitespace', () {
      expect(
        AuthValidators.normalizeTodaPlate('  SSLTODA   No. 00876  '),
        'SSLTODA No. 00876',
      );
    });
  });
}
