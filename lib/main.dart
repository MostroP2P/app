import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/app.dart';
import 'package:mostro/src/rust/frb_generated.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // Initialize the Nostr relay pool with default relays (from config.rs).
  // This must happen before any Nostr/order API calls.
  await nostr_api.initialize(relays: null);

  // Log initial relay state for diagnostics.
  final relays = await nostr_api.getRelays();
  final connState = await nostr_api.getConnectionState();
  debugPrint('[main] relay pool initialized — state=$connState relays=${relays.map((r) => '${r.url}:${r.status}').join(', ')}');

  // Watch for connection state changes in background (logs appear in flutter output).
  _watchConnectionState();

  runApp(const ProviderScope(child: MostroApp()));
}

/// Background watcher: logs every relay pool connection state change.
/// Output visible via `flutter run` / `adb logcat -s flutter`.
void _watchConnectionState() {
  Future.microtask(() async {
    try {
      final stream = await nostr_api.onConnectionStateChanged();
      while (true) {
        final state = await stream.next();
        if (state == null) break;
        debugPrint('[nostr] connection state → $state');
      }
    } catch (e) {
      debugPrint('[nostr] connection watcher error: $e');
    }
  });
}
