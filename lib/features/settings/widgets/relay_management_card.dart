import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/mostro_defaults.dart';

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
  }

  void _toggleRelay(int index, bool value) {
    setState(() => _relays[index].isActive = value);
    // TODO(bridge): call set_relay_active(_relays[index].url, value)
  }

  void _removeRelay(int index) {
    // ignore: unused_local_variable — used by the pending bridge call below.
    final url = _relays[index].url;
    setState(() => _relays.removeAt(index));
    // TODO(bridge): call remove_relay(url)
  }

  Future<void> _showAddRelayDialog() async {
    final controller = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Add Relay'),
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'wss://relay.example.com',
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
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final url = controller.text.trim();
                    if (!url.startsWith('wss://')) {
                      setDialogState(
                        () => errorText = 'Must start with wss://',
                      );
                      return;
                    }
                    if (url.length < 10) {
                      setDialogState(() => errorText = 'URL is too short');
                      return;
                    }
                    if (_relays.any((r) => r.url == url)) {
                      setDialogState(
                        () => errorText = 'Relay already in list',
                      );
                      return;
                    }
                    if (!mounted) return;
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
                    // TODO(bridge): call add_relay(url)
                  },
                  child: const Text('Add'),
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
    assert(colors != null, 'AppColors theme extension must be registered');
    final c = colors!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._relays.indexed.map((record) {
          final (index, relay) = record;
          final dotColor = relay.isActive ? c.mostroGreen : c.textDisabled;

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
                      ? 'Disable relay ${relay.url}'
                      : 'Enable relay ${relay.url}',
                  child: Switch(
                    value: relay.isActive,
                    onChanged: (v) => _toggleRelay(index, v),
                    activeThumbColor: c.mostroGreen,
                  ),
                ),
                // Remove button (user-added relays only)
                if (!relay.isDefault)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: c.destructiveRed),
                    onPressed: () => _removeRelay(index),
                    tooltip: 'Remove relay',
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: _showAddRelayDialog,
          icon: Icon(Icons.add, color: c.mostroGreen),
          label: Text(
            'Add Relay',
            style: TextStyle(color: c.mostroGreen),
          ),
        ),
      ],
    );
  }
}
