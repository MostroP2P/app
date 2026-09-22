@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/release_notes.dart';

/// The release workflow publishes whatever this generator prints, to the
/// GitHub release and to `CHANGELOG.md`, with nobody reading it first.
void main() {
  PullRequest pr(
    int number,
    String title, {
    String author = 'alice',
    bool isBot = false,
    String? sha,
    String mergedAt = '2026-09-10T00:00:00Z',
  }) => PullRequest(
    number: number,
    title: title,
    author: author,
    isBot: isBot,
    mergeSha: sha ?? 'sha$number',
    mergedAt: DateTime.parse(mergedAt),
  );

  Commit merge(int number) => Commit(
    sha: 'sha$number',
    subject: 'Merge pull request #$number from MostroP2P/some-branch',
  );

  ReleaseNotes notesFor(
    List<Commit> commits,
    List<PullRequest> prs, {
    String? previousTag = 'v2.0.0',
  }) => ReleaseNotes.build(
    tag: 'v2.0.1',
    previousTag: previousTag,
    repository: 'MostroP2P/app',
    date: DateTime.utc(2026, 9, 17),
    commits: commits,
    pullRequests: prs,
  );

  group('Entry.parse', () {
    test('reads type, scope and description of a conventional subject', () {
      // Act
      final entry = Entry.parse('fix(relay): keep subscriptions alive');

      // Assert
      expect(entry.type, 'fix');
      expect(entry.scope, 'relay');
      expect(entry.description, 'keep subscriptions alive');
      expect(entry.isBreaking, isFalse);
    });

    test('marks a subject with ! as breaking', () {
      // Act
      final entry = Entry.parse('feat(transport)!: drop gift wrap');

      // Assert
      expect(entry.type, 'feat');
      expect(entry.isBreaking, isTrue);
    });

    test('files a non-conventional subject under "other", text intact', () {
      // Act
      final entry = Entry.parse('Update README with new badge');

      // Assert
      expect(entry.type, 'other');
      expect(entry.scope, isNull);
      expect(entry.description, 'Update README with new badge');
    });

    test('is case-insensitive about the type', () {
      // Act
      final entry = Entry.parse('Feat: add dark mode');

      // Assert
      expect(entry.type, 'feat');
    });
  });

  group('ReleaseNotes.build', () {
    test('uses the PR title and author for a merge commit', () {
      // Arrange
      final commits = [merge(497)];
      final prs = [pr(497, 'fix(relay): keep subscriptions alive')];

      // Act
      final notes = notesFor(commits, prs);

      // Assert
      final entry = notes.entries.single;
      expect(entry.type, 'fix');
      expect(entry.pullRequest, 497);
      expect(entry.author, 'alice');
    });

    test('ignores PRs whose merge commit is outside the range', () {
      // Arrange
      final commits = [merge(2)];
      final prs = [pr(1, 'feat: old'), pr(2, 'feat: new')];

      // Act
      final notes = notesFor(commits, prs);

      // Assert
      expect(notes.entries.map((e) => e.pullRequest), [2]);
    });

    test('keeps a commit pushed straight to main, by short sha', () {
      // Arrange
      final commits = [
        const Commit(sha: 'abcdef1234567890', subject: 'docs: fix typo'),
      ];

      // Act
      final notes = notesFor(commits, const []);

      // Assert
      final entry = notes.entries.single;
      expect(entry.type, 'docs');
      expect(entry.pullRequest, isNull);
      expect(entry.shortSha, 'abcdef1');
    });

    test('falls back to the merge subject when the PR is unknown', () {
      // Arrange — a merge commit the PR listing did not return.
      final commits = [merge(42)];

      // Act
      final notes = notesFor(commits, const []);

      // Assert
      final entry = notes.entries.single;
      expect(entry.pullRequest, 42);
      expect(entry.type, 'other');
    });

    test('drops plain branch merges and the release bookkeeping PR', () {
      // Arrange
      final commits = [
        const Commit(sha: 'm1', subject: "Merge branch 'main' into feat/x"),
        merge(7),
      ];
      final prs = [pr(7, 'chore(release): changelog for v2.0.0')];

      // Act
      final notes = notesFor(commits, prs);

      // Assert
      expect(notes.entries, isEmpty);
    });

    test('lists human contributors once, sorted, without bots', () {
      // Arrange
      final commits = [merge(1), merge(2), merge(3), merge(4)];
      final prs = [
        pr(1, 'feat: a', author: 'zoe'),
        pr(2, 'fix: b', author: 'alice'),
        pr(3, 'fix: c', author: 'zoe'),
        pr(4, 'chore: bump', author: 'dependabot', isBot: true),
      ];

      // Act
      final notes = notesFor(commits, prs);

      // Assert
      expect(notes.contributors, ['alice', 'zoe']);
    });

    test('a new contributor has no PR merged before this release', () {
      // Arrange
      final commits = [merge(10), merge(11)];
      final prs = [
        pr(
          3,
          'feat: earlier work',
          author: 'alice',
          mergedAt: '2026-08-01T00:00:00Z',
        ),
        pr(10, 'fix: a', author: 'alice'),
        pr(11, 'feat: b', author: 'bob'),
      ];

      // Act
      final notes = notesFor(commits, prs);

      // Assert
      expect(notes.newContributors.map((c) => c.login), ['bob']);
      expect(notes.newContributors.single.firstPullRequest, 11);
    });

    test('a PR merged after this release does not make its author known', () {
      // Arrange — re-running the workflow for an old tag.
      final commits = [merge(10)];
      final prs = [
        pr(10, 'fix: a', author: 'bob'),
        pr(90, 'feat: later', author: 'bob', mergedAt: '2027-01-01T00:00:00Z'),
      ];

      // Act
      final notes = notesFor(commits, prs);

      // Assert
      expect(notes.newContributors.map((c) => c.login), ['bob']);
    });

    test('the first release names no new contributors', () {
      // Arrange — with no previous tag everyone would qualify.
      final commits = [merge(1)];
      final prs = [pr(1, 'feat: a', author: 'alice')];

      // Act
      final notes = notesFor(commits, prs, previousTag: null);

      // Assert
      expect(notes.contributors, ['alice']);
      expect(notes.newContributors, isEmpty);
    });
  });

  group('rendered changes', () {
    test('groups by type in a fixed order, breaking changes first', () {
      // Arrange
      final commits = [merge(1), merge(2), merge(3), merge(4)];
      final prs = [
        pr(1, 'docs: relay rules'),
        pr(2, 'fix(chat): scroll'),
        pr(3, 'feat: bonds'),
        pr(4, 'feat(api)!: drop v1'),
      ];

      // Act
      final text = notesFor(commits, prs).renderChanges();

      // Assert
      final order =
          [
            '💥 Breaking Changes',
            '✨ Features',
            '🐛 Bug Fixes',
            '📚 Documentation',
          ].map(text.indexOf).toList();
      expect(order.every((i) => i >= 0), isTrue, reason: text);
      expect(order, [...order]..sort());
      expect(text, isNot(contains('Performance')));
    });

    test('an entry shows scope, PR link and author', () {
      // Arrange
      final notes = notesFor(
        [merge(2)],
        [pr(2, 'fix(chat): scroll to the last message', author: 'bob')],
      );

      // Act
      final text = notes.renderChanges();

      // Assert
      expect(
        text,
        contains(
          '- **chat:** scroll to the last message '
          '([#2](https://github.com/MostroP2P/app/pull/2)) by @bob',
        ),
      );
    });

    test('a PR title cannot plant a link, a tag or a mention', () {
      // Arrange — the title is whatever an outside contributor typed, and
      // this page is where users come for the APK links.
      final notes = notesFor(
        [merge(2)],
        [pr(2, 'fix: see [the fixed apk](https://evil.example) <img> @victim')],
      );

      // Act
      final text = notes.renderChanges();

      // Assert
      expect(text, isNot(contains('[the fixed apk](')));
      expect(text, isNot(contains('<img>')));
      expect(text, isNot(contains('@victim')));
      expect(text, contains('by @alice'));
    });

    test('a breaking entry is listed once, under breaking changes', () {
      // Arrange
      final notes = notesFor([merge(4)], [pr(4, 'feat(api)!: drop v1')]);

      // Act
      final text = notes.renderChanges();

      // Assert
      expect('drop v1'.allMatches(text), hasLength(1));
      expect(text, isNot(contains('✨ Features')));
    });

    test('says so when nothing user-visible changed', () {
      // Act
      final text = notesFor(const [], const []).renderChanges();

      // Assert
      expect(text, contains('No notable changes'));
    });
  });

  group('release body', () {
    test('explains both APKs by the file names the workflow uploads', () {
      // Act
      final body = notesFor([merge(1)], [pr(1, 'feat: a')]).renderReleaseBody();

      // Assert
      expect(body, contains('mostro-v2.0.1-arm64-v8a.apk'));
      expect(body, contains('mostro-v2.0.1-armeabi-v7a.apk'));
      expect(body, contains('SHA256SUMS.txt'));
    });

    test('lists the desktop and iOS downloads next to the APKs', () {
      // Act
      final body = notesFor([merge(1)], [pr(1, 'feat: a')]).renderReleaseBody();

      // Assert
      for (final file in [
        'mostro-v2.0.1-linux-x64.tar.gz',
        'mostro-v2.0.1-windows-x64.zip',
        'mostro-v2.0.1-macos-universal.zip',
        'mostro-v2.0.1-ios-unsigned.ipa',
      ]) {
        expect(body, contains('/releases/download/v2.0.1/$file'));
      }
    });

    test('offers the app bundle to Play Console, not to phones', () {
      // Act
      final body = notesFor([merge(1)], [pr(1, 'feat: a')]).renderReleaseBody();

      // Assert
      expect(body, contains('/releases/download/v2.0.1/mostro-v2.0.1.aab'));
      expect(body, contains('Google Play'));
      expect(body, contains('not installable'));
    });

    test('says how to open builds the OS does not trust', () {
      // Act
      final body = notesFor([merge(1)], [pr(1, 'feat: a')]).renderReleaseBody();

      // Assert — none of the desktop or iOS builds is signed by a vendor
      // certificate, and each OS blocks that in its own way.
      expect(body, contains('xattr -dr com.apple.quarantine'));
      expect(body, contains('SmartScreen'));
      expect(body, contains('sideload'));
    });

    test('a platform whose build failed is not offered for download', () {
      // Arrange — publish goes ahead with whatever was built.
      final notes = notesFor([merge(1)], [pr(1, 'feat: a')]);

      // Act
      final body = notes.renderReleaseBody(
        assets: {
          'mostro-v2.0.1-arm64-v8a.apk',
          'mostro-v2.0.1-armeabi-v7a.apk',
          'mostro-v2.0.1-linux-x64.tar.gz',
        },
      );

      // Assert
      expect(body, contains('mostro-v2.0.1-linux-x64.tar.gz'));
      expect(body, isNot(contains('mostro-v2.0.1-windows-x64.zip')));
      expect(body, isNot(contains('mostro-v2.0.1-macos-universal.zip')));
      expect(body, isNot(contains('SmartScreen')));
      expect(body, contains('Windows, macOS and iOS'));
    });

    test('names every asset the workflows upload', () {
      // Act
      final names = releaseAssetNames('v2.0.1');

      // Assert
      expect(names.keys, [
        'android-v8',
        'android-v7',
        'android-aab',
        'linux',
        'windows',
        'macos',
        'ios',
      ]);
      expect(names['linux'], 'mostro-v2.0.1-linux-x64.tar.gz');
    });

    test('links the comparison with the previous tag', () {
      // Act
      final body = notesFor([merge(1)], [pr(1, 'feat: a')]).renderReleaseBody();

      // Assert
      expect(
        body,
        contains('https://github.com/MostroP2P/app/compare/v2.0.0...v2.0.1'),
      );
    });

    test('credits new contributors with their first PR', () {
      // Arrange
      final notes = notesFor([merge(11)], [pr(11, 'feat: b', author: 'bob')]);

      // Act
      final body = notes.renderReleaseBody();

      // Assert
      expect(body, contains('New Contributors'));
      expect(body, contains('@bob made their first contribution in'));
      expect(body, contains('/pull/11'));
    });

    test('the first release has no comparison link', () {
      // Act
      final body =
          notesFor(
            [merge(1)],
            [pr(1, 'feat: a')],
            previousTag: null,
          ).renderReleaseBody();

      // Assert
      expect(body, isNot(contains('/compare/')));
    });
  });

  group('changelog', () {
    const header = '# Changelog\n\nIntro line.\n';

    test('a section is headed by version and date', () {
      // Act
      final section =
          notesFor([merge(1)], [pr(1, 'feat: a')]).renderChangelogSection();

      // Assert
      expect(section, startsWith('## [2.0.1] - 2026-09-17\n'));
    });

    test('creates the file with a header when there is none', () {
      // Act
      final text = upsertChangelog(null, '2.0.1', '## [2.0.1] - x\n\n- a\n');

      // Assert
      expect(text, startsWith('# Changelog\n'));
      expect(text, contains('## [2.0.1] - x'));
    });

    test('puts a new version above the older ones, header kept', () {
      // Arrange
      const existing = '$header\n## [2.0.0] - 2026-09-01\n\n- first\n';

      // Act
      final text = upsertChangelog(
        existing,
        '2.0.1',
        '## [2.0.1] - x\n\n- second\n',
      );

      // Assert
      expect(text, startsWith(header));
      expect(text.indexOf('[2.0.1]'), lessThan(text.indexOf('[2.0.0]')));
      expect(text, contains('- first'));
    });

    test('re-running a release replaces its section instead of adding one', () {
      // Arrange
      const existing =
          '$header\n## [2.0.1] - old\n\n- stale\n\n'
          '## [2.0.0] - 2026-09-01\n\n- first\n';

      // Act
      final text = upsertChangelog(
        existing,
        '2.0.1',
        '## [2.0.1] - new\n\n- fresh\n',
      );

      // Assert
      expect('## [2.0.1]'.allMatches(text), hasLength(1));
      expect(text, contains('- fresh'));
      expect(text, isNot(contains('- stale')));
      expect(text, contains('- first'));
    });
  });

  group('input parsing', () {
    test('reads `git log --format=%H%x09%s` lines', () {
      // Act
      final commits = parseCommitLog('abc\tfix: a\tb\n\ndef\tfeat: c\n');

      // Assert
      expect(commits.map((c) => c.sha), ['abc', 'def']);
      expect(commits.first.subject, 'fix: a\tb');
    });

    test('reads `gh pr list --json` output, skipping unmerged shapes', () {
      // Arrange
      const json = '''
[
  {"number": 5, "title": "fix: a", "mergedAt": "2026-09-10T10:00:00Z",
   "author": {"login": "alice", "is_bot": false},
   "mergeCommit": {"oid": "abc"}},
  {"number": 6, "title": "chore: b", "mergedAt": "2026-09-10T10:00:00Z",
   "author": {"login": "app/dependabot", "is_bot": true},
   "mergeCommit": {"oid": "def"}},
  {"number": 7, "title": "x", "mergedAt": null, "author": null,
   "mergeCommit": null}
]''';

      // Act
      final prs = parsePullRequests(json);

      // Assert
      expect(prs.map((p) => p.number), [5, 6]);
      expect(prs.first.author, 'alice');
      expect(prs.last.isBot, isTrue);
    });
  });
}
