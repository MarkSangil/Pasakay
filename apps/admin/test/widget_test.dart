import 'package:flutter_test/flutter_test.dart';
import 'package:pasakay_admin/models/admin_models.dart';

void main() {
  test('status labels stay inside the scoped account actions', () {
    expect(statusLabel('pending_verification'), 'Pending verification');
    expect(statusLabel('suspended'), 'Suspended');
    expect(statusLabel('deactivated'), 'Deactivated');
    expect(statusLabel('retained'), 'Retained');
  });

  test('clock labels do not invent a fourth shift', () {
    expect(formatClock('06:00:00'), '6:00 AM');
    expect(formatClock('12:00:00'), '12:00 PM');
    expect(formatClock('18:00:00'), '6:00 PM');
  });
}
