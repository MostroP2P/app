import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/provider_harness.dart';

RatingInfo _rating({required int score, required bool isMine}) =>
    RatingInfo(tradeId: 't1', score: score, isMine: isMine, createdAt: 0);

void main() {
  test('the score the user gave is the one shown', () {
    expect(myRatingScore(_rating(score: 4, isMine: true)), 4);
  });

  test('a closed rating step without a known score shows no score', () {
    // Rehydrated from `rated_at` (a restart, a replayed rate-received, a
    // restored trade): Rust carries a placeholder 0, never a real note.
    expect(myRatingScore(_rating(score: 0, isMine: true)), isNull);
  });

  test("the counterpart's rating is not the user's", () {
    expect(myRatingScore(_rating(score: 5, isMine: false)), isNull);
    expect(myRatingScore(null), isNull);
  });

  group('tradeRatingProvider', () {
    late StreamController<TradeTouch> touches;
    late RatingInfo? stored;

    setUp(() {
      touches = StreamController<TradeTouch>.broadcast();
      stored = null;
    });
    tearDown(() => touches.close());

    /// A container whose rating reads [stored], with the trade screen's
    /// subscription held open and its first read resolved.
    Future<ProviderContainer> mount() async {
      final container = createContainer(
        overrides: [
          tradeTouchProvider.overrideWith((ref) => touches.stream),
          ratingReaderProvider.overrideWithValue((tradeId) async => stored),
        ],
      );
      container.listen(ratedByMeProvider('t1'), (_, _) {});
      await container.read(tradeRatingProvider('t1').future);
      return container;
    }

    /// Rings the trade doorbell and lets the re-read, if any, land.
    Future<void> ring(ProviderContainer container, String? orderId) async {
      touches.add(TradeTouch(orderId: orderId));
      await Future<void>.delayed(Duration.zero);
      await container.read(tradeRatingProvider('t1').future);
    }

    test('a rate-received replayed while the screen is open closes the '
        'step', () async {
      // Arrange: the screen read the trade before the replay reached it.
      final container = await mount();
      expect(container.read(ratedByMeProvider('t1')), isFalse);

      // Act: the replay writes `rated_at` and touches the row; Rust now
      // rehydrates the user's rating from it.
      stored = _rating(score: 0, isMine: true);
      await ring(container, 't1');

      // Assert
      expect(container.read(ratedByMeProvider('t1')), isTrue);
    });

    test("another trade's touch leaves the rating alone", () async {
      // Arrange
      final container = await mount();

      // Act
      stored = _rating(score: 0, isMine: true);
      await ring(container, 't2');

      // Assert
      expect(container.read(ratedByMeProvider('t1')), isFalse);
    });

    test('a resync re-reads it', () async {
      // Arrange
      final container = await mount();

      // Act: the touch stream fell behind and dropped the trade's touch.
      stored = _rating(score: 0, isMine: true);
      await ring(container, null);

      // Assert
      expect(container.read(ratedByMeProvider('t1')), isTrue);
    });
  });
}
