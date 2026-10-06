@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Guards the desktop app icons (`tool/launcher_icon/build_sources.py`).
///
/// None of them is checked by a build that runs on every PR: a wrong size in
/// the macOS icon set, a Windows icon with a single resolution, or a Linux
/// `.desktop` entry whose name differs from the application ID all compile,
/// launch and show a generic icon instead of Mostro's.
void main() {
  /// Width and height from a PNG's IHDR chunk.
  (int, int) pngSize(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits, reason: 'not a PNG');
    return (data.getUint32(16), data.getUint32(20));
  }

  String applicationId() {
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    final match = RegExp(r'set\(APPLICATION_ID "([^"]+)"\)').firstMatch(cmake);
    expect(
      match,
      isNotNull,
      reason: 'linux/CMakeLists.txt sets no APPLICATION_ID',
    );
    return match!.group(1)!;
  }

  group('macOS app icon', () {
    test('every file has the side its name gives', () {
      // Arrange
      final set = Directory('macos/Runner/Assets.xcassets/AppIcon.appiconset');
      final contents = File('${set.path}/Contents.json').readAsStringSync();
      final names =
          RegExp(r'"filename" : "(app_icon_(\d+)\.png)"')
              .allMatches(contents)
              .map((m) => (m.group(1)!, int.parse(m.group(2)!)))
              .toSet();

      // Act / Assert
      expect(names, hasLength(7));
      for (final (name, side) in names) {
        final size = pngSize(File('${set.path}/$name').readAsBytesSync());
        expect(size, (side, side), reason: name);
      }
    });
  });

  group('Windows app icon', () {
    test('carries every size the shell asks for', () {
      // Arrange
      final bytes =
          File('windows/runner/resources/app_icon.ico').readAsBytesSync();
      final data = ByteData.sublistView(bytes);

      // Act — ICONDIR, then one 16-byte entry per image; 0 means 256.
      final count = data.getUint16(4, Endian.little);
      final sides = {
        for (var i = 0; i < count; i++)
          switch (bytes[6 + 16 * i]) {
            0 => 256,
            final side => side,
          },
      };

      // Assert
      expect(sides, containsAll([16, 24, 32, 48, 256]));
    });
  });

  group('Linux desktop integration', () {
    test('the entry and the icon are named after the application ID', () {
      // Arrange
      final id = applicationId();
      final entry = File('linux/packaging/$id.desktop');

      // Act
      final lines = entry.readAsLinesSync();

      // Assert — on Wayland the compositor finds the entry by the window's
      // app ID, then the icon by the entry's Icon key.
      expect(lines.first, '[Desktop Entry]');
      expect(lines, contains('Icon=$id'));
      expect(lines, contains('StartupWMClass=$id'));
      expect(lines.where((l) => l.startsWith('Exec=')), hasLength(1));
      expect(pngSize(File('linux/packaging/$id.png').readAsBytesSync()), (
        256,
        256,
      ));
    });

    test('the menu describes the app in every locale the app speaks', () {
      // Arrange
      final entry = File(
        'linux/packaging/${applicationId()}.desktop',
      ).readAsLinesSync();
      final locales = Directory('lib/l10n')
          .listSync()
          .map((f) => RegExp(r'app_(\w+)\.arb$').firstMatch(f.path)?.group(1))
          .whereType<String>()
          .where((l) => l != 'en');

      // Act / Assert — the English values are the unqualified keys.
      expect(locales, isNotEmpty);
      for (final key in ['GenericName', 'Comment']) {
        expect(entry.where((l) => l.startsWith('$key=')), hasLength(1));
        for (final locale in locales) {
          expect(
            entry.where((l) => l.startsWith('$key[$locale]=')),
            hasLength(1),
            reason: '$key[$locale]',
          );
        }
      }
    });

    test('the bundle ships the icon, the entry and install.sh', () {
      // Arrange
      final cmake = File('linux/CMakeLists.txt').readAsStringSync();

      // Act / Assert
      expect(cmake, contains(r'"packaging/${APPLICATION_ID}.png"'));
      expect(cmake, contains(r'"packaging/${APPLICATION_ID}.desktop"'));
      expect(cmake, contains('install(PROGRAMS "packaging/install.sh"'));
    });

    test('the window loads its icon from the bundle', () {
      // Arrange
      final runner = File('linux/runner/my_application.cc').readAsStringSync();

      // Act / Assert
      expect(runner, contains('gtk_window_set_icon_from_file'));
      expect(runner, contains('APPLICATION_ID ".png"'));
    });
  });

  group('install.sh', () {
    late Directory temp;
    late Directory bundle;
    late Directory dataHome;
    late String id;

    setUp(() {
      id = applicationId();
      temp = Directory.systemTemp.createTempSync('mostro-install-');
      // Characters the Exec key must quote or escape.
      bundle = Directory('${temp.path}/My "apps" \$HOME 100%')..createSync();
      dataHome = Directory('${temp.path}/share');
      Directory('${bundle.path}/data').createSync();
      File('${bundle.path}/mostro').writeAsStringSync('');
      Process.runSync('chmod', ['+x', '${bundle.path}/mostro']);
      File('linux/packaging/install.sh').copySync('${bundle.path}/install.sh');
      for (final ext in ['png', 'desktop']) {
        File(
          'linux/packaging/$id.$ext',
        ).copySync('${bundle.path}/data/$id.$ext');
      }
    });

    tearDown(() => temp.deleteSync(recursive: true));

    ProcessResult run([List<String> args = const []]) => Process.runSync(
      'sh',
      ['${bundle.path}/install.sh', ...args],
      environment: {'XDG_DATA_HOME': dataHome.path},
    );

    test(
      'adds the entry, pointing at this bundle through a link, and the icon',
      () {
        // Act
        final result = run();

        // Assert
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final entry = File('${dataHome.path}/applications/$id.desktop');
        final icon = File(
          '${dataHome.path}/icons/hicolor/256x256/apps/$id.png',
        );
        expect(icon.existsSync(), isTrue);
        final link = Link('${dataHome.path}/$id.bundle');
        expect(
          link.resolveSymbolicLinksSync(),
          bundle.resolveSymbolicLinksSync(),
        );
        final exec = entry.readAsLinesSync().singleWhere(
          (l) => l.startsWith('Exec='),
        );
        // The link keeps the bundle's `"`, `$` and `%` out of the entry.
        expect(exec, 'Exec="${link.path}/mostro"');
      },
      skip: Platform.isWindows,
    );

    test(
      'gives an entry that GLib can launch',
      () {
        // Arrange
        File('${bundle.path}/mostro').writeAsStringSync(
          '#!/bin/sh\ntouch "${temp.path}/launched"\n',
        );
        expect(run().exitCode, 0);

        // Act: GLib rejects an entry whose program it cannot find, without
        // expanding `%%` first, so the escaped bundle path never launched.
        final result = Process.runSync('gio', [
          'launch',
          '${dataHome.path}/applications/$id.desktop',
        ]);

        // Assert
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final launched = File('${temp.path}/launched');
        for (var i = 0; i < 50 && !launched.existsSync(); i++) {
          sleep(const Duration(milliseconds: 100));
        }
        expect(launched.existsSync(), isTrue);
      },
      skip:
          Platform.isWindows ||
                  Process.runSync('sh', ['-c', 'command -v gio']).exitCode != 0
              ? 'needs GLib\'s gio'
              : false,
    );

    test('refuses a data directory the entry cannot name', () {
      // Arrange
      dataHome = Directory('${temp.path}/share 100%');

      // Act
      final result = run();

      // Assert
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('%'));
      expect(
        File('${dataHome.path}/applications/$id.desktop').existsSync(),
        isFalse,
      );
    }, skip: Platform.isWindows);

    test('--uninstall removes them again', () {
      // Arrange
      expect(run().exitCode, 0);

      // Act
      final result = run(['--uninstall']);

      // Assert
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        File('${dataHome.path}/applications/$id.desktop').existsSync(),
        isFalse,
      );
      expect(
        File(
          '${dataHome.path}/icons/hicolor/256x256/apps/$id.png',
        ).existsSync(),
        isFalse,
      );
      expect(Link('${dataHome.path}/$id.bundle').existsSync(), isFalse);
    }, skip: Platform.isWindows);
  });
}
