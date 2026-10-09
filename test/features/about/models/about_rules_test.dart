import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/about/models/about_rules.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _es = lookupAppLocalizations(const Locale('es'));

final _pubkey = '00007cb3${'a1' * 24}95d23f91';
final _lndKey = '02d3280a${'b2' * 24}c5198fc9';
const _lndCommit = 'b9ea7070123456789abcdef0123456789abcdef0';

MostroInstance _node([Map<String, String> extra = const {}]) =>
    MostroInstance.fromTags([
      ['d', _pubkey],
      for (final e in extra.entries) [e.key, e.value],
    ]);

/// The node the handoff draws on 12a/12b.
final _handoffNode = _node({
  'min_order_amount': '500',
  'max_order_amount': '300000',
  'fee': '0',
  'expiration_hours': '23',
  'max_orders_per_response': '10',
  'lnd_node_alias': 'Bitcoin Bolivia 🥜⚡',
  'lnd_node_pubkey': _lndKey,
  'lnd_uris': '$_lndKey@node.example.onion:9735',
  'lnd_version': '0.20.0-beta commit=v0.20.0-beta',
  'lnd_commit_hash': _lndCommit,
  'lnd_chains': 'bitcoin',
  'lnd_networks': 'mainnet',
});

List<String> _labels(List<TechSection> sections) => [
  for (final s in sections) ...s.rows.map((r) => r.label),
];

TechRow _row(List<TechSection> sections, String label) =>
    sections.expand((s) => s.rows).firstWhere((r) => r.label == label);

void main() {
  group('value shaping', () {
    test('lndVersionOnly drops the commit suffix the node appends', () {
      expect(lndVersionOnly('0.20.0-beta commit=v0.20.0-beta'), '0.20.0-beta');
      expect(lndVersionOnly('  0.18.0  '), '0.18.0');
      expect(lndVersionOnly(''), '');
    });

    test('shortHash keeps seven characters', () {
      expect(shortHash(_lndCommit), 'b9ea707');
      expect(shortHash('abc'), 'abc');
    });

    test('splitTagList trims and drops empty entries', () {
      expect(splitTagList(' bitcoin, ,litecoin '), ['bitcoin', 'litecoin']);
      expect(splitTagList(null), isEmpty);
    });

    test('formatPercent follows the locale and rejects unusable values', () {
      expect(formatPercent(0.006, _en), '0.6%');
      expect(formatPercent(0.006, _es), '0,6\u00A0%');
      expect(formatPercent(0.335, _en), '33.5%');
      expect(formatPercent(0, _en), '0%');
      expect(formatPercent(double.infinity, _en), isNull);
      // A finite fraction the parser accepts (bond_amount_pct is uncapped)
      // that overflows once scaled to a percentage.
      expect(formatPercent(1e308, _en), isNull);
      expect(formatPercent(null, _en), isNull);
    });

    test('a figure and its unit never split, in every locale', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        for (final text in [l10n.aboutFeeValue('1'), l10n.aboutHoursShort(1)]) {
          expect(text, isNot(contains(' ')), reason: '$locale: "$text"');
        }
      }
    });
  });

  group('NodeLimits', () {
    test('formats the three figures of a loaded node', () {
      final limits = NodeLimits.of(_handoffNode, _en);

      expect(limits.min, '500');
      expect(limits.max, '300,000');
      expect(limits.fee, '0%');
    });

    test('reads a dash for every figure while the node is missing', () {
      final limits = NodeLimits.of(null, _en);

      expect([limits.min, limits.max, limits.fee], everyElement(missingFigure));
    });
  });

  group('price sources', () {
    test('read by the providers\' names', () {
      expect(
        [
          'yadio',
          'coingecko',
          'currency_api',
          'blockchain',
          'eltoque',
          'nostr',
        ].map(priceSourceName),
        [
          'Yadio',
          'CoinGecko',
          'Currency API',
          'Blockchain.com',
          'El Toque',
          'Nostr',
        ],
      );
    });

    test('a provider the app does not know reads as the node sent it', () {
      expect(priceSourceName('newsource'), 'newsource');
      expect(priceSourceName('CustomProvider'), 'CustomProvider');
      expect(priceSourceName('CoinGecko'), 'CoinGecko');
    });

    test('get a group of their own, one row each, after the bond', () {
      final without = nodeTechSections(_handoffNode, _en);
      final sections = nodeTechSections(
        _handoffNode,
        _en,
        priceSources: const ['blockchain', 'coingecko', 'yadio'],
      );

      expect(sections.map((s) => s.title), [
        'Mostro',
        'Anti-abuse Bond',
        'Price',
        'Lightning Network',
      ]);
      expect(sections[2].rows.map((r) => (r.label, r.value)), [
        ('Source', 'Blockchain.com'),
        ('Source', 'CoinGecko'),
        ('Source', 'Yadio'),
      ]);
      // The other groups are unchanged.
      expect(
        sections.first.rows.map((r) => r.label),
        without.first.rows.map((r) => r.label),
      );
      expect(nodeFieldCount(sections), nodeFieldCount(without) + 3);
    });

    test('a node that names none has no price group', () {
      for (final sources in [null, const <String>[]]) {
        final sections = nodeTechSections(
          _handoffNode,
          _en,
          priceSources: sources,
        );
        expect(sections.map((s) => s.title), isNot(contains('Price')));
      }
    });
  });

  group('NodeSummary', () {
    const node = MostroInstance(
      pubKey: 'node',
      expirationHours: 24,
      bondPolicy: BondPolicy.enabled,
      bondAmountPct: 0.015,
    );

    test('a node that asks for a deposit reads its share, in the locale', () {
      expect(NodeSummary.of(node, _en).deposit, '1.5%');
      expect(NodeSummary.of(node, _es).deposit, '1,5\u00A0%');
    });

    test('a floor goes under the share, in the locale', () {
      const floored = MostroInstance(
        pubKey: 'node',
        bondPolicy: BondPolicy.enabled,
        bondAmountPct: 0.01,
        bondBaseAmountSats: 1000,
      );
      final en = NodeSummary.of(floored, _en);
      final es = NodeSummary.of(floored, _es);

      expect((en.deposit, en.depositUnit), ('1%', 'min. 1,000 sats'));
      expect((es.deposit, es.depositUnit), ('1\u00A0%', 'mín. 1.000 sats'));
    });

    test('a zero share reads as the floor it locks, not 0%', () {
      final summary = NodeSummary.of(
        const MostroInstance(
          pubKey: 'node',
          bondPolicy: BondPolicy.enabled,
          bondAmountPct: 0,
          bondBaseAmountSats: 1000,
        ),
        _en,
      );

      expect((summary.deposit, summary.depositUnit), ('1,000', 'sats'));
    });

    test(
      'a share the node did not send usably reads as the floor it locks',
      () {
        // bond_amount_pct negative or malformed: the parser drops it, and the
        // daemon, reading it as zero, locks the floor alone.
        final summary = NodeSummary.of(
          const MostroInstance(
            pubKey: 'node',
            bondPolicy: BondPolicy.enabled,
            bondBaseAmountSats: 1000,
          ),
          _en,
        );

        expect((summary.deposit, summary.depositUnit), ('1,000', 'sats'));
      },
    );

    test('no share and no floor lock nothing, so read no', () {
      for (final pct in const [0.0, null]) {
        final summary = NodeSummary.of(
          MostroInstance(
            pubKey: 'node',
            bondPolicy: BondPolicy.enabled,
            bondAmountPct: pct,
            bondBaseAmountSats: 0,
          ),
          _en,
        );

        expect(summary.deposit, _en.aboutNodeDepositNone, reason: '$pct');
        expect(summary.depositUnit, isNull, reason: '$pct');
      }
    });

    test('a share too large to show reads a dash, not the floor', () {
      final summary = NodeSummary.of(
        const MostroInstance(
          pubKey: 'node',
          bondPolicy: BondPolicy.enabled,
          bondAmountPct: 1e308,
          bondBaseAmountSats: 1000,
        ),
        _en,
      );

      expect((summary.deposit, summary.depositUnit), (missingFigure, null));
    });

    test('a share with no floor goes alone', () {
      final summary = NodeSummary.of(
        const MostroInstance(
          pubKey: 'node',
          bondPolicy: BondPolicy.enabled,
          bondAmountPct: 0.01,
          bondBaseAmountSats: 0,
        ),
        _en,
      );

      expect((summary.deposit, summary.depositUnit), ('1%', null));
    });

    test('a node with no deposit, or one that predates them, reads no', () {
      for (final policy in [BondPolicy.disabled, BondPolicy.unsupported]) {
        final summary = NodeSummary.of(
          MostroInstance(pubKey: 'node', bondPolicy: policy),
          _en,
        );
        expect(summary.deposit, _en.aboutNodeDepositNone, reason: '$policy');
        expect(summary.depositUnit, isNull, reason: '$policy');
      }
    });

    test('lists the accepted currencies, or all when the node sets none', () {
      String currencies(String? accepted) =>
          NodeSummary.of(
            MostroInstance(pubKey: 'node', fiatCurrenciesAccepted: accepted),
            _en,
          ).currencies;

      expect(currencies('ARS,EUR,USD'), 'ARS, EUR, USD');
      expect(currencies('ARS,BRL,CUP,EUR,USD,VES'), 'ARS, BRL +4');
      expect(currencies(null), _en.aboutFiatCurrenciesAll);
      expect(currencies(''), _en.aboutFiatCurrenciesAll);
    });

    test('says how long an order stays published', () {
      expect(NodeSummary.of(node, _en).orderLifetime, '24\u00A0h');
    });

    test('reads a dash for what the node did not send', () {
      final summary = NodeSummary.of(
        const MostroInstance(pubKey: 'node', bondPolicy: BondPolicy.enabled),
        _en,
      );
      expect(summary.deposit, missingFigure);
      expect(summary.orderLifetime, missingFigure);
    });

    test('reads a dash for every fact while the node is missing', () {
      final summary = NodeSummary.of(null, _en);
      expect([
        summary.deposit,
        summary.currencies,
        summary.orderLifetime,
      ], everyElement(missingFigure));
    });
  });

  group('nodeTechSections', () {
    test('the deposit reads the same on About and in the technical data', () {
      const node = MostroInstance(
        pubKey: 'node',
        bondPolicy: BondPolicy.enabled,
        bondAmountPct: 0.015,
        bondSlashNodeSharePct: 0.335,
      );
      final sections = nodeTechSections(node, _es);

      expect(_row(sections, _es.aboutBondAmountLabel).value, '1,5\u00A0%');
      expect(
        _row(sections, _es.aboutBondAmountLabel).value,
        NodeSummary.of(node, _es).deposit,
      );
      expect(_row(sections, _es.aboutBondNodeShareLabel).value, '33,5\u00A0%');
    });

    test('the handoff node lists its rows in the handoff order', () {
      final sections = nodeTechSections(_handoffNode, _en);

      expect(sections.map((s) => s.title), [
        'Mostro',
        'Anti-abuse Bond',
        'Lightning Network',
      ]);
      expect(sections.last.rows.map((r) => r.label), [
        'Alias',
        'Node public key',
        'Node URI',
        'LND Version',
        'Commit',
        'Chain and network',
      ]);
      expect(_row(sections, 'Chain and network').value, 'bitcoin · mainnet');
      expect(_row(sections, 'LND Version').value, '0.20.0-beta');
      expect(_row(sections, 'Alias').value, 'Bitcoin Bolivia 🥜⚡');
      expect(nodeFieldCount(sections), 11);
    });

    test('splits chain and network again when either lists several', () {
      final sections = nodeTechSections(
        _node({'lnd_chains': 'bitcoin', 'lnd_networks': 'mainnet, testnet'}),
        _en,
      );

      expect(_labels(sections), isNot(contains('Chain and network')));
      expect(_row(sections, 'Supported Chains').value, 'bitcoin');
      expect(_row(sections, 'Supported Networks').value, 'mainnet, testnet');
    });

    test('a Cashu node gets the Cashu group and no Lightning group', () {
      final sections = nodeTechSections(
        _node({
          'escrow_mode': 'cashu',
          'cashu_mint_url': 'https://mint.example.com',
          'lnd_version': '0.18.0',
        }),
        _en,
      );

      expect(sections.map((s) => s.title), contains('Cashu escrow'));
      expect(
        sections.map((s) => s.title),
        isNot(contains('Lightning Network')),
      );
      expect(_row(sections, 'Mint').style, TechValueStyle.wrapped);
    });

    test('a Cashu node gets one mint row per mint it accepts', () {
      // mostro#1047: the maker picks one of these per order.
      final sections = nodeTechSections(
        MostroInstance.fromTags(const [
          ['d', 'npub_test'],
          ['escrow_mode', 'cashu'],
          ['cashu_mint_url', 'https://mint.a.com', 'https://mint.b.com'],
        ]),
        _en,
      );

      final mints = sections
          .expand((s) => s.rows)
          .where((r) => r.label == 'Mint')
          .map((r) => r.value);
      expect(mints, ['https://mint.a.com', 'https://mint.b.com']);
    });

    test('a Cashu node that lists no mint says it accepts any', () {
      final sections = nodeTechSections(_node({'escrow_mode': 'cashu'}), _en);

      expect(_row(sections, 'Mint').value, 'Any mint');
    });

    test('a legacy node keeps the key, the currencies and the bond status', () {
      final sections = nodeTechSections(_node(), _en);

      expect(_labels(sections), [
        'Public key',
        'Fiat Currencies',
        'Bond status',
      ]);
      expect(nodeFieldCount(sections), 3);
    });

    test('commit rows show seven characters and copy the whole hash', () {
      final commit = _row(nodeTechSections(_handoffNode, _en), 'Commit');

      expect(commit.value, 'b9ea707');
      expect(commit.copyValue, _lndCommit);
    });
  });

  group('technicalDataClipboard', () {
    test('puts the app version first and full values on every line', () {
      final app = appTechSection('2.0.0', 'deadbeefcafe', _en);
      final text = technicalDataClipboard(
        app: app,
        limits: NodeLimits.of(_handoffNode, _en),
        nodeSections: nodeTechSections(_handoffNode, _en),
        l10n: _en,
      );
      final lines = text.split('\n');

      expect(lines.first, 'Version: 2.0.0');
      expect(lines, contains('Commit Hash: deadbeefcafe'));
      expect(lines, contains('Max order: 300,000'));
      expect(lines, contains('Public key: $_pubkey'));
      expect(lines, contains('Commit: $_lndCommit'));
      expect(text, isNot(contains('…')));
    });

    test('omits the app commit line when the build set none', () {
      final app = appTechSection('2.0.0', '', _en);

      expect(app.rows.map((r) => r.label), ['Version']);
    });
  });
}
