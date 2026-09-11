import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/models/node_selector_rules.dart';
import 'package:mostro/src/rust/api/node_stats.dart';
import 'package:mostro/src/rust/api/types.dart';

const _a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _c = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

final _now = DateTime.utc(2026, 9, 11, 12, 0);
int _secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

MostroNodeStats _stats({
  String pubkey = _a,
  DateTime? infoSeenAt,
  DateTime? latestOrderAt,
  Map<String, int> orders = const {},
  List<String> accepted = const [],
  bool? bondRequired,
  BigInt? min,
  BigInt? max,
}) => MostroNodeStats(
  pubkey: pubkey,
  infoSeenAt: infoSeenAt == null ? null : _secs(infoSeenAt),
  latestOrderAt: latestOrderAt == null ? null : _secs(latestOrderAt),
  feePct: null,
  minOrderAmount: min,
  maxOrderAmount: max,
  acceptedCurrencies: accepted,
  escrowMode: 'lightning',
  cashuMintUrl: null,
  bondRequired: bondRequired,
  bondPct: null,
  ordersByFiat: [
    for (final e in orders.entries)
      FiatOrderCount(fiatCode: e.key, count: e.value),
  ],
  totalOrders: orders.values.fold(0, (a, b) => a + b),
);

MostroNodeEntry _entry(String pubkey) => MostroNodeEntry(
  pubkey: pubkey,
  region: null,
  isTrusted: false,
  isActive: false,
  name: null,
  picture: null,
  about: null,
  website: null,
);

void main() {
  group('availabilityOf', () {
    test('fresh heartbeat with orders in my currency is online', () {
      // Arrange
      final s = _stats(
        infoSeenAt: _now.subtract(const Duration(minutes: 5)),
        orders: {'ARS': 12, 'VES': 3},
      );
      // Act / Assert
      expect(availabilityOf(s, 'ARS', _now), NodeAvailability.online);
    });

    test('fresh heartbeat but nothing in my currency is noUsefulOrders', () {
      final s = _stats(
        infoSeenAt: _now.subtract(const Duration(minutes: 5)),
        orders: {'COP': 6},
      );
      expect(availabilityOf(s, 'ARS', _now), NodeAvailability.noUsefulOrders);
    });

    test('no preferred currency: any order counts as useful', () {
      final s = _stats(
        infoSeenAt: _now.subtract(const Duration(minutes: 5)),
        orders: {'COP': 6},
      );
      expect(availabilityOf(s, null, _now), NodeAvailability.online);
    });

    test('stale heartbeat and no orders is unreachable', () {
      final s = _stats(
        infoSeenAt: _now.subtract(
          nodeHeartbeatStaleAfter + const Duration(seconds: 1),
        ),
      );
      expect(availabilityOf(s, 'ARS', _now), NodeAvailability.unreachable);
    });

    test('no heartbeat but open orders keeps a Cashu node reachable', () {
      // mostrod in Cashu mode publishes no info event.
      final s = _stats(
        latestOrderAt: _now.subtract(const Duration(hours: 3)),
        orders: {'ARS': 2},
      );
      expect(availabilityOf(s, 'ARS', _now), NodeAvailability.online);
    });

    test('never heard from is unreachable with no signal', () {
      final s = _stats();
      expect(availabilityOf(s, 'ARS', _now), NodeAvailability.unreachable);
      expect(lastSignalAt(s), isNull);
    });

    test('lastSignalAt is the newer of heartbeat and order', () {
      final s = _stats(
        infoSeenAt: _now.subtract(const Duration(hours: 2)),
        latestOrderAt: _now.subtract(const Duration(hours: 1)),
      );
      expect(lastSignalAt(s), _now.subtract(const Duration(hours: 1)));
    });
  });

  group('blockerOf', () {
    test('bond required blocks even when online', () {
      final s = _stats(
        infoSeenAt: _now,
        orders: {'ARS': 5},
        bondRequired: true,
      );
      expect(blockerOf(s, 'ARS', _now), NodeBlocker.bondUnsupported);
    });

    test('unreachable blocks', () {
      expect(blockerOf(_stats(), 'ARS', _now), NodeBlocker.unreachable);
    });

    test('missing stats never block', () {
      expect(blockerOf(null, 'ARS', _now), isNull);
    });

    test('bond explicitly disabled does not block', () {
      final s = _stats(infoSeenAt: _now, bondRequired: false);
      expect(blockerOf(s, null, _now), isNull);
    });
  });

  group('sortNodes', () {
    test('orders in my currency first, unreachable last, ties by registry', () {
      // Arrange
      final entries = [_entry(_a), _entry(_b), _entry(_c)];
      final stats = {
        _a: _stats(pubkey: _a, infoSeenAt: _now, orders: {'ARS': 2, 'VES': 9}),
        _b: _stats(pubkey: _b),
        _c: _stats(pubkey: _c, infoSeenAt: _now, orders: {'ARS': 7}),
      };
      // Act
      final sorted = sortNodes(entries, stats, 'ARS', _now);
      // Assert
      expect(sorted.map((e) => e.pubkey), [_c, _a, _b]);
    });

    test('nodes without stats keep registry order above the unreachable', () {
      final entries = [_entry(_a), _entry(_b)];
      final stats = {_a: _stats(pubkey: _a)};
      final sorted = sortNodes(entries, stats, 'ARS', _now);
      expect(sorted.map((e) => e.pubkey), [_b, _a]);
    });

    test('falls back to total orders when none are in my currency', () {
      final entries = [_entry(_a), _entry(_b)];
      final stats = {
        _a: _stats(pubkey: _a, infoSeenAt: _now, orders: {'COP': 1}),
        _b: _stats(pubkey: _b, infoSeenAt: _now, orders: {'COP': 4}),
      };
      final sorted = sortNodes(entries, stats, 'ARS', _now);
      expect(sorted.map((e) => e.pubkey), [_b, _a]);
    });
  });

  group('currencyChips', () {
    test('my currency first, capped at five, rest overflow', () {
      final chips = currencyChips([
        'VES',
        'BRL',
        'ARS',
        'EUR',
        'COP',
        'USD',
        'CLP',
        'PEN',
      ], 'ars');
      expect(chips.shown, ['ARS', 'VES', 'BRL', 'EUR', 'COP']);
      expect(chips.overflow, 3);
    });

    test('unaccepted currency is not injected', () {
      final chips = currencyChips(['COP', 'VES'], 'ARS');
      expect(chips.shown, ['COP', 'VES']);
      expect(chips.overflow, 0);
    });
  });

  group('acceptsMyFiat', () {
    test('null when nothing to say', () {
      expect(acceptsMyFiat(_stats(), 'ARS'), isNull);
      expect(acceptsMyFiat(_stats(accepted: ['ARS']), null), isNull);
    });
    test('true / false when both sides are known', () {
      expect(acceptsMyFiat(_stats(accepted: ['ARS']), 'ars'), isTrue);
      expect(acceptsMyFiat(_stats(accepted: ['COP']), 'ARS'), isFalse);
    });
  });

  group('figures', () {
    test('abbreviateSats', () {
      expect(abbreviateSats(BigInt.from(950), 'en'), '950');
      expect(abbreviateSats(BigInt.from(5000), 'en'), '5k');
      expect(abbreviateSats(BigInt.from(1500), 'en'), '1.5k');
      expect(abbreviateSats(BigInt.from(1500), 'es'), '1,5k');
      expect(abbreviateSats(BigInt.from(800000), 'en'), '800k');
      expect(abbreviateSats(BigInt.from(2000000), 'en'), '2M');
    });

    test('satsRange needs both bounds', () {
      expect(satsRange(BigInt.from(5000), BigInt.from(2000000), 'en'), '5k–2M');
      expect(satsRange(null, BigInt.from(2000000), 'en'), isNull);
    });

    test('formatFeePct keeps one decimal at least', () {
      expect(formatFeePct(0.6, 'es'), '0,6');
      expect(formatFeePct(1, 'es'), '1,0');
      expect(formatFeePct(0.25, 'en'), '0.25');
    });

    test('fiatEquivalent converts at the BTC price, omitted without one', () {
      expect(
        fiatEquivalent(
          BigInt.from(5000),
          BigInt.from(2000000),
          36000000, // 36 M ARS per BTC
          'es',
        ),
        '≈ 1.800 – 720.000',
      );
      expect(fiatEquivalent(BigInt.one, BigInt.two, null, 'es'), isNull);
      expect(fiatEquivalent(null, BigInt.two, 1, 'es'), isNull);
    });
  });

  group('pubkey shape', () {
    test('hex and npub pass, others fail', () {
      expect(looksLikeNodePubkey(_a), isTrue);
      expect(looksLikeNodePubkey(' ${_a.toUpperCase()} '), isTrue);
      expect(looksLikeNodePubkey('npub1${'q' * 58}'), isTrue);
      expect(looksLikeNodePubkey('a' * 63), isFalse);
      expect(looksLikeNodePubkey('npub1abc'), isFalse);
      expect(looksLikeNodePubkey(''), isFalse);
    });

    test('nsec is spotted', () {
      expect(looksLikePrivateKey('nsec1xyz'), isTrue);
      expect(looksLikePrivateKey(_a), isFalse);
    });
  });
}
