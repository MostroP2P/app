import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';

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
  List<String>? _words;
  bool _loadingWords = false;

  // Privacy mode — placeholder until settings provider is wired in Phase 6
  bool _privacyMode = false;

  String _maskPhrase(List<String> words) {
    if (words.length < 4) return words.join(' ');
    final first = words.take(2).join(' ');
    final last = words.skip(words.length - 2).join(' ');
    final middleCount = words.length - 4;
    final masked = List.filled(middleCount, '•••').join(' ');
    return '$first $masked $last';
  }

  Future<void> _loadAndRevealWords() async {
    if (_loadingWords) return;
    setState(() => _loadingWords = true);

    try {
      // TODO: call Rust bridge get_identity() in Phase 5 to fetch the mnemonic.
      // For now simulate with placeholder.
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;
      setState(() {
        _wordsVisible = true;
        // Placeholder: real words come from the Rust identity API.
        _words ??= List.generate(12, (i) => 'word${i + 1}');
      });

      // Dismiss backup reminder permanently once the user views their words.
      if (mounted) {
        await ref.read(backupReminderProvider.notifier).confirmBackupComplete();
      }
    } finally {
      if (mounted) setState(() => _loadingWords = false);
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
                      Text(
                        _wordsVisible && _words != null
                            ? _words!.join(' ')
                            : (_words != null
                                ? _maskPhrase(_words!)
                                : '••• ••• ••• ••• ••• ••• ••• ••• ••• ••• ••• •••'),
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
                                    ? () => setState(() => _wordsVisible = false)
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
                Opacity(
                  opacity: 0.5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PrivacyOption(
                        title: 'Reputation Mode',
                        subtitle: 'Standard privacy with reputation',
                        selected: !_privacyMode,
                        green: green,
                        onTap: null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _PrivacyOption(
                        title: 'Full Privacy Mode',
                        subtitle: 'Maximum anonymity',
                        selected: _privacyMode,
                        green: green,
                        onTap: null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Coming soon',
                  style: theme.textTheme.bodySmall!.copyWith(color: textSec),
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
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _confirmGenerateNewUser(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Generate New User?'),
        content: const Text(
          'This will permanently replace your current identity. '
          'Make sure you have backed up your current secret words.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: wire to create_identity() Rust bridge in Phase 5.
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import Mnemonic'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          decoration: const InputDecoration(
            hintText: 'Enter your 12 or 24 word phrase...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: wire to import_from_mnemonic() Rust bridge in Phase 5.
            },
            child: const Text('Import'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _confirmRefresh(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Refresh User?'),
        content: const Text(
          'This will re-fetch your trades and orders from the Mostro instance. '
          'Use this if you think your data is out of sync or orders are missing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
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
