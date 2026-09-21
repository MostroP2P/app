import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a stored preference that lands late does not undo a user change',
    () async {
      SharedPreferences.setMockInitialValues({kBondExplainerOpenKey: true});
      final gate = Completer<SharedPreferences>();
      final container = ProviderContainer(
        overrides: [
          bondExplainerOpenProvider.overrideWith(
            () => BondExplainerNotifier(prefs: () => gate.future),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(bondExplainerOpenProvider), isTrue);
      // The user closes the explainer before the preference store answers.
      unawaited(container.read(bondExplainerOpenProvider.notifier).set(false));
      expect(container.read(bondExplainerOpenProvider), isFalse);

      gate.complete(await SharedPreferences.getInstance());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(bondExplainerOpenProvider), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(kBondExplainerOpenKey),
        isFalse,
      );
    },
  );

  test(
    'the stored preference applies when the user has not touched it',
    () async {
      SharedPreferences.setMockInitialValues({kBondExplainerOpenKey: false});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(bondExplainerOpenProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(bondExplainerOpenProvider), isFalse);
    },
  );
}
