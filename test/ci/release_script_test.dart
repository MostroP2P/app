@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drives `scripts/release.sh` against a throwaway clone (docs/RELEASING.md).
///
/// `origin` is a local bare repository and `gh` a stub on `PATH` that records
/// its calls, so nothing here reaches GitHub. Each test seeds `main` at some
/// version and checks which of the script's three steps the run took.
void main() {
  late Directory sandbox;
  late Directory clone;
  late Directory origin;
  late File ghLog;
  late File ghOpenPr;

  final env = <String, String>{};

  ProcessResult git(List<String> args, {Directory? dir}) {
    final result = Process.runSync(
      'git',
      args,
      workingDirectory: (dir ?? clone).path,
      environment: env,
    );
    expect(result.exitCode, 0, reason: 'git ${args.join(' ')}: ${result.stderr}');
    return result;
  }

  String gitOut(List<String> args, {Directory? dir}) =>
      (git(args, dir: dir).stdout as String).trim();

  ProcessResult release(String version) => Process.runSync(
    'bash',
    ['scripts/release.sh', version],
    workingDirectory: clone.path,
    environment: env,
  );

  String ghCalls() => ghLog.existsSync() ? ghLog.readAsStringSync() : '';

  /// Commits [version] to the clone's files and pushes it to `origin/main`.
  void seedMain(String version, {String? pubspec}) {
    File('${clone.path}/pubspec.yaml').writeAsStringSync(
      'name: mostro\nversion: ${pubspec ?? version}+1\n',
    );
    File('${clone.path}/rust/Cargo.toml').writeAsStringSync(
      '[package]\nname = "rust"\nversion = "$version"\n\n'
      '[dependencies]\nfoo = { version = "1.0" }\n',
    );
    File('${clone.path}/rust/Cargo.lock').writeAsStringSync(
      '[[package]]\nname = "rust"\nversion = "$version"\n',
    );
    git(['add', '-A']);
    git(['commit', '-qm', 'seed $version']);
    git(['push', '-q', 'origin', 'HEAD:main']);
  }

  String remoteFile(String ref, String path) =>
      gitOut(['show', '$ref:$path'], dir: origin);

  String remoteBranches() => gitOut(['branch', '--list'], dir: origin);

  /// The clone is back where it started: on main, clean, no release branch.
  void expectRestored() {
    expect(gitOut(['rev-parse', '--abbrev-ref', 'HEAD']), 'main');
    expect(gitOut(['status', '--porcelain']), isEmpty);
    expect(gitOut(['branch', '--list', 'chore/*']), isEmpty);
  }

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('release_script_test');
    origin = Directory('${sandbox.path}/origin.git')..createSync();
    clone = Directory('${sandbox.path}/clone')..createSync();
    final bin = Directory('${sandbox.path}/bin')..createSync();
    ghLog = File('${sandbox.path}/gh.log');
    ghOpenPr = File('${sandbox.path}/gh_open_pr');

    // An isolated git: no user config (signing, hooks, default branch).
    env
      ..clear()
      ..addAll({
        'GIT_CONFIG_GLOBAL': '/dev/null',
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_AUTHOR_NAME': 'Test',
        'GIT_AUTHOR_EMAIL': 'test@example.com',
        'GIT_COMMITTER_NAME': 'Test',
        'GIT_COMMITTER_EMAIL': 'test@example.com',
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'GH_LOG': ghLog.path,
        'GH_OPEN_PR': ghOpenPr.path,
        'GH_FAIL_CREATE': '${sandbox.path}/gh_fail_create',
      });

    // `gh pr list` answers with the stub's open PR, if any; every call is
    // logged, one per line.
    final gh = File('${bin.path}/gh')..writeAsStringSync(r'''#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list") [ -f "$GH_OPEN_PR" ] && cat "$GH_OPEN_PR"; exit 0 ;;
  "pr create")
    [ -f "$GH_FAIL_CREATE" ] && { echo "boom" >&2; exit 1; }
    echo "https://github.com/example/app/pull/99"; exit 0 ;;
esac
exit 0
''');
    Process.runSync('chmod', ['+x', gh.path]);

    git(['init', '-q', '--bare', '-b', 'main'], dir: origin);
    git(['init', '-q', '-b', 'main'], dir: clone);
    git(['remote', 'add', 'origin', origin.path]);
    Directory('${clone.path}/scripts').createSync();
    Directory('${clone.path}/rust').createSync();
    for (final script in ['release.sh', 'bump-version.sh']) {
      File('scripts/$script').copySync('${clone.path}/scripts/$script');
    }
    seedMain('2.0.0');
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  group('when main does not carry the version yet', () {
    test('opens the bump PR from a fresh branch and returns to main', () {
      // Act
      final run = release('2.0.1');

      // Assert
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      const branch = 'chore/release-v2.0.1';
      expect(remoteFile(branch, 'pubspec.yaml'), contains('version: 2.0.1+20001'));
      expect(remoteFile(branch, 'rust/Cargo.toml'), contains('version = "2.0.1"'));
      expect(remoteFile(branch, 'rust/Cargo.lock'), contains('version = "2.0.1"'));
      expect(
        gitOut(['log', '-1', '--format=%s', branch], dir: origin),
        'chore(release): v2.0.1',
      );
      expect(ghCalls(), contains('pr create'));
      expect(ghCalls(), contains('chore(release): v2.0.1'));
      expect(gitOut(['rev-parse', '--abbrev-ref', 'HEAD']), 'main');
      expect(gitOut(['tag', '--list'], dir: origin), isEmpty);
    });

    test('only points at the PR when it is already open', () {
      // Arrange
      ghOpenPr.writeAsStringSync('https://github.com/example/app/pull/7\n');

      // Act
      final run = release('2.0.1');

      // Assert
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, contains('https://github.com/example/app/pull/7'));
      expect(ghCalls(), isNot(contains('pr create')));
      expect(remoteBranches(), isNot(contains('chore/')));
    });

    test('refuses a version that does not move forward', () {
      // Act
      final run = release('1.9.9');

      // Assert
      expect(run.exitCode, isNot(0));
      expect(run.stderr, contains('2.0.0'));
      expect(remoteBranches(), isNot(contains('chore/')));
    });

    test('refuses a stale bump PR once main has moved past it', () {
      // Arrange
      seedMain('2.0.2');
      ghOpenPr.writeAsStringSync('https://github.com/example/app/pull/7\n');

      // Act
      final run = release('2.0.1');

      // Assert
      expect(run.exitCode, isNot(0));
      expect(run.stderr, contains('2.0.2'));
      expect(run.stdout, isNot(contains('pull/7')));
    });

    test('refuses a main whose manifests disagree', () {
      // Arrange
      seedMain('2.0.0', pubspec: '2.0.1');

      // Act
      final run = release('2.0.2');

      // Assert
      expect(run.exitCode, isNot(0));
      expect(run.stderr, contains('disagrees'));
      expect(remoteBranches(), isNot(contains('chore/')));
    });

    test('a failed bump returns to the starting branch and leaves no trace', () {
      // Act — PATCH 100 passes the script's own check; bump-version.sh refuses it.
      final run = release('2.0.100');

      // Assert
      expect(run.exitCode, isNot(0));
      expectRestored();
      expect(remoteBranches(), isNot(contains('chore/')));
    });

    test('a failed PR creation returns to the starting branch', () {
      // Arrange
      File('${sandbox.path}/gh_fail_create').writeAsStringSync('');

      // Act
      final run = release('2.0.1');

      // Assert
      expect(run.exitCode, isNot(0));
      expectRestored();
      expect(run.stderr, contains('gh pr create'));
    });

    test('refuses to start with uncommitted changes', () {
      // Arrange
      File('${clone.path}/pubspec.yaml')
          .writeAsStringSync('dirty\n', mode: FileMode.append);

      // Act
      final run = release('2.0.1');

      // Assert
      expect(run.exitCode, isNot(0));
      expect(run.stderr, contains('uncommitted'));
      expect(remoteBranches(), isNot(contains('chore/')));
    });
  });

  group('when main carries the version', () {
    test('tags origin/main, not the local checkout, and pushes the tag', () {
      // Arrange — main moves on while the clone sits on an older commit.
      seedMain('2.0.1');
      final shipped = gitOut(['rev-parse', 'main'], dir: origin);
      git(['reset', '-q', '--hard', 'HEAD~1']);

      // Act
      final run = release('2.0.1');

      // Assert
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      expect(gitOut(['rev-parse', 'v2.0.1^{commit}'], dir: origin), shipped);
      expect(gitOut(['cat-file', '-t', 'v2.0.1'], dir: origin), 'tag');
      expect(ghCalls(), isNot(contains('pr create')));
    });

    test('refuses when the tag already exists, and says how to retag', () {
      // Arrange
      seedMain('2.0.1');
      git(['tag', '-a', 'v2.0.1', '-m', 'earlier attempt']);
      git(['push', '-q', 'origin', 'v2.0.1']);

      // Act
      final run = release('2.0.1');

      // Assert
      expect(run.exitCode, isNot(0));
      expect(run.stderr, contains('git push origin :v2.0.1'));
    });
  });

  test('rejects a malformed version before touching anything', () {
    // Act
    final run = release('2.0.1-rc1');

    // Assert
    expect(run.exitCode, 64);
    expect(ghLog.existsSync(), isFalse);
  });
}
