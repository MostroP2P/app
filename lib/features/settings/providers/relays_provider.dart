import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/settings/providers/relay_auto_sync_provider.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/types.dart'
    show RelayInfo, RelaySource, RelayStatus;

/// The one spelling of a relay URL the app compares and keys rows by.
///
/// `AutomationIds.settingsRelayItem` normalizes the same way, so a relay is
/// one row with one identifier however its URL was typed.
String canonicalRelayUrl(String url) =>
    url.trim().replaceAll(RegExp(r'/+$'), '');

/// Pulls the next relay status change, or null once the stream closes.
typedef RelayStatusReader = Future<RelayInfo?> Function();

// ── Bridge seams ──────────────────────────────────────────────────────────────

/// The bridge calls behind function seams, so the controller below can be
/// driven in tests without a live Rust core.
final relayListLoaderProvider = Provider<Future<List<RelayInfo>> Function()>(
  (ref) => nostr_api.getRelays,
);

final relayStatusStreamProvider =
    Provider<Future<RelayStatusReader> Function()>(
      (ref) => () async => (await nostr_api.onRelayStatusChanged()).next,
    );

final relayMutatorProvider = Provider<RelayMutator>(
  (ref) => const RelayMutator(),
);

/// Adding and removing a relay, behind a seam for the same reason.
class RelayMutator {
  const RelayMutator();

  Future<void> add(String url) => nostr_api.addRelay(url: url).then((_) {});

  Future<void> remove(String url) => nostr_api.removeRelay(url: url);
}

// ── Controller ────────────────────────────────────────────────────────────────

/// The relay list, live: the persisted set followed by every status change the
/// connection manager publishes and every relay the active node announces.
///
/// **One subscription for the whole process, deliberately** — the same reason
/// [relayAutoSyncProvider] documents: the Rust broadcast sender is
/// process-global and never closes, so a pending `next()` cannot be cancelled
/// from Dart. This provider is therefore not auto-disposed and is never
/// invalidated; screens read it and call its methods instead.
final relaysProvider = StateNotifierProvider<RelaysNotifier, List<RelayInfo>>((
  ref,
) {
  final notifier = RelaysNotifier(
    load: ref.read(relayListLoaderProvider),
    watch: ref.read(relayStatusStreamProvider),
    mutator: ref.read(relayMutatorProvider),
  );
  // An auto-synced relay arrives as a URL only, so the list is re-read. The
  // first emission is empty and lands before any snapshot, which is what
  // seeds the list with the receiver already installed.
  ref.listen<AsyncValue<List<String>>>(
    relayAutoSyncProvider,
    (_, next) => next.whenData((added) {
      if (added.isNotEmpty) {
        debugPrint('[relays] auto-synced: $added');
      }
      notifier.reload();
    }),
    onError: (e, _) => debugPrint('[relays] auto-sync watch failed: $e'),
    fireImmediately: true,
  );
  return notifier;
});

class RelaysNotifier extends StateNotifier<List<RelayInfo>> {
  RelaysNotifier({
    required Future<List<RelayInfo>> Function() load,
    required Future<RelayStatusReader> Function() watch,
    required RelayMutator mutator,
  }) : _load = load,
       _mutator = mutator,
       // Seeded with the defaults of `rust/src/config.rs` so the screen has
       // rows to draw before the first read returns.
       super(
         defaultMostroRelays
             .map(
               (url) => RelayInfo(
                 url: url,
                 isActive: true,
                 isDefault: true,
                 source: RelaySource.default_,
                 isBlacklisted: false,
                 status: RelayStatus.connecting,
               ),
             )
             .toList(growable: false),
       ) {
    _follow(watch);
  }

  final Future<List<RelayInfo>> Function() _load;
  final RelayMutator _mutator;

  /// Serialises reloads and keeps the one requested while another is in
  /// flight — that load may have read its snapshot before the new relay
  /// existed, so dropping the request would hide it until a screen re-entry.
  Future<void>? _inFlight;
  bool _queued = false;

  Future<void> _follow(Future<RelayStatusReader> Function() watch) async {
    final RelayStatusReader next;
    try {
      next = await watch();
    } catch (e) {
      debugPrint('[relays] status stream unavailable: $e');
      return;
    }
    await reload();
    while (mounted) {
      final info = await next();
      if (info == null || !mounted) break;
      _apply(info);
    }
  }

  /// Folds one status change in without reordering: a row that moved under
  /// the finger makes the user toggle the wrong relay.
  void _apply(RelayInfo info) {
    final key = canonicalRelayUrl(info.url);
    final index = state.indexWhere((r) => canonicalRelayUrl(r.url) == key);
    if (index < 0) {
      state = [...state, info];
      return;
    }
    state = [...state.sublist(0, index), info, ...state.sublist(index + 1)];
  }

  Future<void> reload() {
    if (_inFlight != null) {
      _queued = true;
      return _inFlight!;
    }
    return _inFlight = _read().whenComplete(() {
      _inFlight = null;
      if (_queued) {
        _queued = false;
        reload();
      }
    });
  }

  Future<void> _read() async {
    try {
      final relays = await _load();
      if (!mounted) return;
      state = List.unmodifiable(relays);
    } catch (e) {
      debugPrint('[relays] load failed: $e');
    }
  }

  /// Enables or disables a relay optimistically. Returns false when the
  /// bridge rejected it and the row was rolled back, so the caller can tell
  /// the user.
  Future<bool> setActive(String url, bool active) async {
    final key = canonicalRelayUrl(url);
    final before = state;
    state = [
      for (final r in state)
        if (canonicalRelayUrl(r.url) == key) _withActive(r, active) else r,
    ];
    try {
      active ? await _mutator.add(url) : await _mutator.remove(url);
      return true;
    } catch (e) {
      debugPrint('[relays] setActive($active) failed: $e');
      if (mounted) state = before;
      return false;
    }
  }

  /// Adds a relay the user typed. Returns false when the bridge rejected it.
  Future<bool> add(String url) async {
    final canonical = canonicalRelayUrl(url);
    state = [
      ...state,
      RelayInfo(
        url: canonical,
        isActive: true,
        isDefault: false,
        source: RelaySource.userAdded,
        isBlacklisted: false,
        status: RelayStatus.connecting,
      ),
    ];
    try {
      await _mutator.add(canonical);
      return true;
    } catch (e) {
      debugPrint('[relays] add failed: $e');
      if (mounted) {
        state = [
          for (final r in state)
            if (canonicalRelayUrl(r.url) != canonical) r,
        ];
      }
      return false;
    }
  }

  /// Removes a relay. A `MostroDiscovered` one is blacklisted by the Rust
  /// core so the node's list does not bring it back.
  Future<bool> remove(String url) async {
    final key = canonicalRelayUrl(url);
    final before = state;
    state = [
      for (final r in state)
        if (canonicalRelayUrl(r.url) != key) r,
    ];
    try {
      await _mutator.remove(url);
      return true;
    } catch (e) {
      debugPrint('[relays] remove failed: $e');
      if (mounted) state = before;
      return false;
    }
  }

  static RelayInfo _withActive(RelayInfo r, bool active) => RelayInfo(
    url: r.url,
    isActive: active,
    isDefault: r.isDefault,
    source: r.source,
    isBlacklisted: r.isBlacklisted,
    // A relay the user just switched off reports no connection; one just
    // switched on has not established one yet.
    status: active ? RelayStatus.connecting : RelayStatus.disconnected,
    lastConnectedAt: r.lastConnectedAt,
    lastError: r.lastError,
  );
}
