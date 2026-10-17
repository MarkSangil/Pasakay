import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/uuid.dart';
import 'supabase_config.dart';

/// Records screen opens and key actions for the study audit trail.
///
/// What is (and is not) logged:
/// - `screen_*` when a screen appears, plus key actions (call, SMS, report,
///   submit, sign-in/out). Scope agreed with the research team.
/// - Detail values are ids/labels only — never message content,
///   keystrokes, or location.
/// - Fire-and-forget: a failed report is skipped, never stored locally, so
///   logging cannot leak data offline nor block the UI.
class UserAuditTrail {
  const UserAuditTrail();

  Future<void> log(String action, {Map<String, String>? detail}) async {
    try {
      await SupabaseConfig.client.rpc(
        'report_user_audit_log',
        params: {
          'p_log_id': generateUuidV4(),
          'p_action': action,
          'p_detail': (detail == null || detail.isEmpty) ? null : detail,
        },
      );
    } catch (_) {
      // Best effort: a missed entry is a gap in the trail, not an error.
    }
  }
}

final userAuditTrailProvider = Provider<UserAuditTrail>(
  (ref) => const UserAuditTrail(),
);

/// Auto-logs one `screen_*` audit entry the first time a screen state is
/// initialized, as long as its `initState` calls `super.initState()`
/// (the Flutter default contract).
mixin ScreenAudit<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Stable screen code passed to [UserAuditTrail.log],
  /// e.g. `screen_bookings` (max 64 characters, lowercase snake_case).
  String get auditScreen;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(userAuditTrailProvider).log(auditScreen));
  }
}
