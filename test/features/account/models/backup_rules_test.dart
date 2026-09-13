import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/account/models/backup_rules.dart';

const _words = <String>[
  'prefer',
  'olympic',
  'float',
  'negative',
  'alarm',
  'mechanic',
  'capital',
  'because',
  'sausage',
  'struggle',
  'travel',
  'trade',
];

void main() {
  group('backupWordNumber', () {
    test('zero-pads single-digit positions', () {
      expect(backupWordNumber(0), '01');
      expect(backupWordNumber(8), '09');
    });

    test('keeps two-digit positions as they are', () {
      expect(backupWordNumber(11), '12');
    });
  });

  group('buildBackupOptions', () {
    test(
      'offers the right word and three distinct decoys from the mnemonic',
      () {
        for (var seed = 0; seed < 50; seed++) {
          final options = buildBackupOptions(_words, 4, math.Random(seed));

          expect(options, hasLength(backupOptionCount));
          expect(options.toSet(), hasLength(backupOptionCount));
          expect(options, contains('alarm'));
          expect(options.every(_words.contains), isTrue);
        }
      },
    );

    test('pads with fallback decoys when the mnemonic repeats one word', () {
      final repeated = List.filled(12, 'abandon');

      final options = buildBackupOptions(repeated, 0, math.Random(1));

      expect(options, hasLength(backupOptionCount));
      expect(options.toSet(), hasLength(backupOptionCount));
      expect(options, contains('abandon'));
    });
  });

  group('BackupVerification', () {
    test('start asks three distinct ascending positions', () {
      for (var seed = 0; seed < 50; seed++) {
        final round = BackupVerification.start(_words, math.Random(seed));

        expect(round.challenge, hasLength(backupChallengeSize));
        expect(round.challenge.toSet(), hasLength(backupChallengeSize));
        expect(round.challenge, orderedEquals([...round.challenge]..sort()));
        expect(round.activeSlot, 0);
        expect(round.options, contains(_words[round.challenge.first]));
        expect(round.isComplete, isFalse);
      }
    });

    test('a right pick solves the slot and moves to the next one', () {
      final random = math.Random(3);
      final round = BackupVerification.forChallenge(_words, const [
        1,
        5,
        8,
      ], random);

      final (next, outcome) = round.pick(_words, 'olympic', random);

      expect(outcome, BackupPickOutcome.correct);
      expect(next.answers, ['olympic', null, null]);
      expect(next.activeSlot, 1);
      expect(next.options, contains('mechanic'));
      expect(round.answers, [null, null, null], reason: 'round is immutable');
    });

    test('a first wrong pick keeps the slot open and remembers the pick', () {
      final random = math.Random(3);
      final round = BackupVerification.forChallenge(_words, const [
        1,
        5,
        8,
      ], random);

      final (next, outcome) = round.pick(_words, 'trade', random);

      expect(outcome, BackupPickOutcome.wrong);
      expect(next.activeSlot, 0);
      expect(next.wrongPick, 'trade');
      expect(next.misses, 1);
    });

    test('a second wrong pick on the same word restarts the round', () {
      final random = math.Random(3);
      final round = BackupVerification.forChallenge(_words, const [
        1,
        5,
        8,
      ], random);

      final (once, _) = round.pick(_words, 'trade', random);
      final (_, outcome) = once.pick(_words, 'travel', random);

      expect(outcome, BackupPickOutcome.restart);
    });

    test('a right pick resets the miss budget for the next word', () {
      final random = math.Random(3);
      final round = BackupVerification.forChallenge(_words, const [
        1,
        5,
        8,
      ], random);

      final (missed, _) = round.pick(_words, 'trade', random);
      final (solved, _) = missed.pick(_words, 'olympic', random);
      final (_, outcome) = solved.pick(_words, 'trade', random);

      expect(solved.misses, 0);
      expect(solved.wrongPick, isNull);
      expect(outcome, BackupPickOutcome.wrong);
    });

    test('solving all three completes the round and clears the options', () {
      final random = math.Random(3);
      var round = BackupVerification.forChallenge(_words, const [
        1,
        5,
        8,
      ], random);

      for (final word in ['olympic', 'mechanic', 'sausage']) {
        (round, _) = round.pick(_words, word, random);
      }

      expect(round.isComplete, isTrue);
      expect(round.activeSlot, isNull);
      expect(round.options, isEmpty);
    });
  });
}
