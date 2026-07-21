import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';

/// Builds the tag list for a kind-38385 event, always including the `d`
/// (pubkey) tag and merging any extra tags passed in.
List<List<String>> tagsWith(Map<String, String> extra) {
  return [
    ['d', 'npub_test'],
    for (final entry in extra.entries) [entry.key, entry.value],
  ];
}

/// Like [tagsWith] but always advertises an enabled bond policy, so bond
/// parameter parsing/validation can be exercised — the six parameters are gated
/// on `bondPolicy == enabled`.
List<List<String>> enabledTagsWith(Map<String, String> extra) {
  return tagsWith({'bond_enabled': 'true', ...extra});
}

/// The full set of valid bond tags for an enabled node.
const _enabledBondTags = {
  'bond_enabled': 'true',
  'bond_apply_to': 'both',
  'bond_slash_on_waiting_timeout': 'true',
  'bond_amount_pct': '0.05',
  'bond_base_amount_sats': '1000',
  'bond_slash_node_share_pct': '0.5',
  'bond_payout_claim_window_days': '15',
};

void main() {
  group('MostroInstance.fromTags — bond policy state', () {
    test('unsupported when bond_enabled tag is absent', () {
      final instance = MostroInstance.fromTags(tagsWith({}));
      expect(instance.bondPolicy, BondPolicy.unsupported);
    });

    test('disabled when bond_enabled="false"', () {
      final instance = MostroInstance.fromTags(
        tagsWith({'bond_enabled': 'false'}),
      );
      expect(instance.bondPolicy, BondPolicy.disabled);
    });

    test('enabled when bond_enabled="true"', () {
      final instance = MostroInstance.fromTags(
        tagsWith({'bond_enabled': 'true'}),
      );
      expect(instance.bondPolicy, BondPolicy.enabled);
    });

    test('bond_enabled is case-insensitive', () {
      expect(
        MostroInstance.fromTags(tagsWith({'bond_enabled': 'TRUE'})).bondPolicy,
        BondPolicy.enabled,
      );
      expect(
        MostroInstance.fromTags(tagsWith({'bond_enabled': 'False'})).bondPolicy,
        BondPolicy.disabled,
      );
    });

    test('empty bond_enabled="" is treated as missing (unsupported)', () {
      final instance = MostroInstance.fromTags(tagsWith({'bond_enabled': ''}));
      expect(instance.bondPolicy, BondPolicy.unsupported);
    });

    test(
      'whitespace-only bond_enabled is treated as missing (unsupported)',
      () {
        final instance = MostroInstance.fromTags(
          tagsWith({'bond_enabled': '   '}),
        );
        expect(instance.bondPolicy, BondPolicy.unsupported);
      },
    );

    test('malformed bond_enabled falls back to unsupported', () {
      final instance = MostroInstance.fromTags(
        tagsWith({'bond_enabled': 'yes'}),
      );
      expect(instance.bondPolicy, BondPolicy.unsupported);
    });

    test('a value-less bond_enabled tag is treated as missing', () {
      final instance = MostroInstance.fromTags(const [
        ['d', 'npub_test'],
        ['bond_enabled'],
      ]);
      expect(instance.bondPolicy, BondPolicy.unsupported);
    });
  });

  group('MostroInstance.fromTags — bond parameters (enabled node)', () {
    test('parses every bond parameter', () {
      final instance = MostroInstance.fromTags(tagsWith(_enabledBondTags));

      expect(instance.bondPolicy, BondPolicy.enabled);
      expect(instance.bondApplyTo, BondApplyTo.both);
      expect(instance.bondSlashOnWaitingTimeout, isTrue);
      expect(instance.bondAmountPct, 0.05);
      expect(instance.bondBaseAmountSats, 1000);
      expect(instance.bondSlashNodeSharePct, 0.5);
      expect(instance.bondPayoutClaimWindowDays, 15);
    });

    test('bond_apply_to parses take / make / both', () {
      for (final entry
          in {
            'take': BondApplyTo.take,
            'make': BondApplyTo.make,
            'both': BondApplyTo.both,
          }.entries) {
        final instance = MostroInstance.fromTags(
          enabledTagsWith({'bond_apply_to': entry.key}),
        );
        expect(instance.bondApplyTo, entry.value);
      }
    });

    test('invalid bond_apply_to yields null', () {
      final instance = MostroInstance.fromTags(
        enabledTagsWith({'bond_apply_to': 'sometimes'}),
      );
      expect(instance.bondApplyTo, isNull);
    });

    test('bond_slash_on_waiting_timeout parses true/false, else null', () {
      expect(
        MostroInstance.fromTags(
          enabledTagsWith({'bond_slash_on_waiting_timeout': 'true'}),
        ).bondSlashOnWaitingTimeout,
        isTrue,
      );
      expect(
        MostroInstance.fromTags(
          enabledTagsWith({'bond_slash_on_waiting_timeout': 'false'}),
        ).bondSlashOnWaitingTimeout,
        isFalse,
      );
      expect(
        MostroInstance.fromTags(
          enabledTagsWith({'bond_slash_on_waiting_timeout': 'maybe'}),
        ).bondSlashOnWaitingTimeout,
        isNull,
      );
    });
  });

  group('MostroInstance.fromTags — bond parameter validation', () {
    test('bond_amount_pct rejects negative, NaN, Infinity, and garbage', () {
      for (final bogus in ['-0.1', 'NaN', 'Infinity', '-Infinity', 'abc']) {
        expect(
          MostroInstance.fromTags(
            enabledTagsWith({'bond_amount_pct': bogus}),
          ).bondAmountPct,
          isNull,
          reason: 'rejects "$bogus"',
        );
      }
    });

    test(
      'bond_amount_pct accepts any non-negative fraction, including > 1.0',
      () {
        // The daemon does not cap amount_pct at 1.0, so neither do we.
        for (final entry in {'0.0': 0.0, '1.0': 1.0, '1.5': 1.5}.entries) {
          expect(
            MostroInstance.fromTags(
              enabledTagsWith({'bond_amount_pct': entry.key}),
            ).bondAmountPct,
            entry.value,
          );
        }
      },
    );

    test('negative bond_base_amount_sats yields null', () {
      expect(
        MostroInstance.fromTags(
          enabledTagsWith({'bond_base_amount_sats': '-1'}),
        ).bondBaseAmountSats,
        isNull,
      );
      expect(
        MostroInstance.fromTags(
          enabledTagsWith({'bond_base_amount_sats': '0'}),
        ).bondBaseAmountSats,
        0,
      );
    });

    test('bond_slash_node_share_pct rejects values outside [0.0, 1.0]', () {
      for (final bogus in ['2.0', '-0.5', 'NaN', 'Infinity']) {
        expect(
          MostroInstance.fromTags(
            enabledTagsWith({'bond_slash_node_share_pct': bogus}),
          ).bondSlashNodeSharePct,
          isNull,
          reason: 'rejects "$bogus"',
        );
      }
    });

    test('non-positive bond_payout_claim_window_days yields null', () {
      expect(
        MostroInstance.fromTags(
          enabledTagsWith({'bond_payout_claim_window_days': '0'}),
        ).bondPayoutClaimWindowDays,
        isNull,
      );
      expect(
        MostroInstance.fromTags(
          enabledTagsWith({'bond_payout_claim_window_days': '-5'}),
        ).bondPayoutClaimWindowDays,
        isNull,
      );
    });
  });

  group('MostroInstance.fromTags — parameters gated on enabled policy', () {
    void expectNoBondParameters(MostroInstance instance) {
      expect(instance.bondApplyTo, isNull);
      expect(instance.bondSlashOnWaitingTimeout, isNull);
      expect(instance.bondAmountPct, isNull);
      expect(instance.bondBaseAmountSats, isNull);
      expect(instance.bondSlashNodeSharePct, isNull);
      expect(instance.bondPayoutClaimWindowDays, isNull);
    }

    test(
      'disabled node exposes no bond parameters even when tags are present',
      () {
        final instance = MostroInstance.fromTags(
          tagsWith({..._enabledBondTags, 'bond_enabled': 'false'}),
        );

        expect(instance.bondPolicy, BondPolicy.disabled);
        expectNoBondParameters(instance);
      },
    );

    test(
      'unsupported node exposes no bond parameters even when tags are present',
      () {
        // No `bond_enabled` tag, but stray bond parameter tags are present.
        final instance = MostroInstance.fromTags(
          tagsWith({
            'bond_apply_to': 'both',
            'bond_amount_pct': '0.05',
            'bond_payout_claim_window_days': '15',
          }),
        );

        expect(instance.bondPolicy, BondPolicy.unsupported);
        expectNoBondParameters(instance);
      },
    );
  });

  group('MostroInstance.fromTags — non-bond parsing is unaffected', () {
    test('existing tags still parse and bond fields default to null', () {
      final instance = MostroInstance.fromTags(const [
        ['d', 'npub_test'],
        ['mostro_version', '0.13.1'],
        ['max_order_amount', '1000000'],
        ['fee', '0.006'],
      ]);

      expect(instance.pubKey, 'npub_test');
      expect(instance.mostroVersion, '0.13.1');
      expect(instance.maxOrderAmount, 1000000);
      expect(instance.fee, 0.006);

      expect(instance.bondPolicy, BondPolicy.unsupported);
      expect(instance.bondApplyTo, isNull);
      expect(instance.bondSlashOnWaitingTimeout, isNull);
      expect(instance.bondAmountPct, isNull);
      expect(instance.bondBaseAmountSats, isNull);
      expect(instance.bondSlashNodeSharePct, isNull);
      expect(instance.bondPayoutClaimWindowDays, isNull);
    });
  });
}
