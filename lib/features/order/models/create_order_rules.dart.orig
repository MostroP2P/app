import 'dart:math' as math;

import 'package:mostro/features/about/models/mostro_instance.dart'
    show BondApplyTo, BondPolicy;
import 'package:mostro/features/home/providers/home_order_providers.dart';

/// Pure rules of the create-order form (handoff 5a/5b/5c). No Flutter here so
/// every rule is unit-testable; the widgets only render what these return.

// ── Maker bond gate ───────────────────────────────────────────────────────────

/// Whether the form must refuse to publish on this node for now: the node
/// bonds makers (`bond_apply_to = make | both`) and the create flow does not
/// yet consume the daemon's `PayBondInvoice` reply (docs/ANTI_ABUSE_BOND.md
/// Phase 2, T2.3). Publishing would only time out while the daemon holds
/// the order unpublished. Unknown or disabled policy, or a takers-only bond,
/// publishes as before.
bool makerBondBlocks({
  required BondPolicy? policy,
  required BondApplyTo? applyTo,
}) =>
    policy == BondPolicy.enabled &&
    (applyTo == BondApplyTo.make || applyTo == BondApplyTo.both);

// ── Premium colour rule ───────────────────────────────────────────────────────

/// Whom the premium favours, read from the **maker's** side.
///
/// Not the order book's rule: there the colour is read from the taker's side,
/// so the same `+3%` can be lime on one screen and amber on the other.
enum PremiumFavour { good, bad, zero }

/// Lime when `premium × side` is favourable (`side = +1` selling, `−1`
/// buying), amber when it is not, neutral at zero. A seller gains from a
/// positive premium; a buyer gains from a negative one.
PremiumFavour premiumFavour(OrderType side, double premium) {
  if (premium == 0) return PremiumFavour.zero;
  final sign = side == OrderType.sell ? 1 : -1;
  return premium * sign > 0 ? PremiumFavour.good : PremiumFavour.bad;
}

// ── Quick amount chips (5b) ───────────────────────────────────────────────────

/// USD equivalents the quick chips approximate.
const quickAmountUsdBases = [10, 25, 50, 100];

/// Four round fiat amounts worth roughly [quickAmountUsdBases] each, given
/// how many units of the currency one USD buys. Rounds every candidate to the
/// nearest "nice" number (1 / 2 / 2.5 / 5 × a power of ten) so the chips read
/// like amounts people actually type. Duplicates collapse, and fewer than two
/// distinct amounts yields none at all.
///
/// The handoff derives the chips from each currency's usual volume, a figure
/// the app does not have; the node's exchange rate is the closest stand-in.
List<int> quickAmounts(double? fiatPerUsd) {
  if (fiatPerUsd == null || !fiatPerUsd.isFinite || fiatPerUsd <= 0) {
    return const [];
  }
  final amounts = <int>{};
  for (final usd in quickAmountUsdBases) {
    final raw = usd * fiatPerUsd;
    if (raw < 1) continue;
    amounts.add(_niceNumber(raw));
  }
  final sorted = amounts.toList()..sort();
  return sorted.length < 2 ? const [] : sorted;
}

const _niceMantissas = [1.0, 2.0, 2.5, 5.0, 10.0];

int _niceNumber(double value) {
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor());
  final mantissa = value / magnitude;
  var best = _niceMantissas.first;
  for (final candidate in _niceMantissas) {
    if ((candidate - mantissa).abs() < (best - mantissa).abs()) {
      best = candidate;
    }
  }
  return (best * magnitude).round();
}

// ── Amount input parsing ──────────────────────────────────────────────────────

/// The amount typed in a grouped field (`25.000` in `es`, `25,000` in `en`)
/// as the canonical `1234.5` string the rest of the pipeline parses, or null
/// when the text is not a finite positive number.
///
/// Strips the locale's group separator and swaps its decimal separator for
/// `.`. `Infinity`, `-Infinity` and `NaN` parse as doubles and would pass a
/// bare positivity check, only to throw in the sats conversion further down,
/// so they are rejected here.
String? canonicalAmount(
  String text, {
  required String groupSeparator,
  required String decimalSeparator,
}) {
  var cleaned = text.trim();
  if (cleaned.isEmpty) return null;
  cleaned = cleaned.replaceAll(groupSeparator, '');
  if (decimalSeparator != '.') {
    cleaned = cleaned.replaceAll(decimalSeparator, '.');
  }
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite || value <= 0) return null;
  return cleaned;
}

// ── Preview markup ────────────────────────────────────────────────────────────

/// What a fragment of the preview sentence is, so each gets its own colour.
enum PreviewRole { text, amount, sats, premium, duration }

/// One run of the preview sentence.
class PreviewFragment {
  const PreviewFragment(this.text, this.role);

  final String text;
  final PreviewRole role;

  @override
  bool operator ==(Object other) =>
      other is PreviewFragment && other.text == text && other.role == role;

  @override
  int get hashCode => Object.hash(text, role);

  @override
  String toString() => 'PreviewFragment($role, "$text")';
}

const _markStart = '';
const _markEnd = '';

const _roleCodes = {
  PreviewRole.amount: 'a',
  PreviewRole.sats: 's',
  PreviewRole.premium: 'p',
  PreviewRole.duration: 'd',
};

/// Wraps [value] so [previewFragments] can recover its [role] after the
/// localized template has been filled in. The ARB templates carry only
/// placeholders; the markers travel inside the placeholder values, so the
/// translations never see them.
String markPreview(String value, PreviewRole role) =>
    '$_markStart${_roleCodes[role]}$value$_markEnd';

final _markPattern = RegExp('$_markStart([aspd])(.*?)$_markEnd');

/// Splits a filled-in template into fragments by the markers [markPreview]
/// added. Text outside any marker is [PreviewRole.text]. Empty runs are
/// dropped.
List<PreviewFragment> previewFragments(String sentence) {
  final fragments = <PreviewFragment>[];
  var cursor = 0;
  for (final match in _markPattern.allMatches(sentence)) {
    if (match.start > cursor) {
      fragments.add(
        PreviewFragment(
          sentence.substring(cursor, match.start),
          PreviewRole.text,
        ),
      );
    }
    final role =
        _roleCodes.entries
            .firstWhere((entry) => entry.value == match.group(1))
            .key;
    final text = match.group(2)!;
    if (text.isNotEmpty) fragments.add(PreviewFragment(text, role));
    cursor = match.end;
  }
  if (cursor < sentence.length) {
    fragments.add(
      PreviewFragment(sentence.substring(cursor), PreviewRole.text),
    );
  }
  return fragments;
}
