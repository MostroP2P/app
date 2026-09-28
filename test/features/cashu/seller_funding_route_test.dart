import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/cashu/seller_funding_route.dart';
import 'package:mostro/features/settings/providers/escrow_mode_provider.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/widgets/trade_card.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  group('sellerFundingPath', () {
    test('a Cashu node funds the trade with the escrow lock', () {
      expect(
        sellerFundingPath('order-1', cashu: true),
        AppRoute.lockEscrowPath('order-1'),
      );
    });

    test('a Lightning node funds it with the hold invoice', () {
      expect(
        sellerFundingPath('order-1', cashu: false),
        AppRoute.payInvoicePath('order-1'),
      );
    });
  });

  test("the trade card's funding verb names the step the node runs", () {
    final l10n = AppLocalizationsEn();

    expect(
      TradeCard.verbText(TradeRowVerb.payInvoice, l10n, cashu: true),
      l10n.lockEscrowConfirm,
    );
    expect(
      TradeCard.verbText(TradeRowVerb.payInvoice, l10n),
      l10n.tradeVerbPayInvoice,
    );
  });

  test('a Cashu node without a usable mint still routes as Cashu', () async {
    // CodeRabbit on #238: such a node sends no hold invoice, so the seller
    // must land on the escrow screen (and read CashuMintUnknown there), never
    // wait on the Lightning step. The wallet stays gated on availability.
    final container = ProviderContainer(
      overrides: [
        escrowModeProvider.overrideWith(
          (ref) => Stream.value(
            const EscrowModeInfo(
              mode: 'cashu',
              mintUrl: null,
              escrowLocktimeDays: null,
              settlementMarginDays: null,
              isOverridden: true,
              isCashuAvailable: false,
              forceCashuOverride: true,
              mintUrlOverride: null,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(escrowModeProvider.future);

    expect(container.read(isCashuModeProvider), isTrue);
    expect(container.read(isCashuAvailableProvider), isFalse);
  });
}
