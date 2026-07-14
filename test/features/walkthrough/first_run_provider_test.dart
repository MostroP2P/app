import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirstRunNotifier', () {
    test('starts loading then resolves to the stored flag', () async {
      SharedPreferences.setMockInitialValues({kFirstRunCompleteKey: true});

      final notifier = FirstRunNotifier();
      expect(notifier.state, isA<AsyncLoading<bool>>());

      await pumpEventQueue();
      expect(notifier.state, const AsyncData<bool>(true));
    });

    test('defaults to false (first launch) when the key is absent', () async {
      SharedPreferences.setMockInitialValues({});

      final notifier = FirstRunNotifier();
      await pumpEventQueue();

      expect(notifier.state, const AsyncData<bool>(false));
    });

    test('initialValue skips the loading state', () {
      final notifier = FirstRunNotifier(initialValue: true);
      expect(notifier.state, const AsyncData<bool>(true));
    });

    test('markFirstRunComplete() persists and exposes data(true)', () async {
      SharedPreferences.setMockInitialValues({});

      final notifier = FirstRunNotifier(initialValue: false);
      await notifier.markFirstRunComplete();

      expect(notifier.state, const AsyncData<bool>(true));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFirstRunCompleteKey), isTrue);
    });
  });
}
