@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the mechanism that keeps gitignored generated code in sync with the tree.
///
/// `lib/src/rust/` and `lib/l10n/app_localizations*.dart` are gitignored, so a pull
/// that brings in someone else's `rust/src/api/` change leaves the local copies stale
/// and the build fails naming a Dart type that was never generated. `.githooks/`
/// regenerates them — but only in a clone whose `core.hooksPath` points there, which
/// is why `scripts/setup-hooks.sh` exists and why codegen runs it.
void main() {
  final setupHooks = File('scripts/setup-hooks.sh');
  final frbGenerate = File('scripts/frb-generate.sh');

  group('.githooks', () {
    for (final name in const [
      'post-merge',
      'post-checkout',
      'post-rewrite',
      'regen-if-needed.sh',
    ]) {
      test('$name exists and is executable', () {
        // Arrange
        final hook = File('.githooks/$name');

        // Act
        final mode = hook.existsSync() ? hook.statSync().mode : 0;

        // Assert
        expect(hook.existsSync(), isTrue, reason: '.githooks/$name is missing');
        expect(
          mode & 0x40 /* owner execute */,
          isNonZero,
          reason: '.githooks/$name must be executable or git silently skips it',
        );
      });
    }
  });

  group('scripts/setup-hooks.sh', () {
    /// A throwaway git repository holding just the script under test.
    Future<Directory> freshClone() async {
      final tmp = Directory.systemTemp.createTempSync('hooks_setup_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      await Process.run('git', ['init', '-q', tmp.path]);
      Directory('${tmp.path}/scripts').createSync();
      setupHooks.copySync('${tmp.path}/scripts/setup-hooks.sh');
      await Process.run('chmod', ['+x', '${tmp.path}/scripts/setup-hooks.sh']);
      return tmp;
    }

    Future<String> hooksPathOf(Directory repo) async {
      final result = await Process.run('git', [
        'config',
        '--local',
        '--get',
        'core.hooksPath',
      ], workingDirectory: repo.path);
      return (result.stdout as String).trim();
    }

    test('points core.hooksPath at .githooks in a fresh clone', () async {
      // Arrange
      final repo = await freshClone();

      // Act
      final run = await Process.run(
        './scripts/setup-hooks.sh',
        const [],
        workingDirectory: repo.path,
      );

      // Assert
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(await hooksPathOf(repo), '.githooks');
    });

    test('leaves a hooksPath someone else set alone', () async {
      // Arrange
      final repo = await freshClone();
      await Process.run('git', [
        'config',
        'core.hooksPath',
        '.my-hooks',
      ], workingDirectory: repo.path);

      // Act
      final run = await Process.run(
        './scripts/setup-hooks.sh',
        const [],
        workingDirectory: repo.path,
      );

      // Assert
      expect(run.exitCode, isNonZero);
      expect(await hooksPathOf(repo), '.my-hooks');
    });

    test('--check reports an uninstalled clone without changing it', () async {
      // Arrange
      final repo = await freshClone();

      // Act
      final run = await Process.run('./scripts/setup-hooks.sh', const [
        '--check',
      ], workingDirectory: repo.path);

      // Assert
      expect(run.exitCode, isNonZero);
      expect(await hooksPathOf(repo), isEmpty);
    });
  });

  group('scripts/frb-generate.sh', () {
    test('installs the hooks so a clone need not remember to', () {
      // Arrange
      final source = frbGenerate.readAsStringSync();

      // Act
      final invokes = source.contains('scripts/setup-hooks.sh');

      // Assert
      expect(
        invokes,
        isTrue,
        reason:
            'codegen is the one script every clone runs; it must install the hooks',
      );
    });
  });
}
