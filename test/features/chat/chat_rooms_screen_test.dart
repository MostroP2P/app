import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/screens/chat_rooms_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chat_list_fixtures.dart';
import '../../support/provider_harness.dart';
import '../../support/trades_list_fixtures.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<ChatRoomState>? rooms,
}) async {
  tester.view.physicalSize = const Size(360, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = createContainer(
    overrides: chatListOverrides(rooms: rooms, disputes: [kHandoffDispute]),
  );
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => const ChatRoomsScreen())],
    errorBuilder: (_, state) => Scaffold(body: Text('route ${state.uri}')),
  );
  addTearDown(router.dispose);

  await withClock(Clock.fixed(kTradesNow), () async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: buildDarkTheme(),
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('segments carry their pending counts', (tester) async {
    await _pump(tester);

    expect(find.text('Mensajes'), findsOneWidget);
    expect(find.text('Disputas'), findsOneWidget);
    // Two unread messages; one unread dispute.
    expect(find.text('2'), findsWidgets);
    // The old tagline is gone: the group header says it.
    expect(
      find.text('Tus conversaciones de operaciones activas'),
      findsNothing,
    );
  });

  testWidgets('conversations group by whether their trade is open', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('OPERACIONES ACTIVAS'), findsOneWidget);
    expect(find.text('CERRADAS'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('used-jaguar')).dy <
          tester.getTopLeft(find.text('quiet-heron')).dy,
      isTrue,
    );
  });

  testWidgets('the context line names the trade and where it stands', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Le vendes 55 BOB · te toca liberar'), findsOneWidget);
    expect(find.text('Le compras 20.000 ARS · te toca pagar'), findsOneWidget);
    expect(find.text('Le compraste 6.666 ARS · completada'), findsOneWidget);
    // The alias is no longer repeated in the subtitle.
    expect(find.textContaining('Le estás vendiendo sats'), findsNothing);
  });

  testWidgets('an own last message is prefixed', (tester) async {
    await _pump(tester);

    expect(
      find.text('Tú: Te paso el comprobante en un rato', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('opening a conversation clears its badge at once', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(find.text('used-jaguar'));
    await tester.pumpAndSettle();

    expect(find.text('route /chat_room/release'), findsOneWidget);
    final room = container
        .read(chatRoomsNotifierProvider)
        .firstWhere((r) => r.orderId == 'release');
    expect(room.unreadCount, 0);
  });

  testWidgets('the disputes segment says who opened it and when', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Disputas'));
    await withClock(Clock.fixed(kTradesNow), () => tester.pumpAndSettle());

    expect(find.text('La abriste hace 2 h'), findsOneWidget);
    expect(find.text('EN DISPUTA'), findsWidgets);
  });

  testWidgets('with no conversations it explains when a chat opens', (
    tester,
  ) async {
    await _pump(tester, rooms: const []);

    expect(find.text('Todavía no tienes conversaciones'), findsOneWidget);
    expect(
      find.text('El chat se abre cuando una operación queda activa.'),
      findsOneWidget,
    );
  });
}
