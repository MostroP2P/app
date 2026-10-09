import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/shared/mascot/mascot_cues.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/provider_harness.dart';

final DateTime _now = DateTime(2026, 6, 1, 12);

TradeUpdate _update(
  OrderStatus status, {
  TradeUpdateReason? reason,
  DateTime? at,
  String orderId = 'order-1',
}) => TradeUpdate(
  orderId: orderId,
  status: status,
  reason: reason,
  occurredAt: (at ?? _now).millisecondsSinceEpoch ~/ 1000,
);

void main() {
  group('moodForTradeUpdate', () {
    test('gives each step of a trade its face', () {
      expect(
        moodForTradeUpdate(_update(OrderStatus.active)),
        MostroMood.escrowLocked,
      );
      expect(
        moodForTradeUpdate(_update(OrderStatus.fiatSent)),
        MostroMood.fiatSent,
      );
      expect(
        moodForTradeUpdate(_update(OrderStatus.dispute)),
        MostroMood.disputed,
      );
      for (final done in const [
        OrderStatus.success,
        OrderStatus.settledByAdmin,
        OrderStatus.completedByAdmin,
      ]) {
        expect(
          moodForTradeUpdate(_update(done)),
          MostroMood.celebrating,
          reason: done.name,
        );
      }
    });

    test('cries over every way a trade can end without a trade', () {
      for (final ended in const [
        OrderStatus.canceled,
        OrderStatus.cooperativelyCanceled,
        OrderStatus.canceledByAdmin,
        OrderStatus.expired,
      ]) {
        expect(
          moodForTradeUpdate(_update(ended)),
          MostroMood.canceled,
          reason: ended.name,
        );
      }
    });

    test('my own cancel request is not a step: its status is old', () {
      // Rust emits the request with the status the screens already show, so
      // reading it as a step would lock the escrow a second time.
      expect(
        moodForTradeUpdate(
          _update(
            OrderStatus.active,
            reason: TradeUpdateReason.cooperativeCancelRequestedByMe,
          ),
        ),
        isNull,
      );
    });

    test('the counterparty asking to cancel is a surprise', () {
      expect(
        moodForTradeUpdate(
          _update(
            OrderStatus.fiatSent,
            reason: TradeUpdateReason.cooperativeCancelRequestedByPeer,
          ),
        ),
        MostroMood.cancelAsked,
      );
    });

    test('a status Rust only re-states is not news', () {
      // A restore and a reputation re-read are dated now, so the reason is
      // all that tells them from a step (#770).
      for (final status in const [
        OrderStatus.success,
        OrderStatus.canceled,
        OrderStatus.dispute,
        OrderStatus.active,
      ]) {
        expect(
          moodForTradeUpdate(
            _update(status, reason: TradeUpdateReason.replayed),
          ),
          isNull,
          reason: status.name,
        );
      }
    });

    test('the waiting steps leave Mostro as it is', () {
      for (final status in const [
        OrderStatus.pending,
        OrderStatus.waitingBuyerInvoice,
        OrderStatus.waitingPayment,
        OrderStatus.waitingTakerBond,
        OrderStatus.waitingMakerBond,
        OrderStatus.settledHoldInvoice,
        OrderStatus.inProgress,
      ]) {
        expect(
          moodForTradeUpdate(_update(status)),
          isNull,
          reason: status.name,
        );
      }
    });
  });

  group('MascotCueNotifier', () {
    late StreamController<TradeUpdate> updates;
    late ProviderContainer container;
    late BackupReminderNotifier reminder;

    setUp(() {
      updates = StreamController<TradeUpdate>();
      addTearDown(updates.close);
      SharedPreferences.setMockInitialValues({});
      reminder = BackupReminderNotifier(initialValue: true);
      container = createContainer(
        overrides: [
          tradeUpdatesProvider.overrideWith((ref) => updates.stream),
          backupReminderProvider.overrideWith((ref) => reminder),
        ],
      );
      // Built at noon, so no morning greeting is waiting in any test.
      withClock(Clock.fixed(_now), () => container.read(mascotCueProvider));
    });

    Future<void> deliver(TradeUpdate update) async {
      updates.add(update);
      await Future<void>.delayed(Duration.zero);
    }

    MascotCueNotifier cues() => container.read(mascotCueProvider.notifier);

    test('holds nothing until something happens', () {
      withClock(Clock.fixed(_now), () {
        expect(container.read(mascotCueProvider), isNull);
        expect(cues().take(), isNull);
      });
    });

    test('hands a cue over once', () {
      withClock(Clock.fixed(_now), () {
        cues().orderPublished();

        expect(cues().take(), MostroMood.published);
        expect(cues().take(), isNull);
      });
    });

    test('drops a cue nobody saw in time', () {
      cues().cue(MostroMood.fiatSent, at: _now);

      withClock(Clock.fixed(_now.add(const Duration(minutes: 3))), () {
        expect(cues().take(), isNull);
        expect(container.read(mascotCueProvider), isNull);
      });
    });

    test('a weaker cue does not push out a dispute still waiting', () {
      withClock(Clock.fixed(_now), () {
        cues().cue(MostroMood.disputed);
        cues().cue(MostroMood.fiatSent);

        expect(cues().take(), MostroMood.disputed);
      });
    });

    test('a newer cue of the same weight replaces the one waiting', () {
      withClock(Clock.fixed(_now), () {
        cues().cue(MostroMood.escrowLocked);
        cues().cue(MostroMood.fiatSent);

        expect(cues().take(), MostroMood.fiatSent);
      });
    });

    test('anything replaces a dispute nobody saw in time', () {
      cues().cue(MostroMood.disputed, at: _now);

      withClock(Clock.fixed(_now.add(const Duration(minutes: 3))), () {
        cues().cue(MostroMood.fiatSent);
        expect(cues().take(), MostroMood.fiatSent);
      });
    });

    test('five stars is love, any other score a thank-you', () {
      withClock(Clock.fixed(_now), () {
        cues().rated(5);
        expect(cues().take(), MostroMood.loved);

        cues().rated(3);
        expect(cues().take(), MostroMood.thankful);
      });
    });

    test('facepalms when the node says no, not when the network fails', () {
      withClock(Clock.fixed(_now), () {
        cues().daemonRefused('NoDaemonResponse');
        expect(cues().take(), isNull);

        cues().daemonRefused('CantDo:IsNotYourOrder');
        expect(cues().take(), MostroMood.refused);
      });
    });

    test('turns a fresh trade step into a cue', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        updates.add(_update(OrderStatus.active));
        await Future<void>.delayed(Duration.zero);

        expect(cues().take(), MostroMood.escrowLocked);
      });
    });

    test('the third trade done in a day is on fire', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        await deliver(_update(OrderStatus.success, orderId: 'a'));
        expect(cues().take(), MostroMood.celebrating);
        // The same trade told twice is one trade, and one party.
        await deliver(_update(OrderStatus.success, orderId: 'a'));
        expect(cues().take(), isNull);
        await deliver(_update(OrderStatus.settledByAdmin, orderId: 'b'));
        expect(cues().take(), MostroMood.celebrating);
        await deliver(_update(OrderStatus.success, orderId: 'c'));
        expect(cues().take(), MostroMood.onFire);
      });
    });

    test("yesterday's trades do not count towards today's fire", () async {
      container.listen(mascotCueProvider, (_, _) {});
      await withClock(Clock.fixed(_now), () async {
        await deliver(_update(OrderStatus.success, orderId: 'a'));
        await deliver(_update(OrderStatus.success, orderId: 'b'));
        cues().take();
      });

      final tomorrow = _now.add(const Duration(days: 1));
      await withClock(Clock.fixed(tomorrow), () async {
        await deliver(_update(OrderStatus.success, orderId: 'c', at: tomorrow));
        expect(cues().take(), MostroMood.celebrating);
      });
    });

    test('a cancel the counterparty agreed to is a thumbs-up', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        await deliver(
          _update(
            OrderStatus.active,
            reason: TradeUpdateReason.cooperativeCancelRequestedByMe,
          ),
        );
        expect(cues().take(), isNull);
        await deliver(_update(OrderStatus.cooperativelyCanceled));

        expect(cues().take(), MostroMood.agreed);
      });
    });

    test('a request confirmed late still makes the agreement a thumbs-up', () {
      // The daemon's confirmation landed after an offline spell: too old to
      // be a cue, still the record of who asked (#782 review).
      return withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        await deliver(
          _update(
            OrderStatus.active,
            reason: TradeUpdateReason.cooperativeCancelRequestedByMe,
            at: _now.subtract(const Duration(minutes: 10)),
          ),
        );
        await deliver(_update(OrderStatus.cooperativelyCanceled));

        expect(cues().take(), MostroMood.agreed);
      });
    });

    test('a cancel nobody here asked for is still a cry', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        await deliver(_update(OrderStatus.cooperativelyCanceled));

        expect(cues().take(), MostroMood.canceled);
      });
    });

    test('a take the node confirmed, and an invoice it accepted', () {
      withClock(Clock.fixed(_now), () {
        cues().orderTaken();
        expect(cues().take(), MostroMood.orderTaken);

        cues().invoiceAccepted();
        expect(cues().take(), MostroMood.invoiceAccepted);
      });
    });

    test('a backup just verified is a check', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        await reminder.confirmBackupComplete();
        await Future<void>.delayed(Duration.zero);

        expect(cues().take(), MostroMood.backedUp);
      });
    });

    test('a seed import is backed up, but nothing was verified', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        await reminder.markAlreadyBackedUp();
        await Future<void>.delayed(Duration.zero);

        expect(cues().take(), isNull);
      });
    });

    test('a replayed cooperative cancel is not the peer agreeing', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        await deliver(
          _update(
            OrderStatus.active,
            reason: TradeUpdateReason.cooperativeCancelRequestedByMe,
          ),
        );
        await deliver(
          _update(
            OrderStatus.cooperativelyCanceled,
            reason: TradeUpdateReason.replayed,
          ),
        );

        expect(cues().take(), isNull);
      });
    });

    test('a step a restore replays from history is not news', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        updates.add(
          _update(
            OrderStatus.dispute,
            at: _now.subtract(const Duration(days: 3)),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(cues().take(), isNull);
      });
    });
  });

  group('the morning greeting', () {
    ProviderContainer containerAt(DateTime now) {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer(
        overrides: [
          tradeUpdatesProvider.overrideWith((ref) => const Stream.empty()),
          backupReminderProvider.overrideWith(
            (ref) => BackupReminderNotifier(initialValue: false),
          ),
        ],
      );
      withClock(Clock.fixed(now), () => container.read(mascotCueProvider));
      return container;
    }

    test('says gm on the first look of a morning session', () {
      final morning = DateTime(2026, 6, 1, 8, 30);
      final container = containerAt(morning);

      withClock(Clock.fixed(morning), () {
        expect(
          container.read(mascotCueProvider.notifier).take(),
          MostroMood.greeting,
        );
      });
    });

    test('says nothing in the afternoon', () {
      final afternoon = DateTime(2026, 6, 1, 15);
      final container = containerAt(afternoon);

      withClock(Clock.fixed(afternoon), () {
        expect(container.read(mascotCueProvider.notifier).take(), isNull);
      });
    });
  });
}
