/// Stable semantic identifiers for UI automation (Mortsom automation
/// contract). Every actionable control and business-critical state carries
/// one of these through `Semantics(identifier: ...)`; on Android they surface
/// as the accessibility `resource-id`, so black-box drivers can locate them
/// without depending on localized text or widget hierarchy.
///
/// Rules (see `docs/automation-contract.md`):
///  * identifiers are namespaced `<area>.<screen-or-flow>.<control>`;
///  * an identifier is a product contract: renaming or removing one requires
///    coordinated review with the automation owners;
///  * dynamic identifiers use the helpers below so their shape is documented
///    in one place;
///  * where a screen exists in the classic app too, the identifier is the
///    same string, so both applications speak one vocabulary.
///
/// The mirror on the harness side is
/// `crates/app-adapters/mobile-v2/src/selectors.rs` in Mortsom, whose
/// contract test reads this file and fails when the two drift apart.
class AutomationIds {
  AutomationIds._();

  // Environment
  static const String envMarker = 'env.marker';

  // App bar / navigation
  static const String appBarDrawer = 'appbar.drawer';
  static const String appBarBack = 'appbar.back';
  static const String navOrderBook = 'nav.order_book';
  static const String navTrades = 'nav.trades';
  static const String navChat = 'nav.chat';
  static const String drawerAccount = 'drawer.account';
  static const String drawerSettings = 'drawer.settings';
  static const String drawerAbout = 'drawer.about';

  // Onboarding — v2 has no community/node step in the walkthrough.
  static const String walkthroughBack = 'onboarding.walkthrough.back';
  static const String walkthroughSkip = 'onboarding.walkthrough.skip';
  static const String walkthroughNext = 'onboarding.walkthrough.next';
  static const String walkthroughDone = 'onboarding.walkthrough.done';

  // Key management (account screen)
  static const String keysGenerate = 'keys.generate';
  static const String keysGenerateConfirm = 'keys.generate.confirm';
  static const String keysGenerateCancel = 'keys.generate.cancel';
  static const String keysImport = 'keys.import';
  static const String keysSeedReveal = 'keys.seed.reveal';
  // There is deliberately no identifier for the mnemonic itself. A stable
  // readout would put the seed phrase in the accessibility tree, where any
  // accessibility service on the device can read it, and no Mortsom scenario
  // needs it: identities are generated in the app, never transcribed.

  // Settings
  static const String settingsMostroNode = 'settings.mostro_node';
  static const String settingsMostroNodePubkey = 'settings.mostro_node.pubkey';
  static const String settingsRelays = 'settings.relays';
  static const String settingsRelaysAdd = 'settings.relays.add';
  static const String settingsRelaysAddUrl = 'settings.relays.add.url';
  static const String settingsRelaysAddConfirm = 'settings.relays.add.confirm';
  static const String settingsRelaysAddCancel = 'settings.relays.add.cancel';
  static const String settingsWallet = 'settings.wallet';

  /// Row of a configured relay in the relays card.
  static String settingsRelayItem(String url) =>
      'settings.relays.item.${_normalizeRelayUrl(url)}';

  /// Delete control of a configured relay.
  static String settingsRelayDelete(String url) =>
      'settings.relays.item.${_normalizeRelayUrl(url)}.delete';

  /// A relay URL reaches the UI with and without a trailing slash and both
  /// name the same relay, so the identifier normalizes it. Without a URL key
  /// every delete control would share one identifier and automation could not
  /// pick a relay to remove.
  static String _normalizeRelayUrl(String url) =>
      url.trim().replaceAll(RegExp(r'/+$'), '');

  // Mostro node selector (bottom sheet)
  static const String nodeCustomPubkey = 'node.custom.pubkey';
  static const String nodeCustomName = 'node.custom.name';
  static const String nodeCustomConfirm = 'node.custom.confirm';
  static const String nodeCustomCancel = 'node.custom.cancel';
  static const String nodeAddCustom = 'node.add_custom';
  static const String nodeAddCustomCancel = 'node.add_custom.cancel';

  /// Card of one node in the selector list. A user-added node is removed by
  /// long-pressing its card (confirmation dialog), so there is no separate
  /// delete control.
  static String nodeItem(String pubkey) => 'node.item.$pubkey';

  // Wallet / NWC
  //
  // Handoff 10c folded the connect and settings screens into one, so there is
  // no separate "connect from wallet settings" control any more: the single
  // connect CTA is [walletNwcConnect].
  static const String walletSettingsDisconnect = 'wallet.settings.disconnect';
  static const String walletNwcUri = 'wallet.nwc.uri';
  static const String walletNwcPaste = 'wallet.nwc.paste';
  static const String walletNwcConnect = 'wallet.nwc.connect';
  static const String walletConnection = 'wallet.connection';

  /// Machine values of the [walletConnection] readout.
  static const String walletConnected = 'connected';
  static const String walletDisconnected = 'disconnected';

  // Order book and creation.
  //
  // The two book tabs are named by their visible label, not by the orders
  // they list: the "Buy BTC" tab lists *sell* orders (the taker buys). A
  // driver looking for a side picks the tab that lists it.
  static const String orderBookTabBuy = 'order.book.tab.buy';
  static const String orderBookTabSell = 'order.book.tab.sell';
  static const String orderAddFab = 'order.add.fab';
  static const String orderAddBuy = 'order.add.buy';
  static const String orderAddSell = 'order.add.sell';
  static const String orderCreateCurrency = 'order.create.currency';
  static const String orderCreateCurrencySearch =
      'order.create.currency.search';
  static const String orderCreateFiatAmount = 'order.create.fiat_amount';
  // The screen's own `Buy BTC | Sell BTC` control: the side can be switched
  // after arriving from the order book's create button.
  static const String orderCreateSideBuy = 'order.create.side.buy';
  static const String orderCreateSideSell = 'order.create.side.sell';
  // Range orders: the `Single | Range` control replaces the single amount
  // with a min/max pair. [orderCreateRange] names the whole control; the two
  // segments are addressable on their own.
  static const String orderCreateRange = 'order.create.range';
  static const String orderCreateAmountSingle = 'order.create.amount.single';
  static const String orderCreateAmountRange = 'order.create.amount.range';
  static const String orderCreateFiatMin = 'order.create.fiat_min';
  static const String orderCreateFiatMax = 'order.create.fiat_max';
  // Payment methods live on their own screen, opened by the `Add` chip. The
  // free-text field is the one an automated driver can fill with an
  // arbitrary method; `custom_add` turns it into a chip.
  static const String orderCreatePaymentMethodAdd =
      'order.create.payment_method.add';
  static const String orderCreatePaymentMethodSearch =
      'order.create.payment_method.search';
  static const String orderCreatePaymentMethod = 'order.create.payment_method';
  static const String orderCreatePaymentMethodCustomAdd =
      'order.create.payment_method.custom_add';
  // `Market | Fixed` control, as a whole and per segment. Fixed is disabled
  // while a range order is being written.
  static const String orderCreatePriceType = 'order.create.price_type';
  static const String orderCreatePriceMarket = 'order.create.price.market';
  static const String orderCreatePriceFixed = 'order.create.price.fixed';
  // The premium figure; tapping it opens the numeric keyboard in place.
  static const String orderCreatePremium = 'order.create.premium';
  static const String orderCreateSatsAmount = 'order.create.sats_amount';
  static const String orderCreateSubmit = 'order.create.submit';
  static const String orderCreateCancel = 'order.create.cancel';
  static const String orderConfirmHome = 'order.confirm.home';

  /// Row of an order in the public order book.
  static String orderBookItem(String orderId) => 'order.book.item.$orderId';

  /// Currency option in the create-order currency picker.
  ///
  /// The picker lists every supported currency, so only a handful are built
  /// at a time: narrow the list through [orderCreateCurrencySearch] before
  /// looking for one. `search` is not a currency code, so the two identifiers
  /// cannot collide.
  static String orderCreateCurrencyOption(String code) =>
      'order.create.currency.$code';

  /// One method in the payment-method picker. Methods carry spaces and
  /// punctuation, which the identifier keeps verbatim.
  static String orderCreatePaymentMethodOption(String method) =>
      'order.create.payment_method.$method';

  // Take order — v2 asks the fiat amount on the same screen (range orders).
  static const String orderTakeAmount = 'order.take.amount';
  static const String orderTakeAmountConfirm = 'order.take.amount.confirm';
  static const String orderTakeConfirm = 'order.take.confirm';

  // Trade detail
  static const String orderId = 'order.id';
  static const String orderStatus = 'order.status';
  static const String tradePayInvoice = 'trade.payInvoice';
  static const String tradePayBond = 'trade.payBond';
  static const String tradeAddInvoice = 'trade.addInvoice';
  static const String tradeFiatSent = 'trade.fiatSent';
  static const String tradeRelease = 'trade.release';
  static const String tradeReleaseConfirm = 'trade.release.confirm';
  static const String tradeCancel = 'trade.cancel';
  static const String tradeCancelConfirm = 'trade.cancel.confirm';
  static const String tradeDispute = 'trade.dispute';
  static const String tradeDisputeConfirm = 'trade.dispute.confirm';
  static const String tradeRate = 'trade.rate';
  static const String tradeRateSubmit = 'trade.rate.submit';
  static const String tradeRateClose = 'trade.rate.close';
  static const String tradeViewDispute = 'trade.dispute.view';
  static const String tradeClose = 'trade.close';

  /// Star [score] (1-5) on the rating screen.
  static String tradeRateStar(int score) => 'trade.rate.star.$score';

  /// Row of a trade in the My Trades list.
  static String tradesItem(String orderId) => 'trades.item.$orderId';

  // Buyer invoice (NWC generated or manual) and hold-invoice payment
  static const String invoiceNwcText = 'invoice.nwc.text';
  static const String invoiceManual = 'invoice.manual';
  static const String invoiceAmount = 'invoice.amount';
  static const String invoiceOrderId = 'invoice.order_id';
  static const String invoiceText = 'invoice.text';
  static const String invoiceSubmit = 'invoice.submit';

  /// Readout: the daemon's reason for refusing the last submitted invoice.
  /// Present only after a rejection, until the next submission.
  static const String invoiceError = 'invoice.error';
  static const String invoiceCancel = 'invoice.cancel';
  static const String payInvoiceText = 'pay.invoice.text';

  // Anti-abuse bond (docs/ANTI_ABUSE_BOND.md, handoff 14a/14b)
  /// Readout: the bond bolt11, otherwise only drawn as a QR code.
  static const String bondInvoiceText = 'bond.invoice.text';
  static const String bondOrderId = 'bond.order_id';
  static const String bondExplainer = 'bond.explainer';
  static const String bondCancel = 'bond.cancel';
  static const String payOrderId = 'pay.order_id';
  static const String payNwc = 'pay.nwc';
  static const String payCancel = 'pay.cancel';
}
