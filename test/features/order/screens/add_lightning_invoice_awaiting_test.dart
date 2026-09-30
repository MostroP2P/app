import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/order/widgets/invoice_input_field.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

/// #615: an invoice the node has not answered yet is not an error. The
/// submission reached the relays and the node may still accept it — a
/// lightning address costs it an LNURL round trip — and the late reply moves
/// the screen on by itself. So the screen says it is waiting, in the neutral
/// style, with no error readout and no snack bar blaming the connection.

Finder _semantics(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
);

final _en = AppLocalizationsEn();

Future<void> _pumpAndSubmit(
  WidgetTester tester,
  Object error, {
  Future<void> Function()? submit,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWalletConnectedProvider.overrideWithValue(false),
        tradeAmountProvider.overrideWith(
          (ref, orderId) => Stream.value(BigInt.from(999)),
        ),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        tradeInfoProvider.overrideWith((ref, orderId) async => null),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddLightningInvoiceScreen(
          orderId: 'order-1',
          submitInvoice:
              (orderId, invoice, sats) async =>
                  submit != null ? await submit() : throw error,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.enterText(find.byType(TextField), 'lnbc1short');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.tap(_semantics('invoice.submit'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('no verdict yet: a waiting note, not a connection error', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      // Act
      await _pumpAndSubmit(
        tester,
        Exception('AnyhowException(InvoiceAwaitingDaemon)'),
      );

      // Assert
      expect(_semantics('invoice.awaiting'), findsOneWidget);
      expect(find.text(_en.invoiceAwaitingNode), findsOneWidget);
      expect(_semantics('invoice.error'), findsNothing);
      expect(find.text(_en.sessionTimeoutMessage), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      // The form stays: if the node never answers, the buyer can send again.
      expect(_semantics('invoice.text'), findsOneWidget);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a long silence invites sending again', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      // Arrange: a late rejection is only logged, so the screen cannot wait
      // on the node forever.
      await _pumpAndSubmit(
        tester,
        Exception('AnyhowException(InvoiceAwaitingDaemon)'),
      );
      expect(find.text(_en.invoiceAwaitingNode), findsOneWidget);

      // Act
      await tester.pump(const Duration(seconds: 61));

      // Assert: still the neutral readout, now saying to send it again.
      expect(_semantics('invoice.awaiting'), findsOneWidget);
      expect(find.text(_en.invoiceAwaitingNodeLong), findsOneWidget);
      expect(find.text(_en.invoiceAwaitingNode), findsNothing);
      expect(_semantics('invoice.error'), findsNothing);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('waiting never paints the field as an error', (tester) async {
    final semantics = tester.ensureSemantics();
    bool fieldInError() =>
        tester
            .widget<InvoiceInputField>(find.byType(InvoiceInputField))
            .hasError;
    try {
      // Act
      await _pumpAndSubmit(
        tester,
        Exception('AnyhowException(InvoiceAwaitingDaemon)'),
      );

      // Assert: the note is neutral, and so is the field — short wait and
      // long wait alike (PR #617 review).
      expect(_semantics('invoice.awaiting'), findsOneWidget);
      expect(fieldInError(), isFalse);
      await tester.pump(const Duration(seconds: 61));
      expect(find.text(_en.invoiceAwaitingNodeLong), findsOneWidget);
      expect(fieldInError(), isFalse);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('editing the field clears the waiting note', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      // Arrange
      await _pumpAndSubmit(
        tester,
        Exception('AnyhowException(InvoiceAwaitingDaemon)'),
      );
      expect(_semantics('invoice.awaiting'), findsOneWidget);

      // Act
      await tester.enterText(find.byType(TextField), 'lnbc1other');
      await tester.pump();

      // Assert
      expect(_semantics('invoice.awaiting'), findsNothing);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('an answer about an input since edited is not shown', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final pending = Completer<void>();
    try {
      // Arrange: the submission is still waiting for the node.
      await _pumpAndSubmit(
        tester,
        Exception('unused'),
        submit: () => pending.future,
      );

      // Act: the buyer edits the field, then the old submission times out.
      await tester.enterText(find.byType(TextField), 'lnbc1other');
      await tester.pump();
      pending.completeError(
        Exception('AnyhowException(InvoiceAwaitingDaemon)'),
      );
      await tester.pump();
      await tester.pump();

      // Assert: the note was about the text that was sent, not this one.
      expect(_semantics('invoice.awaiting'), findsNothing);
      expect(_semantics('invoice.error'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a real rejection is still an error', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpAndSubmit(
        tester,
        Exception(
          'AnyhowException(Order rejected: invalid Lightning invoice.)',
        ),
      );

      expect(_semantics('invoice.error'), findsOneWidget);
      expect(_semantics('invoice.awaiting'), findsNothing);
      expect(
        tester
            .widget<InvoiceInputField>(find.byType(InvoiceInputField))
            .hasError,
        isTrue,
        reason: 'a rejection still marks the field',
      );
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
