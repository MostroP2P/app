import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Sentinel for copyWith nullable fields.
const _unset = Object();

/// SharedPreferences key under which earlier versions kept the NWC URI, in
/// plain text. Read once, to move it into [NwcUriStore], then removed.
const kNwcUriKey = 'settings.nwcUri';

/// Where the NWC URI is kept. It carries the connection secret — enough to
/// spend from the wallet up to its budget — so it sits in secure storage next
/// to the mnemonic (Keychain / Keystore), not in SharedPreferences. On web
/// that is the same browser storage the mnemonic has: no weaker than it, and
/// no stronger.
class NwcUriStore {
  NwcUriStore({
    required SharedPreferences prefs,
    FlutterSecureStorage storage = _secure,
  }) : _prefs = prefs,
       _storage = storage;

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'nwc.uri';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _storage;

  /// Saves [uri]. The plain copy an earlier version may have left goes in
  /// every case, even when the secure write throws: otherwise that older URI
  /// would come back on the next start in place of this one.
  Future<void> write(String uri) async {
    try {
      await _storage.write(key: _key, value: uri);
    } finally {
      await _prefs.remove(kNwcUriKey);
    }
  }

  /// Forgets the URI — the plain copy first, which cannot fail, so a
  /// keyring that refuses the delete still leaves nothing in plain text.
  Future<void> delete() async {
    await _prefs.remove(kNwcUriKey);
    await _storage.delete(key: _key);
  }

  /// The saved URI, moving one left in SharedPreferences by an earlier
  /// version into secure storage first. When that move fails the plain copy
  /// stays, so the wallet is not lost; the next connect or disconnect clears
  /// it either way.
  Future<String?> load() async {
    final legacy = _prefs.getString(kNwcUriKey);
    if (legacy == null) return _storage.read(key: _key);
    try {
      await _storage.write(key: _key, value: legacy);
      await _prefs.remove(kNwcUriKey);
    } catch (e) {
      debugPrint('[nwc] moving the URI to secure storage failed: $e');
    }
    return legacy;
  }
}

/// Wallet connection state held in memory.
///
/// `null`  → no wallet connected.
/// non-null → wallet connected; contains pubkey + relay URLs + optional balance.
class NwcWalletState {
  NwcWalletState({
    required this.walletPubkey,
    required List<String> relayUrls,
    this.walletName,
    this.balanceSats,
  }) : relayUrls = List.unmodifiable(relayUrls);

  final String walletPubkey;

  /// Immutable list of NWC relay URLs.
  final List<String> relayUrls;
  final String? walletName;
  final int? balanceSats;

  NwcWalletState copyWith({
    String? walletPubkey,
    List<String>? relayUrls,
    String? walletName,
    Object? balanceSats = _unset,
  }) => NwcWalletState(
    walletPubkey: walletPubkey ?? this.walletPubkey,
    relayUrls: relayUrls ?? this.relayUrls,
    walletName: walletName ?? this.walletName,
    balanceSats:
        identical(balanceSats, _unset) ? this.balanceSats : balanceSats as int?,
  );
}

// ── Notifier ───────────────────────────────────────────────────────────────────

class NwcNotifier extends StateNotifier<NwcWalletState?> {
  NwcNotifier({NwcUriStore? store}) : _store = store, super(null);

  final NwcUriStore? _store;

  /// Store wallet state after a successful `connect_wallet` call and, when
  /// [nwcUri] is given, save it so it survives a restart. Returns false when
  /// that save failed: the wallet is connected for this session only.
  Future<bool> setConnected(NwcWalletState wallet, {String? nwcUri}) async {
    state = wallet;
    if (nwcUri == null || _store == null) return true;
    try {
      await _store.write(nwcUri);
      return true;
    } catch (e) {
      debugPrint('[nwc] saving the URI failed: $e');
      return false;
    }
  }

  /// Clear wallet state after `disconnect_wallet` and forget the saved URI.
  /// Returns false when the device could not erase it: the wallet would
  /// reconnect on the next start, so the user must hear about it.
  Future<bool> setDisconnected() async {
    state = null;
    if (_store == null) return true;
    try {
      await _store.delete();
      return true;
    } catch (e) {
      debugPrint('[nwc] forgetting the URI failed: $e');
      return false;
    }
  }

  /// Update balance from a `get_balance` result.
  void updateBalance(int? sats) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(balanceSats: sats);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Wallet connection state. `null` when no wallet is connected.
/// Override in `main()` via [ProviderScope] to inject an [NwcUriStore].
final nwcProvider = StateNotifierProvider<NwcNotifier, NwcWalletState?>(
  (ref) => NwcNotifier(),
);

/// Convenience: `true` when a wallet is connected.
final isWalletConnectedProvider = Provider<bool>(
  (ref) => ref.watch(nwcProvider) != null,
);
