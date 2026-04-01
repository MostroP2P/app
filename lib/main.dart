import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/app.dart';
import 'package:mostro/src/rust/frb_generated.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

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

/// Guards against overlapping diagnostic order polls on rapid reconnects.
bool _isPollingOrders = false;

/// Background watcher: logs every relay pool connection state change.
/// When Online, also polls the order cache after a short delay so we know
/// whether the Kind 38383 subscription actually delivered events.
///
/// Only active in debug builds — this is diagnostic tooling.
void _watchConnectionState() {
  if (!kDebugMode) return;
  Future.microtask(() async {
    try {
      final stream = await nostr_api.onConnectionStateChanged();
      while (true) {
        final state = await stream.next();
        if (state == null) break;
        debugPrint('[nostr] connection state → $state');
        if (state.name == 'online') {
          // Log relay details when we come online.
          final relays = await nostr_api.getRelays();
          for (final r in relays) {
            debugPrint('[nostr] relay ${r.url} → ${r.status}');
          }
          // Wait 5 seconds then poll the order cache — tells us if the
          // Kind 38383 subscription delivered any events.
          // Guard against overlapping polls on rapid reconnects.
          if (!_isPollingOrders) {
            _isPollingOrders = true;
            Future.delayed(const Duration(seconds: 5), () async {
              try {
                final orders = await orders_api.getOrders(filters: null);
                debugPrint('[diag] order cache after 5s: ${orders.length} orders');
                if (orders.isNotEmpty) {
                  debugPrint('[diag] first order: id=${orders.first.id} kind=${orders.first.kind} fiat=${orders.first.fiatCode}');
                }
              } catch (e) {
                debugPrint('[diag] order cache poll error: $e');
              } finally {
                _isPollingOrders = false;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[nostr] connection watcher error: $e');
    }
  });
}
