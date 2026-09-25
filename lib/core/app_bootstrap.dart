import 'dart:async';
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
import 'package:mostro/core/font_licenses.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/core/startup_sequence.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/core/test_environment.dart';
import 'package:mostro/core/lifecycle/app_lifecycle_service.dart';
import 'package:mostro/core/lifecycle/resume_resync.dart';
import 'package:mostro/core/web/bridge_probe.dart';
import 'package:mostro/core/web/store_probe.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/firebase_options.dart';
import 'package:mostro/src/rust/frb_generated.dart';
import 'package:mostro/src/rust/api.dart' as rust_api;
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/src/rust/api/escrow.dart' as escrow_api;
import 'package:mostro/src/rust/api/node_stats.dart' as node_stats_api;
import 'package:mostro/src/rust/api/nwc.dart' as nwc_api;
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/settings.dart' as settings_api;
import 'package:mostro/src/rust/api/bond.dart' as bond_api;
import 'package:mostro/src/rust/api/identity.dart' as identity_api;
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart'
    show BondClaimPhase, BondClaimUpdate, BondSlashedEvent, SlashCause;
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show rawTradesProvider;
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/services/event_cards.dart';
import 'package:mostro/core/app_routes.dart' show appRouter;
import 'package:mostro/src/rust/api/messages.dart' as messages_api;

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

  await runGuarded((startup) => _startup(startup, seedRelays: seedRelays));
}

Future<void> _startup(
  StartupSequence startup, {
  List<String> seedRelays = const [],
}) async {
  // The three platform round trips of startup — push notifications, the Rust
  // engine and the saved preferences — started together rather than one after
  // the other, since all of them run before the first frame (#494, which cut cold start to runApp from 2.3 s to 0.5-0.8 s).
  //
  // Each one is awaited below inside its own named step, so a failure still
  // names the stretch it belongs to: `StartupSequence.currentStep` is a single
  // field, and three steps running under it at once would leave a failure
  // naming whichever of them was set last.
  //
  // `ignore()` is what makes that late await honest. A future that fails while
  // another is still being awaited has no listener yet, and Dart reports it as
  // an unhandled async error before we ever reach its step; `ignore()` marks
  // the error handled without consuming it, and the `await` below still throws.
  final firebase = _initFirebase()..ignore();
  final engine = RustLib.init()..ignore();
  final preferences = SharedPreferences.getInstance()..ignore();

  // The bundled fonts ship under the SIL Open Font License, which allows it
  // only alongside their notices; this adds them to Flutter's licence page.
  // It registers a loader rather than reading the files, and a failure leaves
  // that page two entries short — no reason to stop the app from opening.
  await startup.optional('registering font licences', () async {
    registerFontLicenses();
  });

  // Push notifications only — the app trades, chats and settles without them.
  // Optional on purpose: there is no Firebase configuration for Linux, so this
  // fails there on every run (see lib/firebase_options.dart), and the app has
  // to open anyway.
  await startup.optional('setting up notifications', () => firebase);

  await startup.required('loading the engine', () => engine);

  final (
    prefs,
    firstRunComplete,
    backupPending,
    savedSettings,
  ) = await startup.required('reading your settings', () async {
    final prefs = await preferences;
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
  // too: since #408 that is where web persistence lives. With this step
  // broken, a trade taken in Chrome is gone after a reload.
  await startup.optional('opening the local database', () async {
    await openDatabase(
      isWeb: kIsWeb,
      dataDir: appDataDirPath,
      initDb: rust_api.initDb,
    );
  });

  // Load the persisted active Mostro node into the Rust override before the
  // relay pool starts, so the first subscription targets the user's selected
  // node. No-op when none was saved (the compiled-in default then applies).
  // The resolved pubkey seeds mostroPubkeyProvider so Settings shows the real
  // active node on launch.
  //
  // This is also the first call that proves the Rust bridge is alive end to
  // end, so a failure here is reported to the web probe CI reads — see
  // lib/core/web/bridge_probe.dart (no-op off web). Success is reported only
  // at the end of startup, below.
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
    // Only when the smoke test asks (SMOKE_BOND_STORE=1), and not awaited:
    // it seeds bond rows and checks they come back through the bridge — see
    // lib/core/web/store_probe.dart. A normal launch skips it entirely.
    if (kIsWeb && storeProbeRequested()) unawaited(publishStoreProbe());
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
  // The other side of a slash: a share of a confiscated bond that is yours to
  // claim, and the payout arriving. Optional for the same reason as the line
  // above, and a claim missed here is not lost — My Trades and the trade
  // detail read claims from the core, not from this stream.
  bond_api.BondClaimStream? bondClaimStream;
  await startup.optional('subscribing to bond claim updates', () async {
    bondClaimStream = await bond_api.onBondClaimUpdated();
  });
  // Same reason for the Notifications cards (issue #474): the startup replay
  // of the node's history is what tells the user what happened while away.
  // Optional like the bond notices: these streams feed only the cards. Trade
  // screens and chat open their own subscriptions (trade_state_provider,
  // chat_providers), so without these the app works and only the cards are
  // missing for the session.
  orders_api.TradeUpdatesStream? tradeUpdateStream;
  await startup.optional('subscribing to trade updates', () async {
    tradeUpdateStream = await orders_api.onTradeUpdated();
  });
  messages_api.AnyMessageStream? chatMessageStream;
  await startup.optional('subscribing to chat messages', () async {
    chatMessageStream = await messages_api.onAnyNewMessage();
  });

  // Initialize the Nostr relay pool. `null` means the compiled-in defaults
  // (config.rs); a non-empty seed list replaces them entirely.
  // This must happen before any Nostr/order API calls.
  // Optional — measured with this step forced to fail. The app opens, and the
  // secret words can still be viewed and backed up: they come from secure
  // storage, not from relays, and that is the one thing worth keeping
  // reachable when the network cannot start.
  //
  // Nothing that needs relays works, though. Adding a relay in Settings fails,
  // because the relay API goes through a pool that never started; the order
  // book spins with no message, and My Trades shows empty although the trades
  // are stored. Those screens have no "disconnected" state yet — that is what
  // makes this degradation confusing, not the decision to open.
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
  // runApp stays outside the wrapper, still under the 'building the interface'
  // label. The guard catches only what runApp throws at once: the first frame
  // (MostroApp.build, the first provider reads, the router's initial redirect)
  // is painted later, and a failure there bypasses the guard and the ready
  // flag below alike. Tracked in its own issue.
  final container = await startup.required('building the interface', () async {
    // Logs every relay connection state change (debug builds only).
    _watchConnectionState();

    _warmNodeInfoCache();

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
    final claims = bondClaimStream;
    if (claims != null) _consumeBondClaims(claims, container);

    final eventCards = EventCards(
      notifications: () => container.read(notificationsProvider.notifier),
      // Read from disk, not the prefs provider: its first load is async, and
      // the startup replay must not slip cards past a toggle that is off.
      isEnabled: (event) => prefs.getBool(event.prefsKey) ?? true,
      identityCreatedAt: IdentityService.createdAt,
      currentLocation: _currentLocation,
    );
    final trades = tradeUpdateStream;
    if (trades != null) {
      pumpEvents('trade-cards', trades.next, eventCards.onTradeUpdate);
    }
    final chats = chatMessageStream;
    if (chats != null) {
      pumpEvents('chat-cards', chats.next, eventCards.onChatMessage);
    }

    // Resume = resync in Rust, then re-hydrate every notifier from the bridge
    // (issue #308, docs/PUSH_NOTIFICATIONS.md §10). Attached before runApp so
    // the first suspension is observed too.
    AppLifecycleService(
      onResume: ResumeResync(container: container).run,
    ).attach();
    return container;
  });

  runApp(
    UncontrolledProviderScope(container: container, child: const MostroApp()),
  );
  // Last, not at the first Rust call: the smoke test stops watching once this
  // is set, so anything that failed after it went unseen (#405 review). A
  // failure before here never reaches it and the guard reports the cause.
  markBridgeReady();
}

/// Initialize Firebase (no-op if firebase_options.dart is the placeholder).
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError catch (e) {
    debugPrint(
      '[startup] Firebase not configured: $e — push notifications disabled.',
    );
  }
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

/// Download every known node's kind 38385 settings in the background, so the
/// node selector opens on local data instead of waiting for the relays. Never
/// awaited: startup does not depend on it, and a failure only means the
/// selector fills in from its own fetch, as it did before the cache existed.
void _warmNodeInfoCache() {
  unawaited(
    node_stats_api.refreshMostroNodeInfoCache().catchError((Object e) {
      debugPrint('[main] node info warm-up failed: $e');
    }),
  );
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

/// The route on screen, or null before the router has one.
String? _currentLocation() {
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    return null;
  }
  try {
    return appRouter.routerDelegate.currentConfiguration.uri.toString();
  } catch (_) {
    return null;
  }
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
        // The core wrote `bond.state = Slashed` on the row; the cached
        // trades still carry the provisional `Released` from the
        // resolution that preceded the notice. Re-read so the durable
        // notice on the trade detail appears now, not on the next refresh.
        container.invalidate(rawTradesProvider);
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

/// Turns the core's claim phase changes into notifications
/// (docs/ANTI_ABUSE_BOND.md §8.5): a share to claim (a new claim or a
/// re-prompt), and a payout received. Runs for the process lifetime.
void _consumeBondClaims(
  bond_api.BondClaimStream stream,
  ProviderContainer container,
) {
  Future.microtask(() async {
    while (true) {
      final BondClaimUpdate update;
      try {
        update = await stream.next();
      } catch (e, st) {
        debugPrint('[bond-claim] stream closed: $e\n$st');
        break;
      }
      if (update.phase != BondClaimPhase.pending &&
          update.phase != BondClaimPhase.completed) {
        continue;
      }
      try {
        // The claim the update names, never another node's claim for the
        // same order that happens to be open.
        final claim = await bond_api.getBondClaimFrom(
          nodePubkey: update.nodePubkey,
          orderId: update.orderId,
        );
        if (claim == null) continue;
        await container
            .read(notificationsProvider.notifier)
            .addIfNew(
              NotificationModel.bondClaim(
                orderId: update.orderId,
                nodePubkey: claim.nodePubkey,
                slashedAt: platformInt64ToInt(claim.slashedAt),
                amountSats: claim.amountSats.toInt(),
                completed: update.phase == BondClaimPhase.completed,
                updatedAt: platformInt64ToInt(claim.updatedAt),
              ),
            );
      } catch (e, st) {
        debugPrint('[bond-claim] failed to record notice: $e\n$st');
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
