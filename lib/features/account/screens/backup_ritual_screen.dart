import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Fallback decoy words for the verification step, used only in the
/// (degenerate) case where the mnemonic itself does not contain enough
/// distinct words to build a 4-option grid.
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

/// 3-step backup ritual (pushed via Navigator from the trigger sheet):
///
///   1. Show the 12 secret words (write them on paper).
///   2. Verify 3 words at random.
///   3. Done — backup confirmed and persisted.
///
/// The words live only in this screen's state and are discarded when the
/// screen is left, restoring the masked behavior of the Account screen.
class BackupRitualScreen extends ConsumerStatefulWidget {
  const BackupRitualScreen({super.key});

  @override
  ConsumerState<BackupRitualScreen> createState() => _BackupRitualScreenState();
}

class _BackupRitualScreenState extends ConsumerState<BackupRitualScreen> {
  final _random = math.Random();

  int _step = 0;
  List<String>? _words;

  // ── Verification state ──
  /// The 3 challenged word positions (0-based, sorted ascending).
  List<int> _challenge = const [];

  /// User answers per challenge slot; null = not answered yet.
  List<String?> _filled = [null, null, null];

  /// Index into [_challenge] of the slot currently being answered.
  int _activeSlot = 0;

  /// 4 shuffled options for the active slot.
  List<String> _options = const [];

  /// Option the user last tapped incorrectly (cleared on next tap).
  String? _wrongPick;

  /// Wrong-pick counter for the current verification round. On the 2nd wrong
  /// pick the user is sent back to the words screen and verification restarts,
  /// so the confirmation can't be brute-forced by elimination (#204 review).
  int _failCount = 0;

  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  @override
  void dispose() {
    // Drop the mnemonic from memory as soon as the ritual is left.
    _words = null;
    super.dispose();
  }

  Future<void> _loadWords() async {
    try {
      final words = await IdentityService.getMnemonicWords();
      if (!mounted) return;
      if (words.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).noIdentityFoundMessage,
            ),
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      setState(() => _words = words);
    } catch (e) {
      // Never log the words themselves; the error alone is safe.
      debugPrint('[backup-ritual] failed to load words: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).failedToLoadSecretWordsMessage,
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  // ── Challenge generation ────────────────────────────────────────────────

  void _startVerification() {
    final words = _words;
    if (words == null) return;
    final indices = <int>{};
    while (indices.length < 3 && indices.length < words.length) {
      indices.add(_random.nextInt(words.length));
    }
    setState(() {
      _challenge = indices.toList()..sort();
      _filled = [null, null, null];
      _activeSlot = 0;
      _wrongPick = null;
      _failCount = 0;
      _options = _buildOptions(_challenge[0]);
      _step = 1;
    });
  }

  List<String> _buildOptions(int wordIndex) {
    final words = _words!;
    final correct = words[wordIndex];
    final decoys = <String>{};
    final pool = List<String>.of(words)..shuffle(_random);
    for (final w in pool) {
      if (decoys.length == 3) break;
      if (w != correct) decoys.add(w);
    }
    // Degenerate mnemonics (repeated words) — pad from a static pool.
    for (final w in _fallbackDecoys) {
      if (decoys.length == 3) break;
      if (w != correct) decoys.add(w);
    }
    return [correct, ...decoys]..shuffle(_random);
  }

  void _onOptionTap(String word) {
    final words = _words;
    if (words == null || _activeSlot >= _challenge.length) return;
    final correct = words[_challenge[_activeSlot]];
    if (word == correct) {
      setState(() {
        _filled[_activeSlot] = word;
        _wrongPick = null;
        final next = _filled.indexWhere((w) => w == null);
        if (next != -1) {
          _activeSlot = next;
          _options = _buildOptions(_challenge[next]);
        } else {
          _activeSlot = _challenge.length; // all done
          _options = const [];
        }
      });
    } else {
      _failCount++;
      if (_failCount >= 2) {
        // Second wrong pick this round: don't let the user keep guessing by
        // elimination. Send them back to the 12 words to actually back them
        // up, then restart verification from scratch (#204 review).
        _backToWords();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That was incorrect again. Please review and back up your 12 '
              'words, then verify from the start.',
            ),
          ),
        );
      } else {
        setState(() => _wrongPick = word);
      }
    }
  }

  bool get _allCorrect =>
      _challenge.isNotEmpty && _filled.every((w) => w != null);

  Future<void> _confirm() async {
    if (!_allCorrect || _confirming) return;
    setState(() => _confirming = true);
    try {
      await ref.read(backupReminderProvider.notifier).confirmBackupComplete();
      await ref.read(backupCompletedProvider.notifier).markCompleted();
      if (mounted) setState(() => _step = 2);
    } catch (e) {
      debugPrint('[backup-ritual] confirm error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).failedToSaveBackupStatusMessage,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _backToWords() {
    setState(() {
      _step = 0;
      _challenge = const [];
      _filled = [null, null, null];
      _activeSlot = 0;
      _options = const [];
      _wrongPick = null;
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final elevated = colors?.backgroundElevated ?? const Color(0xFF2A2D35);

    final l10n = AppLocalizations.of(context);
    final title = switch (_step) {
      0 => l10n.backupRitualStep1Title,
      1 => l10n.backupRitualStep2Title,
      _ => l10n.backupRitualStep3Title,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        automaticallyImplyLeading: false,
        leading: _step == 2
            ? null
            : BackButton(
                onPressed: () {
                  if (_step == 1) {
                    _backToWords();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgressBar(step: _step, green: green, elevated: elevated),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: switch (_step) {
                  0 => _buildShowWords(theme, colors),
                  1 => _buildVerify(theme, colors),
                  _ => _buildDone(theme, colors),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1: show words ──────────────────────────────────────────────────

  Widget _buildShowWords(ThemeData theme, AppColors? colors) {
    final l10n = AppLocalizations.of(context);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final elevated = colors?.backgroundElevated ?? const Color(0xFF2A2D35);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final textSubtle = colors?.textSubtle ?? const Color(0xFF9A9A9C);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);

    final words = _words;
    if (words == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _ScrollableStep(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Amber warning card
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.12),
            border: Border.all(color: amber.withValues(alpha: 0.27)),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: amber, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: l10n.backupRitualWarningTitle,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    children: [
                      TextSpan(
                        text: l10n.backupRitualWarningBody,
                        style: const TextStyle(fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: amber, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Words grid card
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            children: [
              for (var row = 0; row < (words.length + 1) ~/ 2; row++) ...[
                if (row > 0) const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      if (col > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: row * 2 + col < words.length
                            ? _WordCell(
                                index: row * 2 + col,
                                word: words[row * 2 + col],
                                background: elevated,
                                indexColor: textSubtle,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                  color: elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.visibility_off_outlined,
                        size: 14, color: textSec),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        l10n.wordsHiddenOnLeaveNote,
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: textSec, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        FilledButton.icon(
          onPressed: _startVerification,
          icon: Text(
            l10n.wroteThemDownVerifyButton,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          label: const Icon(Icons.arrow_forward, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        ],
      ),
    );
  }

  // ── Step 2: verify ──────────────────────────────────────────────────────

  Widget _buildVerify(ThemeData theme, AppColors? colors) {
    final l10n = AppLocalizations.of(context);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final elevated = colors?.backgroundElevated ?? const Color(0xFF2A2D35);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final textSubtle = colors?.textSubtle ?? const Color(0xFF9A9A9C);
    final textDisabled = colors?.textDisabled ?? const Color(0xFF6C757D);
    final red = colors?.destructiveRed ?? const Color(0xFFD84D4D);

    final hasActiveSlot = _activeSlot < _challenge.length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.tapCorrectWordsTitle,
            style: theme.textTheme.titleLarge!
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.verifyInstructionsBody,
            style:
                theme.textTheme.bodySmall!.copyWith(color: textSec, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),

          // Slot rows
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _challenge.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _SlotRow(
                    wordNumber: _challenge[i] + 1,
                    value: _filled[i],
                    isActive: i == _activeSlot,
                    green: green,
                    elevated: elevated,
                    textSubtle: textSubtle,
                    borderColor: textDisabled,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Options for the active slot
          if (hasActiveSlot) ...[
            Text(
              l10n.optionsForWordLabel(_challenge[_activeSlot] + 1),
              style: theme.textTheme.bodySmall!.copyWith(
                color: textSubtle,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var row = 0; row < (_options.length + 1) ~/ 2; row++) ...[
              if (row > 0) const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: row * 2 + col < _options.length
                          ? _OptionButton(
                              word: _options[row * 2 + col],
                              isWrong: _options[row * 2 + col] == _wrongPick,
                              cardBg: cardBg,
                              red: red,
                              borderColor: textDisabled.withValues(alpha: 0.4),
                              onTap: () =>
                                  _onOptionTap(_options[row * 2 + col]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
            if (_wrongPick != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.wrongPickMessage,
                style: theme.textTheme.bodySmall!
                    .copyWith(color: red, fontSize: 12),
              ),
            ],
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: green),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.allWordsCorrectMessage,
                  style: theme.textTheme.bodySmall!.copyWith(color: green),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xl),

          // Footer
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _backToWords,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textSec,
                    side: BorderSide(color: textDisabled),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                  child: Text(
                    l10n.showWordsAgainButton,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: _allCorrect && !_confirming ? _confirm : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: elevated,
                    disabledForegroundColor: textDisabled,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                  child: _confirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          l10n.confirmButtonLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 3: done ────────────────────────────────────────────────────────

  Widget _buildDone(ThemeData theme, AppColors? colors) {
    final l10n = AppLocalizations.of(context);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);

    return _ScrollableStep(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        const Spacer(),
        Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: green.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.check_rounded, size: 64, color: green),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          l10n.accountBackedUpTitle,
          textAlign: TextAlign.center,
          style:
              theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.accountBackedUpBody,
          textAlign: TextAlign.center,
          style:
              theme.textTheme.bodyMedium!.copyWith(color: textSec, height: 1.5),
        ),
        const Spacer(),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(54),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(l10n.done),
        ),
        ],
      ),
    );
  }
}

// ── Internal widgets ──────────────────────────────────────────────────────────

/// Makes a step body scrollable on small screens while still letting
/// [Spacer]s push the CTA to the bottom on tall screens.
class _ScrollableStep extends StatelessWidget {
  const _ScrollableStep({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.step,
    required this.green,
    required this.elevated,
  });

  final int step;
  final Color green;
  final Color elevated;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? green : elevated,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WordCell extends StatelessWidget {
  const _WordCell({
    required this.index,
    required this.word,
    required this.background,
    required this.indexColor,
  });

  final int index;
  final String word;
  final Color background;
  final Color indexColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            (index + 1).toString().padLeft(2, '0'),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: indexColor,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              word,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.wordNumber,
    required this.value,
    required this.isActive,
    required this.green,
    required this.elevated,
    required this.textSubtle,
    required this.borderColor,
  });

  /// 1-based position of the word in the mnemonic.
  final int wordNumber;
  final String? value;
  final bool isActive;
  final Color green;
  final Color elevated;
  final Color textSubtle;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final filled = value != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: filled ? green.withValues(alpha: 0.12) : elevated,
        border: Border.all(
          color: filled
              ? green.withValues(alpha: 0.4)
              : isActive
                  ? green.withValues(alpha: 0.5)
                  : borderColor.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              AppLocalizations.of(context).wordNumberLabel(wordNumber),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textSubtle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value ?? '—',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: filled ? green : textSubtle,
              ),
            ),
          ),
          if (filled) Icon(Icons.check, size: 18, color: green),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.word,
    required this.isWrong,
    required this.cardBg,
    required this.red,
    required this.borderColor,
    required this.onTap,
  });

  final String word;
  final bool isWrong;
  final Color cardBg;
  final Color red;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: isWrong ? red : borderColor),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Text(
            word,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isWrong ? red : null,
            ),
          ),
        ),
      ),
    );
  }
}
