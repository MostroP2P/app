import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;

/// The active Mostro node pubkey, trimmed, falling back to
/// [defaultMostroPubkey] when the user-selected value is empty.
final activeMostroPubkeyProvider = Provider.autoDispose<String>((ref) {
  final pubkey = ref.watch(mostroPubkeyProvider).trim();
  return pubkey.isEmpty ? defaultMostroPubkey : pubkey;
});

/// Fetches the Mostro daemon's Kind 38385 (instance status) event and parses
/// it into a [MostroInstance].
///
/// Reads the active node from [activeMostroPubkeyProvider] so the About screen
/// reflects the user-selected node.
///
/// Returns `null` if no event is returned within the 10-second timeout (relay
/// not reachable, or the daemon has never published a Kind 38385 event).
///
/// `autoDispose` so the fetch is restarted when the About screen is opened
/// fresh, picking up any pubkey change the user made in Settings.
final mostroNodeProvider = FutureProvider.autoDispose<MostroInstance?>((
  ref,
) async {
  final tags = await nostr_api.fetchMostroInstanceTags(
    mostroPubkeyHex: ref.watch(activeMostroPubkeyProvider),
  );
  if (tags == null) return null;
  return MostroInstance.fromTags(tags);
});

/// Display name of the active node (kind 0 metadata or the name the user gave
/// a custom node), or `null` while the registry loads or when it has none.
final activeNodeNameProvider = Provider.autoDispose<String?>((ref) {
  final pubkey = ref.watch(activeMostroPubkeyProvider);
  final nodes = ref.watch(mostroNodesProvider).valueOrNull ?? const [];
  for (final node in nodes) {
    if (node.pubkey != pubkey) continue;
    final name = node.name?.trim() ?? '';
    return name.isEmpty ? null : name;
  }
  return null;
});
