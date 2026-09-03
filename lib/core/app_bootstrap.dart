import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
// Resolves the app's own data directory — never the user-visible Documents
// folder. Web gets the stub; bootstrap only calls it behind `!kIsWeb`.
import 'package:mostro/core/storage/app_data_dir.dart'
    if (dart.library.html) 'package:mostro/core/storage/app_data_dir_web.dart';
import 'package:mostro/core/app.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/core/test_environment.dart';
import 'package:mostro/core/web/bridge_probe.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/firebase_options.dart';
import 'package:mostro/src/rust/frb_generated.dart';
import 'package:mostro/src/rust/api.dart' as rust_api;
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/src/rust/api/escrow.dart' as escrow_api;
import 'package:mostro/src/rust/api/nwc.dart' as nwc_api;
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/settings.dart' as settings_api;
import 'package:mostro/src/rust/api/bond.dart' as bond_api;
import 'package:mostro/src/rust/api/identity.dart' as identity_api;
import 'package:mostro/src/rust/api/types.dart' show SlashCause, BondSlashedEvent;
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';

/// Starts the application.
///
/// Both entry points funnel through here, so a build under test and a
/// production build differ only in what they pass, never in how they start:
/// `lib/main.dart` calls it with no arguments, `lib/main_mortsom.dart` calls
/// it with the local relay seed list.
///
/// [seedRelays] replaces the compiled-in relay defaults when it is not
/// empty. That is what keeps a run against a local relay honest: with the
/// defaults gone, an unreachable local relay fails the test instead of
/// silently succeeding against a public one.
Future<void> bootstrapAndRun({List<String> seedRelays = const []}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (no-op if firebase_options.dart is the placeholder).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError catch (e) {
    debugPrint('[main] Firebase not configured: $e — push notifications disabled.');
  }

  await RustLib.init();

  // Pre-read SharedPreferences so providers start with synchronous initial
  // values — eliminates the AsyncValue.loading() race that caused the router
  // to show the home screen before redirecting to /walkthrough on first launch.
  final prefs = await SharedPreferences.getInstance();
  final firstRunComplete = prefs.getBool(kFirstRunCompleteKey) ?? false;
  final backupDismissed = prefs.getBool(kBackupReminderDismissedKey) ?? false;
  final backupActive = prefs.getBool(kBackupReminderActiveKey) ?? false;
  final backupPending = backupActive && !backupDismissed;
  final savedSettings = AppSettingsState.fromPrefs(prefs);

  // Before any startup work below, so a failure in it is captured at the
  // verbosity the user asked for rather than the default.
  await settings_api.setLoggingEnabled(enabled: savedSettings.loggingEnabled);

  // Initialize persistent SQLite store. Must come before any trade / order
  // operations that read or write trade keys and trade records.
  if (!kIsWeb) {
    try {
      final dataDir = await appDataDirPath();
      await rust_api.initDb(path: p.join(dataDir, 'mostro.db'));
    } catch (e, st) {
      // DB init failure is non-fatal: trade-key and role persistence won't
      // work for this session, but the app can still browse orders and relay
      // messages.  All Rust callers already handle db() == None gracefully.
      debugPrint('[main] DB init failed — running in memory-only mode: $e\n$st');
    }
  }

  // Load the persisted active Mostro node into the Rust override before the
  // relay pool starts, so the first subscription targets the user's selected
  // node. No-op when none was saved (the compiled-in default then applies).
  // The resolved pubkey seeds mostroPubkeyProvider so Settings shows the real
  // active node on launch.
  //
  // This is also the first call that proves the Rust bridge is alive end to
  // end, so its outcome doubles as the web readiness probe CI waits on — see
  // lib/core/web/bridge_probe.dart (no-op off web).
  String activeMostroPubkey = defaultMostroPubkey;
  try {
    await settings_api.rehydrateActiveMostroNode();
    activeMostroPubkey = await settings_api.getMostroPubkey();
    // A Mortsom build is pointed at a locally managed daemon through
    // MOSTRO_PUB_KEY. Seed it only when nothing was ever selected, so a
    // restart keeps whatever the run chose through the UI, and do it here so
    // the very first subscription already targets the daemon under test
    // rather than the compiled-in production node.
    final seedPubkey = TestEnvironment.mostroPubkey;
    if (seedPubkey != null && activeMostroPubkey == defaultMostroPubkey) {
      await settings_api.setActiveMostroNode(pubkey: seedPubkey);
      activeMostroPubkey = await settings_api.getMostroPubkey();
      debugPrint('[main] Mortsom build: active Mostro node seeded from MOSTRO_PUB_KEY');
    }
    // Load the escrow-mode overrides before the relay pool starts, so the first
    // capability fetch already resolves against them. Nothing can have written
    // them in a release build (docs/cashu/README.md §4.3).
    await escrow_api.rehydrateEscrowOverrides();
    markBridgeReady();
  } catch (e) {
    debugPrint('[main] rehydrate active Mostro node failed: $e');
    markBridgeFailed(e);
  }

  // Mirror consumed trade-key indices into secure storage — the copy that
  // outlives mostro.db, which Rust keeps as the primary record (issue #249).
  //
  // Subscribed BEFORE identity init on purpose: loading the identity is itself
  // a publication point (when the database knew a higher counter than secure
  // storage, the reconciled value is published so this copy catches up), and
  // the Tokio broadcast channel drops a value that has no receiver yet.
  // Guarded like every other optional startup step: if the bridge is broken
  // the mirror is simply absent — the database copy is still the primary
  // record — rather than taking startup down before the UI renders.
  try {
    _mirrorTradeKeyIndex(await identity_api.onTradeKeyIndexChanged());
  } catch (e) {
    debugPrint('[identity] trade-key index mirror unavailable: $e');
  }

  // Initialize identity: creates on first launch, reloads on subsequent launches.
  // Must run before Nostr init so the identity key is available for relay auth.
  try {
    await IdentityService.initialize();
  } catch (e, st) {
    debugPrint('[main] Identity init failed — secure storage unavailable: $e\n$st');
  }

  // Subscribe to bond-slashed notices BEFORE relay delivery starts, so the
  // Tokio broadcast channel buffers any notice arriving during startup rather
  // than dropping it (a receiver must exist at send time).
  final bondSlashedStream = await bond_api.onBondSlashed();

  // Initialize the Nostr relay pool. `null` means the compiled-in defaults
  // (config.rs); a non-empty seed list replaces them entirely.
  // This must happen before any Nostr/order API calls.
  await nostr_api.initialize(relays: seedRelays.isEmpty ? null : seedRelays);

  // Log initial relay state for diagnostics.
  final relays = await nostr_api.getRelays();
  final connState = await nostr_api.getConnectionState();
  debugPrint('[main] relay pool initialized — state=$connState relays=${relays.map((r) => '${r.url}:${r.status}').join(', ')}');

  // Watch for connection state changes in background (logs appear in flutter output).
  _watchConnectionState();

  final container = ProviderContainer(
    overrides: [
      firstRunProvider.overrideWith(
        (ref) => FirstRunNotifier(initialValue: firstRunComplete),
      ),
      backupReminderProvider.overrideWith(
        (ref) => BackupReminderNotifier(initialValue: backupPending),
      ),
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(prefs: prefs, initial: savedSettings),
      ),
      nwcProvider.overrideWith(
        (ref) => NwcNotifier(prefs: prefs),
      ),
      mostroPubkeyProvider.overrideWith((ref) => activeMostroPubkey),
    ],
  );

  // Restore NWC wallet connection if a URI was saved from a previous session.
  final savedNwcUri = prefs.getString(kNwcUriKey);
  if (savedNwcUri != null) {
    _restoreNwcConnection(savedNwcUri, container);
  }

  _consumeBondSlashed(bondSlashedStream, container);

  runApp(UncontrolledProviderScope(
    container: container,
    child: const MostroApp(),
  ));
}

/// Persists every consumed trade-key index reported by Rust.
///
/// Runs for the process lifetime. A write failure is logged and the loop
/// continues: the database copy is still authoritative, and the next index
/// (or the load-time reconciliation) supersedes the one that was missed.
void _mirrorTradeKeyIndex(identity_api.TradeKeyIndexStream stream) {
  Future.microtask(() async {
    while (true) {
      final int index;
      try {
        index = await stream.next();
      } catch (e) {
        debugPrint('[identity] trade-key index stream closed: $e');
        break;
      }
      debugPrint('[identity] mirroring trade-key index $index to secure storage');
      try {
        await IdentityService.saveTradeKeyIndex(index);
      } catch (e, st) {
        // The database copy is still authoritative and the next index (or
        // the load-time reconciliation) supersedes the one missed here. An
        // escaping exception would end the microtask and silently drop every
        // later index for the rest of the process.
        debugPrint('[identity] mirror write failed for index $index: $e\n$st');
      }
    }
  });
}

/// Reconnect a previously saved NWC wallet in the background.
void _restoreNwcConnection(String nwcUri, ProviderContainer container) {
  Future.microtask(() async {
    try {
      final info = await nwc_api.connectWallet(nwcUri: nwcUri);
      container.read(nwcProvider.notifier).setConnected(
            NwcWalletState(
              walletPubkey: info.walletPubkey,
              relayUrls: info.relayUrls,
              walletName: info.walletName,
              balanceSats: info.balanceSats?.toInt(),
            ),
          );
      debugPrint('[nwc] wallet restored: ${info.walletName ?? info.walletPubkey}');
    } catch (e) {
      debugPrint('[nwc] wallet restore failed: $e');
    }
  });
}

/// Consumes bond-slashed notices from [stream] and records an in-app
/// notification for each. The tracked order is never touched here — the notice
/// is informational, and the no-overwrite guard lives in the Rust dispatcher.
///
/// [stream] is subscribed before relay delivery starts (see [bootstrapAndRun]),
/// so this drains any notice buffered during startup and then live ones.
/// Notifications go through [NotificationsNotifier.addIfNew] on the DB-backed
/// [notificationsProvider], keyed on the source event id, so the daemon's
/// history replay yields exactly one record and preserves read/delete state.
///
/// Errors are handled per event: a failed record insert is logged and the
/// listener keeps going, so one transient failure never drops future notices.
/// Only a closed/broken stream (a non-null throw from [next]) ends the loop.
void _consumeBondSlashed(
  bond_api.BondSlashedStream stream,
  ProviderContainer container,
) {
  Future.microtask(() async {
    while (true) {
      final BondSlashedEvent event;
      try {
        event = await stream.next();
      } catch (e, st) {
        debugPrint('[bond-slashed] stream closed: $e\n$st');
        break;
      }
      try {
        // Only stable data is stored; the copy is localized at render time.
        await container.read(notificationsProvider.notifier).addIfNew(
              NotificationModel.bondSlashed(
                id: event.eventId,
                orderId: event.orderId,
                amountSats: event.amountSats.toInt(),
                disputeCause: event.cause == SlashCause.dispute,
                fiatCode: event.fiatCode,
                fiatAmount: event.fiatAmount.toInt(),
                paymentMethod: event.paymentMethod,
              ),
            );
      } catch (e, st) {
        debugPrint('[bond-slashed] failed to record notice: $e\n$st');
      }
    }
  });
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
