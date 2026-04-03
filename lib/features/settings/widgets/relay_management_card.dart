import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;

// ── Model ─────────────────────────────────────────────────────────────────────

class _RelayEntry {
  _RelayEntry({
    required this.url,
    required this.isActive,
    required this.isDefault,
  });

  final String url;
  bool isActive;
  final bool isDefault;
}

// ── Widget ────────────────────────────────────────────────────────────────────

/// Inline relay management card shown within the Settings screen.
///
/// Default relays (from config.rs) are pre-populated and cannot be removed.
/// Users may add additional relays with a `wss://` prefix.
class RelayManagementCard extends ConsumerStatefulWidget {
  const RelayManagementCard({super.key});

  @override
  ConsumerState<RelayManagementCard> createState() =>
      _RelayManagementCardState();
}

class _RelayManagementCardState extends ConsumerState<RelayManagementCard> {
  // Defaults mirror rust/src/config.rs — imported from core/mostro_defaults.dart.
  static const _defaultRelays = defaultMostroRelays;

  // TODO(bridge): replace _relays local state with a Riverpod provider backed
  // by the Rust bridge (get_relays / add_relay / remove_relay) so configuration
  // persists across navigations and stays in sync with the backend (Phase 18+).
  late List<_RelayEntry> _relays;

  @override
  void initState() {
    super.initState();
    _relays = _defaultRelays
        .map((url) => _RelayEntry(url: url, isActive: true, isDefault: true))
        .toList();
    _loadRelays();
  }

  Future<void> _loadRelays() async {
    try {
      final relays = await nostr_api.getRelays();
      if (!mounted) return;
      setState(() {
        _relays = relays.map((r) => _RelayEntry(
          url: r.url,
          isActive: r.isActive,
          isDefault: r.isDefault,
        )).toList();
      });
    } catch (e) {
      debugPrint('[RelayManagement] failed to load relays: $e');
    }
  }

  void _toggleRelay(int index, bool value) {
    setState(() => _relays[index].isActive = value);
  }

  void _removeRelay(int index) {
    final url = _relays[index].url;
    setState(() => _relays.removeAt(index));
    nostr_api.removeRelay(url: url).catchError((e) {
      debugPrint('[RelayManagement] removeRelay failed: $e');
    });
  }

  Future<void> _showAddRelayDialog() async {
    final controller = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final l10n = AppLocalizations.of(ctx);
            return AlertDialog(
              title: Text(l10n.addRelayDialogTitle),
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: l10n.relayHintText,
                  errorText: errorText,
                ),
                onChanged: (_) {
                  if (errorText != null) {
                    setDialogState(() => errorText = null);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () {
                    final url = controller.text.trim();
                    if (!url.startsWith('wss://')) {
                      setDialogState(
                        () => errorText = l10n.relayErrorMustStartWithWss,
                      );
                      return;
                    }
                    if (url.length < 10) {
                      setDialogState(() => errorText = l10n.relayErrorUrlTooShort);
                      return;
                    }
                    if (_relays.any((r) => r.url == url)) {
                      setDialogState(
                        () => errorText = l10n.relayErrorDuplicate,
                      );
                      return;
                    }
                    if (!mounted) {
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      return;
                    }
                    setState(() {
                      _relays.add(
                        _RelayEntry(
                          url: url,
                          isActive: true,
                          isDefault: false,
                        ),
                      );
                    });
                    Navigator.of(ctx).pop();
                    nostr_api.addRelay(url: url).then((_) {}, onError: (e) {
                      debugPrint('[RelayManagement] addRelay failed: $e');
                    });
                  },
                  child: Text(l10n.addButtonLabel),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._relays.indexed.map((record) {
          final (index, relay) = record;
          final dotColor = relay.isActive ? colors.mostroGreen : colors.textDisabled;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Relay URL
                Expanded(
                  child: Text(
                    relay.url,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Active toggle
                Semantics(
                  label: relay.isActive
                      ? l10n.disableRelayLabel(relay.url)
                      : l10n.enableRelayLabel(relay.url),
                  child: Switch(
                    value: relay.isActive,
                    onChanged: (v) => _toggleRelay(index, v),
                    activeThumbColor: colors.mostroGreen,
                  ),
                ),
                // Remove button (user-added relays only)
                if (!relay.isDefault)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: colors.destructiveRed),
                    onPressed: () => _removeRelay(index),
                    tooltip: l10n.removeRelayTooltip,
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: _showAddRelayDialog,
          icon: Icon(Icons.add, color: colors.mostroGreen),
          label: Text(
            l10n.addRelayDialogTitle,
            style: TextStyle(color: colors.mostroGreen),
          ),
        ),
      ],
    );
  }
}
