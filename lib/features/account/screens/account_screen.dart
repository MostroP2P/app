import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/backup_palette.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/account/widgets/backup_trigger_sheet.dart';
import 'package:mostro/features/account/widgets/backup_widgets.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/session_provider.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

/// Account — Route `/key_management` (`design_handoff_cuenta_respaldo`,
/// 15a not backed up · 15b backed up).
///
/// The amber banner and the secret-words card are two roads to one task, so
/// exactly one renders: the banner until the words are backed up (it opens
/// the 15c sheet), the card afterwards. The words stay masked until the user
/// taps `Show words` and are masked again when the screen is left; revealing
/// them asks for no confirmation, since the backup flow already took it.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key, @visibleForTesting this.debugWords});

  /// Test-only word source for `Show words`, so widget tests do not reach the
  /// Rust bridge. Never set in production.
  final List<String>? debugWords;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  /// The revealed mnemonic; null while masked.
  List<String>? _words;
  bool _loadingWords = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    // Drop the mnemonic from memory as soon as the screen is left.
    _words = null;
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _revealWords() async {
    if (_loadingWords) return;
    setState(() => _loadingWords = true);
    final l10n = AppLocalizations.of(context);
    try {
      final words =
          widget.debugWords ?? await IdentityService.getMnemonicWords();
      if (!mounted) return;
      if (words.isEmpty) {
        _showMessage(l10n.noIdentityFoundMessage);
        return;
      }
      setState(() => _words = words);
    } catch (e) {
      // Never log the words themselves; the error alone is safe.
      debugPrint('[account] reveal words error: $e');
      if (mounted) {
        _showMessage(
          kDebugMode
              ? 'Failed to load secret words: $e'
              : l10n.failedToLoadSecretWordsMessage,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingWords = false);
    }
  }

  void _hideWords() {
    _copiedTimer?.cancel();
    setState(() {
      _words = null;
      _copied = false;
    });
  }

  Future<void> _copyWords() async {
    final words = _words;
    if (words == null) return;
    await Clipboard.setData(ClipboardData(text: words.join(' ')));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(backupCopyFeedback, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final backedUp = ref.watch(backupCompletedProvider);
    final privacyMode = ref.watch(privacyModeProvider);

    return Scaffold(
      backgroundColor: OrderBookPalette.of(context).bg,
      appBar: redesignAppBar(
        context,
        title: l10n.accountScreenTitle,
        onBack:
            () => context.canPop() ? context.pop() : context.go(AppRoute.home),
      ),
      // #267: SafeArea keeps the Import/Refresh row clear of the system
      // navigation bar.
      body: SafeArea(
        top: false,
        child: BackupFillViewport(
          gap: 11,
          blocks: [
            if (backedUp)
              _SecretWordsCard(
                words: _words,
                loading: _loadingWords,
                copied: _copied,
                onReveal: _revealWords,
                onHide: _hideWords,
                onCopy: _copyWords,
              )
            else
              _BackupBanner(onTap: () => showBackupTriggerSheet(context)),
            _PrivacyCard(
              privacyMode: privacyMode,
              onSelect:
                  (enabled) => ref
                      .read(privacyModeProvider.notifier)
                      .setPrivacyMode(enabled),
              onInfo:
                  () => _showInfoDialog(
                    context,
                    l10n.privacyModesInfoTitle,
                    l10n.privacyModesInfoContent,
                  ),
            ),
          ],
          footer: _AccountActions(
            onGenerate: () => _confirmGenerateNewUser(context),
            onImport: () => _showImportDialog(context),
            onRefresh: () => _confirmRefresh(context),
          ),
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title, String content) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
    );
  }

  /// A new or imported identity is, by definition, not backed up: mask the
  /// old words, re-arm the reminder and clear the backed-up flag, then go
  /// home. The identity has already been replaced when this runs, so a reset
  /// that fails is reported as a backup-status failure, not as a failed
  /// generation or import, and never keeps the other reset from running.
  Future<void> _finishIdentitySwap(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    _copiedTimer?.cancel();
    setState(() {
      _words = null;
      _copied = false;
    });
    ref.read(sessionProvider.notifier).clearSession();
    final reminder = ref.read(backupReminderProvider.notifier);
    final completed = ref.read(backupCompletedProvider.notifier);

    var resetFailed = false;
    for (final reset in [reminder.showBackupReminder, completed.reset]) {
      try {
        await reset();
      } catch (e) {
        debugPrint('[account] backup state reset error: $e');
        resetFailed = true;
      }
    }

    if (!context.mounted) return;
    if (resetFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToSaveBackupStatusMessage)),
      );
    }
    context.go(AppRoute.home);
  }

  void _confirmGenerateNewUser(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.generateNewUserDialogTitle),
            content: Text(l10n.generateNewUserDialogContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ).withAutomationId(AutomationIds.keysGenerateCancel),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  try {
                    // Atomically replaces the stored identity: new mnemonic is
                    // written before old data is cleared, so there is no window
                    // where the user is left without a valid identity.
                    await IdentityService.regenerate();
                  } catch (e) {
                    debugPrint('[account] generateNewUser error: $e');
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          kDebugMode
                              ? 'Failed to generate identity: $e'
                              : l10n.failedToGenerateIdentityMessage,
                        ),
                      ),
                    );
                    return;
                  }
                  // Only reset and navigate once the new identity exists.
                  if (!context.mounted) return;
                  await _finishIdentitySwap(context);
                },
                child: Text(l10n.continueButtonLabel),
              ).withAutomationId(AutomationIds.keysGenerateConfirm),
            ],
          ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => _ImportMnemonicDialog(
            onImport: (words) => _importIdentity(context, words),
          ),
    );
  }

  Future<void> _importIdentity(BuildContext context, List<String> words) async {
    final l10n = AppLocalizations.of(context);
    try {
      await IdentityService.importAndStore(words);
    } catch (e) {
      debugPrint('[account] importIdentity error: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kDebugMode ? 'Import failed: $e' : l10n.invalidMnemonicMessage,
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await _finishIdentitySwap(context);
  }

  void _confirmRefresh(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.refreshUserDialogTitle),
            content: Text(l10n.refreshUserDialogContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  try {
                    await orders_api.restartOrdersSubscription();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.orderBookRefreshedMessage)),
                    );
                  } catch (e) {
                    debugPrint('[account] refresh error: $e');
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          kDebugMode
                              ? 'Refresh failed: $e'
                              : l10n.refreshFailedMessage,
                        ),
                      ),
                    );
                  }
                },
                child: Text(l10n.refreshButtonLabel),
              ),
            ],
          ),
    );
  }
}

// ── 15a · Banner ──────────────────────────────────────────────────────────────

/// `Secure your reputation`, shown until the words are backed up. Opens the
/// 15c sheet.
class _BackupBanner extends StatelessWidget {
  const _BackupBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: pal.amberBorder),
    );

    return Semantics(
      button: true,
      child: Material(
        color: pal.amberFill,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 20, color: pal.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.backupBannerTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: pal.amberTitle,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.backupBannerSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: book.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: book.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 15b · Secret words ────────────────────────────────────────────────────────

class _SecretWordsCard extends StatelessWidget {
  const _SecretWordsCard({
    required this.words,
    required this.loading,
    required this.copied,
    required this.onReveal,
    required this.onHide,
    required this.onCopy,
  });

  /// Null while masked.
  final List<String>? words;
  final bool loading;
  final bool copied;
  final VoidCallback onReveal;
  final VoidCallback onHide;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return _Card(
      padding: const EdgeInsets.all(14),
      gap: 9,
      children: [
        _CardHeader(
          icon: Icons.key_rounded,
          title: l10n.secretWordsTitle,
          trailing: const _BackedUpChip(),
        ),
        BackupWordGrid(words: words),
        if (words == null)
          Material(
            color: pal.revealFill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: BorderSide(color: pal.revealBorder),
            ),
            child: InkWell(
              onTap: loading ? null : onReveal,
              borderRadius: BorderRadius.circular(13),
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: book.limeText,
                        ),
                      )
                    else
                      Icon(
                        Icons.visibility_outlined,
                        size: 15,
                        color: book.limeText,
                      ),
                    const SizedBox(width: 7),
                    Text(
                      l10n.showWordsButton,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: book.limeText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).withAutomationId(AutomationIds.keysSeedReveal)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _WordsLink(
                icon: Icons.visibility_off_outlined,
                label: l10n.hideButtonLabel,
                onTap: onHide,
              ),
              const SizedBox(width: 18),
              _WordsLink(
                icon: copied ? Icons.check_rounded : Icons.copy_rounded,
                label: l10n.copyButtonLabel,
                onTap: onCopy,
              ),
            ],
          ),
      ],
    );
  }
}

class _BackedUpChip extends StatelessWidget {
  const _BackedUpChip();

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: pal.chipFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 11, color: pal.accent),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).backedUpBadgeLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: book.limeInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// `Hide` / `Copy` under the revealed grid.
class _WordsLink extends StatelessWidget {
  const _WordsLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = OrderBookPalette.of(context).textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Privacy ───────────────────────────────────────────────────────────────────

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({
    required this.privacyMode,
    required this.onSelect,
    required this.onInfo,
  });

  final bool privacyMode;
  final ValueChanged<bool> onSelect;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      gap: 12,
      children: [
        _CardHeader(
          icon: Icons.shield_outlined,
          title: l10n.privacyCardTitle,
          trailing: IconButton(
            onPressed: onInfo,
            icon: Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: book.textTertiary,
            ),
            tooltip: l10n.moreInformationTooltip,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
          ),
        ),
        _PrivacyOption(
          title: l10n.reputationMode,
          subtitle: l10n.reputationModeSubtitle,
          selected: !privacyMode,
          onTap: () => onSelect(false),
        ),
        _PrivacyOption(
          title: l10n.fullPrivacyMode,
          subtitle: l10n.fullPrivacyModeSubtitle,
          selected: privacyMode,
          onTap: () => onSelect(true),
        ),
      ],
    );
  }
}

class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);

    return Semantics(
      label: title,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 17,
              height: 17,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? pal.accent : pal.muted,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child:
                  selected
                      ? Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: pal.accent,
                          shape: BoxShape.circle,
                        ),
                      )
                      : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: book.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: book.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Buttons ───────────────────────────────────────────────────────────────────

class _AccountActions extends StatelessWidget {
  const _AccountActions({
    required this.onGenerate,
    required this.onImport,
    required this.onRefresh,
  });

  final VoidCallback onGenerate;
  final VoidCallback onImport;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final outline = OutlinedButton.styleFrom(
      foregroundColor: book.limeText,
      side: BorderSide(color: pal.outlineBorder),
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BackupPrimaryButton(
          label: l10n.generateNewUserButton,
          leading: Icons.person_add_alt_1_outlined,
          onPressed: onGenerate,
        ).withAutomationId(AutomationIds.keysGenerate),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.download_rounded, size: 15),
                label: Text(l10n.importMostroUserButton),
                style: outline.copyWith(
                  padding: const WidgetStatePropertyAll(EdgeInsets.all(13)),
                ),
              ).withAutomationId(AutomationIds.keysImport),
            ),
            const SizedBox(width: 9),
            OutlinedButton(
              onPressed: onRefresh,
              style: outline.copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              child: Icon(
                Icons.refresh_rounded,
                size: 16,
                semanticLabel: l10n.refreshButtonLabel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Shared card pieces ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({
    required this.padding,
    required this.gap,
    required this.children,
  });

  final EdgeInsets padding;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: OrderBookPalette.of(context).surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: BackupPalette.of(context).accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: OrderBookPalette.of(context).textStrong,
            ),
          ),
        ),
        trailing,
      ],
    );
  }
}

// ── Import mnemonic dialog ─────────────────────────────────────────────────────

/// Self-contained dialog that owns its [TextEditingController] lifecycle,
/// preventing the controller from being disposed while the [TextField] is
/// still mounted.
class _ImportMnemonicDialog extends StatefulWidget {
  const _ImportMnemonicDialog({required this.onImport});

  final void Function(List<String> words) onImport;

  @override
  State<_ImportMnemonicDialog> createState() => _ImportMnemonicDialogState();
}

class _ImportMnemonicDialogState extends State<_ImportMnemonicDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final words =
        _controller.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
    final validLength = words.length == 12 || words.length == 24;
    final validWords = words.every((w) => RegExp(r'^[a-zA-Z]+$').hasMatch(w));
    if (!validLength || !validWords) {
      setState(
        () => _error = AppLocalizations.of(context).enterValidMnemonicError,
      );
      return;
    }
    Navigator.pop(context);
    widget.onImport(words);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.importMnemonicDialogTitle),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        decoration: InputDecoration(
          hintText: l10n.importMnemonicHintText,
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.importButtonLabel)),
      ],
    );
  }
}
