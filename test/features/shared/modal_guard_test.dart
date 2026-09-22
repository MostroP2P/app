@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps every modal in the app coming out of `mostro_modal.dart` (#534).
///
/// Standardizing 29 modals is a one-off; keeping them standard is not. The
/// next modal is written by copying a nearby screen, and before this guard
/// the nearest example was always a hand-built `AlertDialog` with its own
/// radius, its own CTA colour and its own scrim. So the raw Flutter entry
/// points are banned outside the one file that owns them: a new modal has to
/// go through `showMostroDialog` / `showMostroSheet`, and gets the app's
/// surface, scrim and footer for free.
///
/// It reads the source rather than the widget tree because that is where the
/// mistake is made — this fails in review, before a screen ships with a
/// second dialog style.
void main() {
  /// The one file allowed to call Flutter's own modal API.
  const owner = 'lib/shared/widgets/mostro_modal.dart';

  /// Generated: flutter_rust_bridge and `flutter gen-l10n` own these, and
  /// neither builds a modal.
  const generated = ['lib/src/rust/', 'lib/l10n/app_localizations'];

  final banned = <String, RegExp>{
    'showDialog': RegExp(r'\bshowDialog\s*[<(]'),
    'showGeneralDialog': RegExp(r'\bshowGeneralDialog\s*[<(]'),
    'showModalBottomSheet': RegExp(r'\bshowModalBottomSheet\s*[<(]'),
    'AlertDialog': RegExp(r'\bAlertDialog\s*\('),
    'SimpleDialog': RegExp(r'\bSimpleDialog\s*\('),
    'Dialog': RegExp(r'(^|[^A-Za-z_])Dialog\s*\('),
  };

  /// Source lines of [file], minus whole-line comments: this guard is about
  /// code, and `app_theme.dart` explains itself by naming `AlertDialog` in
  /// prose. A banned name in a trailing comment does trip it — move the
  /// comment to its own line.
  Iterable<(int, String)> codeLines(File file) sync* {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('//')) continue;
      yield (i + 1, lines[i]);
    }
  }

  /// `File.path` separates with `\` on Windows, so every path here is read
  /// through this: comparing a raw path against `owner` would miss on
  /// Windows, the owner file would be scanned, and its own — permitted —
  /// calls would fail this test.
  String pathOf(File file) =>
      file.path.replaceAll(Platform.pathSeparator, '/');

  Iterable<File> appSources() =>
      Directory('lib').listSync(recursive: true).whereType<File>().where((f) {
        final path = pathOf(f);
        if (!path.endsWith('.dart')) return false;
        if (path == owner) return false;
        return !generated.any(path.contains);
      });

  test('no screen opens a modal behind the standard ones', () {
    // Arrange
    final offenders = <String>[];

    // Act
    for (final file in appSources()) {
      for (final (number, line) in codeLines(file)) {
        for (final entry in banned.entries) {
          if (entry.value.hasMatch(line)) {
            offenders.add('${pathOf(file)}:$number  ${entry.key}');
          }
        }
      }
    }

    // Assert
    expect(
      offenders,
      isEmpty,
      reason:
          'These build a modal by hand. Use showMostroDialog / MostroDialog '
          'or showMostroSheet / MostroSheet from $owner instead — and if the '
          'body really cannot be one of those, open it with '
          "showMostroSheet(bare: true) so it still takes the app's scrim:\n"
          '${offenders.join('\n')}',
    );
  });

  test('the standard modals are the only door, and there is one of each', () {
    // Arrange
    final source = File(owner).readAsStringSync();

    // Act
    int calls(RegExp pattern) => pattern.allMatches(source).length;

    // Assert — two entry points, one call each. A second `showDialog` here
    // would be a second set of defaults, which is what this file exists to
    // prevent.
    expect(calls(RegExp(r'\breturn showDialog<')), 1);
    expect(calls(RegExp(r'\breturn showModalBottomSheet<')), 1);
  });
}
