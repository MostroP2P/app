import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/identity.dart' as identity_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/reputation.dart' as reputation_api;

/// Secure-storage keys.
const _kMnemonic = 'mostro_identity_mnemonic';
const _kTradeKeyIndex = 'mostro_trade_key_index';
const _kPrivacyMode = 'mostro_privacy_mode';
const _kCreatedAt = 'mostro_identity_created_at';

/// What secure storage holds about the identity, read in one go.
class StoredIdentity {
  const StoredIdentity({
    required this.words,
    required this.tradeKeyIndex,
    required this.privacyMode,
    required this.createdAtMillis,
  });

  final List<String> words;
  final int tradeKeyIndex;
  final bool privacyMode;

  /// Zero when the install predates the key.
  final int createdAtMillis;

  /// `null` when no mnemonic was ever stored — a first launch. The other keys
  /// fall back to what an install without them had.
  static StoredIdentity? fromEntries(Map<String, String> entries) {
    final mnemonic = entries[_kMnemonic]?.trim() ?? '';
    if (mnemonic.isEmpty) return null;
    return StoredIdentity(
      words: mnemonic.split(' '),
      tradeKeyIndex: int.tryParse(entries[_kTradeKeyIndex] ?? '') ?? 0,
      privacyMode: entries[_kPrivacyMode] == 'true',
      createdAtMillis: int.tryParse(entries[_kCreatedAt] ?? '') ?? 0,
    );
  }
}

/// Manages identity lifecycle: creation on first launch and reload on
/// subsequent launches. Mnemonic persists in [FlutterSecureStorage]
/// (iOS Keychain / Android Keystore). Rust holds keys only in memory.
/// What the daemon-side recovery after a seed import came to.
@immutable
class RecoveryOutcome {
  const RecoveryOutcome.recovered(int this.count) : _kind = 0;
  const RecoveryOutcome.skipped() : count = null, _kind = 1;
  const RecoveryOutcome.failed() : count = null, _kind = 2;

  /// Orders and disputes the daemon returned; null unless [isRecovered].
  final int? count;
  final int _kind;

  bool get isRecovered => _kind == 0;
  bool get isSkipped => _kind == 1;
  bool get isFailed => _kind == 2;

  @override
  bool operator ==(Object other) =>
      other is RecoveryOutcome && other._kind == _kind && other.count == count;

  @override
  int get hashCode => Object.hash(_kind, count);

  @override
  String toString() => 'RecoveryOutcome($_kind, $count)';
}

class IdentityService {
  IdentityService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Initialize the identity on app startup.
  ///
  /// - First launch (no stored mnemonic): calls [identity_api.createIdentity],
  ///   stores the 12 words in secure storage, and returns the words.
  /// - Subsequent launches: reads the mnemonic from secure storage and
  ///   calls [identity_api.loadIdentityFromMnemonic] to restore in-memory keys.
  ///
  /// Returns the mnemonic words so callers can react if needed (e.g. first-run
  /// flows that want to prime the backup reminder immediately).
  static Future<List<String>> initialize() async {
    // One read, not one per key: each is a platform round trip (on Linux it
    // parses the whole keyring file), this runs before the first frame, and
    // four in a row were a quarter of the way there.
    final stored = StoredIdentity.fromEntries(await _storage.readAll());
    return stored == null ? _createAndStore() : _loadExisting(stored);
  }

  /// Read the stored mnemonic words. Returns an empty list if none is found
  /// (should not happen after [initialize] has run).
  static Future<List<String>> getMnemonicWords() async {
    try {
      final stored = await _storage.read(key: _kMnemonic);
      if (stored == null || stored.trim().isEmpty) return [];
      return stored.trim().split(' ');
    } catch (e) {
      debugPrint('[identity] getMnemonicWords($_kMnemonic) error: $e');
      return [];
    }
  }

  /// When the current identity was created or imported, or null when unknown
  /// (an install older than the timestamp, or unreadable storage).
  ///
  /// Read fresh on every call: an import rewrites it mid-session, and the
  /// history replay that follows must read as the past (issue #474).
  static Future<DateTime?> createdAt() async {
    try {
      final millis = int.tryParse(await _storage.read(key: _kCreatedAt) ?? '');
      if (millis == null || millis <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (e) {
      debugPrint('[identity] createdAt($_kCreatedAt) error: $e');
      return null;
    }
  }

  /// Decide what to write to secure storage for an [incoming] consumed trade
  /// key index, given the [current] stored raw value. Returns null when the
  /// write should be skipped.
  ///
  /// The counter must never move backwards — a lower value means re-deriving
  /// keys the daemon already registered, which it rejects with
  /// `InvalidTradeIndex`. An unparsable or missing stored value is treated as
  /// "nothing known", so [incoming] wins.
  static int? nextStoredTradeKeyIndex(String? current, int incoming) {
    final stored = int.tryParse(current ?? '');
    if (stored != null && stored >= incoming) return null;
    return incoming;
  }

  /// Mirror a consumed trade key index into secure storage.
  ///
  /// Rust owns the counter and persists it in `mostro.db`; this is the second
  /// durable copy, and the only one that survives loss of that file. On the
  /// next launch [_loadExisting] passes it back and Rust reconciles the two by
  /// taking the higher (issue #249).
  ///
  /// Never throws: failing to mirror must not break an order that has already
  /// been created, and the database copy still holds.
  static Future<void> saveTradeKeyIndex(int index) async {
    try {
      final current = await _storage.read(key: _kTradeKeyIndex);
      final next = nextStoredTradeKeyIndex(current, index);
      if (next == null) return;
      await _storage.write(key: _kTradeKeyIndex, value: next.toString());
    } catch (e) {
      debugPrint('[identity] saveTradeKeyIndex($index) error: $e');
    }
  }

  /// Persist privacy mode setting.
  static Future<void> savePrivacyMode(bool enabled) async {
    try {
      await _storage.write(key: _kPrivacyMode, value: enabled.toString());
    } catch (e) {
      debugPrint('[identity] savePrivacyMode($_kPrivacyMode) error: $e');
      rethrow;
    }
  }

  /// Import an identity from a BIP-39 mnemonic phrase and persist it.
  ///
  /// Replaces any currently loaded identity. Throws if [words] is not a valid
  /// 12- or 24-word BIP-39 phrase.
  static Future<void> importAndStore(List<String> words) async {
    await _replaceLoadedIdentity(
      () => identity_api.importFromMnemonic(words: words, recover: false),
    );

    await _storage.write(key: _kMnemonic, value: words.join(' '));
    await Future.wait([
      _storage.write(key: _kTradeKeyIndex, value: '0'),
      _storage.write(key: _kPrivacyMode, value: 'false'),
      _storage.write(
        key: _kCreatedAt,
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      ),
    ]);

    debugPrint('[identity] identity imported — ${words.length} words');
  }

  /// Ask the daemon for this identity's trades after [importAndStore].
  ///
  /// A seed that already traded left the daemon's trade index ahead of the
  /// fresh local counter, and the first order would be refused with
  /// `InvalidTradeIndex`; the Rust restore also resyncs that counter
  /// (`recover_trades`). Privacy mode has no account to recover, so it is
  /// skipped. A failure is reported, never thrown: the import itself stands,
  /// and a later order still resyncs the counter on its own.
  static Future<RecoveryOutcome> recoverAfterImport({
    Future<bool> Function() isPrivacyMode = reputation_api.getPrivacyMode,
    Future<int> Function() recover = orders_api.recoverTrades,
  }) async {
    try {
      if (await isPrivacyMode()) return const RecoveryOutcome.skipped();
      return RecoveryOutcome.recovered(await recover());
    } catch (e) {
      debugPrint('[identity] recoverAfterImport error: $e');
      return const RecoveryOutcome.failed();
    }
  }

  /// Generate a new identity and atomically replace the stored one.
  ///
  /// The new mnemonic is written to secure storage **before** the old metadata
  /// is cleared, so the user is never left without a valid identity if the
  /// operation is interrupted. Use this instead of [deleteAll] + [initialize]
  /// when rotating identities.
  static Future<List<String>> regenerate() async {
    // Clear Rust's in-memory identity state first — createIdentity() returns
    // AlreadyExists if any identity is currently loaded.
    final result = await _replaceLoadedIdentity(identity_api.createIdentity);
    final words = result.mnemonicWords;

    // Write new mnemonic first — this is the critical write.
    await _storage.write(key: _kMnemonic, value: words.join(' '));

    // Reset metadata in parallel now that the new mnemonic is safe.
    await Future.wait([
      _storage.write(key: _kTradeKeyIndex, value: '0'),
      _storage.write(key: _kPrivacyMode, value: 'false'),
      _storage.write(
        key: _kCreatedAt,
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      ),
    ]);

    debugPrint('[identity] identity regenerated — pubkey=${result.publicKey}');
    return words;
  }

  /// Wipe all stored identity data. Called when generating a new user.
  static Future<void> deleteAll() async {
    await Future.wait([
      _deleteKey(_kMnemonic),
      _deleteKey(_kTradeKeyIndex),
      _deleteKey(_kPrivacyMode),
      _deleteKey(_kCreatedAt),
    ]);
  }

  static Future<void> _deleteKey(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('[identity] deleteAll($key) error: $e');
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  /// Delete the identity Rust holds, then [install] the one replacing it.
  ///
  /// Once the deletion has gone through, Rust no longer serves the previous
  /// identity — its subscriptions, push registrations and in-memory stores
  /// are given back — while the screen and secure storage still hold it. So
  /// when [install] is refused after that (`PendingWipeFailed`, issue #555,
  /// or words the core rejects), that identity is loaded again before the
  /// error goes on, and the session is never left without one (review of
  /// #573). A deletion that is itself refused (`WipeNotRecorded`) gave
  /// nothing up, and nothing is reloaded.
  static Future<T> _replaceLoadedIdentity<T>(
    Future<T> Function() install,
  ) async {
    final retired = await _deleteLoadedIdentity();
    try {
      return await install();
    } catch (_) {
      if (retired) await _reloadRetiredIdentity();
      rethrow;
    }
  }

  /// Load the identity secure storage still holds into the core again, and
  /// have Rust rebuild what its deletion gave up. Never throws: the caller
  /// reports the refusal that brought it here, and a reload that fails too
  /// leaves the next launch to load it.
  static Future<void> _reloadRetiredIdentity() async {
    try {
      final stored = StoredIdentity.fromEntries(await _storage.readAll());
      if (stored == null) return;
      await _loadExisting(stored);
      await identity_api.restoreIdentitySession();
      debugPrint('[identity] replacement refused — previous identity reloaded');
    } catch (e) {
      debugPrint('[identity] previous identity not reloaded: $e');
    }
  }

  /// Delete the identity Rust holds, if it holds one, and say whether it did.
  /// An empty slot is not an error for a replacement: a fresh install
  /// followed at once by a regeneration has none.
  static Future<bool> _deleteLoadedIdentity() async {
    try {
      await identity_api.deleteIdentity();
      return true;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!msg.contains('noidentity') &&
          !msg.contains('no identity') &&
          !msg.contains('not loaded')) {
        rethrow;
      }
      debugPrint('[identity] no identity loaded, nothing to delete');
      return false;
    }
  }

  static Future<List<String>> _createAndStore() async {
    final result = await identity_api.createIdentity();
    final words = result.mnemonicWords;

    // Write mnemonic first and await completion — this is the critical write.
    // If it fails, the exception propagates to the caller; no metadata is written.
    await _storage.write(key: _kMnemonic, value: words.join(' '));

    // Metadata writes are secondary — proceed in parallel after mnemonic is safe.
    await Future.wait([
      _storage.write(key: _kTradeKeyIndex, value: '0'),
      _storage.write(key: _kPrivacyMode, value: 'false'),
      _storage.write(
        key: _kCreatedAt,
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      ),
    ]);

    debugPrint('[identity] new identity created — pubkey=${result.publicKey}');
    return words;
  }

  static Future<List<String>> _loadExisting(StoredIdentity stored) =>
      loadExisting(stored);

  /// Loads [stored] into the Rust core, then hands it the saved privacy
  /// mode: the core's flag lives in memory and starts off at every launch,
  /// and left there the next trade would be signed with the identity key.
  @visibleForTesting
  static Future<List<String>> loadExisting(
    StoredIdentity stored, {
    Future<void> Function(StoredIdentity stored)? load,
    Future<void> Function(bool enabled)? applyPrivacyMode,
  }) async {
    await (load ?? _loadIntoCore)(stored);
    await (applyPrivacyMode ?? _applyPrivacyMode)(stored.privacyMode);
    return stored.words;
  }

  static Future<void> _applyPrivacyMode(bool enabled) =>
      reputation_api.setPrivacyMode(enabled: enabled);

  static Future<void> _loadIntoCore(StoredIdentity stored) async {
    final createdAt = stored.createdAtMillis;
    final info = await identity_api.loadIdentityFromMnemonic(
      words: stored.words,
      tradeKeyIndex: stored.tradeKeyIndex,
      privacyMode: stored.privacyMode,
      createdAt: createdAt > 0 ? intToPlatformInt64(createdAt ~/ 1000) : null,
    );

    debugPrint('[identity] identity loaded — pubkey=${info.publicKey}');
  }
}
