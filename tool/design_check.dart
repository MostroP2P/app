/// Checks UI code against the design guide (`.specify/DESIGN_SYSTEM.md`).
///
/// ```sh
/// dart tool/design_check.dart                 # code touched since origin/main
/// dart tool/design_check.dart --base <ref>    # ... since another ref
/// dart tool/design_check.dart --all           # every line: the §14 debt
/// ```
///
/// The "Design guide" CI job runs the first form against the pull request's
/// base. Exits 1 on any break, 2 when git fails. A break that is right on
/// purpose takes `// design-check: ignore DS-XXX-N — reason` (guide §13).
library;

import 'dart:io';

import 'design/design_check.dart';

Future<void> main(List<String> args) async {
  var base = 'origin/main';
  var all = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--base' when i + 1 < args.length:
        base = args[++i];
      case '--all':
        all = true;
      default:
        stderr.writeln(
          'usage: dart tool/design_check.dart [--base <ref>] [--all]',
        );
        exit(64);
    }
  }

  final Map<String, Set<int>?> targets;
  if (all) {
    targets = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File) f.path.replaceAll(r'\', '/'): null,
    };
  } else {
    final diff = await Process.run('git', [
      'diff',
      '--unified=0',
      '--no-color',
      '--no-ext-diff',
      '$base...HEAD',
      '--',
      'lib',
    ]);
    if (diff.exitCode != 0) {
      stderr.writeln('git diff against $base failed:\n${diff.stderr}');
      exit(2);
    }
    targets = addedLines(diff.stdout as String);
  }

  final checked = targets.keys.where(isChecked).toList()..sort();
  final violations = [
    for (final path in checked)
      if (File(path).existsSync())
        ...scan(path, File(path).readAsStringSync(), lines: targets[path]),
  ];

  final annotate = Platform.environment['GITHUB_ACTIONS'] == 'true';
  for (final v in violations) {
    if (annotate) {
      final message = v.message
          .replaceAll('%', '%25')
          .replaceAll('\r', '%0D')
          .replaceAll('\n', '%0A');
      stdout.writeln(
        '::error file=${v.path},line=${v.line},title=${v.rule}::$message',
      );
    } else {
      stdout.writeln(v);
    }
  }

  final scope = all ? 'lib/' : 'the code touched since $base';
  if (violations.isEmpty) {
    stdout.writeln(
      'Design guide: no breaks in $scope (${checked.length} files).',
    );
    return;
  }
  final perRule = <String, int>{};
  for (final v in violations) {
    perRule[v.rule] = (perRule[v.rule] ?? 0) + 1;
  }
  stdout
    ..writeln()
    ..writeln(
      'Design guide: ${violations.length} breaks in $scope: '
      '${(perRule.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key} ×${e.value}').join(', ')}.',
    )
    ..writeln(
      'Rules: .specify/DESIGN_SYSTEM.md. A break that is right on purpose takes '
      '`// design-check: ignore <rule> — <reason>`.',
    );
  exit(1);
}
