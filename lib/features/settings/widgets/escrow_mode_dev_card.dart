import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/escrow_mode_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Developer-only control over the escrow-mode override (§4.3 of
/// `docs/cashu/README.md`).
///
/// It exists so a tester can work against a daemon branch that implements Cashu
/// before it publishes the Kind 38385 tags. **Mount it behind `kDebugMode`** —
/// users must never be able to force a backend their node does not run.
///
/// The card shows the *effective* resolution, which is deliberately not what
/// the About screen shows: About reports what the node advertises, so with the
/// override on the two disagree, and this is the surface that says so.
class EscrowModeDevCard extends ConsumerStatefulWidget {
  const EscrowModeDevCard({super.key});

  @override
  ConsumerState<EscrowModeDevCard> createState() => _EscrowModeDevCardState();
}

class _EscrowModeDevCardState extends ConsumerState<EscrowModeDevCard> {
  final _mintController = TextEditingController();

  /// The value the field was last populated from, so a stream event that did
  /// not change the override never overwrites what the user is typing.
  String? _syncedMintOverride;
  bool _seeded = false;

  @override
  void dispose() {
    _mintController.dispose();
    super.dispose();
  }

  /// Populate the field from the stored override.
  ///
  /// Deliberately **not** called from `build`: assigning `.text` notifies the
  /// controller's listeners, and doing that during a build marks the
  /// `TextField` dirty in the middle of laying it out. The guard matters too —
  /// without it every unrelated escrow event (a node switch, a capability
  /// re-fetch) would wipe whatever the user is halfway through typing.
  void _syncMintField(String? stored) {
    if (stored == _syncedMintOverride) return;
    _syncedMintOverride = stored;
    _mintController.text = stored ?? '';
  }

  Future<void> _applyMintUrl() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(escrowOverrideControllerProvider)
          .setMintUrl(_mintController.text);
    } catch (_) {
      // Rust returns an `InvalidMintUrl` marker, not prose — the localized
      // string lives here.
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsCashuMintOverrideInvalid)),
      );
    }
  }

  String _modeLabel(String marker, AppLocalizations l10n) => switch (marker) {
        'cashu' => l10n.escrowModeCashu,
        'lightning' => l10n.escrowModeLightning,
        _ => l10n.escrowModeUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final info = ref.watch(escrowModeProvider).valueOrNull;

    // Seed once when the first value arrives, then follow real changes. Both
    // paths run outside build — see [_syncMintField].
    ref.listen(escrowModeProvider, (_, next) {
      final stored = next.valueOrNull;
      if (stored != null) _syncMintField(stored.mintUrlOverride);
    });
    if (!_seeded && info != null) {
      _seeded = true;
      // Read at callback time, not build time. An override that arrives in the
      // gap between the two is applied by `ref.listen` first, and a captured
      // copy would then overwrite it with the older value.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = ref.read(escrowModeProvider).valueOrNull;
        if (current != null) _syncMintField(current.mintUrlOverride);
      });
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, color: colors.mostroGreen, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.settingsEscrowOverrideTitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.settingsEscrowOverrideSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          _effectiveState(info, l10n, colors),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsForceCashuLabel),
            value: info?.forceCashuOverride ?? false,
            onChanged: info == null
                ? null
                : (value) => ref
                    .read(escrowOverrideControllerProvider)
                    .setForceCashu(value),
          ),
          TextField(
            controller: _mintController,
            enabled: info != null,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.settingsCashuMintOverrideLabel,
              hintText: 'http://localhost:3338',
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                tooltip: l10n.settingsCashuMintOverrideApply,
                onPressed: info == null ? null : _applyMintUrl,
              ),
            ),
            onSubmitted: (_) => _applyMintUrl(),
          ),
        ],
      ),
    );
  }

  /// The resolution the app actually acts on — mode, effective mint, and
  /// whether a Cashu path may run at all (Cashu mode with no mint may not).
  Widget _effectiveState(
    EscrowModeInfo? info,
    AppLocalizations l10n,
    AppColors colors,
  ) {
    if (info == null) {
      return Text(
        l10n.escrowModeUnknown,
        style: TextStyle(color: colors.textSubtle),
      );
    }

    final mint = info.mintUrl ?? l10n.aboutCashuMintNotAdvertised;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsEscrowEffectiveMode(_modeLabel(info.mode, l10n)),
            style: TextStyle(color: colors.textSubtle),
          ),
          Text(
            l10n.settingsEscrowEffectiveMint(mint),
            style: TextStyle(color: colors.textSubtle),
          ),
          if (info.mode == 'cashu' && !info.isCashuAvailable)
            Text(
              l10n.settingsEscrowCashuUnavailable,
              style: TextStyle(color: colors.destructiveRed),
            ),
        ],
      ),
    );
  }
}
