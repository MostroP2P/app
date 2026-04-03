import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;

/// Fetches the Mostro daemon's Kind 38385 (instance status) event and parses
/// it into a [MostroInstance].
///
/// Returns `null` if no event is returned within the 10-second timeout (relay
/// not reachable, or the daemon has never published a Kind 38385 event).
///
/// `autoDispose` so the fetch is not retried on every navigation but is
/// restarted when the About screen is opened fresh.
final mostroNodeProvider =
    FutureProvider.autoDispose<MostroInstance?>((ref) async {
  final tags = await nostr_api.fetchMostroInstanceTags(
    mostroPubkeyHex: defaultMostroPubkey,
  );
  if (tags == null) return null;
  return MostroInstance.fromTags(tags);
});
