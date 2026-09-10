import 'dart:async';

/// Runs an async load at most once at a time, and remembers that one more was
/// asked for while it was running.
///
/// The naive `if (_loading) return;` guard silently drops that request — and a
/// dropped request is not a no-op when the running load has already read its
/// data: it ends up showing a snapshot taken before whatever triggered the
/// second request. One extra pass afterwards is enough to settle, however many
/// requests arrived while the first was in flight.
class CoalescingLoader {
  CoalescingLoader(this._load);

  final Future<void> Function() _load;

  bool _running = false;
  bool _pending = false;

  /// Whether a load is in flight.
  bool get isRunning => _running;

  /// Run the load, or mark one as owed if it is already running.
  Future<void> run() async {
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    try {
      await _load();
    } finally {
      _running = false;
    }
    if (_pending) {
      _pending = false;
      await run();
    }
  }
}
