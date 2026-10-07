import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uriA =
    'nostr+walletconnect://b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay.example&secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c';
const _uriB =
    'nostr+walletconnect://c889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay.example&secret=81a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c';

/// A keyring that refuses everything: a declined unlock prompt on Linux, an
/// unsigned macOS build.
class _RefusingStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.error(Exception('keyring locked'));

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.error(Exception('keyring locked'));

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.error(Exception('keyring locked'));
}

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'the URI is saved, but never in SharedPreferences in plain text',
    () async {
      final prefs = await _prefs();
      final notifier = NwcNotifier(store: NwcUriStore(prefs: prefs));

      await notifier.setConnected(
        NwcWalletState(walletPubkey: 'pk', relayUrls: const []),
        nwcUri: _uriA,
      );

      expect(
        prefs.getString(kNwcUriKey),
        isNull,
        reason: 'the connection secret must not sit in plain text',
      );
      expect(
        await NwcUriStore(prefs: prefs).load(),
        _uriA,
        reason: 'and it still survives a restart',
      );
    },
  );

  test('a URI left in SharedPreferences moves to secure storage', () async {
    final prefs = await _prefs({kNwcUriKey: _uriA});
    final store = NwcUriStore(prefs: prefs);

    expect(await store.load(), _uriA);
    expect(prefs.getString(kNwcUriKey), isNull, reason: 'plain copy gone');
    expect(await store.load(), _uriA, reason: 'read back from secure');
  });

  test('connecting saves the URI, disconnecting forgets it', () async {
    final prefs = await _prefs();
    final store = NwcUriStore(prefs: prefs);
    final notifier = NwcNotifier(store: store);

    expect(
      await notifier.setConnected(
        NwcWalletState(walletPubkey: 'pk', relayUrls: const []),
        nwcUri: _uriA,
      ),
      isTrue,
    );
    expect(await store.load(), _uriA);
    expect(prefs.getString(kNwcUriKey), isNull, reason: 'never in prefs');

    expect(await notifier.setDisconnected(), isTrue);
    expect(await store.load(), isNull);
  });

  group('with a keyring that refuses', () {
    test('a failed move keeps the wallet for this start', () async {
      final prefs = await _prefs({kNwcUriKey: _uriA});
      final store = NwcUriStore(prefs: prefs, storage: _RefusingStorage());

      expect(await store.load(), _uriA);
    });

    test(
      'disconnecting still erases the plain copy, and says it failed',
      () async {
        final prefs = await _prefs({kNwcUriKey: _uriA});
        final store = NwcUriStore(prefs: prefs, storage: _RefusingStorage());
        final notifier = NwcNotifier(store: store);
        await store.load();

        expect(await notifier.setDisconnected(), isFalse);
        expect(
          prefs.getString(kNwcUriKey),
          isNull,
          reason: 'the disconnected wallet must not come back',
        );
      },
    );

    test('connecting another wallet drops the old plain copy, and says '
        'the new one was not saved', () async {
      final prefs = await _prefs({kNwcUriKey: _uriA});
      final store = NwcUriStore(prefs: prefs, storage: _RefusingStorage());
      final notifier = NwcNotifier(store: store);
      await store.load();

      final saved = await notifier.setConnected(
        NwcWalletState(walletPubkey: 'pk', relayUrls: const []),
        nwcUri: _uriB,
      );
      expect(saved, isFalse);
      expect(
        prefs.getString(kNwcUriKey),
        isNull,
        reason: 'wallet A must not override B on the next start',
      );
    });
  });
}
