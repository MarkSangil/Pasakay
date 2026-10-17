import 'package:flutter_test/flutter_test.dart';
import 'package:pasakay_admin/core/utils/driver_form_validators.dart';
import 'package:pasakay_admin/models/admin_models.dart';

void main() {
  group('DriverFormValidators', () {
    test('requires name, TODA plate, and plate', () {
      expect(DriverFormValidators.requiredName(''), isNotNull);
      expect(DriverFormValidators.requiredName('Juan'), isNull);
      expect(DriverFormValidators.todaPlateNumber(''), isNotNull);
      expect(DriverFormValidators.todaPlateNumber('   '), isNotNull);
      expect(DriverFormValidators.todaPlateNumber('SSLTODA No. 00876'), isNull);
      expect(DriverFormValidators.plateNumber(''), isNotNull);
      expect(DriverFormValidators.plateNumber('ABC123'), isNull);
    });

    test('validates PH contact numbers', () {
      expect(DriverFormValidators.contactNumber('123'), isNotNull);
      expect(DriverFormValidators.contactNumber('09171234567'), isNull);
      expect(DriverFormValidators.contactNumber('+63 917 123 4567'), isNull);
    });

    test('requires password of at least 8 characters when creating', () {
      expect(DriverFormValidators.password('short', required: true), isNotNull);
      expect(
        DriverFormValidators.password('Password123!', required: true),
        isNull,
      );
      expect(DriverFormValidators.password('', required: false), isNull);
    });

    test('requires terminal and shift selections', () {
      expect(DriverFormValidators.requiredSelection(null, 'shift'), isNotNull);
      expect(DriverFormValidators.requiredSelection('abc', 'shift'), isNull);
    });
  });

  group('DriverRecord availability fields', () {
    test('parses shift and terminal from nested select payload', () {
      final driver = DriverRecord.fromJson({
        'driver_id': 'a0000000-0000-4000-8000-000000000001',
        'full_name': 'Juan Dela Cruz',
        'contact_number': '09171234567',
        'toda_number': 'SSLTODA No. 00876',
        'plate_number': 'ABC123',
        'username': '09171234567',
        'terminal_id': 't1',
        'shift_id': 's1',
        'status': 'active',
        'license_verified': true,
        'terminal': {'terminal_id': 't1', 'terminal_name': 'Camella'},
        'shift': {
          'shift_id': 's1',
          'label': '6:00 AM - 12:00 NN',
          'shift_start_time': '06:00:00',
          'shift_end_time': '12:00:00',
        },
      });

      expect(driver.terminalName, 'Camella');
      expect(driver.shiftLabel, '6:00 AM - 12:00 NN');
      expect(driver.shiftId, 's1');
      expect(driver.status, 'active');
    });
  });

  test('status labels stay inside the scoped account actions', () {
    expect(statusLabel('pending_verification'), 'Pending verification');
    // Suspended was replaced by Deactivated (same effect: blocked login).
    expect(statusLabel('suspended'), 'Deactivated');
  });

  group('AuditLogEntry', () {
    test('parses logs and accepts driver_id or commuter_id keys', () {
      final entry = AuditLogEntry.fromJson({
        'log_id': 'd1',
        'action': 'call_driver',
        'detail': {'driver_id': 'a1', 'note': null},
        'occurred_at': '2026-10-17T02:00:00.000Z',
      });
      expect(entry.action, 'call_driver');
      expect(entry.detail, {'driver_id': 'a1'});
      expect(entry.displayText, contains('Called driver'));
      expect(entry.displayText, contains('driver id: a1'));
    });

    test('action labels cover screens and known actions', () {
      expect(auditActionLabel('screen_driver_list'), 'Opened Driver List');
      expect(auditActionLabel('logout'), 'Signed out');
      expect(auditActionLabel('screen_login'), 'Opened Login');
    });
  });
}
