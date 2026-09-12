import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';

const _now = 1700000000;

InvoiceCheck _check(
  String raw, {
  int? expected = 250,
  DecodedInvoice? decoded,
  bool available = true,
  List<String>? nodeNetworks,
}) => checkInvoiceInput(
  raw: raw,
  expectedSats: expected,
  decoded: decoded,
  decoderAvailable: available,
  nodeNetworks: nodeNetworks,
  now: _now,
);

DecodedInvoice _decoded(
  int? sats, {
  int? msat,
  int expiresAt = _now + 600,
  String network = 'mainnet',
}) => (
  amountMsat: msat ?? (sats == null ? null : sats * 1000),
  expiresAt: expiresAt,
  network: network,
);

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
    test('reads mm:ss under an hour and h mm above', () {
      expect(
        formatInvoiceCountdown(const Duration(minutes: 14, seconds: 38)),
        '14:38',
      );
      expect(
        formatInvoiceCountdown(const Duration(hours: 1, minutes: 5)),
        '1 h 05',
      );
      expect(formatInvoiceCountdown(const Duration(seconds: -3)), '00:00');
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
      expect(
        invoiceCountdownTick(const Duration(hours: 2, seconds: 15)),
        const Duration(seconds: 15),
      );
    });
  });

  group('classifyInvoiceInput', () {
    test('tells the shapes apart', () {
      expect(classifyInvoiceInput('  '), InvoiceInputKind.empty);
      expect(classifyInvoiceInput('lnbc2500u1abc'), InvoiceInputKind.bolt11);
      expect(classifyInvoiceInput('LNTB1abc'), InvoiceInputKind.bolt11);
      expect(
        classifyInvoiceInput('lightning:lnbc1abc'),
        InvoiceInputKind.bolt11,
      );
      expect(
        classifyInvoiceInput('satoshi@example.com'),
        InvoiceInputKind.address,
      );
      // The daemon path only resolves `user@domain`; an LNURL would be
      // sent as an invoice, so it is not offered as an address.
      expect(classifyInvoiceInput('LNURL1DP68GURN'), InvoiceInputKind.unknown);
      expect(classifyInvoiceInput('hello'), InvoiceInputKind.unknown);
      expect(classifyInvoiceInput('user@nodomain'), InvoiceInputKind.unknown);
    });
  });

  group('checkInvoiceInput', () {
    final good = _decoded(250);

    test('draws nothing for an empty field', () {
      expect(_check(''), isA<InvoiceCheckNone>());
    });

    test('accepts an unexpired invoice for the trade amount', () {
      final check = _check('lnbc1valid', decoded: good);
      expect(check, isA<InvoiceCheckValid>());
      expect((check as InvoiceCheckValid).sats, 250);
    });

    test('names the amounts of a wrong-amount invoice', () {
      final check = _check('lnbc1wrong', decoded: _decoded(200));
      expect(check, isA<InvoiceCheckError>());
      final error = check as InvoiceCheckError;
      expect(error.problem, InvoiceProblem.wrongAmount);
      expect(error.actualMsat, 200000);
      expect(error.expectedSats, 250);
    });

    test('refuses an expired invoice before comparing amounts', () {
      final check = _check('lnbc1old', decoded: _decoded(200, expiresAt: _now));
      expect((check as InvoiceCheckError).problem, InvoiceProblem.expired);
    });

    test('a sub-sat remainder is a wrong amount, not a rounded match', () {
      final check = _check(
        'lnbc1subsat',
        decoded: _decoded(null, msat: 250500),
      );
      final error = check as InvoiceCheckError;
      expect(error.problem, InvoiceProblem.wrongAmount);
      expect(error.actualMsat, 250500);
      expect(formatInvoiceMsat(250500), '250.5');
      expect(formatInvoiceMsat(250000), '250');
    });

    test('refuses an invoice for another network than the node', () {
      final check = _check(
        'lntb1x',
        decoded: _decoded(250, network: 'testnet'),
        nodeNetworks: const ['mainnet'],
      );
      final error = check as InvoiceCheckError;
      expect(error.problem, InvoiceProblem.wrongNetwork);
      expect(error.invoiceNetwork, 'testnet');
      expect(error.nodeNetwork, 'mainnet');
    });

    test('a matching or unknown node network does not block', () {
      expect(
        _check(
          'lntb1x',
          decoded: _decoded(250, network: 'testnet'),
          nodeNetworks: const ['testnet4'],
        ),
        isA<InvoiceCheckValid>(),
      );
      expect(
        _check('lnbc1x', decoded: good, nodeNetworks: null),
        isA<InvoiceCheckValid>(),
      );
      expect(
        _check('lnbc1x', decoded: good, nodeNetworks: const []),
        isA<InvoiceCheckValid>(),
      );
    });

    test('calls an undecodable invoice malformed', () {
      final check = _check('lnbc1short');
      expect((check as InvoiceCheckError).problem, InvoiceProblem.malformed);
    });

    test('leaves the invoice to the daemon when it cannot judge', () {
      expect(_check('lnbc1x', available: false), isA<InvoiceCheckUnverified>());
      expect(
        _check('lnbc1x', decoded: _decoded(null)),
        isA<InvoiceCheckUnverified>(),
      );
      expect(
        _check('lnbc1x', expected: null, decoded: good),
        isA<InvoiceCheckUnverified>(),
      );
    });

    test('accepts an address and refuses anything else', () {
      expect(_check('satoshi@example.com'), isA<InvoiceCheckAddress>());
      expect(
        (_check('hello') as InvoiceCheckError).problem,
        InvoiceProblem.unrecognized,
      );
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
