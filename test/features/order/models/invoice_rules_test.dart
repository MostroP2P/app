import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;
import 'package:mostro/src/rust/api/types.dart' show InvoiceVerdict;

void main() {
  // Issue #720: the invoice screens grouped sats by hand (none up to five
  // digits, a thin space above) while every other screen used the locale's
  // separator, so `2439 sats` sat next to `≈ 1.449 sats`.
  group('formatInvoiceSats', () {
    test("groups thousands with the locale's separator", () {
      expect(formatInvoiceSats(2439, 'es'), '2.439');
      expect(formatInvoiceSats(2439, 'en'), '2,439');
      expect(formatInvoiceSats(1234567, 'es'), '1.234.567');
      expect(formatInvoiceSats(300000, 'en'), '300,000');
    });

    test('leaves three digits or fewer alone', () {
      expect(formatInvoiceSats(250, 'es'), '250');
      expect(formatInvoiceSats(0, 'en'), '0');
    });
  });

  group('stepExpiry', () {
    test('the taker owes the step: the order goes back to the book', () {
      expect(
        stepExpiry(buyerStep: true, kind: rust_types.OrderKind.sell),
        StepExpiry.backToBook,
      );
      expect(
        stepExpiry(buyerStep: false, kind: rust_types.OrderKind.buy),
        StepExpiry.backToBook,
      );
    });

    test('the maker owes the step: the order is cancelled', () {
      expect(
        stepExpiry(buyerStep: true, kind: rust_types.OrderKind.buy),
        StepExpiry.cancelled,
      );
      expect(
        stepExpiry(buyerStep: false, kind: rust_types.OrderKind.sell),
        StepExpiry.cancelled,
      );
    });
  });

  group('formatInvoiceMsat', () {
    test('shows whole sats like formatInvoiceSats', () {
      expect(formatInvoiceMsat(2439000, 'es'), '2.439');
    });

    test("keeps a sub-sat remainder behind the locale's decimal separator", () {
      expect(formatInvoiceMsat(2439500, 'es'), '2.439,5');
      expect(formatInvoiceMsat(2439500, 'en'), '2,439.5');
      expect(formatInvoiceMsat(250001, 'en'), '250.001');
    });

    // The verdict carries the invoice's amount as a u64: dividing by 1000 as a
    // double would round it before NumberFormat sees it.
    test('keeps every digit of an amount past double precision', () {
      expect(
        formatInvoiceMsat(9007199254740993, 'en'),
        '9,007,199,254,740.993',
      );
    });
  });

  group('holdInvoiceFee', () {
    test('recovers the seller half of the fee mostrod adds', () {
      // 0.6 % of 100 000 sats, halved: 300.
      expect(holdInvoiceFee(holdSats: 100300, nodeFee: 0.006), 300);
      // round(0.01 · 250 / 2) = round(1.25) = 1.
      expect(holdInvoiceFee(holdSats: 251, nodeFee: 0.01), 1);
    });

    test('is zero on a node without fee', () {
      expect(holdInvoiceFee(holdSats: 250, nodeFee: 0), 0);
    });

    test('is null when the node fee is unknown or unusable', () {
      expect(holdInvoiceFee(holdSats: 250, nodeFee: null), isNull);
      expect(holdInvoiceFee(holdSats: 250, nodeFee: double.nan), isNull);
      expect(holdInvoiceFee(holdSats: 0, nodeFee: 0.006), isNull);
    });
  });

  group('invoiceCheckFromVerdict', () {
    test('maps every verdict onto the row model', () {
      expect(
        invoiceCheckFromVerdict(const InvoiceVerdict.empty()),
        isA<InvoiceCheckNone>(),
      );
      expect(
        invoiceCheckFromVerdict(const InvoiceVerdict.unverified()),
        isA<InvoiceCheckUnverified>(),
      );
      expect(
        invoiceCheckFromVerdict(const InvoiceVerdict.address()),
        isA<InvoiceCheckAddress>(),
      );
      final valid = invoiceCheckFromVerdict(
        InvoiceVerdict.valid(
          sats: BigInt.from(250),
          expiresAt: BigInt.from(1700000600),
        ),
      );
      expect(valid, isA<InvoiceCheckValid>());
      expect((valid as InvoiceCheckValid).sats, 250);
      expect(valid.expiresAt, 1700000600);
    });

    test('maps every rejected problem', () {
      for (final (wire, local) in [
        (rust_types.InvoiceProblem.unrecognized, InvoiceProblem.unrecognized),
        (rust_types.InvoiceProblem.malformed, InvoiceProblem.malformed),
        (rust_types.InvoiceProblem.expired, InvoiceProblem.expired),
        (rust_types.InvoiceProblem.wrongAmount, InvoiceProblem.wrongAmount),
        (
          rust_types.InvoiceProblem.expiresTooSoon,
          InvoiceProblem.expiresTooSoon,
        ),
        (rust_types.InvoiceProblem.wrongNetwork, InvoiceProblem.wrongNetwork),
      ]) {
        final check = invoiceCheckFromVerdict(
          InvoiceVerdict.rejected(problem: wire),
        );
        expect(check, isA<InvoiceCheckError>(), reason: '$wire');
        expect((check as InvoiceCheckError).problem, local, reason: '$wire');
      }
    });

    test('carries the fields each problem names', () {
      final wrong = invoiceCheckFromVerdict(
        InvoiceVerdict.rejected(
          problem: rust_types.InvoiceProblem.wrongAmount,
          actualMsat: BigInt.from(300500),
          expectedSats: BigInt.from(250),
        ),
      );
      expect(wrong, isA<InvoiceCheckError>());
      final e = wrong as InvoiceCheckError;
      expect(e.problem, InvoiceProblem.wrongAmount);
      expect(e.actualMsat, 300500);
      expect(e.expectedSats, 250);

      final soon =
          invoiceCheckFromVerdict(
                InvoiceVerdict.rejected(
                  problem: rust_types.InvoiceProblem.expiresTooSoon,
                  minRemainingSecs: BigInt.from(3600),
                ),
              )
              as InvoiceCheckError;
      expect(soon.problem, InvoiceProblem.expiresTooSoon);
      expect(soon.minRemainingSecs, 3600);

      final network =
          invoiceCheckFromVerdict(
                const InvoiceVerdict.rejected(
                  problem: rust_types.InvoiceProblem.wrongNetwork,
                  invoiceNetwork: 'testnet',
                  nodeNetwork: 'mainnet',
                ),
              )
              as InvoiceCheckError;
      expect(network.problem, InvoiceProblem.wrongNetwork);
      expect(network.invoiceNetwork, 'testnet');
      expect(network.nodeNetwork, 'mainnet');
    });

    test('only a usable verdict enables submission', () {
      expect(invoiceCheckAllowsSubmit(const InvoiceCheckNone()), isFalse);
      expect(invoiceCheckAllowsSubmit(const InvoiceCheckPending()), isFalse);
      expect(
        invoiceCheckAllowsSubmit(
          const InvoiceCheckError(InvoiceProblem.expired),
        ),
        isFalse,
      );
      expect(invoiceCheckAllowsSubmit(const InvoiceCheckUnverified()), isTrue);
      expect(invoiceCheckAllowsSubmit(const InvoiceCheckAddress()), isTrue);
      expect(invoiceCheckAllowsSubmit(const InvoiceCheckValid(250)), isTrue);
    });
  });

  group('invoiceCheckWord', () {
    // `invoice.check` is what automation reads instead of the row's
    // translated sentence, so a problem shipped without a word leaves a
    // scenario asserting on a field that never appears.
    test('every problem has a distinct kebab-case word', () {
      final words = {
        for (final problem in InvoiceProblem.values)
          problem: invoiceCheckWord(InvoiceCheckError(problem)),
      };

      expect(words[InvoiceProblem.expiresTooSoon], 'expires-too-soon');
      expect(words[InvoiceProblem.wrongAmount], 'wrong-amount');
      expect(words[InvoiceProblem.wrongNetwork], 'wrong-network');
      expect(words[InvoiceProblem.expired], 'expired');
      expect(words[InvoiceProblem.malformed], 'malformed');
      expect(words[InvoiceProblem.unrecognized], 'unrecognized');

      for (final word in words.values) {
        expect(word, isNotNull);
        expect(word, matches(RegExp(r'^[a-z]+(-[a-z]+)*$')), reason: '$word');
      }
      expect(words.values.toSet(), hasLength(InvoiceProblem.values.length));
    });

    test('the two accepted inputs carry a word of their own', () {
      expect(invoiceCheckWord(const InvoiceCheckValid(250)), 'valid');
      expect(invoiceCheckWord(const InvoiceCheckAddress()), 'address');
    });

    // The screen draws the row for exactly the states that have a word, so
    // absence means "still judging" — never "fine". A harness that read it
    // as a boolean would call an unjudged invoice good.
    test('an open verdict has no word', () {
      expect(invoiceCheckWord(const InvoiceCheckNone()), isNull);
      expect(invoiceCheckWord(const InvoiceCheckPending()), isNull);
      expect(invoiceCheckWord(const InvoiceCheckUnverified()), isNull);
    });
  });

  group('normalizeInvoiceInput', () {
    test('strips whitespace and the lightning scheme', () {
      expect(normalizeInvoiceInput('  lightning:lnbc1abc \n'), 'lnbc1abc');
      expect(normalizeInvoiceInput('LIGHTNING: lnbc1abc'), 'lnbc1abc');
      expect(
        normalizeInvoiceInput('satoshi@example.com'),
        'satoshi@example.com',
      );
    });

    test(
      'drops the line breaks and spaces an invoice copied from mail has',
      () {
        expect(
          normalizeInvoiceInput('lightning:lnbc1850n1p\r\n  qqqsyq\tcyq5'),
          'lnbc1850n1pqqqsyqcyq5',
        );
        expect(normalizeInvoiceInput('lightning: lnbc1 abc'), 'lnbc1abc');
      },
    );
  });

  group('counterpartStars', () {
    test('shows the rating once there are reviews', () {
      expect(counterpartStars(4.93, 16), '★ 4.9');
    });

    test('is null for a counterpart with no rated trade', () {
      expect(counterpartStars(0, 0), isNull);
      expect(counterpartStars(null, null), isNull);
    });
  });

  group('nwcInvoiceExpirySecs', () {
    // Left to the wallet, an NWC invoice may expire inside the node's
    // `invoice_expiration_window` and be refused by the check on every
    // try, with nothing the buyer can do about it.
    test('outlives the node window by the margin', () {
      expect(nwcInvoiceExpirySecs(600), 600 + kNwcInvoiceExpiryMarginSecs);
    });

    test('an unknown window still asks for the margin', () {
      expect(nwcInvoiceExpirySecs(null), kNwcInvoiceExpiryMarginSecs);
    });
  });
}
