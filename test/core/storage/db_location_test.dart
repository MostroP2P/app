import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/storage/db_location.dart';

void main() {
  group('databaseLocation', () {
    test(
      'names the IndexedDB database on the web without a data directory',
      () {
        expect(databaseLocation(isWeb: true), webDatabaseName);
        expect(
          databaseLocation(isWeb: true, dataDir: '/ignored'),
          webDatabaseName,
        );
      },
    );

    test('places the SQLite file inside the data directory off the web', () {
      expect(
        databaseLocation(isWeb: false, dataDir: '/data'),
        '/data/mostro.db',
      );
    });

    test('refuses a missing data directory off the web', () {
      expect(() => databaseLocation(isWeb: false), throwsArgumentError);
      expect(
        () => databaseLocation(isWeb: false, dataDir: ''),
        throwsArgumentError,
      );
    });
  });

  group('openDatabase', () {
    test('opens the store on the web, by name, without asking for a '
        'directory (#408)', () async {
      // Before #408 the web skipped this and every trade vanished on reload.
      final opened = <String>[];
      await openDatabase(
        isWeb: true,
        dataDir: () async => fail('there is no file system on the web'),
        initDb: ({required path}) async => opened.add(path),
      );
      expect(opened, [webDatabaseName], reason: 'the web store must be opened');
    });

    test(
      'opens the SQLite file inside the data directory off the web',
      () async {
        final opened = <String>[];
        await openDatabase(
          isWeb: false,
          dataDir: () async => '/data',
          initDb: ({required path}) async => opened.add(path),
        );
        expect(opened, ['/data/mostro.db']);
      },
    );
  });
}
