import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/lifecycle/resume_resync.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

import '../../support/fake_trades.dart';

/// The v1 dispute-chat bug, encoded (MostroP2P/mobile#675, issue #308): a
/// dispute the peer opened and a trade that moved while the process was
/// suspended must be visible after resume, without a restart. The bridge is
/// a mutable fake: what it holds after "suspension" is what the notifiers
/// must show after the resume routine ran.
void main() {
  late List<rust_types.TradeInfo> bridgeTrades;
  late Map<String, rust_types.Dispute> bridgeDisputes;
  late ProviderContainer container;

  ChatRoomState room(String orderId) => ChatRoomState(
    orderId: orderId,
    peerPubkey: 'peer-$orderId',
    peerHandle: 'Peer',
    peerIconIndex: 0,
    peerColorHue: 0,
    isSelling: false,
  );

  setUp(() {
    bridgeTrades = [fakeTrade(id: 't1', status: rust_types.OrderStatus.active)];
    bridgeDisputes = {};
    container = ProviderContainer(
      overrides: [
        rawTradesProvider.overrideWith((ref) async => bridgeTrades.toList()),
        chatRoomsFromTradesProvider.overrideWith((ref) async {
          final trades = await ref.watch(rawTradesProvider.future);
          return [for (final t in trades) room(t.order.id)];
        }),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<rust_types.Dispute?> lookup({required String tradeId}) async =>
      bridgeDisputes[tradeId];

  ResumeResync routine({Stream<Object?> Function()? updates}) => ResumeResync(
    container: container,
    updates: updates ?? () => const Stream.empty(),
    settleQuiet: const Duration(milliseconds: 30),
    settleMax: const Duration(milliseconds: 200),
    resync:
        () async => const rust_types.ResyncOutcome(
          online: true,
          flushed: 0,
          coalesced: false,
        ),
    hydrators: [
      hydrateTrades,
      hydrateChatRooms,
      (c) => hydrateDisputes(c, getDispute: lookup),
    ],
  );

  test(
    'a trade that moved while suspended shows its new status after resume',
    () async {
      // Arrange — cold start read the trade as active.
      expect(
        (await container.read(rawTradesProvider.future)).single.order.status,
        rust_types.OrderStatus.active,
      );

      // "Suspended": the daemon released the escrow.
      bridgeTrades = [
        fakeTrade(id: 't1', status: rust_types.OrderStatus.success),
      ];

      // Act
      await routine().run();

      // Assert
      expect(
        (await container.read(rawTradesProvider.future)).single.order.status,
        rust_types.OrderStatus.success,
      );
    },
  );

  test(
    'a dispute the peer opened while suspended is listed after resume',
    () async {
      // Arrange — nothing disputed at cold start.
      container.read(disputeNotifierProvider);
      expect(container.read(disputeNotifierProvider), isEmpty);

      // "Suspended": the peer opened a dispute; the trade row moved with it.
      bridgeTrades = [
        fakeTrade(id: 't1', status: rust_types.OrderStatus.dispute),
      ];
      bridgeDisputes['order-t1'] = const rust_types.Dispute(
        id: 'd1',
        tradeId: 'order-t1',
        status: rust_types.DisputeStatus.inReview,
        initiatedByMe: false,
        adminPubkey: 'solver',
        openedAt: 1234,
        isRead: false,
      );

      // Act
      await routine().run();

      // Assert
      final listed = container.read(disputeNotifierProvider).single;
      expect(listed.id, 'd1');
      expect(listed.status, DisputeStatus.inReview);
      expect(listed.adminPubkey, 'solver');
      expect(listed.initiatedByMe, isFalse);
    },
  );

  test(
    'a dispute the solver took while the row still reads fiat-sent is listed',
    () async {
      // `admin-took-dispute` creates the InReview record without touching the
      // trade status: the row may still read active, fiat-sent or in-progress.
      bridgeTrades = [
        fakeTrade(id: 't1', status: rust_types.OrderStatus.fiatSent),
      ];
      bridgeDisputes['order-t1'] = const rust_types.Dispute(
        id: 'd1',
        tradeId: 'order-t1',
        status: rust_types.DisputeStatus.inReview,
        initiatedByMe: false,
        adminPubkey: 'solver',
        openedAt: 1234,
        isRead: false,
      );

      await routine().run();

      expect(container.read(disputeNotifierProvider).single.id, 'd1');
    },
  );

  test('a trade that finished without a dispute is not queried', () async {
    var lookups = 0;
    bridgeTrades = [
      fakeTrade(id: 't1', status: rust_types.OrderStatus.success),
      fakeTrade(id: 't2', status: rust_types.OrderStatus.canceled),
    ];
    final counting = ResumeResync(
      container: container,
      resync:
          () async => const rust_types.ResyncOutcome(
            online: true,
            flushed: 0,
            coalesced: false,
          ),
      hydrators: [
        hydrateTrades,
        (c) => hydrateDisputes(
          c,
          getDispute: ({required tradeId}) async {
            lookups++;
            return null;
          },
        ),
      ],
      updates: () => const Stream.empty(),
      settleMax: const Duration(milliseconds: 50),
    );

    await counting.run();

    expect(lookups, 0);
  });

  test(
    'events that land during the replay, after resync returned, are picked up',
    () async {
      // resync() returns once the subscriptions are re-issued; the events
      // arrive over the next seconds. The first pass sees the old row; the
      // replay writes the new one and emits a trade update; the second pass
      // sees it.
      final updates = StreamController<Object?>();
      addTearDown(updates.close);
      final run = routine(updates: () => updates.stream).run();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        (await container.read(rawTradesProvider.future)).single.order.status,
        rust_types.OrderStatus.active,
        reason: 'the first pass ran against the pre-replay row',
      );

      bridgeTrades = [
        fakeTrade(id: 't1', status: rust_types.OrderStatus.dispute),
      ];
      bridgeDisputes['order-t1'] = const rust_types.Dispute(
        id: 'd1',
        tradeId: 'order-t1',
        status: rust_types.DisputeStatus.open,
        initiatedByMe: false,
        openedAt: 1234,
        isRead: false,
      );
      updates.add(null);
      await run;

      expect(container.read(disputeNotifierProvider).single.id, 'd1');
    },
  );

  test('re-hydrating a dispute keeps the read flag the user set', () async {
    bridgeTrades = [
      fakeTrade(id: 't1', status: rust_types.OrderStatus.dispute),
    ];
    bridgeDisputes['order-t1'] = const rust_types.Dispute(
      id: 'd1',
      tradeId: 'order-t1',
      status: rust_types.DisputeStatus.open,
      initiatedByMe: true,
      openedAt: 1234,
      isRead: false,
    );
    await routine().run();
    container.read(disputeNotifierProvider.notifier).markRead('d1');

    await routine().run();

    expect(container.read(disputeNotifierProvider).single.isRead, isTrue);
  });

  test(
    'a chat room for a trade that revealed its peer while suspended appears',
    () async {
      expect(container.read(chatRoomsNotifierProvider), isEmpty);

      bridgeTrades = [
        fakeTrade(id: 't1', status: rust_types.OrderStatus.active),
        fakeTrade(id: 't2', status: rust_types.OrderStatus.active),
      ];

      await routine().run();

      expect(
        container.read(chatRoomsNotifierProvider).map((r) => r.orderId),
        unorderedEquals(['order-t1', 'order-t2']),
      );
    },
  );

  test(
    'running the routine twice over an unchanged bridge changes nothing',
    () async {
      await routine().run();
      final before = container.read(chatRoomsNotifierProvider);

      await routine().run();

      expect(container.read(chatRoomsNotifierProvider).length, before.length);
      expect((await container.read(rawTradesProvider.future)).length, 1);
    },
  );
}
