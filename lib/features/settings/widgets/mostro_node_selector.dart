import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';
import 'package:mostro/src/rust/api/types.dart';

export 'package:mostro/features/settings/providers/mostro_nodes_provider.dart'
    show mostroPubkeyProvider, truncatePubkey;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Leading emoji token of a region label like `🇨🇺 Cuba`, or `null` when the
/// label carries none.
String? regionFlag(String? region) {
  if (region == null || region.isEmpty) return null;
  final first = region.split(' ').first;
  final isEmoji =
      first.runes.isNotEmpty && first.runes.every((r) => r >= 0x1F000);
  return isEmoji ? first : null;
}

/// Display title for a node entry: kind 0 / user-given name, then the region
/// place name, then the truncated pubkey — with the region flag appended when
/// the name doesn't already carry it.
String nodeDisplayName(MostroNodeEntry entry) {
  final flag = regionFlag(entry.region);
  var name = entry.name ?? '';
  if (name.isEmpty && entry.region != null) {
    name = entry.region!.split(' ').skip(1).join(' ');
  }
  if (name.isEmpty && entry.pubkey == defaultMostroPubkey) {
    name = 'Mostro';
  }
  if (name.isEmpty) name = truncatePubkey(entry.pubkey);
  if (flag != null && !name.contains(flag)) return '$name $flag';
  return name;
}

/// Map a Rust marker error to a localized message. Markers are stable codes —
/// see `rust/src/api/nodes.rs`; prose never crosses the bridge.
String localizedNodeError(AppLocalizations l10n, Object error) {
  final msg = error.toString();
  if (msg.contains('PrivateKeyNotAllowed')) return l10n.privateKeyNotAllowed;
  if (msg.contains('NodeAlreadyExists')) return l10n.nodeAlreadyExists;
  if (msg.contains('InvalidPubkey')) return l10n.invalidPubkeyFormat;
  if (msg.contains('CannotRemoveActiveNode')) {
    return l10n.cannotRemoveActiveNode;
  }
  if (msg.contains('NotInitialized')) return l10n.nodeStorageUnavailable;
  // `NodeIsTrusted` is deliberately unmapped: the UI only offers delete on
  // custom tiles, so it cannot surface from here.
  return l10n.errorSwitchingNode;
}

// ── Widget ────────────────────────────────────────────────────────────────────

/// Bottom sheet listing trusted Mostro communities and user-added nodes; a tap
/// selects the node. Show via [showMostroNodeSelector].
class MostroNodeSelector extends ConsumerStatefulWidget {
  const MostroNodeSelector({super.key});

  @override
  ConsumerState<MostroNodeSelector> createState() => _MostroNodeSelectorState();
}

class _MostroNodeSelectorState extends ConsumerState<MostroNodeSelector> {
  /// Pubkey of the node currently being switched to, or `null` when idle.
  String? _switchingPubkey;

  @override
  void initState() {
    super.initState();
    // Opportunistic refresh so names/avatars are current each time the
    // selector opens; the cached registry shows meanwhile.
    Future.microtask(
      () => ref.read(mostroNodesProvider.notifier).refreshMetadata(),
    );
  }

  Future<void> _onNodeTap(MostroNodeEntry entry) async {
    setState(() => _switchingPubkey = entry.pubkey);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(mostroNodesProvider.notifier).selectNode(entry.pubkey);
      // The user may have dismissed the sheet during the switch; popping via
      // the captured navigator would then close the route underneath it.
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.nodeSwitchedSuccess(nodeDisplayName(entry))),
        ),
      );
    } catch (e) {
      debugPrint('[MostroNodeSelector] selectNode failed: $e');
      if (mounted) setState(() => _switchingPubkey = null);
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorSwitchingNode)));
    }
  }

  Future<void> _onDeleteNode(MostroNodeEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.deleteCustomNodeTitle),
            content: Text(l10n.deleteCustomNodeMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.deleteCustomNodeConfirm),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(mostroNodesProvider.notifier)
          .removeCustomNode(entry.pubkey);
      messenger.showSnackBar(SnackBar(content: Text(l10n.nodeRemovedSuccess)));
    } catch (e) {
      debugPrint('[MostroNodeSelector] removeCustomNode failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(localizedNodeError(AppLocalizations.of(context), e)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final nodesAsync = ref.watch(mostroNodesProvider);
    final nodes = nodesAsync.valueOrNull ?? const <MostroNodeEntry>[];
    final trusted = nodes.where((n) => n.isTrusted).toList();
    final custom = nodes.where((n) => !n.isTrusted).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textSubtle.withAlpha(120),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.selectMostroNode,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.closeButtonLabel,
                  onPressed: () => Navigator.of(context).pop(),
                ).withAutomationId(AutomationIds.nodeCustomCancel),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nodesAsync.isLoading && nodes.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  if (trusted.isNotEmpty) ...[
                    _sectionHeader(context, l10n.trustedNodesSection),
                    const SizedBox(height: AppSpacing.sm),
                    ...trusted.map(
                      (n) => _NodeTile(
                        entry: n,
                        isSwitching: _switchingPubkey != null,
                        isSwitchingThis: _switchingPubkey == n.pubkey,
                        onTap: () => _onNodeTap(n),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _sectionHeader(context, l10n.customNodesSection),
                  const SizedBox(height: AppSpacing.sm),
                  if (custom.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        l10n.noCustomNodesYet,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSubtle,
                        ),
                      ),
                    )
                  else
                    ...custom.map(
                      (n) => _NodeTile(
                        entry: n,
                        isSwitching: _switchingPubkey != null,
                        isSwitchingThis: _switchingPubkey == n.pubkey,
                        onTap: () => _onNodeTap(n),
                        onDelete: () => _onDeleteNode(n),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed:
                          _switchingPubkey != null
                              ? null
                              : () => showAddCustomNodeDialog(context, ref),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addCustomNode),
                    ).withAutomationId(AutomationIds.nodeAddCustom),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Node-operator disclaimer — mirrors v1's community warning.
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(26),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: Colors.amber.withAlpha(100)),
                    ),
                    child: Text(
                      l10n.communityDisclaimerBody,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Text(
      title,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colors.textSubtle,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Node tile ─────────────────────────────────────────────────────────────────

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.entry,
    required this.isSwitching,
    required this.isSwitchingThis,
    required this.onTap,
    this.onDelete,
  });

  final MostroNodeEntry entry;

  /// A switch (to any node) is in flight — all tiles are inert meanwhile.
  final bool isSwitching;

  /// This tile is the switch target — shows the spinner.
  final bool isSwitchingThis;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final about = entry.about;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (isSwitching || entry.isActive) ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color:
                  entry.isActive
                      ? colors.mostroGreen.withAlpha(26)
                      : colors.backgroundCard,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color:
                    entry.isActive
                        ? colors.mostroGreen.withAlpha(100)
                        : colors.textSubtle.withAlpha(40),
              ),
            ),
            child: Row(
              children: [
                _NodeAvatar(entry: entry),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nodeDisplayName(entry),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (entry.isTrusted) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.mostroGreen.withAlpha(30),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.chip,
                                ),
                              ),
                              child: Text(
                                l10n.trustedBadgeLabel,
                                style: TextStyle(
                                  color: colors.mostroGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        truncatePubkey(entry.pubkey),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSubtle,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (about != null && about.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          about,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSubtle),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (isSwitchingThis)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (entry.isActive)
                  Icon(Icons.check_circle, color: colors.mostroGreen, size: 22)
                else if (onDelete != null)
                  IconButton(
                    onPressed: isSwitching ? null : onDelete,
                    tooltip: l10n.deleteCustomNodeTitle,
                    icon: Icon(
                      Icons.delete_outline,
                      color: colors.textSubtle,
                      size: 20,
                    ),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(AppSpacing.xs),
                  ).withAutomationId(
                    AutomationIds.nodeItemDelete(entry.pubkey),
                  ),
              ],
            ),
          ),
        ).withAutomationId(AutomationIds.nodeItem(entry.pubkey), merge: false),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

/// Node avatar: the kind 0 picture when one is advertised (https-only,
/// enforced in Rust), falling back to a deterministic [NymAvatar] derived
/// from the pubkey.
class _NodeAvatar extends StatelessWidget {
  const _NodeAvatar({required this.entry});

  final MostroNodeEntry entry;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final picture = entry.picture;
    final fallback = _fallback();
    if (picture == null || picture.isEmpty) return fallback;
    // Fetching the avatar reveals the device's IP to whatever server the node
    // operator put in their kind 0 — inherent to the v1-inherited design.
    // cacheWidth bounds decoding: the URL is operator-controlled, and without
    // it a huge image would be decoded at full size in memory.
    return ClipOval(
      child: Image.network(
        picture,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        cacheWidth:
            (_size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _fallback() {
    // Derive icon/hue from the pubkey so the placeholder is stable per node.
    final iconIndex = _hexSlice(0, 8) % 37;
    final colorHue = _hexSlice(8, 16) % 360;
    return NymAvatar(iconIndex: iconIndex, colorHue: colorHue, size: _size);
  }

  int _hexSlice(int start, int end) {
    if (entry.pubkey.length < end) return 0;
    return int.tryParse(entry.pubkey.substring(start, end), radix: 16) ?? 0;
  }
}

// ── Add-custom-node dialog ────────────────────────────────────────────────────

class AddCustomNodeDialog extends ConsumerStatefulWidget {
  const AddCustomNodeDialog({super.key});

  @override
  ConsumerState<AddCustomNodeDialog> createState() =>
      _AddCustomNodeDialogState();
}

class _AddCustomNodeDialogState extends ConsumerState<AddCustomNodeDialog> {
  final _pubkeyController = TextEditingController();
  final _nameController = TextEditingController();
  String? _errorText;
  bool _submitting = false;

  @override
  void dispose() {
    _pubkeyController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _pubkeyController.text.trim();
    final l10n = AppLocalizations.of(context);
    if (input.isEmpty) {
      setState(() => _errorText = l10n.invalidPubkeyFormat);
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final name = _nameController.text.trim();
      await ref
          .read(mostroNodesProvider.notifier)
          .addCustomNode(input: input, name: name.isEmpty ? null : name);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.nodeAddedSuccess)));
    } catch (e) {
      debugPrint('[AddCustomNodeDialog] addCustomNode failed: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = localizedNodeError(AppLocalizations.of(context), e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addCustomNode),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pubkeyController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.nodePubkeyFieldLabel,
              hintText: l10n.nodePubkeyFieldHint,
              errorText: _errorText,
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ).withAutomationId(AutomationIds.nodeCustomPubkey),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: l10n.nodeNameOptionalLabel),
          ).withAutomationId(AutomationIds.nodeCustomName),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ).withAutomationId(AutomationIds.nodeAddCustomCancel),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child:
              _submitting
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(l10n.addButtonLabel),
        ).withAutomationId(AutomationIds.nodeCustomConfirm),
      ],
    );
  }
}

/// Show the [AddCustomNodeDialog].
void showAddCustomNodeDialog(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (_) => const AddCustomNodeDialog(),
  );
}

// ── Entry point ───────────────────────────────────────────────────────────────

/// Show the [MostroNodeSelector] as a modal bottom sheet.
void showMostroNodeSelector(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => const MostroNodeSelector(),
  );
}
