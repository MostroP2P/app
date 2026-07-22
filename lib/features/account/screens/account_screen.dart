import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/account/widgets/backup_trigger_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/session_provider.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

/// Account screen — Route `/key_management`.
///
/// Shows: Secret Words card, Privacy card, Generate New User,
/// Import User, and Refresh User buttons.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  // Secret words state
  bool _wordsVisible = false;
  bool _showBackupCheckbox = false;
  List<String>? _words;
  bool _loadingWords = false;

  /// All 12 words are hidden until the user explicitly taps "Show".
  String _fullyMaskedPhrase() => List.filled(12, '•••').join(' ');

  Future<void> _loadAndRevealWords() async {
    if (_loadingWords) return;
    setState(() => _loadingWords = true);
    final l10n = AppLocalizations.of(context);

    try {
      final words = await IdentityService.getMnemonicWords();

      if (!mounted) return;
      if (words.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.noIdentityFoundMessage),
          ),
        );
        return;
      }
      final backupPending = ref.read(backupReminderProvider);
      setState(() {
        _wordsVisible = true;
        _showBackupCheckbox = backupPending;
        _words = words;
      });
      // Backup is NOT confirmed here — user must tick the checkbox explicitly.
    } catch (e) {
      debugPrint('[account] _loadAndRevealWords error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kDebugMode
                  ? 'Failed to load secret words: $e'
                  : l10n.failedToLoadSecretWordsMessage,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingWords = false);
    }
  }

  Future<void> _confirmBackup() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(backupReminderProvider.notifier).confirmBackupComplete();
      await ref.read(backupCompletedProvider.notifier).markCompleted();
      if (mounted) setState(() => _showBackupCheckbox = false);
    } catch (e) {
      debugPrint('[account] _confirmBackup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kDebugMode
                  ? 'Failed to confirm backup: $e'
                  : l10n.failedToConfirmBackupMessage,
            ),
          ),
        );
      }
      // Rethrow so _BackupConfirmRowState._handleConfirm sees the failure
      // and leaves the checkbox unchecked for retry.
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final l10n = AppLocalizations.of(context);
    final privacyMode = ref.watch(privacyModeProvider);
    final backupPending = ref.watch(backupReminderProvider);
    final backupDone = ref.watch(backupCompletedProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountScreenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── Backup ritual banner — entry point for the 3-step backup
          // flow while the backup reminder is active.
          if (backupPending) ...[
            _BackupRitualBanner(
              onTap: () => showBackupTriggerSheet(context),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── Secret Words Card ──────────────────────────────────────────
          _SectionCard(
            color: cardBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHeader(
                  icon: Icons.key,
                  iconColor: green,
                  title: l10n.secretWordsTitle,
                  badge: backupDone ? _BackedUpBadge(green: green) : null,
                  onInfo:
                      () => _showInfoDialog(
                        context,
                        l10n.secretWordsTitle,
                        l10n.secretWordsInfoContent,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.toRestoreYourAccount,
                  style: theme.textTheme.bodySmall!.copyWith(color: textSec),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _wordsVisible && _words != null
                          ? SelectableText(
                            _words!.join(' '),
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontFamily: 'monospace',
                              height: 1.6,
                            ),
                          )
                          : Text(
                            _fullyMaskedPhrase(),
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontFamily: 'monospace',
                              height: 1.6,
                            ),
                          ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child:
                            _loadingWords
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : TextButton.icon(
                                  onPressed:
                                      _wordsVisible
                                          ? () => setState(() {
                                            _wordsVisible = false;
                                            _showBackupCheckbox = false;
                                          })
                                          : _loadAndRevealWords,
                                  icon: Icon(
                                    _wordsVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 16,
                                    color: green,
                                  ),
                                  label: Text(
                                    _wordsVisible ? l10n.hideButtonLabel : l10n.showButtonLabel,
                                    style: TextStyle(color: green),
                                  ),
                                ),
                      ),
                      // Backup confirmation checkbox — appears when words are
                      // visible and backup has not yet been confirmed.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child:
                            _showBackupCheckbox
                                ? _BackupConfirmRow(
                                  green: green,
                                  onConfirm: _confirmBackup,
                                )
                                : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Privacy Card ───────────────────────────────────────────────
          _SectionCard(
            color: cardBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHeader(
                  icon: Icons.shield_outlined,
                  iconColor: green,
                  title: l10n.privacyCardTitle,
                  onInfo:
                      () => _showInfoDialog(
                        context,
                        l10n.privacyModesInfoTitle,
                        l10n.privacyModesInfoContent,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.controlPrivacySettings,
                  style: theme.textTheme.bodySmall!.copyWith(color: textSec),
                ),
                const SizedBox(height: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PrivacyOption(
                      title: l10n.reputationMode,
                      subtitle: l10n.reputationModeSubtitle,
                      selected: !privacyMode,
                      green: green,
                      onTap:
                          () => ref
                              .read(privacyModeProvider.notifier)
                              .setPrivacyMode(false),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _PrivacyOption(
                      title: l10n.fullPrivacyMode,
                      subtitle: l10n.fullPrivacyModeSubtitle,
                      selected: privacyMode,
                      green: green,
                      onTap:
                          () => ref
                              .read(privacyModeProvider.notifier)
                              .setPrivacyMode(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Generate New User ──────────────────────────────────────────
          FilledButton.icon(
            onPressed: () => _confirmGenerateNewUser(context),
            icon: const Icon(Icons.person_add_outlined),
            label: Text(l10n.generateNewUserButton),
            style: FilledButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Import + Refresh buttons ───────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showImportDialog(context),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l10n.importMostroUserButton),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: green,
                    side: BorderSide(color: green),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => _confirmRefresh(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: green,
                  side: BorderSide(color: green),
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                child: const Icon(Icons.refresh_outlined),
              ),
            ],
          ),
        ],
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
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  try {
                    // Atomically replaces the stored identity: new mnemonic is
                    // written before old data is cleared, so there is no window
                    // where the user is left without a valid identity.
                    await IdentityService.regenerate();
                    ref.read(sessionProvider.notifier).clearSession();
                    await ref
                        .read(backupReminderProvider.notifier)
                        .showBackupReminder();
                    await ref.read(backupCompletedProvider.notifier).reset();
                    // Only clear UI state and navigate once the new identity exists.
                    if (!context.mounted) return;
                    setState(() {
                      _wordsVisible = false;
                      _showBackupCheckbox = false;
                      _words = null;
                    });
                    context.go(AppRoute.home);
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
                  }
                },
                child: Text(l10n.continueButtonLabel),
              ),
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
      ref.read(sessionProvider.notifier).clearSession();
      await ref.read(backupReminderProvider.notifier).showBackupReminder();
      await ref.read(backupCompletedProvider.notifier).reset();
      if (!context.mounted) return;
      setState(() {
        _wordsVisible = false;
        _showBackupCheckbox = false;
        _words = null;
      });
      context.go(AppRoute.home);
    } catch (e) {
      debugPrint('[account] importIdentity error: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kDebugMode
                ? 'Import failed: $e'
                : l10n.invalidMnemonicMessage,
          ),
        ),
      );
    }
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

// ── Internal widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onInfo,
    this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onInfo;

  /// Optional badge shown right after the title (e.g. "Backed up").
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
        ),
        if (badge != null) ...[
          const SizedBox(width: AppSpacing.sm),
          badge!,
        ],
        const Spacer(),
        IconButton(
          onPressed: onInfo,
          icon: const Icon(Icons.info_outline, size: 18),
          tooltip: AppLocalizations.of(context).moreInformationTooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}

// ── Backup ritual banner + badge ──────────────────────────────────────────────

/// Banner shown while the backup reminder is active. Tapping it opens the
/// backup ritual trigger sheet.
class _BackupRitualBanner extends StatelessWidget {
  const _BackupRitualBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final l10n = AppLocalizations.of(context);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            border: Border.all(color: amber.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: amber, size: 24),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.backupBannerTitle,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                        color: amber,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.backupBannerSubtitle,
                      style:
                          theme.textTheme.bodySmall!.copyWith(color: textSec),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small green "Backed up" chip shown in the Secret Words card header once
/// the backup ritual (or legacy checkbox) has been completed.
class _BackedUpBadge extends StatelessWidget {
  const _BackedUpBadge({required this.green});

  final Color green;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 12, color: green),
          const SizedBox(width: 3),
          Text(
            AppLocalizations.of(context).backedUpBadgeLabel,
            style: TextStyle(
              color: green,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Backup confirmation checkbox ──────────────────────────────────────────────

class _BackupConfirmRow extends StatefulWidget {
  const _BackupConfirmRow({required this.green, required this.onConfirm});

  final Color green;
  final Future<void> Function() onConfirm;

  @override
  State<_BackupConfirmRow> createState() => _BackupConfirmRowState();
}

class _BackupConfirmRowState extends State<_BackupConfirmRow> {
  bool _checked = false;
  bool _pending = false;

  Future<void> _handleConfirm() async {
    if (_checked || _pending) return;
    setState(() => _pending = true);
    try {
      await widget.onConfirm();
      if (mounted) setState(() => _checked = true);
    } catch (_) {
      // Parent already shows a SnackBar; leave checkbox unchecked so
      // the user can retry.
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = !_checked && !_pending;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: InkWell(
        onTap: interactive ? _handleConfirm : null,
        borderRadius: BorderRadius.circular(4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child:
                  _pending
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Checkbox(
                        value: _checked,
                        activeColor: widget.green,
                        onChanged: interactive ? (_) => _handleConfirm() : null,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                AppLocalizations.of(context).backupConfirmCheckbox,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.green,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final Color green;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: title,
      button: onTap != null,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTapHint: onTap != null ? 'select $title' : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? green : Colors.white30,
                  width: 2,
                ),
              ),
              child:
                  selected
                      ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                      : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
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
