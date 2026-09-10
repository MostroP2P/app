import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The account's public key, on the account screen.
///
/// Identifies the active account without revealing anything secret — the
/// secret words stay behind their own Show control. Separate from the screen
/// because the screen loads the key over the Rust bridge and this does not:
/// what the card renders for a key, for no key, and for a replaced key is
/// testable on its own.
class PublicKeyCard extends StatelessWidget {
  const PublicKeyCard({super.key, required this.publicKey});

  /// The stored identity's public key. Null while it loads, and when secure
  /// storage holds no identity.
  final String? publicKey;

  /// Shown in place of a key that is absent or still loading.
  static const String placeholder = '—';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              l10n.pubkeyLabel,
              style: theme.textTheme.bodySmall!.copyWith(color: textSec),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              publicKey ?? placeholder,
              style: theme.textTheme.bodySmall!.copyWith(
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      // The visible text ellipsizes at whatever width the card gets; the
      // readout carries the whole key, which is what automation compares.
    ).withAutomationId(
      AutomationIds.keysPublicKey,
      label: publicKey ?? '',
    );
  }
}
