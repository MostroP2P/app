import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/account/providers/my_reputation_provider.dart';
import 'package:mostro/src/rust/api/my_reputation.dart';

/// The protocol's own example: 23 ratings averaging 4.8, first trade on
/// 2023-11-24.
const sampleMyReputation = MyReputation(
  nodePubkey: 'node-a',
  rating: 4.8,
  reviews: 23,
  since: 1700784000,
  operatingDays: 142,
  fetchedAt: 1700784000,
);

/// The Account screen's reputation card without the bridge: [cached] is the
/// node's last answer ([readCached] when it changes during the test), and
/// asking again answers nothing. [onRefresh] counts the requests.
List<Override> myReputationOverrides({
  MyReputation? cached,
  MyReputation? Function()? readCached,
  String? nodeName,
  void Function()? onRefresh,
}) => [
  myReputationCoreProvider.overrideWithValue(
    MyReputationCore(
      readCache: () async => readCached != null ? readCached() : cached,
      refresh: () async {
        onRefresh?.call();
        return null;
      },
      // Single-subscription, like the bridge's: a second listen throws.
      changes: () => StreamController<MyReputation>().stream,
    ),
  ),
  activeNodeNameProvider.overrideWith((ref) => nodeName),
];
