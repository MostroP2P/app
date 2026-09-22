import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/widgets/language_selector.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The `lib/l10n/app_*.arb` files are the one source of truth for which
/// languages the app speaks. A few places outside Dart still have to name
/// every language themselves; each test below holds one of them to the ARB
/// set, so adding or dropping a language cannot miss one silently.
///
/// Walkthrough highlights are checked per locale in highlight_config_test.dart.
Set<String> _arbLocales() {
  final locales = {
    for (final f in Directory('lib/l10n').listSync())
      if (RegExp(r'app_([a-z]{2})\.arb$').firstMatch(f.path) case final m?)
        m.group(1)!,
  };
  expect(locales, isNotEmpty, reason: 'no app_*.arb files in lib/l10n');
  return locales;
}

/// The single match of [pattern] in [path], or a failure naming the file.
String _one(String path, RegExp pattern) {
  final matches = pattern.allMatches(File(path).readAsStringSync()).toList();
  expect(matches, hasLength(1), reason: '$path: expected one $pattern');
  return matches.single.group(1)!;
}

Set<String> _quoted(String list) => {
  for (final m in RegExp(r'''["'`]([a-z]{2})["'`]''').allMatches(list))
    m.group(1)!,
};

void main() {
  late Set<String> arb;
  setUpAll(() => arb = _arbLocales());

  test('generated supportedLocales match the ARB files (run flutter gen-l10n)',
      () {
    expect(
      {for (final l in AppLocalizations.supportedLocales) l.languageCode},
      arb,
    );
  });

  test('the language picker has a name for every language', () {
    expect(languageNames.keys.toSet(), arb);
  });

  test('Rust SUPPORTED_LOCALES matches the ARB files', () {
    final list = _one(
      'rust/src/api/settings.rs',
      RegExp(r'const SUPPORTED_LOCALES: &\[&str\] = &\[([^\]]*)\]'),
    );
    expect(_quoted(list), arb);
  });

  test('the web push worker has a notice in every language', () {
    final body = _one(
      'web/push_worker_logic.js',
      RegExp(r'const CHAT_WAKE_BODIES = \{([^}]*)\}'),
    );
    final keys = {
      for (final m in RegExp(r'^\s*([a-z]{2}):', multiLine: true)
          .allMatches(body))
        m.group(1)!,
    };
    expect(keys, arb);
  });

  test('announcement spec 006 requires exactly the ARB languages', () {
    final line = _one(
      'specs/006-announcement-channel/spec.md',
      RegExp(r'must contain \*\*exactly\*\* ([^.]*)\.'),
    );
    expect(_quoted(line), arb);
  });

  test('announcement spec 006 example carries exactly the ARB languages', () {
    final example = _one(
      'specs/006-announcement-channel/spec.md',
      RegExp(r'```json\n(\{.*?\})\n```', dotAll: true),
    );
    final locales = (jsonDecode(example) as Map<String, dynamic>)['locales']
        as Map<String, dynamic>;
    expect(locales.keys.toSet(), arb);
  });
}
