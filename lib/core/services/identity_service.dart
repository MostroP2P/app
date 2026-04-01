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

    await Future.wait([
      _storage.write(key: _kMnemonic, value: words.join(' ')),
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
