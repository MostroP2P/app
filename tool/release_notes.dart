// Writes the GitHub release description and updates CHANGELOG.md for a tag.
// Run by .github/workflows/release.yml; see docs/RELEASING.md to run it by hand.
//
//   dart run tool/release_notes.dart \
//     --tag v2.0.1 [--previous-tag v2.0.0] --repository MostroP2P/app \
//     --commits commits.tsv --pull-requests prs.json \
//     --body-out RELEASE_BODY.md --changelog CHANGELOG.md [--assets-dir dist]
//
//   --assets-dir  the files that were built; the Downloads section links only
//                 those and names the platforms that are missing.
//
//   commits.tsv  git log --first-parent --format=%H%x09%s <previous>..<tag>
//   prs.json     gh pr list --state merged --limit 10000 \
//                  --json number,title,author,mergeCommit,mergedAt
import 'dart:io';

import 'release/release_notes.dart';

const _required = [
  'tag',
  'repository',
  'commits',
  'pull-requests',
  'body-out',
  'changelog',
];
final _tagPattern = RegExp(r'^v\d+\.\d+\.\d+$');

void main(List<String> arguments) {
  final Map<String, String> options;
  try {
    options = _parse(arguments);
  } on FormatException catch (error) {
    _fail(error.message);
  }

  final tag = options['tag']!;
  if (!_tagPattern.hasMatch(tag)) _fail('--tag must look like v2.0.1: $tag');
  final previousTag = options['previous-tag'];

  final ReleaseNotes notes;
  try {
    notes = ReleaseNotes.build(
      tag: tag,
      previousTag:
          (previousTag == null || previousTag.isEmpty) ? null : previousTag,
      repository: options['repository']!,
      date: DateTime.now().toUtc(),
      commits: parseCommitLog(File(options['commits']!).readAsStringSync()),
      pullRequests: parsePullRequests(
        File(options['pull-requests']!).readAsStringSync(),
      ),
    );
  } on FileSystemException catch (error) {
    _fail('cannot read ${error.path}: ${error.message}');
  } on FormatException catch (error) {
    _fail('malformed input: ${error.message}');
  }

  final assetsDir = options['assets-dir'];
  final assets =
      assetsDir == null
          ? null
          : {
            for (final entity in Directory(assetsDir).listSync())
              if (entity is File) entity.uri.pathSegments.last,
          };
  File(
    options['body-out']!,
  ).writeAsStringSync(notes.renderReleaseBody(assets: assets));

  final changelog = File(options['changelog']!);
  changelog.writeAsStringSync(
    upsertChangelog(
      changelog.existsSync() ? changelog.readAsStringSync() : null,
      notes.version,
      notes.renderChangelogSection(),
    ),
  );

  stdout.writeln(
    '${notes.entries.length} entries, '
    '${notes.contributors.length} contributors, '
    '${notes.newContributors.length} new.',
  );
}

Map<String, String> _parse(List<String> arguments) {
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    final name = arguments[i];
    if (!name.startsWith('--') || i + 1 >= arguments.length) {
      throw FormatException('expected "--option value", got "$name"');
    }
    options[name.substring(2)] = arguments[i + 1];
  }
  final missing = _required.where((name) => !options.containsKey(name));
  if (missing.isNotEmpty) {
    throw FormatException('missing --${missing.join(', --')}');
  }
  return options;
}

Never _fail(String message) {
  stderr.writeln('release_notes: $message');
  exit(64);
}
