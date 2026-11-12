import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/cashu/cashu_error_messages.dart';
import 'package:mostro/l10n/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  String messageFor(String tail) =>
      cashuErrorMessage(Exception('CashuUnsupportedUnit: $tail'), l10n);

  // Issue #391: a dollar or millisat token was refused as "carries no proof of
  // the mint's signature", which tells the user the token is forged. Rust
  // refuses it from the token alone, so the token is untouched — say so, and
  // say which unit it is in.
  test('a token in another unit names that unit', () {
    for (final (code, name) in [
      ('msat', 'millisats'),
      ('usd', 'dollars (USD)'),
      ('eur', 'euros (EUR)'),
      // A currency code the app has no name for is shown as the code.
      ('gbp', 'GBP'),
    ]) {
      expect(
        messageFor(code),
        'This wallet only holds sats, and this token is in $name. It was '
        'left untouched: you can redeem it in a wallet that supports that '
        'unit.',
      );
    }
  });

  // #810: an escrow for a trade on another node is refused before any swap.
  test('a trade on another node says so', () {
    expect(
      cashuErrorMessage(Exception('TradeOnOtherNode'), l10n),
      l10n.tradeOnOtherNode,
    );
  });

  test('a unit the app cannot name gets the generic message', () {
    const generic =
        'This wallet only holds sats, and this token is in another unit '
        '(such as millisats or dollars). It was left untouched: you can '
        'redeem it in a wallet that supports its unit.';

    expect(messageFor('other'), generic);
    // Rust never sends free text here, but if it did, none of it is shown:
    // the token's maker chose it.
    final hostile = messageFor('some custom unit');
    expect(hostile, generic);
    expect(hostile, isNot(contains('some')));
  });

  // C3b-1 and C3b-2: paying a Lightning invoice and receiving over one. Each
  // marker arrives as the bridge throws it, with a cdk detail after it, and
  // must reach its own message — never the generic one, and never another
  // marker's.
  test('every melt and mint marker has its own message', () {
    final cases = {
      'CashuInvalidInvoice': l10n.cashuErrorInvalidInvoice,
      'CashuInvoiceNoAmount': l10n.cashuErrorInvoiceNoAmount,
      'CashuInvoiceExpired': l10n.cashuErrorInvoiceExpired,
      'CashuMeltUnsupported': l10n.cashuErrorMeltUnsupported,
      'CashuMeltAmountOutOfRange': l10n.cashuErrorMeltAmountOutOfRange,
      'CashuMeltQuoteFailed': l10n.cashuErrorMeltQuoteFailed,
      'CashuMeltQuoteExpired': l10n.cashuErrorMeltQuoteExpired,
      'CashuMeltFeeChanged': l10n.cashuErrorMeltFeeChanged,
      'CashuMeltInFlight': l10n.cashuErrorMeltInFlight,
      'CashuMeltInsufficientFunds': l10n.cashuErrorMeltInsufficientFunds,
      'CashuMeltFailed': l10n.cashuErrorMeltFailed,
      'CashuMintUnsupported': l10n.cashuErrorMintUnsupported,
      'CashuMintAmountOutOfRange': l10n.cashuErrorMintAmountOutOfRange,
      'CashuMintQuoteUnknown': l10n.cashuErrorMintQuoteUnknown,
      'CashuMintQuoteFailed': l10n.cashuErrorMintQuoteFailed,
    };
    for (final MapEntry(key: marker, value: message) in cases.entries) {
      final shown = cashuErrorMessage(
        Exception('$marker: Insufficient funds (InvalidMintUrl)'),
        l10n,
      );
      expect(shown, message, reason: marker);
      expect(shown, isNot(l10n.cashuErrorGeneric), reason: marker);
    }
    // Ten markers, ten different things to tell the user.
    expect(cases.values.toSet(), hasLength(cases.length));
  });

  test('the melt and the escrow shortfalls stay apart', () {
    expect(
      cashuErrorMessage(Exception('CashuMeltInsufficientFunds'), l10n),
      l10n.cashuErrorMeltInsufficientFunds,
    );
    expect(
      cashuErrorMessage(Exception('CashuInsufficientFunds'), l10n),
      l10n.lockEscrowInsufficientFunds,
    );
  });
}
