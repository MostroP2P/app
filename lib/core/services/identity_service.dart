import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:mostro/src/rust/api/identity.dart' as identity_api;

/// Secure-storage keys.
const _kMnemonic = 'mostro_identity_mnemonic';
const _kTradeKeyIndex = 'mostro_trade_key_index';
const _kPrivacyMode = 'mostro_privacy_mode';
const _kCreatedAt = 'mostro_identity_created_at';

/// Manages identity lifecycle: creation on first launch and reload on
/// subsequent launches. Mnemonic persists in [FlutterSecureStorage]
/// (iOS Keychain / Android Keystore). Rust holds keys only in memory.
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
    final storedMnemonic = await _storage.read(key: _kMnemonic);

    if (storedMnemonic == null || storedMnemonic.trim().isEmpty) {
      return _createAndStore();
    } else {
      return _loadExisting(storedMnemonic);
    }
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

  /// Persist an updated trade-key index after each new trade key is derived.
  static Future<void> saveTradeKeyIndex(int index) async {
    try {
      await _storage.write(key: _kTradeKeyIndex, value: index.toString());
    } catch (e) {
      debugPrint('[identity] saveTradeKeyIndex($_kTradeKeyIndex) error: $e');
      rethrow;
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
    await identity_api.deleteIdentity();
    await identity_api.importFromMnemonic(words: words, recover: false);

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

  /// Generate a new identity and atomically replace the stored one.
  ///
  /// The new mnemonic is written to secure storage **before** the old metadata
  /// is cleared, so the user is never left without a valid identity if the
  /// operation is interrupted. Use this instead of [deleteAll] + [initialize]
  /// when rotating identities.
  static Future<List<String>> regenerate() async {
    // Clear Rust's in-memory identity state first — createIdentity() returns
    // AlreadyExists if any identity is currently loaded.
    // deleteIdentity() may throw if no identity is loaded (e.g. fresh install
    // followed immediately by regenerate); ignore that case and proceed.
    try {
      await identity_api.deleteIdentity();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!msg.contains('noidentity') && !msg.contains('no identity') && !msg.contains('not loaded')) {
        rethrow;
      }
      debugPrint('[identity] regenerate: no identity loaded, skipping deleteIdentity');
    }
    final result = await identity_api.createIdentity();
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

  static Future<List<String>> _loadExisting(String storedMnemonic) async {
    final words = storedMnemonic.trim().split(' ');

    final indexStr = await _storage.read(key: _kTradeKeyIndex);
    final privacyStr = await _storage.read(key: _kPrivacyMode);
    final createdAtStr = await _storage.read(key: _kCreatedAt);

    final tradeKeyIndex = int.tryParse(indexStr ?? '0') ?? 0;
    final privacyMode = privacyStr == 'true';
    final createdAt = int.tryParse(createdAtStr ?? '0') ?? 0;

    final info = await identity_api.loadIdentityFromMnemonic(
      words: words,
      tradeKeyIndex: tradeKeyIndex,
      privacyMode: privacyMode,
      createdAt: createdAt > 0 ? createdAt ~/ 1000 : null,
    );

    debugPrint('[identity] identity loaded — pubkey=${info.publicKey}');
    return words;
  }
}
