import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/storage/app_data_dir.dart';
import 'package:path/path.dart' as p;

void main() {
  group('appDataDirPath', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('mostro_data_dir_test_');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('creates the resolved directory and returns it', () async {
      // Arrange — a data root that exists but has no 'mostro' subdirectory yet.
      final env = {'XDG_DATA_HOME': tmp.path, 'HOME': tmp.path};

      // Act
      final path = await appDataDirPath(
        env: env,
        isLinux: true,
        documentsDirPath: () async => fail('must not fall back'),
      );

      // Assert — created, and inside the data root rather than Documents.
      expect(path, p.posix.join(tmp.path, 'mostro'));
      expect(Directory(path).existsSync(), isTrue);
    });

    test('falls back to the documents directory when creation fails', () async {
      // Arrange — XDG_DATA_HOME points at a *file*, so creating a directory
      // under it fails the way an unwritable data root would.
      final blocker = File(p.join(tmp.path, 'not-a-dir'))..writeAsStringSync('');
      final env = {'XDG_DATA_HOME': blocker.path, 'HOME': blocker.path};

      // Act
      final path = await appDataDirPath(
        env: env,
        isLinux: true,
        documentsDirPath: () async => '/fallback/documents',
      );

      // Assert — startup survives on the fallback instead of throwing.
      expect(path, '/fallback/documents');
    });

    test('uses the documents directory on platforms other than Linux', () async {
      final path = await appDataDirPath(
        env: {'XDG_DATA_HOME': tmp.path},
        isLinux: false,
        documentsDirPath: () async => '/fallback/documents',
      );

      expect(path, '/fallback/documents');
    });

    test('falls back when the environment resolves to no path at all', () async {
      final path = await appDataDirPath(
        env: const {},
        isLinux: true,
        documentsDirPath: () async => '/fallback/documents',
      );

      expect(path, '/fallback/documents');
    });
  });

  group('resolveLinuxDataDir', () {
    test('uses XDG_DATA_HOME when it is set to an absolute path', () {
      // Arrange
      final env = {'XDG_DATA_HOME': '/home/u/.local/share', 'HOME': '/home/u'};

      // Act
      final dir = resolveLinuxDataDir(env);

      // Assert
      expect(dir, '/home/u/.local/share/mostro');
    });

    test('honours an XDG_DATA_HOME pointing outside ~/.local/share', () {
      final dir =
          resolveLinuxDataDir({'XDG_DATA_HOME': '/data/xdg', 'HOME': '/home/u'});

      expect(dir, '/data/xdg/mostro');
    });

    test('falls back to \$HOME/.local/share when XDG_DATA_HOME is unset', () {
      final dir = resolveLinuxDataDir({'HOME': '/home/u'});

      expect(dir, '/home/u/.local/share/mostro');
    });

    test('falls back to \$HOME when XDG_DATA_HOME is empty', () {
      // The XDG spec treats an empty value exactly like an unset one.
      final dir =
          resolveLinuxDataDir({'XDG_DATA_HOME': '', 'HOME': '/home/u'});

      expect(dir, '/home/u/.local/share/mostro');
    });

    test('ignores a relative XDG_DATA_HOME, as the XDG spec requires', () {
      // A relative value would resolve against the process working directory,
      // putting the database somewhere unpredictable.
      final dir =
          resolveLinuxDataDir({'XDG_DATA_HOME': '.share', 'HOME': '/home/u'});

      expect(dir, '/home/u/.local/share/mostro');
    });

    test('returns null when neither XDG_DATA_HOME nor HOME is usable', () {
      // The caller must fall back to path_provider rather than guess a path.
      expect(resolveLinuxDataDir(const {}), isNull);
      expect(resolveLinuxDataDir(const {'HOME': ''}), isNull);
      expect(resolveLinuxDataDir(const {'HOME': 'relative/home'}), isNull);
    });

    test('never resolves inside the user-visible Documents folder', () {
      // Regression: the database used to live in getApplicationDocumentsDirectory(),
      // i.e. XDG_DOCUMENTS_DIR — a folder users tidy up, deleting their identity
      // and trade history by accident.
      final dir = resolveLinuxDataDir({
        'HOME': '/home/u',
        'XDG_DOCUMENTS_DIR': '/home/u/Documentos',
      });

      expect(dir, isNot(contains('Documentos')));
      expect(dir, isNot(contains('Documents')));
    });
  });
}
