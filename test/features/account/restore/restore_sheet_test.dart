import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/restore/restore_run.dart';
import 'package:mostro/features/account/restore/restore_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

/// The restore sheet (20a–20d) in Spanish, the handoff's language, over a
/// page with the button that opens it. The core is replaced by [steps] and
/// [answer].
void main() {
  late StreamController<RestoreProgress> steps;
  late Completer<int> answer;
  late int recoveries;
  late bool closed;


  /// Frames enough for the route to open and the run to subscribe; the
  /// active stage spins, so the tree never settles.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    RestoreSummary summary = const RestoreSummary(
      inProgress: 0,
      needsAction: 0,
    ),
  }) async {
    // Made here, in the test's fake-async zone: a completer made in setUp
    // completes on the real clock, after the test has already looked.
    steps = StreamController<RestoreProgress>.broadcast();
    addTearDown(steps.close);
    answer = Completer<int>();
    recoveries = 0;
    closed = false;
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [restoreSummaryProvider.overrideWith((ref) => summary)],
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () async {
                        await showRestoreSheet(
                          context,
                          run: RestoreRun(
                            progress: () async => steps.stream,
                            recover: () {
                              recoveries++;
                              return answer.future;
                            },
                          ),
                        );
                        closed = true;
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await frames(tester);
  }

  Future<void> send(WidgetTester tester, List<RestoreProgress> sent) async {
    sent.forEach(steps.add);
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester, {Object? error}) async {
    if (error != null) {
      answer.completeError(error);
    } else {
      answer.complete(3);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('20a: the three stages, the second one running', (tester) async {
    await open(tester);
    await send(tester, [const RestoreProgress.connected()]);

    expect(find.text('Restaurando tu cuenta'), findsOneWidget);
    expect(find.text('Puede tardar unos segundos'), findsOneWidget);
    expect(find.text('Conectado con el nodo Mostro'), findsOneWidget);
    expect(find.text('Solicitando tus órdenes'), findsOneWidget);
    expect(find.text('Cargando detalles'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('restore.cancel')), findsOneWidget);
  });

  testWidgets('20b: the total and the count, in the loading row', (
    tester,
  ) async {
    await open(tester);
    await send(tester, const [
      RestoreProgress.connected(),
      RestoreProgress.found(found: 3, toLoad: 3),
      RestoreProgress.loaded(done: 2, toLoad: 3),
    ]);

    expect(find.text('2 de 3 órdenes recuperadas'), findsOneWidget);
    expect(find.text('3 órdenes encontradas'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('restore.stage.2')),
        matching: find.text('2/3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the counter reads as a count of orders, not as 2/3', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await send(tester, const [
      RestoreProgress.connected(),
      RestoreProgress.found(found: 3, toLoad: 3),
      RestoreProgress.loaded(done: 2, toLoad: 3),
    ]);

    expect(find.bySemanticsLabel('2 de 3 órdenes'), findsOneWidget);
    expect(find.bySemanticsLabel('2/3'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a tap outside does not close it; Cancelar does', (
    tester,
  ) async {
    await open(tester);

    await tester.tapAt(const Offset(180, 20));
    await frames(tester);
    expect(find.text('Restaurando tu cuenta'), findsOneWidget);

    await tester.tap(find.byKey(const Key('restore.cancel')));
    await frames(tester);
    expect(closed, isTrue);
    expect(find.text('Restaurando tu cuenta'), findsNothing);
  });

  group('20c', () {
    testWidgets('says the account was imported and marks the failed stage', (
      tester,
    ) async {
      await open(tester);
      await send(tester, [const RestoreProgress.connected()]);
      await finish(tester, error: Exception('NoDaemonResponse'));

      expect(find.text('No pudimos restaurar tus órdenes'), findsOneWidget);
      expect(find.text('Tu cuenta sí quedó importada'), findsOneWidget);
      expect(find.text('Sin respuesta'), findsOneWidget);
      expect(find.textContaining('desde Cuenta.', findRichText: true),
          findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.byIcon(Icons.error_outline),
        findsOneWidget,
        reason: 'one error icon in the whole sheet',
      );
    });

    testWidgets('Reintentar asks the node again', (tester) async {
      await open(tester);
      await finish(tester, error: Exception('offline'));
      answer = Completer<int>();

      await tester.tap(find.byKey(const Key('restore.retry')));
      await frames(tester);

      expect(recoveries, 2);
      expect(find.text('Restaurando tu cuenta'), findsOneWidget);
    });

    testWidgets('Continuar sin restaurar closes it', (tester) async {
      await open(tester);
      await finish(tester, error: Exception('offline'));

      await tester.tap(find.byKey(const Key('restore.continue')));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
    });
  });

  group('20d', () {
    testWidgets('sums up what came back and what waits for the user', (
      tester,
    ) async {
      await open(
        tester,
        summary: const RestoreSummary(inProgress: 1, needsAction: 1),
      );
      await send(tester, const [
        RestoreProgress.connected(),
        RestoreProgress.found(found: 3, toLoad: 3),
        RestoreProgress.loaded(done: 3, toLoad: 3),
      ]);
      await finish(tester);

      expect(find.text('Cuenta restaurada'), findsOneWidget);
      expect(find.text('Recuperamos todo lo que el nodo tenía'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(
        find.text('Reputación'),
        findsNothing,
        reason: 'the summary has no reputation card',
      );
      expect(
        find.text('Tienes 1 orden activa esperando tu acción'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('restore.partial')), findsNothing);

      await tester.tap(find.byKey(const Key('restore.close')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('an account with no orders is not an error', (tester) async {
      await open(tester);
      await send(tester, const [
        RestoreProgress.connected(),
        RestoreProgress.found(found: 0, toLoad: 0),
      ]);
      answer.complete(0);
      await tester.pumpAndSettle();

      expect(find.text('Esta cuenta no tenía órdenes en el nodo'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      expect(find.byKey(const Key('restore.action')), findsNothing);
    });

    testWidgets('orders that did not load are named, with a retry', (
      tester,
    ) async {
      await open(tester);
      await send(tester, const [
        RestoreProgress.connected(),
        RestoreProgress.found(found: 3, toLoad: 3),
        RestoreProgress.loaded(done: 1, toLoad: 3),
      ]);
      await finish(tester);

      expect(
        find.text('2 de 3 órdenes no se pudieron cargar'),
        findsOneWidget,
      );
      answer = Completer<int>();
      await tester.tap(find.byKey(const Key('restore.partial.retry')));
      await frames(tester);
      expect(recoveries, 2);
    });
  });
}
