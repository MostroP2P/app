import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Pure rules of the About redesign (`design_handoff_acerca_de`, 12a/12b):
/// which node fields 12b lists and how each value is shaped, the three limit
/// figures of 12a, the field count, and the plain-text block `Copy all data`
/// puts on the clipboard. No widgets, no providers — unit-tested directly.
///
/// 12a and 12b both read one [MostroInstance], so the node event is parsed
/// once for the two screens.

// ── Row model ─────────────────────────────────────────────────────────────────

/// How a value is set on 12b.
enum TechValueStyle {
  /// Short prose (`Bitcoin Bolivia`, `Enabled`): Outfit, one row.
  text,

  /// Versions, hashes, counts and durations: Manrope, one row.
  figure,

  /// Keys and URIs: label above, value truncated in the middle, copyable.
  key,

  /// A long value whose every part matters (a mint URL): label above, value
  /// in full.
  wrapped,
}

@immutable
class TechRow {
  const TechRow(this.label, this.value, this.style, {String? fullValue})
    : _fullValue = fullValue;

  final String label;

  /// What the row shows. Keys are truncated by the widget, not here, so
  /// [value] stays the whole key for them.
  final String value;
  final TechValueStyle style;
  final String? _fullValue;

  /// What the clipboard gets: the unabridged value (the whole commit hash
  /// where the row shows seven characters).
  String get copyValue => _fullValue ?? value;
}

@immutable
class TechSection {
  const TechSection(this.title, this.rows);

  final String title;
  final List<TechRow> rows;
}

// ── Value shaping ─────────────────────────────────────────────────────────────

/// Characters of a commit hash shown on a row.
const int shortHashLength = 7;

/// Placeholder for a figure the node has not sent (yet).
const String missingFigure = '—';

String shortHash(String hash) =>
    hash.length <= shortHashLength ? hash : hash.substring(0, shortHashLength);

/// `0.20.0-beta commit=v0.20.0-beta` → `0.20.0-beta`: the commit already has
/// its own row.
String lndVersionOnly(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed.split(RegExp(r'\s+')).first;
}

/// A comma-separated tag value as a clean list (`bitcoin, litecoin`).
List<String> splitTagList(String? raw) => (raw ?? '')
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList(growable: false);

String formatSats(int sats, String locale) =>
    NumberFormat.decimalPattern(locale).format(sats);

/// The node fee (a fraction, `0.006`) as `0.6%` in the locale's style, or
/// `null` when the node sent nothing usable.
String? formatFee(double? fraction, AppLocalizations l10n) {
  if (fraction == null) return null;
  final pct = fraction * 100;
  if (!pct.isFinite || pct < 0) return null;
  return l10n.aboutFeeValue(
    NumberFormat('#,##0.##', l10n.localeName).format(pct),
  );
}

// ── 12a · limits ──────────────────────────────────────────────────────────────

/// The three figures of the connected-node card: [missingFigure] for each one
/// the node did not send, and for all three while [MostroInstance] is `null`.
@immutable
class NodeLimits {
  const NodeLimits({required this.min, required this.max, required this.fee});

  factory NodeLimits.of(MostroInstance? node, AppLocalizations l10n) {
    final min = node?.minOrderAmount;
    final max = node?.maxOrderAmount;
    return NodeLimits(
      min: min == null ? missingFigure : formatSats(min, l10n.localeName),
      max: max == null ? missingFigure : formatSats(max, l10n.localeName),
      fee: formatFee(node?.fee, l10n) ?? missingFigure,
    );
  }

  final String min;
  final String max;
  final String fee;
}

// ── 12b · sections ────────────────────────────────────────────────────────────

/// The app's own group, first on 12b and first in the clipboard block.
/// [appCommit] is the build's `GIT_COMMIT`, empty when the build set none.
TechSection appTechSection(
  String appVersion,
  String appCommit,
  AppLocalizations l10n,
) {
  return TechSection(l10n.aboutAppSection, [
    TechRow(l10n.aboutVersionLabel, appVersion, TechValueStyle.figure),
    if (appCommit.isNotEmpty)
      TechRow(
        l10n.aboutCommitHashLabel,
        shortHash(appCommit),
        TechValueStyle.figure,
        fullValue: appCommit,
      ),
  ]);
}

/// Every group of node fields 12b lists, empty groups dropped. The anti-abuse
/// bond group always has its status row; the settlement group is Cashu or
/// Lightning, never both, because About reports what this node runs.
List<TechSection> nodeTechSections(MostroInstance node, AppLocalizations l10n) {
  return [
    TechSection('Mostro', _mostroRows(node, l10n)),
    TechSection(l10n.aboutAntiAbuseBondSection, _bondRows(node, l10n)),
    if (node.escrowMode == EscrowMode.cashu)
      TechSection(l10n.aboutCashuEscrowSection, _cashuRows(node, l10n))
    else
      TechSection(
        l10n.aboutLightningNetworkSection,
        _lightningRows(node, l10n),
      ),
  ].where((s) => s.rows.isNotEmpty).toList(growable: false);
}

/// The `N fields` count on 12a: the node's rows only, not the app's.
int nodeFieldCount(List<TechSection> nodeSections) =>
    nodeSections.fold(0, (sum, s) => sum + s.rows.length);

List<TechRow> _mostroRows(MostroInstance node, AppLocalizations l10n) {
  final fiat = node.fiatCurrenciesAccepted?.trim() ?? '';
  return [
    TechRow(l10n.aboutPublicKeyLabel, node.pubKey, TechValueStyle.key),
    if (node.mostroVersion != null)
      TechRow(
        l10n.aboutMostroVersionLabel,
        node.mostroVersion!,
        TechValueStyle.figure,
      ),
    if (node.commitHash != null)
      TechRow(
        l10n.aboutMostroCommitLabel,
        shortHash(node.commitHash!),
        TechValueStyle.figure,
        fullValue: node.commitHash,
      ),
    if (node.maxOrdersPerResponse != null)
      TechRow(
        l10n.aboutMaxOrdersPerResponseLabel,
        '${node.maxOrdersPerResponse}',
        TechValueStyle.figure,
      ),
    if (node.expirationHours != null)
      TechRow(
        l10n.aboutOrderExpiryLabel,
        l10n.aboutHoursShort(node.expirationHours!),
        TechValueStyle.figure,
      ),
    TechRow(
      l10n.aboutFiatCurrenciesLabel,
      fiat.isEmpty ? l10n.aboutFiatCurrenciesAll : fiat,
      TechValueStyle.text,
    ),
    if (node.expirationSeconds != null)
      TechRow(
        l10n.aboutWaitingTimeoutLabel,
        l10n.aboutSecondsShort(node.expirationSeconds!),
        TechValueStyle.figure,
      ),
    if (node.holdInvoiceExpirationWindow != null)
      TechRow(
        l10n.aboutHoldInvoiceExpLabel,
        l10n.aboutSecondsShort(node.holdInvoiceExpirationWindow!),
        TechValueStyle.figure,
      ),
    if (node.holdInvoiceCltvDelta != null)
      TechRow(
        l10n.aboutHoldInvoiceCltvLabel,
        '${node.holdInvoiceCltvDelta} ${l10n.aboutBlocksSuffix}',
        TechValueStyle.figure,
      ),
    if (node.invoiceExpirationWindow != null)
      TechRow(
        l10n.aboutInvoiceExpWindowLabel,
        l10n.aboutSecondsShort(node.invoiceExpirationWindow!),
        TechValueStyle.figure,
      ),
    if (node.pow != null)
      TechRow(l10n.aboutProofOfWorkLabel, '${node.pow}', TechValueStyle.figure),
  ];
}

/// Status covers all three policy states. The parameters need no policy check:
/// the parser leaves them null unless the policy is enabled.
List<TechRow> _bondRows(MostroInstance node, AppLocalizations l10n) {
  final status = switch (node.bondPolicy) {
    BondPolicy.enabled => l10n.aboutBondEnabledValue,
    BondPolicy.disabled => l10n.aboutBondDisabledValue,
    BondPolicy.unsupported => l10n.aboutBondUnsupportedValue,
  };
  final applyTo = switch (node.bondApplyTo) {
    BondApplyTo.take => l10n.aboutBondAppliesToTakers,
    BondApplyTo.make => l10n.aboutBondAppliesToMakers,
    BondApplyTo.both => l10n.aboutBondAppliesToBoth,
    null => null,
  };
  return [
    TechRow(l10n.aboutBondStatusLabel, status, TechValueStyle.text),
    if (applyTo != null)
      TechRow(l10n.aboutBondAppliesToLabel, applyTo, TechValueStyle.text),
    if (node.bondAmountPercent != null)
      TechRow(
        l10n.aboutBondAmountLabel,
        node.bondAmountPercent!,
        TechValueStyle.figure,
      ),
    if (node.bondBaseAmountSats != null)
      TechRow(
        l10n.aboutBondBaseAmountLabel,
        '${formatSats(node.bondBaseAmountSats!, l10n.localeName)} '
        '${l10n.aboutSatoshisSuffix}',
        TechValueStyle.figure,
      ),
    if (node.bondSlashNodeSharePercent != null)
      TechRow(
        l10n.aboutBondNodeShareLabel,
        node.bondSlashNodeSharePercent!,
        TechValueStyle.figure,
      ),
    if (node.bondSlashOnWaitingTimeout != null)
      TechRow(
        l10n.aboutBondSlashOnTimeoutLabel,
        node.bondSlashOnWaitingTimeout!
            ? l10n.aboutBondEnabledValue
            : l10n.aboutBondDisabledValue,
        TechValueStyle.text,
      ),
    if (node.bondPayoutClaimWindowDays != null)
      TechRow(
        l10n.aboutBondClaimWindowLabel,
        l10n.aboutBondClaimWindowValue(node.bondPayoutClaimWindowDays!),
        TechValueStyle.text,
      ),
  ];
}

/// The mint row is shown even when missing: a Cashu node with no mint is
/// misconfigured, and saying so beats an empty group. It is never truncated —
/// the host is the part that matters.
List<TechRow> _cashuRows(MostroInstance node, AppLocalizations l10n) => [
  TechRow(
    l10n.aboutCashuMintUrlLabel,
    node.cashuMintUrl ?? l10n.aboutCashuMintNotAdvertised,
    TechValueStyle.wrapped,
  ),
  if (node.cashuEscrowLocktimeDays != null)
    TechRow(
      l10n.aboutCashuLocktimeLabel,
      l10n.aboutDaysValue(node.cashuEscrowLocktimeDays!),
      TechValueStyle.text,
    ),
  if (node.cashuSettlementMarginDays != null)
    TechRow(
      l10n.aboutCashuSettlementMarginLabel,
      l10n.aboutDaysValue(node.cashuSettlementMarginDays!),
      TechValueStyle.text,
    ),
];

/// The alias is shown exactly as the node sends it, emoji included: it is the
/// name its operator chose.
List<TechRow> _lightningRows(MostroInstance node, AppLocalizations l10n) => [
  if (node.lndNodeAlias != null)
    TechRow(l10n.aboutAliasLabel, node.lndNodeAlias!, TechValueStyle.text),
  if (node.lndNodePublicKey != null)
    TechRow(
      l10n.aboutNodePublicKeyLabel,
      node.lndNodePublicKey!,
      TechValueStyle.key,
    ),
  if (node.lndUris != null)
    TechRow(l10n.aboutNodeUriLabel, node.lndUris!, TechValueStyle.key),
  if (node.lndVersion != null)
    TechRow(
      l10n.aboutLndVersionLabel,
      lndVersionOnly(node.lndVersion!),
      TechValueStyle.figure,
    ),
  if (node.lndCommitHash != null)
    TechRow(
      l10n.aboutCommitLabel,
      shortHash(node.lndCommitHash!),
      TechValueStyle.figure,
      fullValue: node.lndCommitHash,
    ),
  ..._chainRows(node, l10n),
];

/// `bitcoin · mainnet` in one row while the node names one chain and one
/// network; two rows again as soon as either lists more than one.
List<TechRow> _chainRows(MostroInstance node, AppLocalizations l10n) {
  final chains = splitTagList(node.lndChains);
  final networks = splitTagList(node.lndNetworks);
  if (chains.length == 1 && networks.length == 1) {
    return [
      TechRow(
        l10n.aboutChainNetworkLabel,
        '${chains.single} · ${networks.single}',
        TechValueStyle.figure,
      ),
    ];
  }
  return [
    if (chains.isNotEmpty)
      TechRow(
        l10n.aboutSupportedChainsLabel,
        chains.join(', '),
        TechValueStyle.figure,
      ),
    if (networks.isNotEmpty)
      TechRow(
        l10n.aboutSupportedNetworksLabel,
        networks.join(', '),
        TechValueStyle.figure,
      ),
  ];
}

// ── Clipboard ─────────────────────────────────────────────────────────────────

/// The block `Copy all data` copies: one `label: value` per line with full
/// values, the app's version on the first line, and a blank line plus the
/// group title between groups. The connected-node limits follow the app group,
/// since 12b does not repeat them as rows.
String technicalDataClipboard({
  required TechSection app,
  required NodeLimits limits,
  required List<TechSection> nodeSections,
  required AppLocalizations l10n,
}) {
  return [
    for (final row in app.rows) '${row.label}: ${row.copyValue}',
    '',
    l10n.aboutConnectedNodeTitle,
    '${l10n.aboutMinOrderCell}: ${limits.min}',
    '${l10n.aboutMaxOrderCell}: ${limits.max}',
    '${l10n.aboutFeeCell}: ${limits.fee}',
    for (final section in nodeSections) ...[
      '',
      section.title,
      for (final row in section.rows) '${row.label}: ${row.copyValue}',
    ],
  ].join('\n');
}
