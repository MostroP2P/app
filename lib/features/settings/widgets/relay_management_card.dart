import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/core/services/coalescing_loader.dart';
import 'package:mostro/core/test_environment.dart';
import 'package:mostro/features/settings/providers/relay_auto_sync_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/types.dart' show RelaySource;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// The one spelling of a relay URL the app compares and keys rows by.
///
/// `AutomationIds.settingsRelayItem` normalizes the same way, so a relay is
/// one row with one identifier however its URL was typed.
String canonicalRelayUrl(String url) =>
    url.trim().replaceAll(RegExp(r'/+$'), '');

// ── Model ─────────────────────────────────────────────────────────────────────

class _RelayEntry {
  _RelayEntry({
    required this.url,
    required this.isActive,
    required this.isDefault,
    this.source = RelaySource.default_,
  });

  final String url;
  bool isActive;
  final bool isDefault;
  final RelaySource source;

  bool get isFromMostro => source == RelaySource.mostroDiscovered;
}

// ── Widget ────────────────────────────────────────────────────────────────────

/// Inline relay management card shown within the Settings screen.
///
/// Default relays (from config.rs) are pre-populated and cannot be removed.
/// Users may add additional relays with a `wss://` prefix. Relays the active
/// Mostro node announces in its kind 10002 list are auto-added by the Rust
/// core and labelled as such; removing one blacklists it so the node's list
/// does not bring it back.
class RelayManagementCard extends ConsumerStatefulWidget {
  const RelayManagementCard({super.key});

  @override
  ConsumerState<RelayManagementCard> createState() =>
      _RelayManagementCardState();
}

class _RelayManagementCardState extends ConsumerState<RelayManagementCard> {
  // Defaults mirror rust/src/config.rs — imported from core/mostro_defaults.dart.
  static const _defaultRelays = defaultMostroRelays;

  late List<_RelayEntry> _relays;
  /// Serialises reloads and keeps the one an auto-sync asks for while another
  /// is in flight — that load may have read its snapshot before the new relay
  /// existed, so dropping the request would hide it until a screen re-entry.
  late final CoalescingLoader _loader = CoalescingLoader(_readRelays);
  ProviderSubscription<AsyncValue<List<String>>>? _autoSyncSub;

  @override
  void initState() {
    super.initState();
    _relays = _defaultRelays
        .map((url) => _RelayEntry(url: url, isActive: true, isDefault: true))
        .toList();
    // The initial load is driven by this subscription, not started here:
    // `relayAutoSyncProvider` emits once the Rust-side receiver exists, so
    // the first snapshot is taken with nothing able to slip past it. Every
    // later emission is a node-announced relay to fold into the list.
    _autoSyncSub = ref.listenManual<AsyncValue<List<String>>>(
      relayAutoSyncProvider,
      (_, next) => next.whenData((added) {
        if (added.isNotEmpty) {
          debugPrint('[RelayManagement] auto-synced relays: $added');
        }
        _loadRelays();
      }),
      onError: (e, _) =>
          debugPrint('[RelayManagement] auto-sync watch failed: $e'),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _autoSyncSub?.close();
    super.dispose();
  }

  Future<void> _loadRelays() => _loader.run();

  Future<void> _readRelays() async {
    try {
      final relays = await nostr_api.getRelays();
      if (!mounted) return;
      setState(() {
        _relays = relays.map((r) => _RelayEntry(
          url: r.url,
          isActive: r.isActive,
          isDefault: r.isDefault,
          source: r.source,
        )).toList();
      });
    } catch (e) {
      debugPrint('[RelayManagement] failed to load relays: $e');
    }
  }

  Future<void> _toggleRelay(int index, bool value) async {
    final url = _relays[index].url;
    setState(() => _relays[index].isActive = value);
    try {
      if (value) {
        await nostr_api.addRelay(url: url);
      } else {
        await nostr_api.removeRelay(url: url);
      }
    } catch (e) {
      debugPrint('[RelayManagement] toggleRelay failed: $e');
      if (!mounted) return;
      setState(() {
        final currentIndex = _relays.indexWhere((r) => r.url == url);
        if (currentIndex != -1) {
          _relays[currentIndex].isActive = !value;
        }
      });
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? l10n.relayAddFailed : l10n.relayRemoveFailed)),
      );
    }
  }

  Future<void> _removeRelay(int index) async {
    final url = _relays[index].url;
    final removed = _relays[index];
    setState(() => _relays.removeAt(index));
    try {
      await nostr_api.removeRelay(url: url);
    } catch (e) {
      debugPrint('[RelayManagement] removeRelay failed: $e');
      if (!mounted) return;
      setState(() => _relays.insert(index, removed));
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.relayRemoveFailed)),
      );
    }
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
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: l10n.relayHintText,
                  errorText: errorText,
                ),
                onChanged: (_) {
                  if (errorText != null) {
                    setDialogState(() => errorText = null);
                  }
                },
              ).withAutomationId(AutomationIds.settingsRelaysAddUrl),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ).withAutomationId(AutomationIds.settingsRelaysAddCancel),
                TextButton(
                  onPressed: () {
                    // Canonicalized before anything else looks at it: a relay
                    // written with and without a trailing slash is the same
                    // relay, and two rows for it would share one automation
                    // identifier, which no driver could then tell apart.
                    final url = canonicalRelayUrl(controller.text);
                    // A Mortsom run points the app at a local relay, which is
                    // plain ws:// on a private address. Outside the test
                    // environment the wss:// requirement is unchanged.
                    final schemeOk = url.startsWith('wss://') ||
                        (TestEnvironment.allowInsecureRelays &&
                            url.startsWith('ws://'));
                    if (!schemeOk) {
                      setDialogState(
                        () => errorText = l10n.relayErrorMustStartWithWss,
                      );
                      return;
                    }
                    if (url.length < 10) {
                      setDialogState(() => errorText = l10n.relayErrorUrlTooShort);
                      return;
                    }
                    if (_relays.any((r) => canonicalRelayUrl(r.url) == url)) {
                      setDialogState(
                        () => errorText = l10n.relayErrorDuplicate,
                      );
                      return;
                    }
                    if (!mounted) {
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      return;
                    }
                    final newEntry = _RelayEntry(
                      url: url,
                      isActive: true,
                      isDefault: false,
                    );
                    setState(() => _relays.add(newEntry));
                    Navigator.of(ctx).pop();
                    nostr_api.addRelay(url: url).then((_) {}, onError: (e) {
                      debugPrint('[RelayManagement] addRelay failed: $e');
                      if (!mounted) return;
                      setState(() => _relays.removeWhere((r) => r.url == url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context).relayAddFailed),
                        ),
                      );
                    });
                  },
                  child: Text(l10n.addButtonLabel),
                ).withAutomationId(AutomationIds.settingsRelaysAddConfirm),
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

          // The row holds a toggle and, for user-added relays, a delete
          // button, so merge: false keeps those addressable on their own.
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
                // Relay URL, plus where it came from when a node added it
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relay.url,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (relay.isFromMostro)
                        Text(
                          l10n.relayFromMostroLabel,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colors.textDisabled,
                              ),
                        ),
                    ],
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
                // Remove button (user-added and node-announced relays)
                if (!relay.isDefault)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: colors.destructiveRed),
                    onPressed: () => _removeRelay(index),
                    tooltip: l10n.removeRelayTooltip,
                  ).withAutomationId(
                    AutomationIds.settingsRelayDelete(relay.url),
                  ),
              ],
            ),
          ).withAutomationId(
            AutomationIds.settingsRelayItem(relay.url),
            merge: false,
            label: relay.url,
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
        ).withAutomationId(AutomationIds.settingsRelaysAdd),
      ],
    );
  }
}
