import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two things about `lib/core/app_bootstrap.dart` that cannot be executed
/// in a unit test — reaching `bootstrapAndRun` needs Rust, preferences and
/// relays, i.e. the whole app assembled to watch it fail to assemble.
///
/// Everything about the sequence itself is behavioural, in
/// startup_sequence_test.dart. These two are here for the same reason
/// test/web/pages_bundle_test.dart exists: greps are the only tool available,
/// and both of these are silent when wrong.
void main() {
  final source = File('lib/core/app_bootstrap.dart').readAsStringSync();

  group('startup guard (#389)', () {
    test('a failure reaches runApp, naming the step that failed', () {
      // Without this the sequence throws, runApp never runs, and Flutter paints
      // nothing — not a broken page, an absent one. #227 is the precedent that
      // motivated the guard, not a case it covers: that crash happens inside
      // the engine's own bootstrap, before main() runs (#370).
      // Two independent substrings rather than one exact call: the literal
      // broke the first time an argument was added to it, which is the failure
      // mode of a grep and the reason only two are left in this file.
      expect(
        source.contains('runApp(StartupFailureApp('),
        isTrue,
        reason:
            'the last-resort catch must reach runApp with the failure '
            'surface, or a failed startup is a blank page again',
      );
      expect(
        source.contains('step: startup.currentStep'),
        isTrue,
        reason: 'the failure surface must be handed the step that failed',
      );
    });

    test('the local database is opened on the web too (#408)', () {
      // Before #408 this call sat inside `if (!kIsWeb)`, because the web store
      // was a stub. It is not any more: web persistence lives there now, so
      // re-adding that guard — the easy way to resolve a conflict in this
      // file — would quietly take out every web feature built on top of it.
      const label = "startup.optional('opening the local database'";
      final start = source.indexOf(label);
      expect(start, greaterThanOrEqualTo(0), reason: 'the step went missing');

      final end = source.indexOf('});', start);
      expect(end, greaterThan(start), reason: 'could not delimit the step');
      final block = source.substring(start, end);

      expect(
        block.contains('rust_api.initDb('),
        isTrue,
        reason: 'the database is not opened in the step named for it',
      );
      expect(
        RegExp(r'if\s*\(\s*!\s*kIsWeb\s*\)').hasMatch(block),
        isFalse,
        reason:
            'initDb must not be skipped on the web: since #408 that is '
            'where web persistence lives (#233)',
      );
    });
  });
}
