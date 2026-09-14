import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/backup_palette.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/features/account/models/backup_rules.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/widgets/backup_widgets.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// 3-step backup (`design_handoff_cuenta_respaldo`, 16a–16d), pushed from the
/// 15c sheet:
///
///   1. Write down the 12 words (16a).
///   2. Tap 3 of them, asked at random (16b/16c).
///   3. Done — the backup is confirmed and persisted (16d).
///
/// `View words` goes back to step 1 keeping what was solved; only a second
/// wrong pick on one word throws the round away (#223). The words live only
/// in this screen's state and are dropped when it is left.
class BackupRitualScreen extends ConsumerStatefulWidget {
  const BackupRitualScreen({
    super.key,
    @visibleForTesting this.debugWords,
    @visibleForTesting this.debugChallenge,
    @visibleForTesting this.debugRandom,
  });

  /// Test-only word source. When non-null, the words come from here instead
  /// of the Rust bridge. Never set in production.
  final List<String>? debugWords;

  /// Test-only positions (0-based) the first round asks, so goldens show a
  /// fixed challenge. Never set in production.
  final List<int>? debugChallenge;

  /// Test-only seed for the option order. Never set in production.
  final math.Random? debugRandom;

  @override
  ConsumerState<BackupRitualScreen> createState() => _BackupRitualScreenState();
}

class _BackupRitualScreenState extends ConsumerState<BackupRitualScreen> {
  late final math.Random _random = widget.debugRandom ?? math.Random();

  int _step = 0;
  List<String>? _words;

  /// The verification round; kept while the user reviews the words.
  BackupVerification? _round;
  bool _confirming = false;

  /// Test-only: the correct word for the slot being verified, or null when no
  /// slot is open. Lets widget tests tap the right or a wrong option despite
  /// the randomised challenge. Never used in production UI.
  @visibleForTesting
  String? get debugCorrectWordForActiveSlot {
    final words = _words;
    final round = _round;
    final slot = round?.activeSlot;
    if (words == null || round == null || slot == null) return null;
    return words[round.challenge[slot]];
  }

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  @override
  void dispose() {
    // Drop the mnemonic from memory as soon as the flow is left.
    _words = null;
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadWords() async {
    try {
      final words =
          widget.debugWords ?? await IdentityService.getMnemonicWords();
      if (!mounted) return;
      if (words.isEmpty) {
        _showMessage(AppLocalizations.of(context).noIdentityFoundMessage);
        Navigator.of(context).pop();
        return;
      }
      setState(() => _words = words);
    } catch (e) {
      // Never log the words themselves; the error alone is safe.
      debugPrint('[backup-ritual] failed to load words: $e');
      if (!mounted) return;
      _showMessage(AppLocalizations.of(context).failedToLoadSecretWordsMessage);
      Navigator.of(context).pop();
    }
  }

  void _toVerify() {
    final words = _words;
    if (words == null) return;
    final challenge = widget.debugChallenge;
    setState(() {
      _round ??=
          challenge == null
              ? BackupVerification.start(words, _random)
              : BackupVerification.forChallenge(words, challenge, _random);
      _step = 1;
    });
  }

  void _reviewWords() => setState(() => _step = 0);

  void _onPick(String word) {
    final words = _words;
    final round = _round;
    if (words == null || round == null) return;
    final (next, outcome) = round.pick(words, word, _random);
    if (outcome == BackupPickOutcome.restart) {
      // Second wrong pick on this word: don't let the user grind through the
      // options by elimination. Back to the words, and a fresh round (#223).
      setState(() {
        _round = null;
        _step = 0;
      });
      _showMessage(
        AppLocalizations.of(context).backupRitualSecondFailureMessage,
      );
      return;
    }
    setState(() => _round = next);
  }

  Future<void> _confirm() async {
    if (!(_round?.isComplete ?? false) || _confirming) return;
    // Read both notifiers up front: the user can still review the words and
    // leave while this awaits, and `ref` is unusable once the state is gone —
    // the backup would be persisted but never marked completed in memory.
    final reminder = ref.read(backupReminderProvider.notifier);
    final completed = ref.read(backupCompletedProvider.notifier);
    setState(() => _confirming = true);
    try {
      await reminder.confirmBackupComplete();
      await completed.markCompleted();
      if (mounted) setState(() => _step = 2);
    } catch (e) {
      debugPrint('[backup-ritual] confirm error: $e');
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).failedToSaveBackupStatusMessage,
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = switch (_step) {
      0 => l10n.backupRitualStep1Title,
      1 => l10n.backupRitualStep2Title,
      _ => l10n.backupRitualStep3Title,
    };

    return PopScope(
      // System back while verifying reviews the words, like the arrow does.
      canPop: _step != 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _reviewWords();
      },
      child: Scaffold(
        backgroundColor: OrderBookPalette.of(context).bg,
        appBar: redesignAppBar(
          context,
          title: title,
          onBack: switch (_step) {
            0 => () => Navigator.of(context).pop(),
            1 => _reviewWords,
            _ => null,
          },
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  redesignSidePadding,
                  0,
                  redesignSidePadding,
                  14,
                ),
                child: BackupProgressBar(step: _step),
              ),
              Expanded(
                child: switch (_step) {
                  0 => _buildWriteDown(l10n),
                  1 => _buildVerify(l10n),
                  _ => _buildDone(l10n),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 16a · Write down ────────────────────────────────────────────────────

  Widget _buildWriteDown(AppLocalizations l10n) {
    final words = _words;
    if (words == null) return const Center(child: CircularProgressIndicator());
    return BackupFillViewport(
      blocks: [const _WriteDownWarning(), _WordsCard(words: words)],
      footer: BackupPrimaryButton(
        label: l10n.wroteThemDownVerifyButton,
        trailing: Icons.arrow_forward_rounded,
        onPressed: _toVerify,
      ),
    );
  }

  // ── 16b / 16c · Verify ──────────────────────────────────────────────────

  Widget _buildVerify(AppLocalizations l10n) {
    final round = _round;
    if (round == null) return const SizedBox.shrink();
    final book = OrderBookPalette.of(context);
    final slot = round.activeSlot;

    return BackupFillViewport(
      gap: 14,
      blocks: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.tapCorrectWordsTitle,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: book.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.verifyInstructionsBody,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: book.textSecondary,
              ),
            ),
          ],
        ),
        _SlotsCard(round: round, activeSlot: slot),
        if (slot != null)
          _OptionsBlock(
            label: l10n.optionsForWordLabel(round.challenge[slot] + 1),
            options: round.options,
            wrongPick: round.wrongPick,
            onPick: _onPick,
          )
        else
          const _AllCorrectLine(),
      ],
      footer: Row(
        children: [
          _ReviewWordsButton(onPressed: _reviewWords),
          const SizedBox(width: 9),
          Expanded(
            child: BackupPrimaryButton(
              label: l10n.confirmButtonLabel,
              loading: _confirming,
              onPressed: round.isComplete ? _confirm : null,
            ),
          ),
        ],
      ),
    );
  }

  // ── 16d · Done ──────────────────────────────────────────────────────────

  Widget _buildDone(AppLocalizations l10n) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    return BackupFillViewport(
      gap: 18,
      centered: true,
      blocks: [
        Center(
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.doneFill,
            ),
            child: Icon(Icons.check_rounded, size: 44, color: pal.accent),
          ),
        ),
        Text(
          l10n.accountBackedUpTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: book.textPrimary,
          ),
        ),
        Text(
          l10n.accountBackedUpBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.55,
            color: book.textSecondary,
          ),
        ),
      ],
      footer: BackupPrimaryButton(
        label: l10n.done,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

// ── 16a pieces ────────────────────────────────────────────────────────────────

class _WriteDownWarning extends StatelessWidget {
  const _WriteDownWarning();

  @override
  Widget build(BuildContext context) {
    final pal = BackupPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: pal.amberFill,
        border: Border.all(color: pal.amberBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 17, color: pal.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: l10n.backupRitualWarningTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: pal.amberTitle,
                ),
                children: [
                  TextSpan(
                    text: l10n.backupRitualWarningBody,
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: pal.amberText,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordsCard extends StatelessWidget {
  const _WordsCard({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackupWordGrid(words: words, large: true),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: pal.noteFill,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  size: 14,
                  color: book.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).wordsHiddenOnLeaveNote,
                    style: TextStyle(fontSize: 12, color: book.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 16b / 16c pieces ──────────────────────────────────────────────────────────

class _SlotsCard extends StatelessWidget {
  const _SlotsCard({required this.round, required this.activeSlot});

  final BackupVerification round;
  final int? activeSlot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OrderBookPalette.of(context).surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (var i = 0; i < round.challenge.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _SlotRow(
              wordNumber: round.challenge[i] + 1,
              value: round.answers[i],
              active: i == activeSlot,
            ),
          ],
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.wordNumber,
    required this.value,
    required this.active,
  });

  /// 1-based position of the word in the mnemonic.
  final int wordNumber;
  final String? value;
  final bool active;

  /// Fixed so `Word #12` never wraps onto a second line.
  static const _labelWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    final solved = value != null;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color:
            solved
                ? pal.slotDoneFill
                : active
                ? pal.slotActiveFill
                : pal.slotFill,
        border: Border.all(
          width: 1.5,
          color:
              solved
                  ? pal.slotDoneBorder
                  : active
                  ? pal.accent
                  : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(
              AppLocalizations.of(context).wordNumberLabel(wordNumber),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: book.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 21,
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    solved
                        ? Text(
                          value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.figures,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: book.limeInk,
                          ),
                        )
                        : Container(width: 16, height: 1.5, color: pal.muted),
              ),
            ),
          ),
          if (solved) Icon(Icons.check_rounded, size: 16, color: pal.accent),
        ],
      ),
    );
  }
}

class _OptionsBlock extends StatelessWidget {
  const _OptionsBlock({
    required this.label,
    required this.options,
    required this.wrongPick,
    required this.onPick,
  });

  final String label;
  final List<String> options;
  final String? wrongPick;
  final ValueChanged<String> onPick;

  static const _gap = 9.0;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    final rows = (options.length + 1) ~/ 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.05,
            color: book.textTertiary,
          ),
        ),
        for (var r = 0; r < rows; r++) ...[
          const SizedBox(height: _gap),
          Row(
            children: [
              for (var c = 0; c < 2; c++) ...[
                if (c > 0) const SizedBox(width: _gap),
                Expanded(
                  child:
                      r * 2 + c < options.length
                          ? _OptionTile(
                            word: options[r * 2 + c],
                            wrong: options[r * 2 + c] == wrongPick,
                            onTap: () => onPick(options[r * 2 + c]),
                          )
                          : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
        if (wrongPick != null) ...[
          const SizedBox(height: _gap),
          Text(
            AppLocalizations.of(context).wrongPickMessage,
            style: TextStyle(fontSize: 12, color: pal.wrong),
          ),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.word,
    required this.wrong,
    required this.onTap,
  });

  final String word;
  final bool wrong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: wrong ? pal.wrong : pal.optionBorder),
    );
    return Material(
      color: pal.optionFill,
      shape: shape,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Text(
            word,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: book.textStrong,
            ),
          ),
        ),
      ),
    );
  }
}

class _AllCorrectLine extends StatelessWidget {
  const _AllCorrectLine();

  @override
  Widget build(BuildContext context) {
    final pal = BackupPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline_rounded, size: 15, color: pal.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            AppLocalizations.of(context).allWordsCorrectMessage,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: OrderBookPalette.of(context).limeInk,
            ),
          ),
        ),
      ],
    );
  }
}

/// `View words`: back to 16a, keeping what was solved.
class _ReviewWordsButton extends StatelessWidget {
  const _ReviewWordsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.visibility_outlined, size: 15),
      label: Text(
        AppLocalizations.of(context).reviewWordsButton,
        maxLines: 1,
        softWrap: false,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: book.textMuted,
        side: BorderSide(color: pal.secondaryBorder),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
