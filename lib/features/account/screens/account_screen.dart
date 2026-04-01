import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

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
  String _fullyMaskedPhrase() =>
      List.filled(12, '•••').join(' ');

  Future<void> _loadAndRevealWords() async {
    if (_loadingWords) return;
    setState(() => _loadingWords = true);

    try {
      final words = await IdentityService.getMnemonicWords();

      if (!mounted) return;
      if (words.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No identity found — try restarting the app.')),
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
                  : 'Failed to load secret words. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingWords = false);
    }
  }

  Future<void> _confirmBackup() async {
    try {
      await ref.read(backupReminderProvider.notifier).confirmBackupComplete();
      if (mounted) setState(() => _showBackupCheckbox = false);
    } catch (e) {
      debugPrint('[account] _confirmBackup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kDebugMode
                  ? 'Failed to confirm backup: $e'
                  : 'Failed to confirm backup. Please try again.',
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
    final privacyMode = ref.watch(privacyModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── Secret Words Card ──────────────────────────────────────────
          _SectionCard(
            color: cardBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHeader(
                  icon: Icons.key,
                  iconColor: green,
                  title: 'Secret Words',
                  onInfo: () => _showInfoDialog(
                    context,
                    'Secret Words',
                    'Your 12 secret words are the only way to recover your account. '
                        'Back them up in a safe place — never share them with anyone.',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'To restore your account',
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
                        child: _loadingWords
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : TextButton.icon(
                                onPressed: _wordsVisible
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
                                  _wordsVisible ? 'Hide' : 'Show',
                                  style: TextStyle(color: green),
                                ),
                              ),
                      ),
                      // Backup confirmation checkbox — appears when words are
                      // visible and backup has not yet been confirmed.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: _showBackupCheckbox
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
                  title: 'Privacy',
                  onInfo: () => _showInfoDialog(
                    context,
                    'Privacy Modes',
                    'Reputation mode lets others see your successful trades.\n\n'
                        'Full privacy mode keeps your activity completely anonymous — '
                        'no reputation is built.',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Control your privacy settings',
                  style: theme.textTheme.bodySmall!.copyWith(color: textSec),
                ),
                const SizedBox(height: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PrivacyOption(
                      title: 'Reputation Mode',
                      subtitle: 'Standard privacy with reputation',
                      selected: !privacyMode,
                      green: green,
                      onTap: () => ref
                          .read(privacyModeProvider.notifier)
                          .setPrivacyMode(false),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _PrivacyOption(
                      title: 'Full Privacy Mode',
                      subtitle: 'Maximum anonymity',
                      selected: privacyMode,
                      green: green,
                      onTap: () => ref
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
            label: const Text('Generate New User'),
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
                  label: const Text('Import Mostro User'),
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
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _confirmGenerateNewUser(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Generate New User?'),
        content: const Text(
          'This will create a brand-new identity. Your current secret words '
          'will no longer work — make sure they are backed up before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                // Atomically replaces the stored identity: new mnemonic is
                // written before old data is cleared, so there is no window
                // where the user is left without a valid identity.
                await IdentityService.regenerate();
                await ref
                    .read(backupReminderProvider.notifier)
                    .showBackupReminder();
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
                          : 'Failed to generate identity. Please try again.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ImportMnemonicDialog(
        onImport: (words) => _importIdentity(context, words),
      ),
    );
  }

  Future<void> _importIdentity(BuildContext context, List<String> words) async {
    try {
      await IdentityService.importAndStore(words);
      await ref.read(backupReminderProvider.notifier).showBackupReminder();
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
                : 'Invalid mnemonic. Please check your words and try again.',
          ),
        ),
      );
    }
  }

  void _confirmRefresh(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refresh User?'),
        content: const Text(
          'This will re-fetch your trades and orders from the Mostro instance. '
          'Use this if you think your data is out of sync or orders are missing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // TODO: wire restore-session action in Phase 7.
            },
            child: const Text('Refresh'),
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
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onInfo,
          icon: const Icon(Icons.info_outline, size: 18),
          tooltip: 'More information',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
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
              child: _pending
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
            child: selected
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
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
    final words = _controller.text.trim().split(RegExp(r'\s+'));
    if (words.length != 12 && words.length != 24) {
      setState(() => _error = 'Enter a valid 12 or 24 word phrase.');
      return;
    }
    Navigator.pop(context);
    widget.onImport(words);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Mnemonic'),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        decoration: InputDecoration(
          hintText: 'Enter your 12 or 24 word phrase...',
          errorText: _error,
        ),
        onChanged: (_) { if (_error != null) setState(() => _error = null); },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Import'),
        ),
      ],
    );
  }
}
