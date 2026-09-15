import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/lifecycle/app_lifecycle_service.dart';

void main() {
  const debounce = Duration(milliseconds: 50);

  late int resumes;
  late int pauses;
  late AppLifecycleService service;

  setUp(() {
    resumes = 0;
    pauses = 0;
  });

  AppLifecycleService attach(
    WidgetTester tester, {
    Future<void> Function()? onResume,
  }) {
    service = AppLifecycleService(
      onResume: onResume ?? () async => resumes++,
      onPause: () => pauses++,
      debounce: debounce,
    )..attach();
    addTearDown(service.detach);
    return service;
  }

  Future<void> deliver(
    WidgetTester tester,
    List<AppLifecycleState> states,
  ) async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(debounce * 2);
  }

  testWidgets('a paused → resumed suspension fires the resume handler once', (
    tester,
  ) async {
    // Arrange
    attach(tester);

    // Act
    await deliver(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
    ]);

    // Assert
    expect(pauses, 1);
    expect(resumes, 1);
  });

  testWidgets('hidden arms the latch too — what web and desktop deliver', (
    tester,
  ) async {
    attach(tester);

    await deliver(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.resumed,
    ]);

    expect(resumes, 1);
  });

  testWidgets(
    'an inactive → resumed flap never suspended anything and is ignored',
    (tester) async {
      // A permission dialog, a share sheet, an app-switcher peek.
      attach(tester);

      await deliver(tester, [
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);

      expect(pauses, 0);
      expect(resumes, 0);
    },
  );

  testWidgets('a resume that flaps within the debounce runs once, at the end', (
    tester,
  ) async {
    attach(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 10));
    expect(resumes, 0, reason: 'still inside the debounce');
    await tester.pump(debounce * 2);

    expect(resumes, 1);
    expect(pauses, 2);
  });

  testWidgets('a second paused while suspended does not re-arm or re-pause', (
    tester,
  ) async {
    attach(tester);

    await deliver(tester, [
      AppLifecycleState.paused,
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
    ]);

    expect(pauses, 1);
    expect(resumes, 1);
  });

  testWidgets('a throwing resume handler is logged, not rethrown', (
    tester,
  ) async {
    attach(tester, onResume: () async => throw StateError('boom'));

    await deliver(tester, [
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
    ]);

    expect(tester.takeException(), isNull);
  });

  testWidgets('detach stops a pending resume', (tester) async {
    final s = attach(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    s.detach();
    await tester.pump(debounce * 2);

    expect(resumes, 0);
  });

  test('the service exposes its latch for tests', () {
    final s = AppLifecycleService(onResume: () async {});
    expect(s.suspended, isFalse);
    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(s.suspended, isTrue);
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(s.suspended, isFalse);
    s.detach();
  });
}
