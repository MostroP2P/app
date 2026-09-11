import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Display helpers shared by the node selector, its cards, the custom-node
/// dialog and the Settings row.

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
  // custom cards, so it cannot surface from here.
  return l10n.errorSwitchingNode;
}
