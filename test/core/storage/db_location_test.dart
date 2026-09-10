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
}
