import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';

import '../../support/provider_harness.dart';

void main() {
  group('order book pipeline lifetime', () {
    test('tears down once nothing is displaying the filtered list', () async {
      var bookDisposed = false;
      final container = createContainer(overrides: [
        orderBookProvider.overrideWith((ref) {
          ref.onDispose(() => bookDisposed = true);
          return Stream.value(<OrderItem>[]);
        }),
      ]);

      // HomeScreen watches both in the same build, so orderReasonsProvider is
      // always a live watcher of filteredOrdersProvider. Listening to only one
      // here would let a plain-Provider revert of the other slip through: the
      // chain would stay pinned in the app while this test kept passing.
      final list = container.listen(filteredOrdersProvider, (_, __) {});
      final reasons = container.listen(orderReasonsProvider, (_, __) {});
      await container.read(orderBookProvider.future);
      expect(bookDisposed, isFalse);

      // The user leaves Home for Chat or Trades — routes that replace Home
      // (`context.go`), not the pushed Settings/About that keep it mounted.
      list.close();
      reasons.close();
      await container.pump();

      expect(
        bookDisposed,
        isTrue,
        reason: 'a derived provider that outlives the screen pins the whole '
            'map+filter+sort pipeline to every relay event',
      );
    });
  });
}
