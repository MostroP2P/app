import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;

/// Fetches the Mostro daemon's Kind 38385 (instance status) event and parses
/// it into a [MostroInstance].
///
/// Reads the active Mostro node pubkey from [mostroPubkeyProvider] so the
/// About screen reflects the user-selected node. Falls back to
/// [defaultMostroPubkey] if the provider value is empty.
///
/// Returns `null` if no event is returned within the 10-second timeout (relay
/// not reachable, or the daemon has never published a Kind 38385 event).
///
/// `autoDispose` so the fetch is restarted when the About screen is opened
/// fresh, picking up any pubkey change the user made in Settings.
final mostroNodeProvider =
    FutureProvider.autoDispose<MostroInstance?>((ref) async {
  final pubkey = ref.watch(mostroPubkeyProvider);
  final resolvedPubkey =
      pubkey.trim().isEmpty ? defaultMostroPubkey : pubkey.trim();

  final tags = await nostr_api.fetchMostroInstanceTags(
    mostroPubkeyHex: resolvedPubkey,
  );
  if (tags == null) return null;
  return MostroInstance.fromTags(tags);
});
