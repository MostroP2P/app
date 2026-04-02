import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mostro/core/app.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/src/rust/frb_generated.dart';
import 'package:mostro/src/rust/api.dart' as rust_api;
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  // Initialize persistent SQLite store. Must come before any trade / order
  // operations that read or write trade keys and trade records.
  if (!kIsWeb) {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      await rust_api.initDb(path: p.join(docsDir.path, 'mostro.db'));
    } catch (e, st) {
      // DB init failure is non-fatal: trade-key and role persistence won't
      // work for this session, but the app can still browse orders and relay
      // messages.  All Rust callers already handle db() == None gracefully.
      debugPrint('[main] DB init failed — running in memory-only mode: $e\n$st');
    }
  }

  // Initialize identity: creates on first launch, reloads on subsequent launches.
  // Must run before Nostr init so the identity key is available for relay auth.
  await IdentityService.initialize();

  // Pre-read SharedPreferences so providers start with synchronous initial
  // values — eliminates the AsyncValue.loading() race that caused the router
  // to show the home screen before redirecting to /walkthrough on first launch.
  final prefs = await SharedPreferences.getInstance();
  final firstRunComplete = prefs.getBool(kFirstRunCompleteKey) ?? false;
  final backupDismissed = prefs.getBool(kBackupReminderDismissedKey) ?? false;
  final backupActive = prefs.getBool(kBackupReminderActiveKey) ?? false;
  final backupPending = backupActive && !backupDismissed;

  // Initialize the Nostr relay pool with default relays (from config.rs).
  // This must happen before any Nostr/order API calls.
  await nostr_api.initialize(relays: null);

  // Log initial relay state for diagnostics.
  final relays = await nostr_api.getRelays();
  final connState = await nostr_api.getConnectionState();
  debugPrint('[main] relay pool initialized — state=$connState relays=${relays.map((r) => '${r.url}:${r.status}').join(', ')}');

  // Watch for connection state changes in background (logs appear in flutter output).
  _watchConnectionState();

  runApp(ProviderScope(
    overrides: [
      firstRunProvider.overrideWith(
        (ref) => FirstRunNotifier(initialValue: firstRunComplete),
      ),
      backupReminderProvider.overrideWith(
        (ref) => BackupReminderNotifier(initialValue: backupPending),
      ),
    ],
    child: const MostroApp(),
  ));
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
