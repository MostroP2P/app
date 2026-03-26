/// Identity provider — real implementation (Phase 3 T031).
///
/// Wraps the Rust identity API exposed by flutter_rust_bridge.
/// Stores the session master key in platform secure storage so it survives
/// app restarts (the Rust layer never touches the keychain directly).
library identity_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../src/rust/api/identity.dart' as rust_identity;
import '../src/rust/api/nostr.dart' as rust_nostr;
import '../src/rust/api/types.dart';

// Re-export types used by screens.
export '../src/rust/api/types.dart' show IdentityInfo, NymIdentity;

const _masterKeyStorageKey = 'mostro_master_key';
const _secureStorage = FlutterSecureStorage();

class IdentityNotifier extends AsyncNotifier<IdentityInfo?> {
  @override
  Future<IdentityInfo?> build() async {
    return rust_identity.getIdentity();
  }

  /// Create a new identity.  Returns the 12-word recovery phrase — show once
  /// and discard.  Stores master key in secure storage and bootstraps nostr.
  Future<String> createIdentity() async {
    state = const AsyncValue.loading();
    try {
      final result = await rust_identity.createIdentity();
      await _secureStorage.write(
          key: _masterKeyStorageKey, value: result.masterKeyHex);
      await rust_nostr.initializeNostr(relayUrls: null);
      state = AsyncValue.data(result.info);
      return result.mnemonic;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Import from a BIP-39 mnemonic phrase.
  Future<void> importFromMnemonic(String words,
      {bool recover = false}) async {
    state = const AsyncValue.loading();
    try {
      final result = await rust_identity.importFromMnemonic(
          words: words, recover: recover);
      await _secureStorage.write(
          key: _masterKeyStorageKey, value: result.masterKeyHex);
      await rust_nostr.initializeNostr(relayUrls: null);
      state = AsyncValue.data(result.info);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Import from a bech32-encoded nsec private key.
  Future<void> importFromNsec(String nsec) async {
    state = const AsyncValue.loading();
    try {
      final result = await rust_identity.importFromNsec(nsec: nsec);
      await _secureStorage.write(
          key: _masterKeyStorageKey, value: result.masterKeyHex);
      await rust_nostr.initializeNostr(relayUrls: null);
      state = AsyncValue.data(result.info);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Verify a PIN.  Returns true when correct (or when no PIN is set).
  Future<bool> unlock(String pin) => rust_identity.unlock(pin: pin);

  /// Set or replace the device PIN.
  Future<void> setPin(String pin) => rust_identity.setPin(pin: pin);

  /// Delete all local identity data and wipe the secure storage entry.
  Future<void> deleteIdentity() async {
    state = const AsyncValue.loading();
    try {
      await rust_identity.deleteIdentity();
      await _secureStorage.delete(key: _masterKeyStorageKey);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final identityProvider =
    AsyncNotifierProvider<IdentityNotifier, IdentityInfo?>(
  IdentityNotifier.new,
);
