import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/startup_failure.dart';
import 'package:mostro/core/startup_sequence.dart';

void main() {
  group('startup guard (#389)', () {
    test('a failure reaches runApp, naming the step that failed', () async {
      // Without this the sequence throws, runApp never runs, and Flutter paints
      // nothing — not a broken page, an absent one.
      final calls = <String>[];
      Widget? painted;
      Object? reported;
      final boom = StateError('boom');

      await runGuarded(
        (startup) async {
          await startup.optional('opening the local database', () async {});
          await startup.required('building the interface', () async {
            throw boom;
          });
        },
        run: (app) {
          calls.add('run');
          painted = app;
        },
        onFailed: (e) {
          calls.add('onFailed');
          reported = e;
        },
      );

      expect(
        painted,
        isA<StartupFailureApp>()
            .having((a) => a.step, 'step', 'building the interface')
            .having((a) => a.error, 'error', same(boom)),
        reason: 'the failure surface must be painted with the step that failed',
      );
      expect(reported, same(boom), reason: 'CI must be handed the cause');
      expect(
        calls,
        ['run', 'onFailed'],
        reason:
            'the screen goes first: if reporting to CI threw, the person would '
            'be left with a blank page',
      );
    });

    test('a startup that succeeds paints nothing from the guard', () async {
      var ran = false;
      await runGuarded(
        (startup) => startup.required('loading the engine', () async {}),
        run: (_) => ran = true,
        onFailed: (_) => ran = true,
      );
      expect(ran, isFalse, reason: 'the failure surface is for failures only');
    });

    test('startup calls openDatabase with nothing skipping it on the web '
        '(#408)', () {
      // Before #408 this call sat inside `if (!kIsWeb)`, because the web store
      // was a stub. It is not any more: web persistence lives there now, so
      // re-adding that guard — the easy way to resolve a conflict in this
      // file — would quietly take out every web feature built on top of it.
      //
      // What openDatabase does is executed in db_location_test.dart. This grep
      // covers only the call site, on purpose: running it means running all of
      // startup with ~20 Rust calls faked, far more code than the one line it
      // protects.
      final source = File('lib/core/app_bootstrap.dart').readAsStringSync();
      const label = "startup.optional('opening the local database'";
      final start = source.indexOf(label);
      expect(start, greaterThanOrEqualTo(0), reason: 'the step went missing');

      final end = source.indexOf('});', start);
      expect(end, greaterThan(start), reason: 'could not delimit the step');
      final block = source.substring(start, end);

      expect(
        block.contains('openDatabase('),
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
