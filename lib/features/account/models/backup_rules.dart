import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What a masked word shows on the Account screen (15b).
const backupWordMask = '••••••••';

/// Words asked back in the verification step (16b).
const backupChallengeSize = 3;

/// Options offered for the word being verified: the right one and decoys.
const backupOptionCount = 4;

/// Wrong picks on one word that send the user back to their words (#223).
const backupMaxMisses = 2;

/// Decoys used only when the mnemonic itself has too few distinct words to
/// fill the options (a degenerate mnemonic with repeated words).
const _fallbackDecoys = [
  'mountain',
  'river',
  'orange',
  'planet',
  'silver',
  'garden',
  'rocket',
  'candle',
];

/// `01`…`12`: the position of word [index] (0-based), zero-padded.
String backupWordNumber(int index) => (index + 1).toString().padLeft(2, '0');

/// [backupOptionCount] options for word [wordIndex] of [words], shuffled: the
/// right word plus decoys drawn from the mnemonic itself, so a decoy never
/// gives itself away by not being one of the user's words.
List<String> buildBackupOptions(
  List<String> words,
  int wordIndex,
  math.Random random,
) {
  final correct = words[wordIndex];
  final decoys = <String>{};
  for (final w in [...List.of(words)..shuffle(random), ..._fallbackDecoys]) {
    if (decoys.length == backupOptionCount - 1) break;
    if (w != correct) decoys.add(w);
  }
  return [correct, ...decoys]..shuffle(random);
}

/// What a pick did to the verification.
enum BackupPickOutcome {
  /// Right word: its slot is solved.
  correct,

  /// Wrong word, first miss on it: the user may try again.
  wrong,

  /// Second miss on the same word: the round is over and the user goes back
  /// to their words (#223).
  restart,
}

/// One round of the verification step (16b/16c): which words are asked, what
/// has been answered and the options for the word being asked.
///
/// Immutable — [pick] returns the next round. Leaving for the words
/// (`View words`) keeps the round; only [BackupPickOutcome.restart] drops it.
@immutable
class BackupVerification {
  const BackupVerification._({
    required this.challenge,
    required this.answers,
    required this.options,
    required this.misses,
    this.wrongPick,
  });

  /// A fresh round over [words]: [backupChallengeSize] distinct positions,
  /// ascending, the first one active.
  factory BackupVerification.start(List<String> words, math.Random random) {
    final positions = <int>{};
    final size = math.min(backupChallengeSize, words.length);
    while (positions.length < size) {
      positions.add(random.nextInt(words.length));
    }
    return BackupVerification.forChallenge(
      words,
      positions.toList()..sort(),
      random,
    );
  }

  /// A fresh round asking exactly [challenge] (0-based positions).
  factory BackupVerification.forChallenge(
    List<String> words,
    List<int> challenge,
    math.Random random,
  ) {
    return BackupVerification._(
      challenge: List.unmodifiable(challenge),
      answers: List.unmodifiable(List<String?>.filled(challenge.length, null)),
      options:
          challenge.isEmpty
              ? const []
              : List.unmodifiable(
                buildBackupOptions(words, challenge.first, random),
              ),
      misses: 0,
    );
  }

  /// Positions asked, 0-based and ascending.
  final List<int> challenge;

  /// The word placed in each slot of [challenge], or null while open.
  final List<String?> answers;

  /// Options for the active slot; empty once every slot is solved.
  final List<String> options;

  /// Wrong picks on the word being asked.
  final int misses;

  /// The last wrong option picked, until the next pick.
  final String? wrongPick;

  /// Index into [challenge] of the first open slot, or null when solved.
  int? get activeSlot {
    final i = answers.indexOf(null);
    return i < 0 ? null : i;
  }

  bool get isComplete => challenge.isNotEmpty && activeSlot == null;

  /// The next round after the user picks [word].
  (BackupVerification, BackupPickOutcome) pick(
    List<String> words,
    String word,
    math.Random random,
  ) {
    final slot = activeSlot;
    if (slot == null) return (this, BackupPickOutcome.correct);

    if (word != words[challenge[slot]]) {
      if (misses + 1 >= backupMaxMisses) {
        return (this, BackupPickOutcome.restart);
      }
      return (
        BackupVerification._(
          challenge: challenge,
          answers: answers,
          options: options,
          misses: misses + 1,
          wrongPick: word,
        ),
        BackupPickOutcome.wrong,
      );
    }

    final answered = List<String?>.of(answers)..[slot] = word;
    final next = answered.indexOf(null);
    return (
      BackupVerification._(
        challenge: challenge,
        answers: List.unmodifiable(answered),
        options:
            next < 0
                ? const []
                : List.unmodifiable(
                  buildBackupOptions(words, challenge[next], random),
                ),
        misses: 0,
      ),
      BackupPickOutcome.correct,
    );
  }
}
