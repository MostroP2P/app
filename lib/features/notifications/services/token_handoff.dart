import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mostro/src/rust/api/types.dart';

/// Hands the device token to Rust, and keeps trying when Rust cannot take
/// it yet.
///
/// `set_push_token` fails with `StorageUnavailable` while the database is
/// not up — a token can arrive before `init_db` finished, or during a
/// storage hiccup. Dropping it would leave Rust with no token (or a
/// superseded one) until the next FCM refresh, which may be weeks away. So
/// the latest token is kept and re-offered on a bounded backoff, and
/// [retryPending] lets the permission re-check try again on demand. An
/// `InvalidToken` is a bug, not a transient: it is logged and dropped.
class TokenHandoff {
  TokenHandoff({
    required this.setToken,
    this.delays = const [
      Duration(seconds: 1),
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 2),
    ],
    Timer Function(Duration, void Function())? schedule,
  }) : _schedule = schedule ?? Timer.new;

  /// The bridge call, injected for tests.
  final Future<void> Function(String token, PushPlatform platform) setToken;

  /// Backoff between attempts; the list's length bounds the retries.
  final List<Duration> delays;

  final Timer Function(Duration, void Function()) _schedule;

  String? _pending;
  PushPlatform? _platform;
  int _failures = 0;
  Timer? _timer;

  /// The token Rust has not accepted yet, if any. Exposed for tests.
  @visibleForTesting
  String? get pending => _pending;

  /// A new token from the device: supersedes whatever was pending.
  Future<void> offer(String token, PushPlatform platform) {
    _timer?.cancel();
    _timer = null;
    _pending = token;
    _platform = platform;
    _failures = 0;
    return _attempt();
  }

  /// Try the pending token again now, ahead of its backoff.
  Future<void> retryPending() {
    if (_pending == null) return Future.value();
    _timer?.cancel();
    _timer = null;
    return _attempt();
  }

  /// Forget the pending token and its retry: the user turned push off, and
  /// a retry landing afterwards would hand Rust a token they just let go.
  ///
  /// The returned future completes once no hand-over is in flight, so a
  /// caller can clear Rust's token after it: a `set_push_token` still
  /// running would otherwise write the token back after the clear.
  Future<void> discard() async {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _platform = null;
    while (_inFlight != null) {
      await _inFlight;
    }
  }

  /// The bridge call currently running, if any.
  Future<void>? _inFlight;

  Future<void> _attempt() {
    final attempt = _runAttempt();
    _inFlight = attempt;
    return attempt.whenComplete(() {
      if (identical(_inFlight, attempt)) _inFlight = null;
    });
  }

  Future<void> _runAttempt() async {
    final token = _pending;
    final platform = _platform;
    if (token == null || platform == null) return;
    try {
      await setToken(token, platform);
      if (_pending == token) _pending = null;
      return;
    } catch (e) {
      final message = e.toString();
      if (!message.contains('StorageUnavailable')) {
        // InvalidToken, or anything unexpected: not worth retrying.
        debugPrint('[push] token not handed to Rust, dropped: $e');
        if (_pending == token) _pending = null;
        return;
      }
      if (_pending != token) return; // superseded meanwhile
      if (_failures >= delays.length) {
        debugPrint('[push] token not handed to Rust after retries: $e');
        return;
      }
      final delay = delays[_failures];
      _failures++;
      debugPrint('[push] storage not ready for the token, retrying in $delay');
      _timer = _schedule(delay, () {
        _timer = null;
        unawaited(_attempt());
      });
    }
  }
}
