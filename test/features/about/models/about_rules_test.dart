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

    test('formatFee follows the locale and rejects unusable values', () {
      expect(formatFee(0.006, _en), '0.6%');
      expect(formatFee(0.006, _es), '0,6 %');
      expect(formatFee(0, _en), '0%');
      expect(formatFee(double.infinity, _en), isNull);
      expect(formatFee(null, _en), isNull);
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

  group('nodeTechSections', () {
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
