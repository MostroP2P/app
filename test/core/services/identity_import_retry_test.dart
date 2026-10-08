import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException, PlatformInt64, PlatformInt64Util;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/src/rust/api/identity.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:mostro/src/rust/frb_generated.dart';

const _old =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';
const _new =
    'prefer olympic float negative alarm mechanic '
    'capital because sausage struggle travel trade';

/// The identity slot as Rust keeps it: `delete_identity` fails on an empty
/// slot, and the import and the creation are refused while [refuseImports]
/// and [refuseCreates] hold, the way a pending wipe that fails again refuses
/// them (issue #555). [importError] stands in for any other refusal.
class _Api implements RustLibApi {
  bool loaded = true;
  bool refuseImports = false;
  bool refuseCreates = false;
  Object? deleteError;
  Object? importError;
  int deletes = 0;
  int imports = 0;
  List<String>? reloaded;
  int restores = 0;

  @override
  Future<void> crateApiIdentityDeleteIdentity() async {
    deletes++;
    if (deleteError case final error?) throw error;
    if (!loaded) throw AnyhowException('NoIdentity');
    loaded = false;
  }

  @override
  Future<IdentityInfo> crateApiIdentityImportFromMnemonic({
    required List<String> words,
    required bool recover,
  }) async {
    imports++;
    if (refuseImports) throw AnyhowException('PendingWipeFailed');
    if (importError case final error?) throw error;
    loaded = true;
    return IdentityInfo(
      publicKey: 'imported',
      privacyMode: false,
      tradeKeyIndex: 0,
      createdAt: PlatformInt64Util.from(0),
    );
  }

  @override
  Future<IdentityCreationResult> crateApiIdentityCreateIdentity() async {
    if (loaded) throw AnyhowException('AlreadyExists');
    if (refuseCreates) throw AnyhowException('PendingWipeFailed');
    loaded = true;
    return IdentityCreationResult(
      publicKey: 'created',
      mnemonicWords: _new.split(' '),
    );
  }

  @override
  Future<IdentityInfo> crateApiIdentityLoadIdentityFromMnemonic({
    required List<String> words,
    required int tradeKeyIndex,
    required bool privacyMode,
    PlatformInt64? createdAt,
  }) async {
    reloaded = words;
    loaded = true;
    return IdentityInfo(
      publicKey: 'reloaded',
      privacyMode: privacyMode,
      tradeKeyIndex: tradeKeyIndex,
      createdAt: PlatformInt64Util.from(0),
    );
  }

  @override
  Future<void> crateApiReputationSetPrivacyMode({
    required bool enabled,
  }) async {}

  @override
  Future<void> crateApiIdentityRestoreIdentitySession() async {
    if (!loaded) throw AnyhowException('NoIdentity');
    restores++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The bridge initializes once per isolate; each test resets the slot.
  late _Api api;
  setUpAll(() => RustLib.initMock(api: _Delegate(() => api)));
  setUp(() => api = _Api());

  // The release UI used to call the second attempt an invalid mnemonic: it
  // failed on `NoIdentity` before the import, and its pending-wipe gate, ran.
  test('an import refused for a pending wipe can be retried', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mostro_identity_mnemonic': _old,
    });
    api.refuseImports = true;

    await expectLater(
      IdentityService.importAndStore(_new.split(' ')),
      throwsA(
        isA<AnyhowException>().having(
          (e) => e.message,
          'message',
          'PendingWipeFailed',
        ),
      ),
    );
    expect(
      await IdentityService.getMnemonicWords(),
      _old.split(' '),
      reason: 'a refused import keeps the stored identity',
    );

    // The storage recovered: the retry reaches the import and lands.
    api.refuseImports = false;
    await IdentityService.importAndStore(_new.split(' '));

    expect(api.deletes, 2);
    expect(api.imports, 2);
    expect(await IdentityService.getMnemonicWords(), _new.split(' '));
  });

  // Review of #573: by the time the replacement is refused, the deletion has
  // retired the previous identity in Rust, while the screen and secure
  // storage still hold it. Left there, every action failed on `NoIdentity`
  // until a restart.
  test('a refused import loads the identity it was to replace again', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mostro_identity_mnemonic': _old,
    });
    api.refuseImports = true;

    await expectLater(
      IdentityService.importAndStore(_new.split(' ')),
      throwsA(isA<AnyhowException>()),
    );

    expect(api.loaded, isTrue, reason: 'the session is never left without one');
    expect(api.reloaded, _old.split(' '));
    expect(api.restores, 1, reason: 'Rust rebuilds what the deletion gave up');
  });

  test(
    'a refused generation loads the identity it was to replace again',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'mostro_identity_mnemonic': _old,
      });
      api.refuseCreates = true;

      await expectLater(
        IdentityService.regenerate(),
        throwsA(isA<AnyhowException>()),
      );

      expect(api.loaded, isTrue);
      expect(api.reloaded, _old.split(' '));
      expect(
        api.restores,
        1,
        reason: 'Rust rebuilds what the deletion gave up',
      );
      expect(await IdentityService.getMnemonicWords(), _old.split(' '));
    },
  );

  // Not only a pending wipe: any refusal after the deletion has the same
  // effect on the session.
  test('words the core rejects leave the previous identity loaded', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mostro_identity_mnemonic': _old,
    });
    api.importError = AnyhowException('invalid mnemonic');

    await expectLater(
      IdentityService.importAndStore(_new.split(' ')),
      throwsA(isA<AnyhowException>()),
    );

    expect(api.loaded, isTrue);
    expect(api.reloaded, _old.split(' '));
    expect(api.restores, 1, reason: 'Rust rebuilds what the deletion gave up');
  });

  test('a deletion that fails is not followed by a reload', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mostro_identity_mnemonic': _old,
    });
    api.deleteError = AnyhowException('WipeNotRecorded');

    await expectLater(
      IdentityService.importAndStore(_new.split(' ')),
      throwsA(isA<AnyhowException>()),
    );

    expect(api.reloaded, isNull, reason: 'the identity was never given up');
    expect(api.restores, 0);
    expect(api.imports, 0);
  });

  test('any other deletion failure still stops the import', () async {
    FlutterSecureStorage.setMockInitialValues({});
    api.deleteError = StateError('bridge down');

    await expectLater(
      IdentityService.importAndStore(_new.split(' ')),
      throwsA(isA<StateError>()),
    );
    expect(api.imports, 0);
  });
}

/// Forwards to the current test's [_Api].
class _Delegate implements RustLibApi {
  _Delegate(this._api);

  final _Api Function() _api;

  @override
  Future<void> crateApiIdentityDeleteIdentity() =>
      _api().crateApiIdentityDeleteIdentity();

  @override
  Future<IdentityInfo> crateApiIdentityImportFromMnemonic({
    required List<String> words,
    required bool recover,
  }) =>
      _api().crateApiIdentityImportFromMnemonic(words: words, recover: recover);

  @override
  Future<IdentityCreationResult> crateApiIdentityCreateIdentity() =>
      _api().crateApiIdentityCreateIdentity();

  @override
  Future<IdentityInfo> crateApiIdentityLoadIdentityFromMnemonic({
    required List<String> words,
    required int tradeKeyIndex,
    required bool privacyMode,
    PlatformInt64? createdAt,
  }) => _api().crateApiIdentityLoadIdentityFromMnemonic(
    words: words,
    tradeKeyIndex: tradeKeyIndex,
    privacyMode: privacyMode,
    createdAt: createdAt,
  );

  @override
  Future<void> crateApiReputationSetPrivacyMode({required bool enabled}) =>
      _api().crateApiReputationSetPrivacyMode(enabled: enabled);

  @override
  Future<void> crateApiIdentityRestoreIdentitySession() =>
      _api().crateApiIdentityRestoreIdentitySession();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
