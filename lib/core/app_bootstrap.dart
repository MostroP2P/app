import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Resolves the app's own data directory — never the user-visible Documents
// folder. Web gets the stub; bootstrap only calls it behind `!kIsWeb`.
import 'package:mostro/core/storage/db_location.dart';
import 'package:mostro/core/storage/app_data_dir.dart'
    if (dart.library.html) 'package:mostro/core/storage/app_data_dir_web.dart';
import 'package:mostro/core/app.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/core/startup_failure.dart';
import 'package:mostro/core/startup_sequence.dart';
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
import 'package:mostro/src/rust/api/types.dart'
    show SlashCause, BondSlashedEvent;
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
  // Outside the guard on purpose: the rescue below paints through runApp, which
  // needs the binding too. Catching a failure here would only let us try to
  // render a screen that cannot render, so this one is honestly unguarded.
  WidgetsFlutterBinding.ensureInitialized();

  final startup = StartupSequence();
  try {
    await _startup(startup, seedRelays: seedRelays);
  } catch (e, st) {
    // The failure surface calls runApp too, and that is the whole fix: without
    // it an exception here means runApp never runs and Flutter paints nothing —
    // the page is not broken, it is absent, with no message anywhere.
    //
    // #227 is the precedent that motivated this guard, not a case it covers:
    // that crash fires inside the engine's own CanvasKitRenderer.initialize,
    // before main() runs, which is why #370 fixed it in web/index.html and
    // stated that no app-level try/catch could reach it.
    debugPrint('[startup] fatal while ${startup.currentStep}: $e\n$st');
    // The screen first: it is what a person is waiting for, and it is the whole
    // point of this catch. Anything ahead of it that could throw would leave
    // them with the blank page this exists to replace.
    runApp(StartupFailureApp(step: startup.currentStep, error: e));
    // Then CI. No-op off web; on web it hands test/web/smoke/smoke.mjs the
    // cause, so the run stops with a reason instead of timing out waiting for
    // a bridge that is never coming.
    markBridgeFailed(e);
  }
}

Future<void> _startup(
  StartupSequence startup, {
  List<String> seedRelays = const [],
}) async {
  // Push notifications only — the app trades, chats and settles without them.
  //
  // The one optional step that handles anything itself: this repo ships a
  // placeholder Firebase config, so every run throws UnsupportedError here.
  // That is an expected state, not a failure, and letting it reach the helper
  // would make every single run log a "failed" nobody reads by the time it
  // means something. Caught below and reported as what it is; everything else
  // falls through to the helper.
  await startup.optional('setting up notifications', () async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on UnsupportedError catch (e) {
      // The placeholder config, which is an expected state rather than a
      // failure. Swallowed here so it does not reach the helper's generic
      // "failed" line, which every run would then log for nothing.
      debugPrint(
        '[startup] Firebase not configured — push notifications disabled: $e',
      );
    }
    // Anything else — a third-party JS SDK's config, network or internals —
    // falls through to the helper and is reported as the degradation it is.
  });

  await startup.required('loading the engine', RustLib.init);

  // Pre-read SharedPreferences so providers start with synchronous initial
  // values — eliminates the AsyncValue.loading() race that caused the router
  // to show the home screen before redirecting to /walkthrough on first launch.
  final (
    prefs,
    firstRunComplete,
    backupPending,
    savedSettings,
  ) = await startup.required('reading your settings', () async {
    final prefs = await SharedPreferences.getInstance();
    final backupDismissed = prefs.getBool(kBackupReminderDismissedKey) ?? false;
    final backupActive = prefs.getBool(kBackupReminderActiveKey) ?? false;
    return (
      prefs,
      prefs.getBool(kFirstRunCompleteKey) ?? false,
      backupActive && !backupDismissed,
      AppSettingsState.fromPrefs(prefs),
    );
  });

  // Before any startup work below, so a failure in it is captured at the
  // verbosity the user asked for rather than the default.
  await startup.optional('applying your log settings', () async {
    await settings_api.setLoggingEnabled(enabled: savedSettings.loggingEnabled);
  });

  // The persistent store (a SQLite file off the web, an IndexedDB database on
  // it, #408). Must come before any trade / order operation that reads or
  // writes trade keys and trade records.
  //
  // Optional, and it was already written that way before this guard existed:
  // without it the session is memory-only — trade keys and roles do not
  // survive a restart — but orders still browse and relay messages still
  // arrive, and every Rust caller handles a missing database. Runs on the web
  // too: since #408 that is where web persistence lives, so skipping it there
  // would quietly take out every feature built on top of it.
  await startup.optional('opening the local database', () async {
    final location = databaseLocation(
      isWeb: kIsWeb,
      dataDir: kIsWeb ? null : await appDataDirPath(),
    );
    await rust_api.initDb(path: location);
  });

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
  // Named here rather than through a helper: the catch below does more than
  // record the failure — it tells the web bridge probe, and CI reads that.
  startup.currentStep = 'selecting the Mostro node';
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
      debugPrint(
        '[main] Mortsom build: active Mostro node seeded from MOSTRO_PUB_KEY',
      );
    }
    // Load the escrow-mode overrides before the relay pool starts, so the first
    // capability fetch already resolves against them. Nothing can have written
    // them in a release build (docs/cashu/README.md §4.3).
    await escrow_api.rehydrateEscrowOverrides();
    // A Mortsom build may ask the daemon for a short order expiry; set
    // before any order can be created.
    final orderExpiry = TestEnvironment.orderExpirySecs;
    if (orderExpiry != null) {
      await settings_api.setTestOrderExpiry(secs: BigInt.from(orderExpiry));
      debugPrint('[main] Mortsom build: orders expire after ${orderExpiry}s');
    }
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
  // Named here rather than through a helper: this block keeps its own handler
  // and its own log prefix, which the identity work is grouped under.
  startup.currentStep = 'mirroring trade key indices';
  try {
    _mirrorTradeKeyIndex(await identity_api.onTradeKeyIndexChanged());
  } catch (e) {
    debugPrint('[identity] trade-key index mirror unavailable: $e');
  }

  // Initialize identity: creates on first launch, reloads on subsequent launches.
  // Must run before Nostr init so the identity key is available for relay auth.
  // Named here rather than through a helper, for the same reason as above.
  startup.currentStep = 'loading your identity';
  try {
    await IdentityService.initialize();
  } catch (e, st) {
    debugPrint(
      '[main] Identity init failed — secure storage unavailable: $e\n$st',
    );
  }

  // Subscribe to bond-slashed notices BEFORE relay delivery starts, so the
  // Tokio broadcast channel buffers any notice arriving during startup rather
  // than dropping it (a receiver must exist at send time).
  bond_api.BondSlashedStream? bondSlashedStream;
  await startup.optional('subscribing to bond notices', () async {
    bondSlashedStream = await bond_api.onBondSlashed();
  });

  // Initialize the Nostr relay pool. `null` means the compiled-in defaults
  // (config.rs); a non-empty seed list replaces them entirely.
  // This must happen before any Nostr/order API calls.
  // Optional because the app already knows how to be disconnected: it shows
  // connection state, and Settings can switch node or edit the relay list. An
  // app that opens offline can be fixed from inside; one that does not open
  // cannot be fixed at all.
  await startup.optional('connecting to the network', () async {
    await nostr_api.initialize(relays: seedRelays.isEmpty ? null : seedRelays);
  });

  // Log initial relay state for diagnostics.
  await startup.optional('reading relay status', () async {
    final relays = await nostr_api.getRelays();
    final connState = await nostr_api.getConnectionState();
    debugPrint(
      '[main] relay pool initialized — state=$connState relays=${relays.map((r) => '${r.url}:${r.status}').join(', ')}',
    );
  });

  // Assembling the container, restoring the wallet and starting the watchers
  // are one stretch with no natural place to stop. Unlabelled, they ran under
  // the name of whichever optional step finished last, so a failure here named
  // a step that had already succeeded (#405 review).
  //
  // runApp stays outside the wrapper: the label is still 'building the
  // interface' when it runs, so it is already covered, and the guard sits above
  // both either way. Purely so this reads as one statement rather than a
  // closure with the whole tail inside it.
  final container = await startup.required('building the interface', () async {
    // Logs every relay connection state change (debug builds only).
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
        nwcProvider.overrideWith((ref) => NwcNotifier(prefs: prefs)),
        mostroPubkeyProvider.overrideWith((ref) => activeMostroPubkey),
      ],
    );

    // Restore NWC wallet connection if a URI was saved from a previous session.
    final savedNwcUri = prefs.getString(kNwcUriKey);
    if (savedNwcUri != null) {
      _restoreNwcConnection(savedNwcUri, container);
    }

    final slashed = bondSlashedStream;
    if (slashed != null) _consumeBondSlashed(slashed, container);
    return container;
  });

  runApp(
    UncontrolledProviderScope(container: container, child: const MostroApp()),
  );
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
      debugPrint(
        '[identity] mirroring trade-key index $index to secure storage',
      );
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
      container
          .read(nwcProvider.notifier)
          .setConnected(
            NwcWalletState(
              walletPubkey: info.walletPubkey,
              relayUrls: info.relayUrls,
              walletName: info.walletName,
              balanceSats: info.balanceSats?.toInt(),
            ),
          );
      debugPrint(
        '[nwc] wallet restored: ${info.walletName ?? info.walletPubkey}',
      );
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
        await container
            .read(notificationsProvider.notifier)
            .addIfNew(
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
                debugPrint(
                  '[diag] order cache after 5s: ${orders.length} orders',
                );
                if (orders.isNotEmpty) {
                  debugPrint(
                    '[diag] first order: id=${orders.first.id} kind=${orders.first.kind} fiat=${orders.first.fiatCode}',
                  );
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
