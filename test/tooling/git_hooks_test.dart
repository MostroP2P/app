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
    /// A throwaway git repository holding the installer and the hooks it copies.
    Future<Directory> freshClone() async {
      final tmp = Directory.systemTemp.createTempSync('hooks_setup_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      await Process.run('git', ['init', '-q', tmp.path]);
      Directory('${tmp.path}/scripts').createSync();
      setupHooks.copySync('${tmp.path}/scripts/setup-hooks.sh');
      await Process.run('chmod', ['+x', '${tmp.path}/scripts/setup-hooks.sh']);
      Directory('${tmp.path}/.githooks').createSync();
      for (final hook in Directory('.githooks').listSync().whereType<File>()) {
        hook.copySync('${tmp.path}/.githooks/${hook.uri.pathSegments.last}');
      }
      return tmp;
    }

    Future<ProcessResult> install(Directory repo, [List<String> args = const []]) =>
        Process.run('./scripts/setup-hooks.sh', args, workingDirectory: repo.path);

    Future<String> hooksPathOf(Directory repo) async {
      final result = await Process.run('git', [
        'config',
        '--get',
        'core.hooksPath',
      ], workingDirectory: repo.path);
      return (result.stdout as String).trim();
    }

    File installed(Directory repo, String name) =>
        File('${repo.path}/.git/hooks/$name');

    test('copies the hooks into .git/hooks, leaving core.hooksPath unset',
        () async {
      // Arrange
      final repo = await freshClone();

      // Act
      final run = await install(repo);

      // Assert — a copy under .git/hooks is the whole point: no ref can write
      // there, so checking out a hostile branch cannot swap the hook out.
      expect(run.exitCode, 0, reason: '${run.stderr}');
      for (final name in const [
        'pre-commit',
        'post-merge',
        'post-checkout',
        'post-rewrite',
        'regen-if-needed.sh',
      ]) {
        expect(installed(repo, name).existsSync(), isTrue, reason: name);
      }
      expect(await hooksPathOf(repo), isEmpty);
    });

    test('migrates a clone still pointing core.hooksPath at the tracked dir',
        () async {
      // Arrange — the arrangement this script used to create, and the one that
      // makes `git checkout` run code from the incoming ref.
      final repo = await freshClone();
      await Process.run('git', [
        'config',
        'core.hooksPath',
        '.githooks',
      ], workingDirectory: repo.path);

      // Act
      final run = await install(repo);

      // Assert
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(await hooksPathOf(repo), isEmpty);
      expect(installed(repo, 'post-checkout').existsSync(), isTrue);
    });

    test('refuses to clobber a hook it did not install', () async {
      // Arrange
      final repo = await freshClone();
      final mine = installed(repo, 'pre-commit')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho mine\n');

      // Act
      final run = await install(repo);

      // Assert
      expect(run.exitCode, isNonZero);
      expect(mine.readAsStringSync(), contains('echo mine'));
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
      final run = await install(repo);

      // Assert
      expect(run.exitCode, isNonZero);
      expect(await hooksPathOf(repo), '.my-hooks');
    });

    test('--check reports an uninstalled clone without changing it', () async {
      // Arrange
      final repo = await freshClone();

      // Act
      final run = await install(repo, const ['--check']);

      // Assert
      expect(run.exitCode, isNonZero);
      expect(installed(repo, 'post-checkout').existsSync(), isFalse);
    });

    test('refreshes a copy that has fallen behind its source', () async {
      // Arrange — an edit in .githooks/ only reaches a clone when the installer
      // runs again, so this is the path that keeps copies from going stale.
      final repo = await freshClone();
      await install(repo);
      // Keeps the marker: this is our copy gone stale, not somebody else's hook.
      installed(repo, 'post-merge').writeAsStringSync(
        '#!/bin/sh\n# installed by scripts/setup-hooks.sh\n# stale\n',
      );

      // Act
      final run = await install(repo);

      // Assert
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(
        installed(repo, 'post-merge').readAsStringSync(),
        File('.githooks/post-merge').readAsStringSync(),
      );
    });

    test('is a no-op the second time', () async {
      // Arrange
      final repo = await freshClone();
      await install(repo);

      // Act
      final run = await install(repo);

      // Assert
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, contains('up to date'));
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
