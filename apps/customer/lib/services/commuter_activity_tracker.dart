import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/session_provider.dart';
import '../core/utils/uuid.dart';

/// Reports recorded foreground usage so admins can tell study participants
/// who actually open the app apart from those who merely registered.
///
/// Mirrors the driver-side tracker exactly (privacy-conscious by design):
/// - session_start on login / foreground return, heartbeat every
///   [fallbackHeartbeatSeconds] while foreground + authenticated,
///   session_end with reason `logout` / `background`.
/// - No location, keystroke, or personal data. Usage totals are derived
///   server-side from persisted heartbeat timestamps.
/// - Missed beats are skipped, never queued: a network gap shows up as a
///   gap in usage, not as inflated time.
class CommuterActivityTracker {
  CommuterActivityTracker(this._ref);

  final Ref _ref;

  static const int fallbackHeartbeatSeconds = 30;

  AppLifecycleListener? _listener;
  Timer? _timer;
  String? _commuterId;
  String? _sessionId;
  bool _foreground = true;
  bool _busy = false;
  int _heartbeatSeconds = fallbackHeartbeatSeconds;

  /// Starts lifecycle observation. Safe to call once; extra calls no-op.
  void ensureStarted() {
    _listener ??= AppLifecycleListener(
      onShow: () => _onForeground(),
      onResume: () => _onForeground(),
      onHide: () => _onBackground(),
      onPause: () => _onBackground(),
    );
    _sync();
  }

  /// Called whenever the signed-in commuter changes (null on sign-out).
  /// A null commuter only closes an orphaned session as `background`; the
  /// explicit logout path ends its session with reason `logout` first.
  void setCommuter(String? commuterId) {
    if (commuterId == _commuterId) return;
    final hadSession = _sessionId != null;
    _commuterId = commuterId;
    if (commuterId == null) {
      if (hadSession) unawaited(_endSession('background'));
      _stopTimer();
      _sessionId = null;
    } else {
      _sync();
    }
  }

  /// Ends the current session with reason `logout`. Call BEFORE signing out
  /// so the RPC still runs as the authenticated commuter.
  Future<void> endForLogout() async {
    _stopTimer();
    if (_sessionId != null) {
      await _endSession('logout');
      _sessionId = null;
    }
  }

  void dispose() {
    _stopTimer();
    _listener?.dispose();
    _listener = null;
  }

  void _onForeground() {
    if (_foreground) return;
    _foreground = true;
    _sync();
  }

  void _onBackground() {
    _foreground = false;
    _stopTimer();
    if (_sessionId != null) {
      unawaited(_endSession('background'));
      _sessionId = null;
    }
  }

  void _sync() {
    if (_commuterId == null || !_foreground) return;
    if (_sessionId != null) {
      _startTimer();
      return;
    }
    unawaited(_startSession());
  }

  Future<void> _startSession() async {
    if (_busy || _commuterId == null || _sessionId != null) return;
    _busy = true;
    try {
      final repo = _ref.read(customerRepositoryProvider);
      try {
        final config = await repo.fetchActivityConfig();
        final hb = config['heartbeat_seconds'];
        if (hb != null && hb >= 10 && hb <= 300) _heartbeatSeconds = hb;
      } catch (_) {
        // Offline at login: fall back to the default interval.
      }
      final sessionId = generateUuidV4();
      await repo.reportActivity(sessionId: sessionId, event: 'session_start');
      // setCommuter(null) may have run while starting; don't resurrect.
      if (_commuterId == null) {
        unawaited(
          repo.reportActivity(
            sessionId: sessionId,
            event: 'session_end',
            endReason: 'background',
          ),
        );
        return;
      }
      _sessionId = sessionId;
      _startTimer();
    } catch (_) {
      // Start failures retry on the next foreground transition or tick.
      // No queue: a missed start simply leaves a gap in usage.
    } finally {
      _busy = false;
    }
  }

  void _startTimer() {
    _stopTimer();
    if (_commuterId == null || !_foreground || _sessionId == null) return;
    _timer = Timer.periodic(
      Duration(seconds: _heartbeatSeconds),
      (_) => unawaited(_heartbeat()),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _heartbeat() async {
    final sessionId = _sessionId;
    if (sessionId == null || _commuterId == null || !_foreground) return;
    final heartbeatId = generateUuidV4();
    try {
      await _ref
          .read(customerRepositoryProvider)
          .reportActivity(
            sessionId: sessionId,
            event: 'heartbeat',
            heartbeatId: heartbeatId,
          );
    } catch (_) {
      // One bounded retry with the SAME id (server dedupes); then skip.
      // Skipped beats understate usage rather than inventing it.
      try {
        await Future<void>.delayed(const Duration(seconds: 5));
        if (_sessionId != sessionId || !_foreground) return;
        await _ref
            .read(customerRepositoryProvider)
            .reportActivity(
              sessionId: sessionId,
              event: 'heartbeat',
              heartbeatId: heartbeatId,
            );
      } catch (_) {
        // Unknown/closed session: drop it so the next tick starts fresh.
        if (_sessionId == sessionId) {
          _sessionId = null;
          _stopTimer();
          _sync();
        }
      }
    }
  }

  Future<void> _endSession(String reason) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      await _ref
          .read(customerRepositoryProvider)
          .reportActivity(
            sessionId: sessionId,
            event: 'session_end',
            endReason: reason,
          );
    } catch (_) {
      // Best effort: an unrecorded end just leaves the session to go stale,
      // which the server reports as inactive (never as active).
    }
  }
}

/// Single owner for the tracker: starts/stops foreground sessions as the
/// commuter session changes. Watched from the app root so it lives as long
/// as the app.
final commuterActivityTrackerProvider = Provider<CommuterActivityTracker>((ref) {
  final tracker = CommuterActivityTracker(ref);
  tracker.ensureStarted();
  ref.onDispose(tracker.dispose);
  ref.listen<AsyncValue<dynamic>>(sessionProvider, (previous, next) {
    if (next.isLoading || next.hasError) return;
    next.whenData((commuter) {
      tracker.setCommuter((commuter as dynamic)?.id as String?);
    });
  }, fireImmediately: true);
  return tracker;
});
