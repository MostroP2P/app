import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;
import 'package:mostro/src/rust/api/types.dart' show InvoiceVerdict;

void main() {
  group('invoiceOrderTag', () {
    test('keeps the first eight characters behind a hash', () {
      expect(invoiceOrderTag('09150348-1a2b-4c3d'), '#09150348');
    });

    test('keeps a short id whole', () {
      expect(invoiceOrderTag('order-1'), '#order-1');
    });
  });

  group('formatInvoiceSats', () {
    test('has no separator up to five digits', () {
      expect(formatInvoiceSats(250), '250');
      expect(formatInvoiceSats(99999), '99999');
    });

    test('groups by a thin space from six digits', () {
      expect(formatInvoiceSats(300000), '300 000');
      expect(formatInvoiceSats(1234567), '1 234 567');
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

  group('countdown', () {
    test('reads mm:ss under an hour and the localized h mm above', () {
      String hours(String h, String m) => '$h Std. $m';
      expect(
        formatInvoiceCountdown(
          const Duration(minutes: 14, seconds: 38),
          hours: hours,
        ),
        '14:38',
      );
      expect(
        formatInvoiceCountdown(
          const Duration(hours: 1, minutes: 5),
          hours: hours,
        ),
        '1 Std. 05',
      );
      expect(
        formatInvoiceCountdown(const Duration(seconds: -3), hours: hours),
        '00:00',
      );
    });

    test('turns urgent under a minute', () {
      expect(isInvoiceCountdownUrgent(const Duration(seconds: 60)), isFalse);
      expect(isInvoiceCountdownUrgent(const Duration(seconds: 59)), isTrue);
    });

    test('ticks every second under an hour, on the minute above', () {
      expect(
        invoiceCountdownTick(const Duration(minutes: 10)),
        const Duration(seconds: 1),
      );
      // 2:00:15 still reads 2 h 00 at +15 s; it turns 1 h 59 at +16 s.
      expect(
        invoiceCountdownTick(const Duration(hours: 2, seconds: 15)),
        const Duration(seconds: 16),
      );
      // 2:00:00 turns 1 h 59 one second later, not a minute later.
      expect(
        invoiceCountdownTick(const Duration(hours: 2)),
        const Duration(seconds: 1),
      );
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
          expiresAt: intToPlatformInt64(1700000600),
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

  group('normalizeInvoiceInput', () {
    test('strips whitespace and the lightning scheme', () {
      expect(normalizeInvoiceInput('  lightning:lnbc1abc \n'), 'lnbc1abc');
      expect(normalizeInvoiceInput('LIGHTNING: lnbc1abc'), 'lnbc1abc');
      expect(
        normalizeInvoiceInput('satoshi@example.com'),
        'satoshi@example.com',
      );
    });
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
}
