// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Mostro';

  @override
  String get loading => 'Loading…';

  @override
  String get actionFailedAnnouncement => 'Action failed';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get done => 'Done';

  @override
  String get skip => 'Skip';

  @override
  String get chatTimestampYesterday => 'Yesterday';

  @override
  String get disputesEmptyState => 'Your disputes will appear here';

  @override
  String get disputeAttachFile => 'Attach file';

  @override
  String get disputeWriteMessageHint => 'Write a message…';

  @override
  String get disputeSend => 'Send';

  @override
  String get orderDispute => 'Order dispute';

  @override
  String get disputeSolverAssigned =>
      'A dispute resolver has taken your dispute. They will contact you here shortly.';

  @override
  String get disputeChatClosed =>
      'This dispute has been resolved. The chat is closed.';

  @override
  String get messageCopied => 'Copied';

  @override
  String get disputeLoadError => 'Failed to load disputes. Please try again.';

  @override
  String get disputeSolverNotAssigned =>
      'No resolver has taken this dispute yet. You can write once one does.';

  @override
  String get disputeNotFound => 'Dispute not found.';

  @override
  String get disputeNotFoundForOrder => 'Dispute not found for this order.';

  @override
  String get disputeResolved => 'Resolved';

  @override
  String get disputeSuccessfullyCompleted => 'Successfully completed';

  @override
  String get disputeCoopCancelMessage =>
      'The order was cooperatively cancelled. No funds were transferred.';

  @override
  String orderLabel(String orderId) {
    return 'Order $orderId';
  }

  @override
  String get disputeStatusClosed => 'Closed';

  @override
  String disputeWith(String role, String counterparty) {
    return 'Dispute with $role: $counterparty';
  }

  @override
  String get seller => 'Seller';

  @override
  String get buyer => 'Buyer';

  @override
  String get disputeStatusInitiated => 'Initiated';

  @override
  String get disputeStatusInProgress => 'In progress';

  @override
  String get disputeStatusResolved => 'Resolved';

  @override
  String get disputeInProgress =>
      'This dispute is currently in progress. A resolver is reviewing your case.';

  @override
  String get disputeInstruction1 =>
      'Wait for a resolver to take your dispute. Once they arrive, share any relevant evidence to help clarify the situation.';

  @override
  String get disputeInstruction2 =>
      'The final decision will be made based on the evidence presented.';

  @override
  String get disputeInstruction3 =>
      'If you don\'t respond, the system will assume you don\'t want to cooperate and you might lose the dispute.';

  @override
  String disputeOpenedByYouAgainstSeller(String counterparty) {
    return 'You opened this dispute against the seller $counterparty. Please read the following carefully:';
  }

  @override
  String disputeOpenedByYouAgainstBuyer(String counterparty) {
    return 'You opened this dispute against the buyer $counterparty. Please read the following carefully:';
  }

  @override
  String get disputeWaitingForAdmin =>
      'Waiting for a resolver to take the dispute';

  @override
  String get disputeLostFundsToBuyer =>
      'The dispute resolver settled the dispute in the buyer\'s favour. The sats were released to the buyer.';

  @override
  String get disputeLostFundsToSeller =>
      'The dispute resolver cancelled the order and returned the sats to the seller. You did not receive the sats.';

  @override
  String get walkthroughWelcomeTitle => 'P2P Bitcoin, no KYC';

  @override
  String get walkthroughWelcomeBody1 =>
      'Mostro is a peer-to-peer exchange that lets you trade Bitcoin for any currency and payment method, with no KYC and no need to give your data to anyone.';

  @override
  String get walkthroughWelcomeBody2 =>
      'It\'s built on Nostr, which makes it censorship-resistant. No one can stop you from trading.';

  @override
  String get walkthroughPrivacyTitle => 'Privacy by default';

  @override
  String get walkthroughPrivacyBody1 =>
      'Mostro generates a new identity for every trade, so your trades can\'t be linked.';

  @override
  String get walkthroughPrivacyBody2 =>
      'You can also decide how private you want to be:';

  @override
  String get walkthroughReputationModeName => 'Reputation mode';

  @override
  String get walkthroughReputationModeBody =>
      'Lets others see your successful trades and trust level.';

  @override
  String get walkthroughFullPrivacyModeName => 'Full privacy mode';

  @override
  String get walkthroughFullPrivacyModeBody =>
      'No reputation is built, but your activity is completely anonymous.';

  @override
  String get walkthroughPrivacyFooter =>
      'Switch modes anytime from the Account screen. That\'s also where you should save your secret words. They\'re the only way to recover your account.';

  @override
  String get walkthroughHeldTitle => 'Security at every step';

  @override
  String get walkthroughHeldBody1 =>
      'The seller\'s sats stay locked until the trade ends. This protects both sides.';

  @override
  String get walkthroughHeldBody2 =>
      'The app is also designed to be intuitive and easy for all kinds of users.';

  @override
  String get walkthroughChatTitle => 'Fully encrypted chat';

  @override
  String get walkthroughChatBody1 =>
      'Each trade has its own private chat, end-to-end encrypted. Only you and your counterpart can read it, unless one of you shares its key.';

  @override
  String get walkthroughChatBody2 =>
      'In a dispute, sharing that key with a dispute resolver lets them read the chat and help settle it.';

  @override
  String get walkthroughTakeTitle => 'Take an order';

  @override
  String get walkthroughTakeBody1 =>
      'Browse the order book, choose an order that works for you, and follow the trade step by step.';

  @override
  String get walkthroughTakeBody2 =>
      'You\'ll be able to check your counterpart\'s profile, chat securely, and complete the trade with ease.';

  @override
  String get walkthroughMakeTitle => 'Can\'t find what you need?';

  @override
  String get walkthroughMakeBody1 =>
      'You can also create your own order and wait for someone to take it.';

  @override
  String get walkthroughMakeBody2 =>
      'Set the amount and your preferred payment method. Mostro handles the rest.';

  @override
  String get walkthroughNext => 'Next';

  @override
  String walkthroughStepCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String walkthroughStepSemantics(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get tabBuyBtc => 'Buy BTC';

  @override
  String get tabSellBtc => 'Sell BTC';

  @override
  String get filterButtonLabel => 'Filter';

  @override
  String filtersActiveCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString filters on',
      one: '1 filter on',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'No orders available';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int m) {
    return '${m}m ago';
  }

  @override
  String hoursAgo(int h) {
    return '${h}h ago';
  }

  @override
  String daysAgo(int d) {
    return '${d}d ago';
  }

  @override
  String get invoiceRejected =>
      'The node rejected this invoice. Check its amount and expiry and add a new one.';

  @override
  String get invoiceCopied => 'Invoice copied';

  @override
  String get submitButtonLabel => 'Submit';

  @override
  String get orderAlreadyTaken => 'Order has already been taken';

  @override
  String get nodeProtocolUnsupported =>
      'This Mostro node uses a protocol version this app does not support. Pick another node in Settings, or check for an app update';

  @override
  String get nodeCapabilitiesUnknown =>
      'Still checking what the selected Mostro node supports. Try again in a moment';

  @override
  String get tradeOnOtherNode =>
      'This trade belongs to another Mostro node. Switch to that node to act on it';

  @override
  String get mostroMaintenanceMode =>
      'The Mostro node you are connected to is under maintenance. Try again later, or connect to a different Mostro node in Settings';

  @override
  String get storageUnavailable =>
      'The app cannot create or take orders while its local database is unavailable. Restart the app and try again';

  @override
  String get rangeOrderWithSats =>
      'A range order can\'t have a fixed sats amount: it is priced at market when taken.';

  @override
  String get orderIdCopied => 'Order ID copied';

  @override
  String get comingSoonMessage => 'Coming soon';

  @override
  String get tradeStatusCompleted => 'Completed';

  @override
  String get tradeStatusCancelled => 'Cancelled';

  @override
  String get tradeStatusDisputed => 'Disputed';

  @override
  String get accountScreenTitle => 'Account';

  @override
  String get secretWordsTitle => 'Secret Words';

  @override
  String get privacyCardTitle => 'Privacy';

  @override
  String get reputationMode => 'Reputation Mode';

  @override
  String get reputationModeSubtitle =>
      'Your trades count toward your public reputation';

  @override
  String get fullPrivacyMode => 'Full Privacy Mode';

  @override
  String get fullPrivacyModeSubtitle =>
      'Each trade uses a new identity, no reputation';

  @override
  String get generateNewUserButton => 'Generate New User';

  @override
  String get importMostroUserButton => 'Import Mostro User';

  @override
  String get generateNewUserDialogTitle => 'Generate New User?';

  @override
  String get generateNewUserDialogContent =>
      'This will create a brand-new identity. Your current secret words will no longer work — make sure they are backed up before continuing.';

  @override
  String get continueButtonLabel => 'Continue';

  @override
  String get importMnemonicDialogTitle => 'Import secret words';

  @override
  String get importMnemonicHintText => 'Enter your 12 secret words';

  @override
  String get importButtonLabel => 'Import';

  @override
  String get refreshUserDialogTitle => 'Refresh User?';

  @override
  String get refreshUserDialogContent =>
      'This will re-fetch your trades and orders from the Mostro node. Use this if you think your data is out of sync or orders are missing.';

  @override
  String get hideButtonLabel => 'Hide';

  @override
  String get showWordsButton => 'Show words';

  @override
  String get settingsScreenTitle => 'Settings';

  @override
  String get languageSettingTitle => 'Language';

  @override
  String get appearanceSettingTitle => 'Appearance';

  @override
  String get appearanceDialogTitle => 'Appearance';

  @override
  String get allCurrencies => 'All currencies';

  @override
  String get lightningAddressSettingTitle => 'Lightning Address';

  @override
  String get nwcWalletSettingTitle => 'NWC Wallet';

  @override
  String get relaysSettingTitle => 'Relays';

  @override
  String get pushNotificationsSettingTitle => 'Push Notifications';

  @override
  String get logReportSettingTitle => 'Log Report';

  @override
  String get mostroNodeSettingTitle => 'Mostro Node';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystemDefault => 'System default';

  @override
  String get lightningAddressDialogTitle => 'Lightning Address';

  @override
  String get lightningAddressHintText => 'user@domain.com';

  @override
  String get invalidLightningAddressFormat => 'Must be in user@domain format';

  @override
  String get clearButtonLabel => 'Clear';

  @override
  String get saveButtonLabel => 'Save';

  @override
  String get scanQrCodeTitle => 'Scan QR Code';

  @override
  String get selectLanguageTitle => 'Select Language';

  @override
  String get selectCurrencyDialogTitle => 'Select Currency';

  @override
  String get addRelayDialogTitle => 'Add Relay';

  @override
  String get addButtonLabel => 'Add';

  @override
  String get relayHintText => 'wss://relay.example.com';

  @override
  String get relayErrorMustStartWithWss => 'Must start with wss://';

  @override
  String get relayErrorUrlTooShort => 'URL is too short';

  @override
  String get relayErrorDuplicate => 'Relay already in list';

  @override
  String get pasteQrCodeHeading => 'Paste QR Code Content';

  @override
  String get pasteButtonLabel => 'Paste';

  @override
  String get clipboardEmptyError => 'Clipboard is empty';

  @override
  String get enterValueError => 'Please enter a value';

  @override
  String get trustedBadgeLabel => 'Trusted';

  @override
  String get confirmButtonLabel => 'Confirm';

  @override
  String get selectMostroNode => 'Choose a node';

  @override
  String get addCustomNode => 'Add your own node';

  @override
  String get nodePubkeyFieldLabel => 'Public key';

  @override
  String get nodePubkeyFieldHint => '64-char hex or npub…';

  @override
  String get nodeNameOptionalLabel => 'Name (optional)';

  @override
  String get invalidPubkeyFormat =>
      'Enter a valid public key (64-char hex or npub)';

  @override
  String get privateKeyNotAllowed =>
      'That is a private key — never share it. Enter the node\'s public key instead';

  @override
  String get nodeAlreadyExists => 'This node is already in the list';

  @override
  String get nodeAddedSuccess => 'Node added';

  @override
  String nodeSwitchedSuccess(String nodeName) {
    return 'Now using $nodeName';
  }

  @override
  String get errorSwitchingNode => 'Failed to switch node';

  @override
  String get cannotRemoveActiveNode =>
      'The active node can\'t be removed — switch to another node first';

  @override
  String get deleteCustomNodeTitle => 'Remove node';

  @override
  String get deleteCustomNodeMessage =>
      'Remove this custom node from your list?';

  @override
  String get deleteCustomNodeConfirm => 'Remove';

  @override
  String get nodeRemovedSuccess => 'Node removed';

  @override
  String get nodeStorageUnavailable =>
      'The local database isn\'t ready. Restart the app and try again';

  @override
  String nodeSelectorSubtitle(String code) {
    return 'Orders and currencies for $code, your currency';
  }

  @override
  String get nodeSelectorSubtitleNoCurrency => 'Open orders on each node';

  @override
  String nodeMissingCurrencyChip(String code) {
    return 'NO $code';
  }

  @override
  String get nodeOrdersNowLabel => 'orders now';

  @override
  String get nodeNoOrdersLabel => 'no orders';

  @override
  String nodeOrdersInCurrency(int count, String code) {
    return '· $count in $code';
  }

  @override
  String get nodeFeeLabel => 'fee';

  @override
  String get nodeFeeTooltip => 'Mostro splits the fee between both parties.';

  @override
  String get nodePerTradeLabel => 'per trade';

  @override
  String get nodeCustodyLightning => 'Lightning custody';

  @override
  String nodeCustodyCashu(String mint) {
    return 'Cashu custody · $mint';
  }

  @override
  String get nodeCustodyUnknown => 'Custody —';

  @override
  String nodeBondPct(String pct) {
    return 'Deposit $pct%';
  }

  @override
  String get nodeBondNone => 'No deposit';

  @override
  String nodeStatusOnline(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString orders',
      one: '1 order',
    );
    return 'Online · $_temp0';
  }

  @override
  String get nodeStatusNoUsefulOrders => 'No orders in your currencies';

  @override
  String nodeStatusUnreachable(String ago) {
    return 'Not responding · last seen $ago';
  }

  @override
  String get nodeStatusUnreachableNoSignal => 'Not responding';

  @override
  String get nodeChoiceSubtitle =>
      'Select the Mostro node you want to trade on';

  @override
  String get nodeOperatorDisclaimer =>
      'The Mostro development team is not responsible for how node operators use the platform. Each operator controls their own Mostro node and is solely responsible for their actions. By using Mostro, you accept full responsibility for your trades and acknowledge that the development team has no control over individual node operators.';

  @override
  String get nodeChoiceConfirm => 'Use this node';

  @override
  String get nodeChoiceSaveFailed => 'Couldn\'t save your choice. Try again.';

  @override
  String get nodeVerifyKeyWarning =>
      'Verify the key with the operator. A fake node can see your orders.';

  @override
  String get nodeInvalidPubkeyShort => 'This is not a valid public key.';

  @override
  String get nodeNameFieldHint => 'Local Mostro';

  @override
  String get nodePubkeyCopied => 'Key copied';

  @override
  String get nodeNotSelectableOffline => 'This node is not responding';

  @override
  String get nodeStatsLoading => 'Loading node data';

  @override
  String get nodeSwitchConfirmTitle => 'Change node?';

  @override
  String nodeSwitchConfirmBody(String currentNode, String newNode) {
    return 'You have a trade in progress on $currentNode. It stays there; the order book will now show $newNode.';
  }

  @override
  String get nodeSwitchConfirmAction => 'Change node';

  @override
  String get nodeTradesCheckFailed => 'Couldn\'t check your trades. Try again.';

  @override
  String get notificationsScreenTitle => 'Notifications';

  @override
  String get markAllAsReadMenuItem => 'Mark all as read';

  @override
  String get clearAllMenuItem => 'Clear all';

  @override
  String get youMustBackUpYourAccount => 'You must back up your account';

  @override
  String get tapToViewAndSaveSecretWords =>
      'Tap to view and save your secret words.';

  @override
  String get noNotifications => 'No notifications';

  @override
  String get markAsRead => 'Mark as read';

  @override
  String get deleteNotificationLabel => 'Delete';

  @override
  String get rateScreenHeader => 'RATE';

  @override
  String get successfulOrder => 'Successful order';

  @override
  String get closeRatingButton => 'CLOSE';

  @override
  String get aboutScreenTitle => 'About';

  @override
  String get linkCopiedToClipboard => 'Link copied to clipboard';

  @override
  String get pubkeyLabel => 'Pubkey';

  @override
  String get relaysLabel => 'Relays';

  @override
  String get footerTagline => 'Open-source. Non-custodial. Private.';

  @override
  String get drawerTitle => 'Mostro';

  @override
  String get drawerTagline => 'P2P exchange';

  @override
  String get drawerStageBadge => 'Beta';

  @override
  String drawerVersion(String version) {
    return 'Version $version';
  }

  @override
  String get drawerAccountMenuItem => 'Account';

  @override
  String get drawerSettingsMenuItem => 'Settings';

  @override
  String get drawerAboutMenuItem => 'About';

  @override
  String get navOrderBook => 'Order Book';

  @override
  String get navMyTrades => 'My Trades';

  @override
  String get navChat => 'Chat';

  @override
  String get loadingOrders => 'Loading orders…';

  @override
  String get errorLoadingOrders =>
      'Could not load orders. Please check your connection.';

  @override
  String get retry => 'Retry';

  @override
  String disableRelayLabel(String url) {
    return 'Disable relay $url';
  }

  @override
  String enableRelayLabel(String url) {
    return 'Enable relay $url';
  }

  @override
  String get removeRelayTooltip => 'Remove relay';

  @override
  String get relayAddFailed => 'Failed to add relay';

  @override
  String get relayRemoveFailed => 'Failed to remove relay';

  @override
  String get backupRitualSecondFailureMessage =>
      'That was incorrect again. Please review and back up your secret words, then verify from the start.';

  @override
  String get cancelTradeDialogTitle => 'Cancel trade?';

  @override
  String get cancelTradeDialogContent =>
      'Requesting a cooperative cancel. Your counterpart must also agree for the trade to be fully cancelled.';

  @override
  String get cancelTradeDialogContentNotStarted =>
      'The trade has not started yet, so it is cancelled right away. Your counterpart does not need to agree.';

  @override
  String get cancelTradeDialogContentMaybeStarted =>
      'If the trade has not started yet, it is cancelled right away. If it has, your counterpart must also agree.';

  @override
  String get noButtonLabel => 'No';

  @override
  String get yesButtonLabel => 'Yes';

  @override
  String get yesCancelButtonLabel => 'Yes, cancel';

  @override
  String get cancelRequestSent => 'Cancel request sent';

  @override
  String get cancelRequestFailed => 'Failed to cancel. Please try again.';

  @override
  String get tradeCardCancelRequestedByMeTitle => 'Cancel requested';

  @override
  String get tradeCardCancelRequestedByMeMessage =>
      'You asked to cancel this trade. It stays open until your counterpart also cancels. If they do not respond, you can open a dispute.';

  @override
  String get tradeCardCancelRequestedByPeerTitle =>
      'Your counterpart wants to cancel';

  @override
  String get tradeCardCancelRequestedByPeerMessage =>
      'They asked to cancel this trade. Accept to end it with no funds moved, or keep trading.';

  @override
  String get tradeCancelRequestedByMeNotice =>
      'You asked to cancel this trade. It stays open until your counterpart also cancels. If they do not respond, you can open a dispute.';

  @override
  String get tradeCancelRequestedByPeerNotice =>
      'Your counterpart asked to cancel this trade. Accept to end it with no funds moved, or keep trading.';

  @override
  String get acceptCancelButton => 'Accept cancel';

  @override
  String get cancelTradeDialogContentAccept =>
      'Your counterpart asked to cancel. Cancelling now ends the trade for both of you and no funds are moved.';

  @override
  String get fiatSentFailed =>
      'Failed to mark the payment as sent. Please try again.';

  @override
  String get releaseFailed => 'Failed to release. Please try again.';

  @override
  String get releasePendingLabel => 'Releasing… waiting for the node';

  @override
  String get releaseSentNotice =>
      'Release sent. The node can take up to a minute to confirm it.';

  @override
  String get releaseUnconfirmedNotice =>
      'The node has not confirmed the release yet. If the order doesn\'t update, you can release again.';

  @override
  String get cancelTradeButton => 'Cancel trade';

  @override
  String get payHoldInvoiceButton => 'Pay invoice';

  @override
  String get openDisputeButton => 'Open dispute';

  @override
  String get releaseSatsButton => 'Release sats';

  @override
  String get confirmReleaseSatsButton => 'Confirm & release sats';

  @override
  String get shareOrderButton => 'Share order';

  @override
  String get orderPillYouAreSelling => 'YOU ARE SELLING';

  @override
  String get orderPillYouAreBuying => 'YOU ARE BUYING';

  @override
  String get myOrderSellTitle => 'Your sell order';

  @override
  String get myOrderBuyTitle => 'Your buy order';

  @override
  String get cancelOrderFailed => 'Failed to cancel order. Please try again.';

  @override
  String get closeButtonLabel => 'Close';

  @override
  String get copyButtonLabel => 'Copy';

  @override
  String get orderStatusWaitingForTaker => 'Waiting for a taker';

  @override
  String get orderStatusInProgress => 'In progress';

  @override
  String get orderStatusExpired => 'Expired';

  @override
  String get copyOrderIdTooltip => 'Copy order ID';

  @override
  String get orderNotFoundTitle => 'Order Not Found';

  @override
  String get orderNotFoundMessage => 'This order is no longer available.';

  @override
  String get orderCancelledSuccess => 'Order cancelled successfully.';

  @override
  String get aboutDocumentationTitle => 'Documentation';

  @override
  String get aboutMostroNodeTitle => 'Mostro Node';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String get aboutCommitHashLabel => 'Commit Hash';

  @override
  String get aboutLicenseLabel => 'License';

  @override
  String get aboutLicenseName => 'AGPLv3+';

  @override
  String get aboutGithubRepoName => 'MostroP2P/app';

  @override
  String get aboutCopiedToClipboard => 'Copied to clipboard';

  @override
  String get aboutLicenseDialogTitle => 'GNU Affero General Public License v3';

  @override
  String get aboutNodeLoadingText => 'Loading node information…';

  @override
  String get aboutNodeUnavailable => 'Node information unavailable';

  @override
  String get aboutNodeRetry => 'Retry';

  @override
  String get aboutLightningNetworkSection => 'Lightning Network';

  @override
  String get aboutFiatCurrenciesLabel => 'Fiat Currencies';

  @override
  String get aboutPriceSourceLabel => 'Source';

  @override
  String get aboutPriceSection => 'Price';

  @override
  String get aboutPriceSourcesFootnote =>
      'Price sources are the providers behind the rates the node publishes now; one that failed or was set aside is not listed.';

  @override
  String get aboutMostroVersionLabel => 'Mostro Version';

  @override
  String get aboutMostroCommitLabel => 'Mostro Commit';

  @override
  String get aboutHoldInvoiceExpLabel => 'Hold Invoice Expiration';

  @override
  String get aboutHoldInvoiceCltvLabel => 'Hold Invoice CLTV';

  @override
  String get aboutInvoiceExpWindowLabel => 'Invoice Expiration Window';

  @override
  String get aboutProofOfWorkLabel => 'Proof of Work';

  @override
  String get aboutMaxOrdersPerResponseLabel => 'Max Orders/Response';

  @override
  String get aboutLndVersionLabel => 'LND Version';

  @override
  String get aboutSupportedChainsLabel => 'Supported Chains';

  @override
  String get aboutSupportedNetworksLabel => 'Supported Networks';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutBlocksSuffix => 'blocks';

  @override
  String get aboutFiatCurrenciesAll => 'All';

  @override
  String get aboutAntiAbuseBondSection => 'Anti-abuse Deposit';

  @override
  String get aboutBondEnabledValue => 'Enabled';

  @override
  String get aboutBondDisabledValue => 'Disabled';

  @override
  String get aboutBondUnsupportedValue => 'Not supported';

  @override
  String get aboutBondStatusLabel => 'Deposit status';

  @override
  String get aboutBondAppliesToLabel => 'Applies to';

  @override
  String get aboutBondAppliesToTakers => 'Takers';

  @override
  String get aboutBondAppliesToMakers => 'Makers';

  @override
  String get aboutBondAppliesToBoth => 'Makers and takers';

  @override
  String get aboutBondAmountLabel => 'Deposit amount';

  @override
  String get aboutBondBaseAmountLabel => 'Minimum deposit';

  @override
  String get aboutBondNodeShareLabel => 'Node\'s share of a forfeited deposit';

  @override
  String get aboutBondSlashOnTimeoutLabel => 'Forfeited when a step times out';

  @override
  String get aboutBondClaimWindowLabel => 'Payout claim window';

  @override
  String aboutBondClaimWindowValue(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString days',
      one: '$countString day',
    );
    return '$_temp0';
  }

  @override
  String get openDisputeFailed => 'Could not open dispute. Please try again.';

  @override
  String get openDisputeTitle => 'Open dispute';

  @override
  String get openDisputeConfirmation =>
      'Are you sure you want to open a dispute? This escalates the trade to a dispute resolver and cannot be undone.';

  @override
  String get disputeAlreadyOpen => 'A dispute for this trade is already open.';

  @override
  String get tradeNotDisputable =>
      'A dispute can only be opened once the funds are locked for this trade.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Submit your Lightning invoice so the seller can lock the funds.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'Waiting for the buyer to submit their Lightning invoice.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Pay the invoice to lock the sats and start the trade.';

  @override
  String get tradeLoadError => 'An error occurred while loading the trade.';

  @override
  String get tradeWaitingForHoldInvoice => 'Waiting for the invoice…';

  @override
  String get shareButtonLabel => 'Share';

  @override
  String get shareFailed => 'Could not share the invoice';

  @override
  String get waitingForPaymentConfirmation =>
      'Waiting for payment confirmation…';

  @override
  String get orderNoLongerActive => 'This order is no longer active';

  @override
  String get tradeNoLongerYours => 'You\'re no longer part of this trade';

  @override
  String get sessionTimeoutMessage =>
      'No response received. Check your connection and try again later.';

  @override
  String get noRelayAcceptedMessage =>
      'No relay accepted your message. Check your relays in Settings and try again';

  @override
  String get noIdentityFoundMessage =>
      'No identity found — try restarting the app.';

  @override
  String get failedToLoadSecretWordsMessage =>
      'Failed to load secret words. Please try again.';

  @override
  String get privacyModesInfoTitle => 'Privacy Modes';

  @override
  String get privacyModesInfoContent =>
      'Reputation mode lets others see your successful trades.\n\nFull privacy mode keeps your activity completely anonymous — no reputation is built.';

  @override
  String get failedToGenerateIdentityMessage =>
      'Failed to generate identity. Please try again.';

  @override
  String get pendingWipeBannerTitle =>
      'Previous user\'s data is still on this device';

  @override
  String get pendingWipeBannerBody =>
      'Deleting the previous identity could not remove its trades and chats from this device. The app will retry the next time a new user is generated or imported.';

  @override
  String get pendingWipeBlockedMessage =>
      'The previous user\'s data could not be removed from this device, so the new user was not set up and your current user was kept. Please try again.';

  @override
  String get wipeNotRecordedMessage =>
      'The current user could not be removed safely, so nothing was changed. Please try again.';

  @override
  String get identitySwapStorageUnavailableMessage =>
      'This device\'s storage is not available right now, so the current user was kept and nothing was changed. Restart the app and try again.';

  @override
  String get identitySwapPreviousNotReloadedMessage =>
      'The new user was not set up, and the current user could not be fully restored. Restart the app to load it again.';

  @override
  String get invalidMnemonicMessage =>
      'Invalid secret words. Please check your words and try again.';

  @override
  String get enterValidMnemonicError => 'Enter your 12 secret words.';

  @override
  String get orderBookRefreshedMessage => 'Order book refreshed';

  @override
  String get refreshFailedMessage => 'Refresh failed';

  @override
  String get refreshButtonLabel => 'Refresh';

  @override
  String get okButtonLabel => 'OK';

  @override
  String get moreInformationTooltip => 'More information';

  @override
  String get backedUpBadgeLabel => 'Backed up';

  @override
  String get backupBannerTitle => 'Secure your reputation';

  @override
  String get backupBannerSubtitle =>
      'Back up your 12 words — it takes 60 seconds.';

  @override
  String get failedToSaveBackupStatusMessage =>
      'Failed to save backup status. Please try again.';

  @override
  String get backupRitualStep1Title => 'Step 1 of 3 · Write down your words';

  @override
  String get backupRitualStep2Title => 'Step 2 of 3 · Verify';

  @override
  String get backupRitualStep3Title => 'Step 3 of 3 · Done';

  @override
  String get backupRitualWarningTitle => 'Write them on paper. ';

  @override
  String get backupRitualWarningBody =>
      'Don\'t store them in photos, screenshots or the cloud — anyone with these 12 words can steal your reputation.';

  @override
  String get wordsHiddenOnLeaveNote =>
      'They will be hidden when you leave this screen';

  @override
  String get wroteThemDownVerifyButton => 'I wrote them down — verify';

  @override
  String get tapCorrectWordsTitle => 'Tap the correct words';

  @override
  String get verifyInstructionsBody =>
      'We ask for 3 at random. If you get them right, we know they\'re safely written down.';

  @override
  String optionsForWordLabel(int number) {
    return 'OPTIONS FOR WORD #$number';
  }

  @override
  String get wrongPickMessage => 'Not quite — check your paper and try again.';

  @override
  String get allWordsCorrectMessage => 'All 3 words correct';

  @override
  String get reviewWordsButton => 'View words';

  @override
  String get accountBackedUpTitle => 'Your account is backed up';

  @override
  String get accountBackedUpBody =>
      'Your reputation is safe. If you ever lose your phone, restore your account with your 12 words.';

  @override
  String wordNumberLabel(int number) {
    return 'Word #$number';
  }

  @override
  String get backupTriggerBody =>
      'Your reputation lives in a key only you hold. If you lose your phone, you lose that reputation — ';

  @override
  String get backupTriggerBodyHighlight => 'back it up in 60 seconds.';

  @override
  String get backupStepWriteDown => 'Write your 12 words down on paper';

  @override
  String get backupStepVerifyRandom => 'We ask for 3 at random to confirm';

  @override
  String get backupStepSecured => 'Done — your account is secured';

  @override
  String get backupNowButton => 'Back up now';

  @override
  String get backupLaterButton => 'I\'ll do it later';

  @override
  String get nwcConnectionFailedMessage =>
      'Connection failed. Please check your NWC URI and try again.';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'Clipboard does not contain a valid NWC URI.';

  @override
  String get scanQrButtonLabel => 'Scan QR';

  @override
  String get connectButtonLabel => 'Connect';

  @override
  String get walletDisconnectedMessage => 'Wallet disconnected';

  @override
  String get relayLabel => 'Relay';

  @override
  String get disconnectButtonLabel => 'Disconnect';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count more)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Choose which events show a notification in the app.';

  @override
  String get notifTradeUpdatesTitle => 'Trade updates';

  @override
  String get notifTradeUpdatesSubtitle =>
      'Status changes in your active trades';

  @override
  String get notifNewMessagesTitle => 'New messages';

  @override
  String get notifNewMessagesSubtitle => 'Messages from your trade counterpart';

  @override
  String get notifPaymentAlertsTitle => 'Payment alerts';

  @override
  String get notifPaymentAlertsSubtitle =>
      'Lightning payment confirmations and failures';

  @override
  String get notifDisputeUpdatesTitle => 'Dispute updates';

  @override
  String get notifDisputeUpdatesSubtitle =>
      'Resolver actions and dispute resolutions';

  @override
  String get notifAnnouncementsTitle => 'Announcements';

  @override
  String get notifAnnouncementsSubtitle =>
      'Releases, outages and relay changes, signed by the Mostro project';

  @override
  String get announcementsGroupSubtitle =>
      'Announcements are read from the relays and never answered: nothing about you is sent.';

  @override
  String get announcementLevelInfo => 'Announcement';

  @override
  String get announcementLevelWarning => 'Notice';

  @override
  String get announcementLevelCritical => 'Security update';

  @override
  String get announcementOpenLink => 'Open link';

  @override
  String get notificationsBellCritical =>
      'Notifications, a security update is unread';

  @override
  String get searchCurrenciesHint => 'Search currencies…';

  @override
  String get noCurrenciesFoundMessage => 'No currencies found';

  @override
  String get shareLogsTooltip => 'Share logs';

  @override
  String get noLogsToShareTooltip => 'No logs to share';

  @override
  String get noLogEntriesMessage => 'No log entries';

  @override
  String get failedToShareLogsMessage => 'Failed to share logs';

  @override
  String get logReportShareHeading => 'Mostro log report';

  @override
  String get tradeFilterAll => 'All';

  @override
  String get tradeFilterPending => 'Pending';

  @override
  String get tradeFilterWaitingInvoice => 'Waiting Invoice';

  @override
  String get tradeFilterWaitingPayment => 'Waiting Payment';

  @override
  String get tradeFilterActive => 'Active';

  @override
  String get tradeFilterFiatSent => 'Fiat Sent';

  @override
  String get tradeFilterSuccess => 'Success';

  @override
  String get tradeFilterCanceled => 'Cancelled';

  @override
  String get tradeFilterDispute => 'Dispute';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get noTradesTitle => 'No trades';

  @override
  String get noTradesSubtitle =>
      'Your active and completed trades will appear here.';

  @override
  String get couldNotLoadTradesMessage => 'Could not load trades';

  @override
  String get sellingBitcoin => 'Selling Bitcoin';

  @override
  String get buyingBitcoin => 'Buying Bitcoin';

  @override
  String get tradeInstructionActiveBuyer =>
      'Once you have sent the money, mark it below. Only open a dispute if the seller stops responding.';

  @override
  String get tradeInstructionFiatSentBuyer =>
      'Payment marked as sent. Waiting for the seller to confirm receipt and release your sats.';

  @override
  String get tradeInstructionActiveSeller =>
      'Contact the buyer with payment instructions via the chat above.';

  @override
  String get tradeInstructionFiatSentSeller =>
      'The buyer has confirmed they sent the payment. Once you verify receipt, release the sats.';

  @override
  String get tradeInstructionDisputed =>
      'A dispute resolver has been assigned. They will contact you through the app.';

  @override
  String get tradeInstructionPending =>
      'Your order is published and waiting for a counterpart to take it. You can cancel it at any time.';

  @override
  String get tradeInstructionCancelled =>
      'This trade was cancelled. No funds were exchanged.';

  @override
  String get tradeInstructionInProgress => 'Trade in progress.';

  @override
  String get theAgreedAmount => 'the agreed amount';

  @override
  String get tradeHeadlinePending => 'Waiting for someone to take your order';

  @override
  String get tradeHeadlineInProgress => 'The trade is being set up';

  @override
  String get tradeHeadlineWaitingInvoiceBuyer =>
      'Share a Lightning invoice to receive your sats';

  @override
  String get tradeHeadlineWaitingInvoiceSeller =>
      'Waiting for the buyer to share an invoice';

  @override
  String get tradeHeadlineWaitingPaymentBuyer =>
      'Waiting for the seller to lock the sats';

  @override
  String get tradeHeadlineWaitingPaymentSeller =>
      'Pay the invoice to lock the sats';

  @override
  String tradeHeadlineActiveBuyer(String amount) {
    return 'Send $amount to the seller';
  }

  @override
  String tradeHeadlineActiveSeller(String amount) {
    return 'Waiting for the buyer to send $amount';
  }

  @override
  String get tradeHeadlineFiatSentBuyer =>
      'Waiting for the seller to release your sats';

  @override
  String tradeHeadlineFiatSentSeller(String amount) {
    return 'Confirm you received $amount';
  }

  @override
  String get tradeHeadlineDisputed => 'Dispute in progress';

  @override
  String get tradeHeadlineCancelled => 'Order cancelled';

  @override
  String get tradeHeadlineLoading => 'Loading trade…';

  @override
  String get tradeTimerPendingConsequence =>
      'If it expires, the order is removed from the book. It won\'t affect your reputation.';

  @override
  String get tradeTimerExpiryBackToBook =>
      'If it expires, the order goes back to the book.';

  @override
  String get tradeTimerExpiryCancelled =>
      'If it expires, the order is cancelled.';

  @override
  String get tradeTimerEscrowCancels =>
      'Approximate time. If it runs out, Mostro cancels the trade.';

  @override
  String get tradeTimerEscrowDisputes =>
      'Approximate time. If it runs out, Mostro opens a dispute.';

  @override
  String get tradeTimerEscrowCancellingBuyer =>
      'Mostro is about to cancel the trade and return the sats to the seller.';

  @override
  String get tradeTimerEscrowCancellingSeller =>
      'Mostro is about to cancel the trade. Your sats stay in your wallet.';

  @override
  String get tradeTimerEscrowDisputing => 'A dispute is about to be opened.';

  @override
  String get tradeStepOrderTaken => 'Order taken';

  @override
  String get tradeStepWaitingTaker => 'Waiting for a taker';

  @override
  String get tradeStepInvoiceBuyer => 'The seller locks the sats';

  @override
  String get tradeStepInvoiceSeller => 'You lock the sats';

  @override
  String get tradeStepFiatBuyer => 'You send the payment';

  @override
  String get tradeStepFiatSeller => 'The buyer sends the payment';

  @override
  String get tradeStepReleaseBuyer => 'The seller releases your sats';

  @override
  String get tradeStepReleaseSeller => 'You confirm and release the sats';

  @override
  String get tradeStepPayoutBuyer => 'Mostro sends you your sats';

  @override
  String get tradeStepRate => 'Rate the trade';

  @override
  String tradeCreatedAtLabel(String date) {
    return 'created $date';
  }

  @override
  String stepIndicator(int current, int total) {
    return 'STEP $current OF $total';
  }

  @override
  String get addLightningInvoiceButton => 'Add Lightning invoice';

  @override
  String get viewDisputeButton => 'View dispute';

  @override
  String get yourTradeTimelineTitle => 'YOUR TRADE';

  @override
  String get messageSendFailed => 'Failed to send message. Please try again.';

  @override
  String get invalidTradeId => 'Invalid trade ID';

  @override
  String get selectForDetailsHint => 'Select ℹ or 👤\nfor details';

  @override
  String noMessagesYet(String handle) {
    return 'No messages yet.\nSay hello to $handle!';
  }

  @override
  String get exchangeInfoTooltip => 'Trade Info';

  @override
  String get userInfoTooltip => 'User Info';

  @override
  String chattingWith(String handle) {
    return 'You are chatting with $handle';
  }

  @override
  String get unknownPeerHandle => 'Unknown';

  @override
  String get messagesTab => 'Messages';

  @override
  String get disputesTab => 'Disputes';

  @override
  String get tradeInformationTitle => 'Trade Information';

  @override
  String get orderIdLabel => 'Order ID';

  @override
  String get fiatAmountLabel => 'Fiat Amount';

  @override
  String get satsAmountLabel => 'Sats Amount';

  @override
  String get peerReputationUnavailable =>
      'This user\'s reputation is not available';

  @override
  String get statusLabel => 'Status';

  @override
  String get paymentMethodLabel => 'Payment Method';

  @override
  String get createdLabel => 'Created';

  @override
  String get userInformationTitle => 'User Information';

  @override
  String get fileTypeVideo => 'Video';

  @override
  String get fileTypeImage => 'Image';

  @override
  String get fileTypeArchive => 'Archive';

  @override
  String get fileTypeFile => 'File';

  @override
  String buyingSatsAmount(String sats) {
    return 'Buying $sats sats';
  }

  @override
  String sellingSatsAmount(String sats) {
    return 'Selling $sats sats';
  }

  @override
  String get viewOrderLink => 'View order';

  @override
  String timeLeftLabel(String time) {
    return '$time left';
  }

  @override
  String get invoiceNoLongerExpected =>
      'This order is no longer waiting for an invoice. Updating its status…';

  @override
  String get invoiceAwaitingNode =>
      'Sent. The node hasn\'t answered yet — you\'ll be taken to the trade as soon as it does.';

  @override
  String get invoiceAwaitingNodeLong =>
      'Still no answer from the node. If the trade doesn\'t move on, send it again.';

  @override
  String get invoiceSubmitInFlight =>
      'An invoice for this order is already being sent. Wait for the reply.';

  @override
  String get waitingForTradeAmount =>
      'Waiting for trade amount — please try again shortly.';

  @override
  String get fetchingTradeAmount => 'Fetching trade amount…';

  @override
  String get enterInvoiceManually => 'Enter invoice manually';

  @override
  String get rangeAmountTakeAction => 'Take order';

  @override
  String orderAmountOutOfRange(int min, int max) {
    return 'Amount must be between $min and $max sats for this Mostro node';
  }

  @override
  String orderCurrencyNotAccepted(String currency) {
    return 'This Mostro node does not accept $currency. Pick another currency';
  }

  @override
  String orderAmountOutOfRangeFiat(int min, int max, String currency) {
    return 'Amount must be between $min and $max $currency for this Mostro node';
  }

  @override
  String get priceTypeMarket => 'Market';

  @override
  String get priceTypeFixed => 'Fixed';

  @override
  String get priceTypeInfoTooltip => 'Price type info';

  @override
  String get premiumSectionLabel => 'Premium';

  @override
  String get fixedPriceRangeNotAvailable =>
      'Fixed price isn\'t available for range orders. Turn off the range to use a fixed price.';

  @override
  String get priceTypesDialogTitle => 'Price Types';

  @override
  String get priceTypesDialogContent =>
      'Market Price: Your order follows the market rate, with the premium or discount you set.\n\nFixed Price: You set the exact sats amount; it does not follow the market.';

  @override
  String get newOrderTitle => 'New order';

  @override
  String get amountSectionSell => 'How much you sell';

  @override
  String get amountSectionBuy => 'How much you buy';

  @override
  String get amountModeSingle => 'Single';

  @override
  String get amountModeRange => 'Range';

  @override
  String get amountMinLabel => 'Minimum';

  @override
  String get amountMaxLabel => 'Maximum';

  @override
  String paymentMethodsChosenCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString selected',
      one: '1 selected',
      zero: 'none selected',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodAdd => 'Add';

  @override
  String get paymentMethodSearchHint => 'Search methods';

  @override
  String get customPaymentMethodLabel => 'Custom payment method';

  @override
  String get priceSectionTitle => 'Price';

  @override
  String premiumSellAbove(String premium) {
    return 'You sell $premium% above market price';
  }

  @override
  String premiumSellBelow(String premium) {
    return 'You sell $premium% below market';
  }

  @override
  String premiumBuyBelow(String premium) {
    return 'You pay $premium% less than market';
  }

  @override
  String premiumBuyAbove(String premium) {
    return 'You pay $premium% more';
  }

  @override
  String get premiumExactMarket => 'Exact market price';

  @override
  String get fixedPriceNote =>
      'At a fixed price the order does not follow the market: the sats amount stays exactly as you write it.';

  @override
  String get previewHintNoAmount =>
      'Write an amount and you\'ll see here how the order looks.';

  @override
  String previewSellMarket(String amount, String premium, String active) {
    return 'You sell BTC for $amount at market price $premium$active';
  }

  @override
  String previewSellMarketExact(String amount, String active) {
    return 'You sell BTC for $amount at market price$active';
  }

  @override
  String previewBuyMarket(String amount, String premium, String active) {
    return 'You buy BTC for $amount at market price $premium$active';
  }

  @override
  String previewBuyMarketExact(String amount, String active) {
    return 'You buy BTC for $amount at market price$active';
  }

  @override
  String previewSellFixed(String sats, String amount, String active) {
    return 'You sell $sats for $amount at a fixed price$active';
  }

  @override
  String previewBuyFixed(String sats, String amount, String active) {
    return 'You buy $sats for $amount at a fixed price$active';
  }

  @override
  String previewActiveSuffix(String hours) {
    return ' · active $hours';
  }

  @override
  String get publishOrder => 'Publish order';

  @override
  String removePaymentMethod(String method) {
    return 'Remove $method';
  }

  @override
  String get satsUnitLabel => 'sats';

  @override
  String satsAmount(String amount) {
    return '$amount sats';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String get paymentMethodsLabel => 'Payment methods';

  @override
  String get customPaymentMethodHint => 'Custom payment method…';

  @override
  String amountRangeError(String min, String max) {
    return 'Amount must be between $min and $max';
  }

  @override
  String get enterAmountTitle => 'Enter Amount';

  @override
  String minMaxRangeLabel(String min, String max, String currency) {
    return 'Min: $min – Max: $max $currency';
  }

  @override
  String get ratingFailed => 'Rating failed. Please try again.';

  @override
  String get submitUppercaseButton => 'SUBMIT';

  @override
  String selectStarTooltip(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Select $countString stars',
      one: 'Select 1 star',
    );
    return '$_temp0';
  }

  @override
  String get disputeDetailsTitle => 'Dispute Details';

  @override
  String get disputeIdLabel => 'Dispute ID';

  @override
  String disputeReasonLabel(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get solverLabel => 'Resolver';

  @override
  String get serberoLabel => 'Serbero';

  @override
  String get disputeSerberoAssigned =>
      'Serbero, an automated assistant, is helping with your dispute. It will ask you a few questions here and hand the case to a person if needed.';

  @override
  String get disputeSolverTookOver =>
      'A dispute resolver has taken over your dispute.';

  @override
  String get disputeScreenTitle => 'Dispute';

  @override
  String get filtersDialogTitle => 'Filters';

  @override
  String get resetButton => 'Reset';

  @override
  String get currencyLabel => 'Currency';

  @override
  String get ratingLabel => 'Rating';

  @override
  String get applyButton => 'Apply';

  @override
  String get successLabel => 'Success';

  @override
  String get copyButton => 'Copy';

  @override
  String get shareButton => 'Share';

  @override
  String sendSatsToAddress(String sats) {
    return 'Send $sats sats to:';
  }

  @override
  String get changeButton => 'Change';

  @override
  String get unableToOpenNotification => 'Unable to open notification details.';

  @override
  String get reasonBestPremium => 'Best premium';

  @override
  String get reasonMostReputable => 'Most reputable';

  @override
  String get marketPriceCaption => 'Market price';

  @override
  String get sortNewest => 'Newest';

  @override
  String ordersCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString orders',
      one: '1 order',
    );
    return '$_temp0';
  }

  @override
  String get sortBestPremium => 'Best premium';

  @override
  String get sortBestReputation => 'Best reputation';

  @override
  String get sortSheetTitle => 'Sort by';

  @override
  String get orderCardPremiumCaption => 'premium';

  @override
  String get orderCardPriceCaption => 'price';

  @override
  String orderFixedAmount(String sats) {
    return 'Fixed amount · for $sats';
  }

  @override
  String get reputationNew => 'New';

  @override
  String get bottomNavBook => 'Book';

  @override
  String get bottomNavTrades => 'Trades';

  @override
  String get fabDismissHint => 'Tap outside to close';

  @override
  String get addOrderFabLabel => 'Create order';

  @override
  String get ordersEmptyHint =>
      'New orders appear here as soon as they are published.';

  @override
  String get ordersEmptyFilteredHint => 'No orders match your filters.';

  @override
  String get clearFiltersButton => 'Clear filters';

  @override
  String get hideEarlierEvents => 'Hide earlier events';

  @override
  String viewEarlierEvents(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View $countString earlier events',
      one: 'View 1 earlier event',
    );
    return '$_temp0';
  }

  @override
  String get goToTrade => 'Go to trade';

  @override
  String get disputeWord => 'Dispute';

  @override
  String get tradeWord => 'Trade';

  @override
  String get notifSectionRecent => 'Recent';

  @override
  String notificationDeletedSnack(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString notifications deleted',
      one: 'Notification deleted',
    );
    return '$_temp0';
  }

  @override
  String get notificationDeletedUndo => 'Undo';

  @override
  String get payingStatus => 'Paying…';

  @override
  String get payWithWalletButton => 'Pay with Wallet';

  @override
  String get generatingInvoiceNwc => 'Generating invoice via NWC…';

  @override
  String get unableToGenerateInvoice =>
      'Unable to generate invoice automatically';

  @override
  String get avatarIconLabel => 'Avatar icon';

  @override
  String get disputeDescResolvedBuyerFavour =>
      'Dispute resolved in the buyer\'s favour';

  @override
  String get disputeDescResolvedYourFavour => 'Dispute resolved in your favour';

  @override
  String get disputeDescResolvedSellerFavour =>
      'Dispute resolved in the seller\'s favour';

  @override
  String get disputeDescCooperativeCancel => 'Order cancelled cooperatively';

  @override
  String get disputeDescResolved => 'Dispute resolved';

  @override
  String get disputeDescYouOpened => 'You opened this dispute';

  @override
  String get disputeDescCounterpartOpened =>
      'Your counterpart opened this dispute';

  @override
  String get notificationsBellNoUnread =>
      'Notifications, no unread notifications';

  @override
  String get notificationsBellBackupActive =>
      'Notifications, backup reminder active';

  @override
  String notificationsBellUnread(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notifications, $countString unread',
      one: 'Notifications, 1 unread',
    );
    return '$_temp0';
  }

  @override
  String drawerBadgeNewCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString new',
      one: '1 new',
    );
    return '$_temp0';
  }

  @override
  String get bondSlashedViewPolicy => 'View policy';

  @override
  String get bondSlashedViewTrade => 'View trade';

  @override
  String bondSlashedTradeNoticeDispute(String sats) {
    return 'Your $sats-sat deposit was forfeited in this dispute.';
  }

  @override
  String bondSlashedTradeNoticeTimeout(String sats) {
    return 'Your $sats-sat deposit was forfeited after a step timed out.';
  }

  @override
  String get bondSlashedTitle => 'Deposit forfeited';

  @override
  String bondSlashedMessageTimeout(String amount, String orderId) {
    return 'Your $amount-sat deposit for order $orderId was forfeited after a step timed out. Your order status is unchanged.';
  }

  @override
  String bondSlashedMessageDispute(String amount, String orderId) {
    return 'Your $amount-sat deposit for order $orderId was forfeited when the dispute was resolved. Your order status is unchanged.';
  }

  @override
  String get bondSlashedCauseTimeout => 'A step timed out';

  @override
  String get bondSlashedCauseDispute => 'Dispute resolution';

  @override
  String get bondSlashedDetailOrder => 'Order';

  @override
  String get bondSlashedDetailAmount => 'Deposit amount';

  @override
  String get bondSlashedDetailCause => 'Cause';

  @override
  String get bondSlashedDetailFiat => 'Fiat';

  @override
  String get bondSlashedDetailPaymentMethod => 'Payment method';

  @override
  String aboutDaysValue(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString days',
      one: '$countString day',
    );
    return '$_temp0';
  }

  @override
  String get aboutCashuEscrowSection => 'Cashu escrow';

  @override
  String get aboutCashuMintUrlLabel => 'Mint';

  @override
  String get aboutCashuLocktimeLabel => 'Escrow locktime';

  @override
  String get aboutCashuSettlementMarginLabel => 'Settlement margin';

  @override
  String get escrowModeLightning => 'Lightning';

  @override
  String get escrowModeCashu => 'Cashu';

  @override
  String get escrowModeUnknown => 'Not advertised';

  @override
  String get settingsEscrowOverrideTitle => 'Escrow backend (developer)';

  @override
  String get settingsEscrowOverrideSubtitle =>
      'Test Cashu against a node that does not advertise it yet. Debug builds only.';

  @override
  String get settingsForceCashuLabel => 'Force Cashu escrow';

  @override
  String get settingsCashuMintOverrideLabel => 'Mint URL override';

  @override
  String get settingsCashuMintOverrideApply => 'Apply';

  @override
  String get settingsCashuMintOverrideInvalid =>
      'That is not a valid mint URL. Use http or https with a host.';

  @override
  String settingsEscrowEffectiveMode(String mode) {
    return 'Effective backend: $mode';
  }

  @override
  String settingsEscrowEffectiveMint(String mint) {
    return 'Effective mint: $mint';
  }

  @override
  String get settingsEscrowCashuUnavailable =>
      'Cashu cannot run without a mint — set one below.';

  @override
  String get tradeStatusPayoutPending => 'Payout pending';

  @override
  String get tradeHeadlinePayoutPending => 'Waiting for your sats';

  @override
  String get tradeInstructionPayoutPending =>
      'The seller released your sats and Mostro sends them to you. If the payment fails, you can add a new Lightning invoice.';

  @override
  String get tradeScreenTitle => 'Your trade';

  @override
  String get tradeChipWaiting => 'WAITING';

  @override
  String get tradeChipActive => 'ACTIVE';

  @override
  String get tradeChipYourTurn => 'YOUR TURN';

  @override
  String get tradeChipDispute => 'DISPUTE';

  @override
  String get tradeChatLockedNote =>
      'No chat yet: until the trade is active, neither party knows who the other is.';

  @override
  String get tradeChatEncrypted => 'End-to-end encrypted';

  @override
  String get tradeChatClosed => 'Conversation closed · view messages';

  @override
  String get tradeChatWithBuyer => 'Chat with the buyer';

  @override
  String get tradeChatWithSeller => 'Chat with the seller';

  @override
  String get tradeChatWithCounterpart => 'Chat with your counterpart';

  @override
  String tradeChatNewMessages(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString new messages',
      one: '1 new message',
    );
    return '$_temp0';
  }

  @override
  String get tradeChatOpen => 'Open';

  @override
  String get tradeChatClosedAnnouncement =>
      'The conversation is closed. You can still read its messages';

  @override
  String get tradeBodyWaitingPaymentBuyer =>
      'The seller is locking the sats. Once they are locked, it\'s your turn to pay.';

  @override
  String tradeBodyActiveSeller(String method) {
    return 'Share your $method details in the chat above.';
  }

  @override
  String tradeBodyActiveBuyer(String method) {
    return 'Via $method, with the details they shared in the chat. Once you\'ve sent it, mark it below.';
  }

  @override
  String tradeBodyFiatSentSeller(String method) {
    return 'The buyer marked the payment as sent. Check your $method account before releasing.';
  }

  @override
  String tradeBodyActiveBuyerStablecoin(String method) {
    return 'Send it on $method, to the address they shared in the chat: on another network it can be lost. Then paste the transaction ID in the chat (it is your proof in a dispute) and mark it below.';
  }

  @override
  String tradeBodyActiveSellerStablecoin(String method) {
    return 'Share your $method address in the chat above.';
  }

  @override
  String tradeBodyFiatSentSellerStablecoin(String method) {
    return 'The buyer marked the payment as sent. Before releasing, check that it reached your $method address, with the transaction ID from the chat.';
  }

  @override
  String get tradeReleaseIrreversible => 'Releasing the sats cannot be undone.';

  @override
  String get tradeTimerYouHave => 'You have';

  @override
  String get tradeTimerTheyHave => 'They have';

  @override
  String get tradeTimerOrderHas => 'Time left';

  @override
  String get tradeRoleBuyer => 'Buyer';

  @override
  String get tradeRoleSeller => 'Seller';

  @override
  String get tradeFiatSentAction => 'I\'ve sent the payment';

  @override
  String get tradeCloseAction => 'Close';

  @override
  String get tradeSendRatingAction => 'Send rating';

  @override
  String get tradeCompletedTitle => 'Trade completed';

  @override
  String tradeRatedCounterpart(String alias, String score) {
    return 'You rated $alias with $score';
  }

  @override
  String get tradeIdLabel => 'ID';

  @override
  String tradeCreatedTodayLabel(String time) {
    return 'created today $time';
  }

  @override
  String get releaseSheetTitle => 'Release the sats?';

  @override
  String get releaseSheetBody =>
      'This cannot be undone. Only release once the money is in your account.';

  @override
  String get releaseSheetConfirm => 'Yes, release';

  @override
  String get releaseSheetBack => 'Back';

  @override
  String get orderSideChipSell => 'Selling BTC';

  @override
  String get orderSideChipBuy => 'Buying BTC';

  @override
  String orderDetailMarketPremium(String premium) {
    return 'Market price · $premium premium';
  }

  @override
  String myOrderWaitingNote(String ago) {
    return 'Published $ago. We\'ll let you know as soon as someone takes it: you can close this screen.';
  }

  @override
  String get orderStatusTakenWaitingInvoice => 'Taken · waiting for invoice';

  @override
  String get orderStatusTakenWaitingPayment => 'Taken · waiting for payment';

  @override
  String get orderDetailCreatedLabel => 'Created';

  @override
  String get orderDetailIdLabel => 'ID';

  @override
  String paymentMethodsMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get paymentMethodsSheetTitle => 'Payment methods';

  @override
  String get cancelOrderSheetTitle => 'Cancel the order?';

  @override
  String get cancelOrderSheetBody =>
      'It is removed from the order book and this cannot be undone.';

  @override
  String get goBackButtonLabel => 'Go back';

  @override
  String get takeOrderYouPay => 'You pay';

  @override
  String get takeOrderYouReceive => 'You receive';

  @override
  String get takeOrderYouSend => 'You send';

  @override
  String takeOrderSatsFrom(String sats) {
    return 'from $sats';
  }

  @override
  String takeOrderMarketFooter(String premium) {
    return 'Market price · $premium premium. The final figure is set when you take it.';
  }

  @override
  String takeOrderFixedFooterSeller(String sats) {
    return 'Fixed amount · the seller asks for $sats';
  }

  @override
  String takeOrderFixedFooterBuyer(String sats) {
    return 'Fixed amount · the buyer offers $sats';
  }

  @override
  String get counterpartySeller => 'Seller';

  @override
  String get counterpartyBuyer => 'Buyer';

  @override
  String get takeOrderPayWithLabel => 'You pay with';

  @override
  String get takeOrderPaidWithLabel => 'You get paid with';

  @override
  String get takeOrderPublishedLabel => 'Published';

  @override
  String get takeOrderNoteBuyer =>
      'When you take it, the seller locks the sats in Mostro. You only pay once they are locked.';

  @override
  String get takeOrderNoteSeller =>
      'When you take it, you lock the sats in Mostro. The buyer pays afterwards.';

  @override
  String get takeOrderButton => 'Take order';

  @override
  String get takeOrderTaking => 'Taking…';

  @override
  String get takeOrderUnavailable => 'No longer available';

  @override
  String get takeOrderFailed => 'Could not take the order. Please try again.';

  @override
  String get takeOrderClosed => 'Closed';

  @override
  String get easterEggWhitepaper =>
      '31 October 2008: nine pages, nobody\'s permission. Happy Halloween.';

  @override
  String get easterEggGenesis =>
      'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks';

  @override
  String get easterEggPizzaDay =>
      '22 May 2010: 10,000 BTC for two pizzas. Hope they were good.';

  @override
  String get settingsGroupApp => 'Application';

  @override
  String get settingsGroupPayments => 'Payments';

  @override
  String get settingsGroupNetwork => 'Network';

  @override
  String get settingsGroupHelp => 'Help';

  @override
  String get fiatCurrencySettingTitle => 'Fiat currency';

  @override
  String notificationsEnabledOfTotal(int count, int total) {
    return '$count of $total';
  }

  @override
  String get notificationsAllOff => 'Off';

  @override
  String get lightningAddressUnset => 'Not set';

  @override
  String get nwcWalletNotConnected => 'Not connected';

  @override
  String relaysConnectedOfTotal(int connected, int total) {
    return '$connected of $total connected';
  }

  @override
  String get relaysSummaryHealthy => 'You receive orders and messages normally';

  @override
  String get relaysSummaryAtRisk => 'You may stop seeing new orders';

  @override
  String get relayStatusConnected => 'Connected';

  @override
  String get relayStatusOffline => 'No connection';

  @override
  String get addRelayButtonLabel => 'Add relay';

  @override
  String get relaysFootnote =>
      'Relays carry your orders and messages. With fewer than two connected you may stop seeing new orders.';

  @override
  String get lastRelayBlockedMessage =>
      'Keep at least one relay active: without relays you cannot see or publish orders.';

  @override
  String get nwcExplainerTitle => 'Connect your wallet';

  @override
  String get nwcExplainerSubtitle => 'With Nostr Wallet Connect';

  @override
  String get nwcExplainerBody =>
      'Mostro will collect and pay your trade invoices from this wallet, so you never have to copy an invoice by hand.';

  @override
  String get nwcUriFieldLabel => 'Connection URI';

  @override
  String get nwcUriPlaceholder => 'nostr+walletconnect://…';

  @override
  String get nwcStorageFootnote =>
      'The URI is stored only on this device and is never published to Nostr.';

  @override
  String get walletConnectedMessage => 'Wallet connected';

  @override
  String get nwcConnectedStatus => 'Connected';

  @override
  String nwcBalanceSats(String sats) {
    return '$sats sats';
  }

  @override
  String get notificationsSystemDenied =>
      'Notifications are turned off in your system settings.';

  @override
  String get openSystemSettingsAction => 'Open settings';

  @override
  String get notificationsPermissionNotAsked =>
      'This browser has not been allowed to show notifications yet.';

  @override
  String get allowNotificationsAction => 'Allow notifications';

  @override
  String get notificationsPrivacyFootnote =>
      'Notifications carry no amounts and no counterparties. A push travels through Google\'s or Apple\'s servers and says only that there is something to see.';

  @override
  String get pushMasterToggleTitle => 'Push notifications';

  @override
  String get pushMasterToggleSubtitle =>
      'Wakes the app when a trade or chat message arrives. The notification itself carries nothing.';

  @override
  String get pushWebStopsWithTab =>
      'Stops 30 to 48 h after this tab last ran Mostro';

  @override
  String get pushStatusOff =>
      'Off — nothing is registered with the push server';

  @override
  String pushStatusCleanupPending(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Off — removal of $countString push registrations is pending',
      one: 'Off — removal of 1 push registration is pending',
    );
    return '$_temp0';
  }

  @override
  String get pushStatusNoToken => 'Waiting for this device\'s push token';

  @override
  String get pushStatusIdle => 'On — no open trades to register';

  @override
  String pushStatusRegistered(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Registered for $countString trades',
      one: 'Registered for 1 trade',
    );
    return '$_temp0';
  }

  @override
  String pushStatusLastRegistered(String ago) {
    return 'last registered $ago';
  }

  @override
  String get pushStatusUnreachable => 'Push server unreachable — retrying';

  @override
  String get pushStatusNodeRefused =>
      'This Mostro node is not accepted by the push server';

  @override
  String get pushStatusRateLimited =>
      'Push request limit reached — retrying shortly';

  @override
  String get pushUnsupportedPlatform =>
      'Push notifications are not available on this platform';

  @override
  String get pushToggleSaveFailed => 'Could not change push notifications';

  @override
  String get pushNewMessageBody => 'You have a new message';

  @override
  String get notificationPrefSaveFailed => 'Could not save that preference';

  @override
  String get logsScreenTitle => 'Logs';

  @override
  String get logFilterAll => 'All';

  @override
  String get logFilterRelays => 'Relays';

  @override
  String get logFilterOrders => 'Orders';

  @override
  String get logFilterPayments => 'Payments';

  @override
  String get verboseLoggingTitle => 'Verbose logging';

  @override
  String get verboseLoggingSubtitle => 'More detail, more battery';

  @override
  String get newLogsChipLabel => 'New logs';

  @override
  String get noLogsForFilter => 'No entries for this filter';

  @override
  String get aboutAppSection => 'Application';

  @override
  String get aboutSourceCodeLabel => 'Source code';

  @override
  String get aboutUserGuideLabel => 'User guide';

  @override
  String get aboutTechnicalDocsLabel => 'Technical documentation';

  @override
  String get aboutLanguageSpanish => 'Spanish';

  @override
  String get aboutLanguageEnglish => 'English';

  @override
  String get aboutConnectedNodeTitle => 'Connected node';

  @override
  String get aboutMinOrderCell => 'Min order';

  @override
  String get aboutMaxOrderCell => 'Max order';

  @override
  String get aboutFeeCell => 'Fee';

  @override
  String aboutFeeValue(String value) {
    return '$value%';
  }

  @override
  String get aboutNodeDepositNone => 'No';

  @override
  String aboutNodeDepositFloor(String amount) {
    return 'min. $amount sats';
  }

  @override
  String get aboutDepositCell => 'Deposit';

  @override
  String get aboutCurrenciesCell => 'Currencies';

  @override
  String get aboutOrderExpiryCell => 'Expiration';

  @override
  String get aboutNodeTechnicalDataRow => 'Node technical data';

  @override
  String aboutFieldCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString fields',
      one: '$countString field',
    );
    return '$_temp0';
  }

  @override
  String get aboutTechnicalDataTitle => 'Technical data';

  @override
  String get aboutPublicKeyLabel => 'Public key';

  @override
  String get aboutOrderExpiryLabel => 'Order expiration';

  @override
  String get aboutWaitingTimeoutLabel => 'Waiting timeout';

  @override
  String aboutHoursShort(int count) {
    return '$count h';
  }

  @override
  String aboutSecondsShort(int count) {
    return '$count s';
  }

  @override
  String get aboutAliasLabel => 'Alias';

  @override
  String get aboutNodePublicKeyLabel => 'Node public key';

  @override
  String get aboutNodeUriLabel => 'Node URI';

  @override
  String get aboutCommitLabel => 'Commit';

  @override
  String get aboutChainNetworkLabel => 'Chain and network';

  @override
  String get aboutTechnicalFootnote =>
      'These details identify the node you trade with. Useful for support, or to verify it before sending funds.';

  @override
  String get aboutCopyAllData => 'Copy all data';

  @override
  String get tradesGroupNeedsAction => 'Needs your action';

  @override
  String get tradesGroupInProgress => 'In progress';

  @override
  String get tradesGroupClosed => 'Closed';

  @override
  String get tradesDirectionSell => 'You sell';

  @override
  String get tradesDirectionBondClaim => 'Deposit claim';

  @override
  String get tradesDirectionBuy => 'You buy';

  @override
  String tradesCounterpartyTo(String handle) {
    return 'to $handle';
  }

  @override
  String tradesCounterpartyFrom(String handle) {
    return 'from $handle';
  }

  @override
  String get tradeListChipYourTurn => 'Your turn';

  @override
  String get tradeListChipPublished => 'Published';

  @override
  String get tradeListChipInProgress => 'In progress';

  @override
  String get tradeListChipWaitingInvoice => 'Awaiting invoice';

  @override
  String get tradeListChipWaitingPayment => 'Awaiting payment';

  @override
  String get tradeListChipWaitingSats => 'Awaiting sats';

  @override
  String get tradeListChipDispute => 'In dispute';

  @override
  String get tradeListChipCompleted => 'Completed';

  @override
  String get tradeListChipCancelled => 'Cancelled';

  @override
  String get tradeListChipExpired => 'Expired';

  @override
  String get tradeVerbAddInvoice => 'Add invoice';

  @override
  String get tradeVerbPayBond => 'Pay deposit';

  @override
  String get tradeHeadlineWaitingBond => 'Lock your deposit to continue';

  @override
  String get tradeInstructionWaitingBond =>
      'The node holds this take until the refundable deposit is paid. The order stays open to others meanwhile.';

  @override
  String get takeOrderBondNotice =>
      'This node asks takers to lock a refundable deposit first; it comes back when the trade ends honestly.';

  @override
  String takeOrderBondNoticeEstimate(String sats) {
    return 'This node asks takers to lock a refundable deposit of ≈ $sats sats first; it comes back when the trade ends honestly.';
  }

  @override
  String get tradeVerbPayInvoice => 'Pay invoice';

  @override
  String get tradeVerbSendPayment => 'Send payment';

  @override
  String get tradeVerbReleaseSats => 'Release sats';

  @override
  String get tradeVerbRate => 'Rate';

  @override
  String get tradeListFilterAll => 'All';

  @override
  String get tradeListFilterActive => 'Active';

  @override
  String get tradeListFilterCompleted => 'Completed';

  @override
  String get tradeListFilterCancelled => 'Cancelled';

  @override
  String get tradeListFilterTitle => 'Show trades';

  @override
  String get relativeTimeNow => 'now';

  @override
  String relativeTimeMinutes(int count) {
    return '$count min ago';
  }

  @override
  String relativeTimeHours(int count) {
    return '$count h ago';
  }

  @override
  String get relativeTimeYesterday => 'yesterday';

  @override
  String satsFigureEstimate(String sats) {
    return '≈ $sats sats';
  }

  @override
  String satsFigureExact(String sats) {
    return '$sats sats';
  }

  @override
  String get chatGroupActive => 'Active trades';

  @override
  String chatContextSellActive(String amount, String currency) {
    return 'You sell $amount $currency';
  }

  @override
  String chatContextBuyActive(String amount, String currency) {
    return 'You buy $amount $currency';
  }

  @override
  String chatContextSellClosed(String amount, String currency) {
    return 'You sold $amount $currency';
  }

  @override
  String chatContextBuyClosed(String amount, String currency) {
    return 'You bought $amount $currency';
  }

  @override
  String get chatTurnAddInvoice => 'your turn to add the invoice';

  @override
  String get chatTurnPayBond => 'your turn to pay the deposit';

  @override
  String get chatTurnPayInvoice => 'your turn to pay the invoice';

  @override
  String get chatTurnSendPayment => 'your turn to pay';

  @override
  String get chatTurnRelease => 'your turn to release';

  @override
  String get chatTurnRate => 'your turn to rate';

  @override
  String get chatYouLabel => 'You:';

  @override
  String get chatListFootnote =>
      'Each conversation belongs to one trade and is end-to-end encrypted. Once the trade ends, it stays here to read.';

  @override
  String get chatListEmptyTitle => 'No conversations yet';

  @override
  String get chatListEmptyBody => 'A chat opens when a trade becomes active.';

  @override
  String get chatClosedNotice =>
      'This trade has ended. The conversation stays here to read.';

  @override
  String disputeOpenedByYou(String time) {
    return 'You opened it $time';
  }

  @override
  String disputeOpenedByPeer(String time) {
    return 'The counterpart opened it $time';
  }

  @override
  String get invoiceReceiveTitle => 'Receive your sats';

  @override
  String get invoiceLockTitle => 'Lock your sats';

  @override
  String get bondTitle => 'Anti-abuse deposit';

  @override
  String get bondRefundableLabel => 'Refundable deposit';

  @override
  String get bondComesBack => 'comes back to you when the trade completes';

  @override
  String bondFiatComesBack(String fiat) {
    return '≈ $fiat · comes back to you when the trade completes';
  }

  @override
  String bondPaySemantics(String sats) {
    return 'Refundable deposit of $sats sats';
  }

  @override
  String bondReleasesIn(String time) {
    return 'The order is released if you don\'t pay in $time';
  }

  @override
  String bondRowHeld(String bold) {
    return 'The sats stay $bold; they are not spent';
  }

  @override
  String get bondRowHeldBold => 'held in your wallet';

  @override
  String bondRowReleased(String bold) {
    return 'If the trade ends well, $bold';
  }

  @override
  String get bondRowReleasedBold => 'it is released on its own';

  @override
  String bondRowLost(String bold) {
    return 'You only lose it if there is a dispute and $bold';
  }

  @override
  String bondRowLostTimeout(String bold) {
    return 'You lose it if you let a step time out, or if there is a dispute and $bold';
  }

  @override
  String get bondRowLostBold => 'you lose it';

  @override
  String get bondWhyTitle => 'Why Mostro asks for a deposit';

  @override
  String get bondWhyCustody =>
      'Mostro does not hold funds, so it cannot penalise whoever abandons a trade; the deposit does that job, and protects every user against scammers.';

  @override
  String get bondWhyHold =>
      'Your wallet holds the sats without sending them; when the trade completes, they are released on their own.';

  @override
  String get bondWhyDispute =>
      'If you open a dispute and win, you get it back too. It is only charged when you lose a dispute.';

  @override
  String get bondWhyDisputeTimeout =>
      'If you open a dispute and win, you get it back too. It is only charged when you lose a dispute or let a waiting step time out.';

  @override
  String get bondReadDocs => 'Read the documentation';

  @override
  String get bondContextOrder => 'Order';

  @override
  String bondContextBuy(String fiat) {
    return 'You buy $fiat';
  }

  @override
  String bondContextSell(String fiat) {
    return 'You sell $fiat';
  }

  @override
  String get bondContextEquals => 'Deposit equals';

  @override
  String bondContextPercent(String pct) {
    return '$pct% of the amount';
  }

  @override
  String get bondDontPublish => 'Don\'t publish the order';

  @override
  String get bondAbandoned =>
      'Order dropped. Nothing was published and nothing was charged.';

  @override
  String bondPublishesIn(String time) {
    return 'Not published yet: the order is dropped if you don\'t pay in $time';
  }

  @override
  String get bondInvoiceMissingMaker =>
      'This device has no copy of the deposit invoice and the node does not resend it for an order you created. Drop the order and create it again.';

  @override
  String get bondExpiredBodyMaker =>
      'It was not paid in time: the order was never published and no sats left your wallet.';

  @override
  String get bondExpiredNoticeMaker =>
      'The deposit invoice expired; the order was not published';

  @override
  String get orderStatusWaitingBond =>
      'Waiting for your deposit — not published yet';

  @override
  String get bondAlreadyLocked =>
      'Your deposit was already paid, so the order is published. Cancel it from the order screen.';

  @override
  String get bondCancelRefusedTitle => 'The node didn\'t cancel the deposit';

  @override
  String get bondCancelRefusedBody =>
      'This Mostro node may not support cancelling an unpaid deposit yet, or your deposit was just paid. If you haven\'t paid it, you can remove the order from this device. If the invoice is paid later, the order will still be published.';

  @override
  String get bondRemoveFromDevice => 'Remove from this device';

  @override
  String get bondLeaveMakerTitle => 'Don\'t publish this order?';

  @override
  String get bondLeaveMakerBody =>
      'The order won\'t be published and its deposit invoice is cancelled.';

  @override
  String get bondLeaveTakerTitle => 'Don\'t take this order?';

  @override
  String get bondLeaveTakerBody =>
      'The order stays in the book for others and the deposit invoice is cancelled.';

  @override
  String get bondKeepWaiting => 'Keep waiting';

  @override
  String createOrderBondNoticeEstimate(String sats) {
    return 'This node asks you to lock a refundable deposit of ≈ $sats sats before the order is published; it comes back when the trade ends honestly.';
  }

  @override
  String get createOrderBondNotice =>
      'This node asks you to lock a refundable deposit before the order is published; it comes back when the trade ends honestly.';

  @override
  String get bondClaimTitle => 'Claim your share';

  @override
  String get bondClaimShareLabel => 'Your share';

  @override
  String bondClaimShareSemantics(String sats) {
    return 'Share of $sats sats to claim';
  }

  @override
  String bondClaimContext(String context) {
    return 'From the trade of $context';
  }

  @override
  String bondClaimDeadline(String date) {
    return 'Claim before $date';
  }

  @override
  String get bondClaimExplainer =>
      'Your counterpart\'s deposit was forfeited in your favour. Add an invoice for exactly this amount and the node pays it to you.';

  @override
  String get bondClaimFieldLabel => 'Lightning invoice';

  @override
  String get bondClaimFieldHint => 'lnbc… for exactly the share';

  @override
  String get bondClaimSubmit => 'Send invoice';

  @override
  String get bondClaimSent => 'Invoice sent to the node';

  @override
  String get bondClaimSubmittedTitle => 'Invoice sent';

  @override
  String get bondClaimSubmittedBody => 'Waiting for the node to confirm it.';

  @override
  String get bondClaimAcknowledgedTitle => 'Payout in progress';

  @override
  String get bondClaimAcknowledgedBody =>
      'The node accepted your invoice and is paying it. If it cannot be routed, you will be asked for a new one.';

  @override
  String get bondClaimCompletedTitle => 'Paid';

  @override
  String bondClaimCompletedBody(String sats) {
    return '$sats sats reached your wallet.';
  }

  @override
  String get bondClaimExpiredTitle => 'The claim window ended';

  @override
  String bondClaimExpiredBody(String date) {
    return 'It closed on $date. The share can no longer be claimed.';
  }

  @override
  String get bondClaimMissing => 'No claim found for this order.';

  @override
  String get bondClaimErrorAmount =>
      'The invoice must be for exactly the share shown.';

  @override
  String get bondClaimErrorExpired =>
      'The claim window ended; the share can no longer be claimed.';

  @override
  String get bondClaimErrorRejected =>
      'The node did not accept the invoice. Try another one.';

  @override
  String get bondClaimErrorNotClaimable =>
      'This claim is not open for an invoice right now.';

  @override
  String get bondClaimErrorNoKey =>
      'This device has no key for that trade, so it cannot claim the share.';

  @override
  String get tradeVerbClaimPayout => 'Claim payout';

  @override
  String get chatTurnClaimPayout => 'your turn to claim the payout';

  @override
  String get tradeBadgePayoutPending => 'Payout pending';

  @override
  String get tradeBadgePayoutInProgress => 'Payout in progress';

  @override
  String get tradeBadgePayoutPaid => 'Payout paid';

  @override
  String bondBannerPendingTitle(String sats) {
    return '$sats sats are ready to come back to you';
  }

  @override
  String bondBannerPendingBody(String sats) {
    return 'Your counterpart\'s deposit was forfeited in your favour. Add any Lightning invoice for $sats sats to claim it.';
  }

  @override
  String get bondBannerAddInvoice => 'Add payout invoice';

  @override
  String get bondBannerView => 'View claim';

  @override
  String get bondBannerInProgressTitle => 'Payout in progress';

  @override
  String bondBannerInProgressBody(String sats) {
    return 'The node is paying your $sats-sat share.';
  }

  @override
  String get bondBannerPaidTitle => 'Payout received';

  @override
  String bondBannerPaidBody(String sats, String date) {
    return '$sats sats were paid to you on $date.';
  }

  @override
  String bondBannerExpired(String date) {
    return 'The claim on your counterpart\'s deposit closed on $date.';
  }

  @override
  String get bondClaimNewTitle => 'Deposit payout to claim';

  @override
  String bondClaimNewMessage(String sats) {
    return 'You can claim $sats sats from a forfeited deposit. Add a Lightning invoice to receive them.';
  }

  @override
  String get bondClaimPaidTitle => 'Deposit payout received';

  @override
  String bondClaimPaidMessage(String sats) {
    return 'Deposit payout of $sats sats received.';
  }

  @override
  String get bondDontTake => 'Don\'t take the order';

  @override
  String get bondLockedNowEscrow =>
      'Deposit locked. Now lock the trade amount.';

  @override
  String get bondLostRace =>
      'Another user took this order before your deposit was paid';

  @override
  String get bondMakerCanceled => 'The maker cancelled this order';

  @override
  String get bondExpiredNotice =>
      'The deposit invoice expired; the order went back to the book';

  @override
  String get bondExpiredTitle => 'The deposit invoice expired';

  @override
  String get bondExpiredBody =>
      'It was not paid in time: the order went back to the book and no sats left your wallet.';

  @override
  String get bondInvoiceMissing =>
      'This device has no copy of the deposit invoice. Ask the node for it again to keep taking the order.';

  @override
  String get bondRequestAgain => 'Request the invoice again';

  @override
  String get bondRequestFailed => 'The node did not resend the deposit invoice';

  @override
  String get invoiceYouReceiveLabel => 'You will receive';

  @override
  String get invoiceToPayLabel => 'To pay';

  @override
  String invoiceReceiveSemantics(String sats) {
    return '$sats satoshis to receive';
  }

  @override
  String invoicePaySemantics(String sats) {
    return '$sats satoshis to pay';
  }

  @override
  String invoiceFeeIncluded(String sats) {
    return 'Includes $sats sats of Mostro fee';
  }

  @override
  String invoiceTimeToSend(String time) {
    return 'You have $time to send it';
  }

  @override
  String invoiceExpiresIn(String time) {
    return 'The invoice expires in $time';
  }

  @override
  String get invoiceFieldHint => 'lnbc… or user@domain';

  @override
  String get invoiceFieldPromptLabel => 'Paste your invoice here';

  @override
  String get invoiceFieldFilledLabel => 'Lightning invoice';

  @override
  String get invoiceFieldAddressLabel => 'Lightning address';

  @override
  String get invoiceScanButton => 'Scan';

  @override
  String get invoiceReplaceButton => 'Replace';

  @override
  String get invoiceFieldSemantics => 'Lightning invoice or address, required';

  @override
  String invoiceFilledSemantics(String sats) {
    return 'Lightning invoice for $sats sats';
  }

  @override
  String get invoiceValidAddress =>
      'Valid address · the invoice will be requested on sending';

  @override
  String invoiceValidInvoice(String sats) {
    return 'Valid invoice · $sats sats';
  }

  @override
  String invoiceErrorWrongAmount(String actual, String expected) {
    return 'The invoice is for $actual sats; it must be for $expected sats.';
  }

  @override
  String get invoiceErrorExpired => 'The invoice has already expired';

  @override
  String invoiceErrorExpiresTooSoon(String minutes) {
    return 'The invoice expires in less than $minutes minutes; the node needs more time to pay it.';
  }

  @override
  String get invoiceErrorMalformed => 'This invoice is incomplete or mistyped';

  @override
  String get invoiceErrorUnrecognized =>
      'Not an invoice (lnbc…) or a Lightning address (user@domain)';

  @override
  String get invoiceSellerLabel => 'Seller';

  @override
  String get invoiceBuyerLabel => 'Buyer';

  @override
  String get invoiceYouPayLabel => 'You pay';

  @override
  String get invoiceYouGetLabel => 'You receive';

  @override
  String get invoiceSendButton => 'Send invoice';

  @override
  String get invoiceCancelTrade => 'Cancel trade';

  @override
  String get invoiceOpenWallet => 'Open in my wallet';

  @override
  String get invoiceHoldNote =>
      'The sats are held: they don\'t leave your wallet until you confirm the buyer\'s payment.';

  @override
  String invoiceQrSemantics(String invoice) {
    return 'Lightning invoice QR code: $invoice';
  }

  @override
  String get invoiceBackToBook => 'Back to the order book';

  @override
  String get invoiceStepElapsed =>
      'Time is up. Mostro will close this step shortly unless it is completed.';

  @override
  String get stepElapsedBackToBook =>
      'Time is up. If it is not completed, Mostro will return the order to the book shortly.';

  @override
  String get stepElapsedCancelled =>
      'Time is up. If it is not completed, Mostro will cancel the order shortly.';

  @override
  String invoiceErrorWrongNetwork(String invoice, String node) {
    return 'The invoice is for $invoice; the node uses $node.';
  }

  @override
  String invoiceCountdownHours(String hours, String minutes) {
    return '$hours h $minutes';
  }

  @override
  String get countdownExpiresInLabel => 'Expires in';

  @override
  String get bondPayWithinLabel => 'Pay within';

  @override
  String get tradeCardWaitingBuyerInvoiceTitle =>
      'Waiting for the buyer\'s invoice';

  @override
  String get tradeCardWaitingBuyerInvoiceMessage =>
      'The trade continues once the buyer adds a Lightning invoice.';

  @override
  String get tradeCardWaitingPaymentTitle =>
      'Waiting for the seller\'s payment';

  @override
  String get tradeCardWaitingPaymentMessage =>
      'The trade continues once the seller locks the sats.';

  @override
  String get tradeCardWaitingTakerBondTitle => 'Deposit payment pending';

  @override
  String get tradeCardWaitingTakerBondMessage =>
      'The taker\'s deposit must be paid before the trade starts.';

  @override
  String get tradeCardActiveTitle => 'Trade active';

  @override
  String get tradeCardActiveMessage =>
      'The sats are locked. The buyer can now send the payment.';

  @override
  String get tradeCardFiatSentTitle => 'Payment marked as sent';

  @override
  String get tradeCardFiatSentMessage =>
      'The buyer marked the payment as sent.';

  @override
  String get tradeCardSettledHoldInvoiceTitle => 'Sats released';

  @override
  String get tradeCardSettledHoldInvoiceMessage =>
      'The seller released the sats. The buyer\'s payout is on its way.';

  @override
  String get tradeCardSuccessTitle => 'Trade completed';

  @override
  String get tradeCardSuccessMessage => 'The trade finished successfully.';

  @override
  String get tradeCardCanceledTitle => 'Trade cancelled';

  @override
  String get tradeCardCanceledMessage => 'The trade was cancelled.';

  @override
  String get tradeCardExpiredTitle => 'Order expired';

  @override
  String get tradeCardExpiredMessage =>
      'The order expired before the trade could continue.';

  @override
  String get tradeCardCooperativelyCanceledTitle =>
      'Trade cancelled by agreement';

  @override
  String get tradeCardCooperativelyCanceledMessage =>
      'Both parties agreed to cancel the trade.';

  @override
  String get tradeCardDisputeTitle => 'Dispute opened';

  @override
  String get tradeCardDisputeMessage => 'A dispute was opened on this trade.';

  @override
  String get tradeCardCanceledByAdminTitle => 'Cancelled by the resolver';

  @override
  String get tradeCardCanceledByAdminMessage =>
      'The dispute resolver cancelled the trade.';

  @override
  String get tradeCardSettledByAdminTitle => 'Settled by the resolver';

  @override
  String get tradeCardSettledByAdminMessage =>
      'The dispute resolver released the sats to the buyer.';

  @override
  String get tradeCardCompletedByAdminTitle => 'Completed by the resolver';

  @override
  String get tradeCardCompletedByAdminMessage =>
      'The dispute resolver completed the trade.';

  @override
  String get tradeCardUpdatedTitle => 'Trade updated';

  @override
  String get tradeCardUpdatedMessage => 'The status of this trade changed.';

  @override
  String get tradeCardCanceledByMakerMessage =>
      'The maker cancelled the order.';

  @override
  String get tradeCardCanceledBondLostRaceMessage =>
      'Another user took this order before the deposit was paid.';

  @override
  String get tradeCardCanceledBondExpiredMessage =>
      'The deposit invoice expired unpaid.';

  @override
  String get chatCardTitle => 'New messages';

  @override
  String get chatCardSolverTitle => 'Messages from the resolver';

  @override
  String chatCardMessage(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString new messages from your counterpart',
      one: '1 new message from your counterpart',
    );
    return '$_temp0';
  }

  @override
  String chatCardSolverMessage(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString new messages from the dispute resolver',
      one: '1 new message from the dispute resolver',
    );
    return '$_temp0';
  }

  @override
  String get invalidTradeIndexError =>
      'Your account is out of sync with this Mostro node, so it refused the order. Try again in a moment';

  @override
  String get invalidFiatCurrencyError =>
      'This Mostro node does not accept that currency, so it refused the order. Pick another currency';

  @override
  String get recoveringTradesMessage =>
      'Account imported. Recovering your trades from Mostro…';

  @override
  String recoveredTradesMessage(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Account imported. $countString trades recovered',
      one: 'Account imported. 1 trade recovered',
      zero: 'Account imported. You had no trades in progress',
    );
    return '$_temp0';
  }

  @override
  String get recoverTradesFailedMessage =>
      'Account imported, but Mostro did not answer, so your trades in progress were not recovered';

  @override
  String get paymentMethodsChosenLabel => 'Selected';

  @override
  String paymentMethodsSelectedCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString methods selected',
      one: '1 method selected',
      zero: 'Select at least one method',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodsConfirm => 'Confirm methods';

  @override
  String get paymentMethodAddCustom => 'Add custom payment method';

  @override
  String get paymentMethodsDiscardTitle => 'Discard the changes?';

  @override
  String get paymentMethodsDiscardConfirm => 'Discard';

  @override
  String get paymentMethodsKeepEditing => 'Keep editing';

  @override
  String get fundsAtRiskTitle => 'This user still has sats in play';

  @override
  String get fundsAtRiskBody =>
      'If you continue, this user\'s keys are replaced and nothing listed here can be finished or recovered from this device. This is not recommended: you can lose these sats.';

  @override
  String get fundsAtRiskSellerEscrow => 'Sats locked in escrow for a sale';

  @override
  String get fundsAtRiskBondLocked => 'Deposit locked';

  @override
  String get fundsAtRiskPayoutClaim => 'Deposit payout not collected yet';

  @override
  String get fundsAtRiskTradeInProgress => 'Trade in progress';

  @override
  String get fundsAtRiskBondInvoicePending => 'Deposit invoice still payable';

  @override
  String get fundsAtRiskCashuBalance => 'Ecash in the Cashu wallet';

  @override
  String get fundsAtRiskCashuHint => 'Only this user\'s words bring it back';

  @override
  String get fundsAtRiskKeep => 'Keep this user';

  @override
  String get fundsAtRiskContinue => 'Continue anyway';

  @override
  String get restoreSheetTitle => 'Restoring your account';

  @override
  String get restoreSheetWaiting => 'This may take a few seconds';

  @override
  String restoreSheetLoading(int done, int total) {
    return '$done of $total orders recovered';
  }

  @override
  String get restoreStageConnecting => 'Connecting to the Mostro node';

  @override
  String get restoreStageConnected => 'Connected to the Mostro node';

  @override
  String get restoreStageRequesting => 'Requesting your orders';

  @override
  String restoreStageFound(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString orders found',
      one: '1 order found',
    );
    return '$_temp0';
  }

  @override
  String get restoreStageLoading => 'Loading details';

  @override
  String get restoreStageNoResponse => 'No response';

  @override
  String restoreLoadingCountSemantics(int done, int total) {
    return '$done of $total orders';
  }

  @override
  String get restoreFailedTitle => 'We couldn\'t restore your orders';

  @override
  String get restoreFailedSubtitle => 'Your account was imported';

  @override
  String restoreFailedBody(String place) {
    return 'Check your connection and try again. You can retry any time from $place.';
  }

  @override
  String get restoreContinueWithout => 'Continue without restoring';

  @override
  String get restoreDoneTitle => 'Account restored';

  @override
  String get restoreDoneSubtitle => 'We recovered everything the node had';

  @override
  String get restoreDoneEmptySubtitle =>
      'This account had no orders on the node';

  @override
  String get restoreSummaryOrders => 'Orders';

  @override
  String get restoreSummaryInProgress => 'In progress';

  @override
  String restoreActionNotice(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have $countString active orders waiting for you',
      one: 'You have 1 active order waiting for you',
    );
    return '$_temp0';
  }

  @override
  String restorePartialNotice(int missing, int total) {
    return '$missing of $total orders couldn\'t be loaded';
  }

  @override
  String get attachSheetTitle => 'Send a file';

  @override
  String get attachSheetBody =>
      'It is encrypted on your device. Only your counterpart can open it.';

  @override
  String get attachSheetBodySolver =>
      'It is encrypted on your device. Only the resolver can open it.';

  @override
  String get attachSourcePhoto => 'Photo';

  @override
  String get attachSourceCamera => 'Camera';

  @override
  String get attachSourcePdf => 'PDF document';

  @override
  String get attachConfirmTitle => 'Send this file?';

  @override
  String attachConfirmBody(String fileName, String size) {
    return '$fileName ($size)';
  }

  @override
  String get attachmentTooLarge => 'Files can be up to 25 MB.';

  @override
  String get attachmentUnsupported =>
      'Only JPEG, PNG and PDF files can be sent.';

  @override
  String get attachmentInvalidImage => 'This image could not be read.';

  @override
  String get attachmentReadFailed => 'The file could not be read.';

  @override
  String get attachmentPeerUnknown =>
      'You can send files once someone takes the order.';

  @override
  String get attachmentUploadFailed =>
      'The upload failed. Check your connection and try again.';

  @override
  String get attachmentSendFailed => 'The file could not be sent.';

  @override
  String get attachmentDownloadFailed => 'The file could not be downloaded.';

  @override
  String get attachmentDecryptFailed => 'This file could not be decrypted.';

  @override
  String get attachmentUploading => 'Sending…';

  @override
  String get attachmentDiscard => 'Discard';

  @override
  String get attachmentSave => 'Save';

  @override
  String get attachmentSaved => 'File saved';

  @override
  String get attachmentSaveFailed => 'The file could not be saved.';

  @override
  String attachmentImageSemantics(String fileName) {
    return 'Image: $fileName';
  }

  @override
  String get attachmentOpenImage => 'Open image';

  @override
  String get attachmentOpenWith => 'Open with…';

  @override
  String get attachmentShare => 'Share';

  @override
  String get attachmentMoreActions => 'More options';

  @override
  String get attachmentNoAppToOpen =>
      'No app on this device can open this file.';

  @override
  String get attachmentOpenFailed => 'The file could not be opened.';

  @override
  String get attachmentShareFailed => 'The file could not be shared.';

  @override
  String get attachmentSaveOnly => 'This type of file can only be saved.';

  @override
  String get cashuWalletTitle => 'Cashu wallet';

  @override
  String get cashuBalanceLabel => 'Balance';

  @override
  String cashuMintLabel(String mint) {
    return 'Mint: $mint';
  }

  @override
  String get cashuNotConnected => 'Not connected to a mint';

  @override
  String get cashuNoMintSet =>
      'No mint set. Set one, or receive a token to use its mint.';

  @override
  String get cashuSetMintButton => 'Set mint';

  @override
  String get cashuChangeMintButton => 'Change mint';

  @override
  String get cashuMintDialogTitle => 'Cashu mint';

  @override
  String get cashuMintFieldLabel => 'Mint URL';

  @override
  String get cashuMintFieldHint => 'https://mint.example.com';

  @override
  String get cashuChangeMintTitle => 'Change mint?';

  @override
  String cashuChangeMintWarning(String sats, String mint) {
    return 'Your $sats sats stay at $mint. They come back when you connect to that mint again.';
  }

  @override
  String get cashuErrorNoMint => 'Set a mint in the Cashu wallet first.';

  @override
  String get cashuErrorInvalidMintUrl =>
      'That is not a mint URL you can use. It must start with https://.';

  @override
  String get cashuErrorWalletOnOtherMint =>
      'Your Cashu wallet uses another mint. Switch it to this node\'s mint in Settings → Cashu wallet, then try again.';

  @override
  String get cashuReceiveButton => 'Receive';

  @override
  String get cashuSendButton => 'Send';

  @override
  String get cashuReceiveHint => 'Paste or scan a Cashu token';

  @override
  String get cashuReceiveTitle => 'Receive a token';

  @override
  String get cashuTokenFieldLabel => 'Cashu token';

  @override
  String get cashuPasteTokenHint => 'Paste a Cashu token';

  @override
  String get qrScanUnavailable => 'Not available on this device';

  @override
  String get cashuAmountLabel => 'Amount in sats';

  @override
  String cashuReceived(int sats) {
    return 'Received $sats sats';
  }

  @override
  String get cashuSyncButton => 'Sync with mint';

  @override
  String get cashuSynced => 'Synced with mint';

  @override
  String get cashuTokenTitle => 'Your token';

  @override
  String get cashuTokenWarning =>
      'Anyone who redeems this token keeps the funds. Treat it like cash: send it once, to one person.';

  @override
  String get cashuCopyToken => 'Copy';

  @override
  String get cashuTokenCopied => 'Token copied';

  @override
  String get cashuWalletExplanation =>
      'This wallet holds ecash from the mint you choose. It exists to fund and receive Cashu trades — it is not a general-purpose wallet.';

  @override
  String get cashuErrorNotEnabled =>
      'This Mostro node does not settle trades with Cashu.';

  @override
  String get cashuErrorNotConnected =>
      'The wallet is not connected to a mint yet.';

  @override
  String get cashuErrorMintUnreachable =>
      'Could not reach the mint. Check your connection and try again.';

  @override
  String get cashuErrorMintUnusable =>
      'This mint is missing features the wallet needs. Choose another mint.';

  @override
  String get cashuErrorUnsupportedOnWeb =>
      'The Cashu wallet is not available on the web version yet.';

  @override
  String get cashuErrorAmountZero => 'Enter an amount greater than zero.';

  @override
  String cashuErrorAmountTooLarge(int sats) {
    return 'You only have $sats sats.';
  }

  @override
  String get cashuErrorReceiveFailed =>
      'That token could not be redeemed. It may be from another mint, or already spent.';

  @override
  String get cashuErrorSendFailed =>
      'Could not create the token. You may not have enough funds.';

  @override
  String get cashuErrorNoIdentity =>
      'Create or import an account before using the wallet.';

  @override
  String get cashuErrorGeneric =>
      'Something went wrong with the wallet. Please try again.';

  @override
  String get cashuLastTokenPending =>
      'You exported a token. It is money until someone redeems it — keep it until you are sure it arrived.';

  @override
  String get cashuShowLastToken => 'Show it again';

  @override
  String get cashuLastTokenDone => 'I\'ve sent it';

  @override
  String get cashuTokenTooLargeForQr =>
      'This token is too large for a QR code. Copy it instead.';

  @override
  String get cashuErrorNoMnemonic =>
      'This account was imported from a private key, so there are no secret words to derive the wallet from. The Cashu wallet needs an account created from secret words.';

  @override
  String get cashuErrorTokenUnverified =>
      'This token could not be verified: it carries no proof of the mint\'s signature, so it was not accepted.';

  @override
  String get cashuErrorUnsupportedUnit =>
      'This wallet only holds sats, and this token is in another unit (such as millisats or dollars). It was left untouched: you can redeem it in a wallet that supports its unit.';

  @override
  String cashuErrorUnsupportedUnitNamed(String unit) {
    return 'This wallet only holds sats, and this token is in $unit. It was left untouched: you can redeem it in a wallet that supports that unit.';
  }

  @override
  String get cashuUnitMsat => 'millisats';

  @override
  String get cashuUnitUsd => 'dollars (USD)';

  @override
  String get cashuUnitEur => 'euros (EUR)';

  @override
  String get cashuErrorSendUnresolved =>
      'The send failed and the wallet could not confirm the funds are back. Sync with the mint before trying again.';

  @override
  String get cashuSendEcashOption => 'Ecash';

  @override
  String get cashuSendLightningOption => 'Lightning';

  @override
  String get cashuInvoiceDialogTitle => 'Pay a Lightning invoice';

  @override
  String get cashuInvoiceFieldLabel => 'Lightning invoice';

  @override
  String get cashuPasteInvoiceHint => 'Paste a Lightning invoice';

  @override
  String get cashuInvoiceScanHint => 'Paste or scan a Lightning invoice';

  @override
  String get cashuMeltConfirmTitle => 'Confirm payment';

  @override
  String get cashuMeltAmount => 'Amount';

  @override
  String get cashuMeltFees => 'Fees, up to';

  @override
  String get cashuMeltTotal => 'Total, up to';

  @override
  String get cashuMeltFeesNote =>
      'Fees the mint does not use come back to your wallet.';

  @override
  String get cashuMeltQuoteRefreshed =>
      'The price changed. Check the new total before paying.';

  @override
  String get cashuPayButton => 'Pay';

  @override
  String cashuMeltPaidTitle(String sats) {
    return 'Paid $sats sats';
  }

  @override
  String cashuMeltPaidFee(String fee) {
    return 'Fee: $fee sats';
  }

  @override
  String get cashuMeltPendingTitle => 'Payment in progress';

  @override
  String get cashuMeltPendingBody =>
      'The outcome isn\'t confirmed yet. Those sats stay on hold; tap “Sync with mint” later to settle them.';

  @override
  String get cashuMeltFailedTitle => 'Payment failed';

  @override
  String get cashuErrorInvalidInvoice =>
      'That is not a Lightning invoice this wallet can pay.';

  @override
  String get cashuErrorInvoiceNoAmount =>
      'This invoice has no amount. Ask for one that states how much to pay.';

  @override
  String get cashuErrorInvoiceExpired =>
      'This invoice has expired. Ask for a new one.';

  @override
  String get cashuErrorMeltUnsupported =>
      'This mint cannot pay Lightning invoices.';

  @override
  String get cashuErrorMeltAmountOutOfRange =>
      'This mint does not pay invoices of that amount.';

  @override
  String get cashuErrorMeltQuoteFailed =>
      'The mint could not quote this payment. Try again later.';

  @override
  String get cashuErrorMeltQuoteExpired =>
      'The payment quote expired. Nothing was paid; start again.';

  @override
  String get cashuErrorMeltFeeChanged =>
      'The fees went up since you confirmed. Nothing was paid; start again.';

  @override
  String get cashuErrorMeltInFlight =>
      'A Lightning payment from this wallet is still in progress. Wait for it to finish, then try again.';

  @override
  String get cashuErrorMeltInsufficientFunds =>
      'You do not have enough in the wallet to pay this invoice and its fees.';

  @override
  String get cashuErrorMeltFailed =>
      'The payment did not go through. Nothing was paid; the sats are back in your balance.';

  @override
  String get lockEscrowTitle => 'Lock the escrow';

  @override
  String get lockEscrowExplanation =>
      'Lock your ecash in a 2-of-3 escrow at this node\'s mint. Neither you nor the buyer can move it alone — and if the node disappears, you can reclaim it yourself once the locktime passes.';

  @override
  String get lockEscrowAmount => 'Escrow';

  @override
  String get lockEscrowFee => 'Mostro fee';

  @override
  String get lockEscrowTotal => 'Total';

  @override
  String get lockEscrowBalance => 'Your balance';

  @override
  String get lockEscrowConfirm => 'Lock escrow';

  @override
  String get lockEscrowFundWallet => 'Fund your wallet';

  @override
  String get lockEscrowSubmitted => 'Escrow locked and sent';

  @override
  String get lockEscrowInsufficientFunds =>
      'Your wallet does not hold enough for the escrow and the fee.';

  @override
  String get lockEscrowNotTheSeller => 'Only the seller funds the escrow.';

  @override
  String get lockEscrowInvalidToken =>
      'The escrow could not be built correctly. Nothing was sent.';

  @override
  String get lockEscrowFailed =>
      'The mint could not lock the escrow. Your funds have not moved.';

  @override
  String lockEscrowMint(String mint) {
    return 'Mint: $mint';
  }

  @override
  String lockEscrowLocktime(int days) {
    return 'Reclaimable by you after $days days';
  }

  @override
  String get lockEscrowRequestMissing =>
      'This trade has no escrow request yet. Wait for the buyer\'s take to arrive, then try again.';

  @override
  String get lockEscrowWrongTradeKey =>
      'This device does not hold the key this order was taken with. Restore your account on the device you started the trade on.';

  @override
  String get lockEscrowLocktimeNotReached =>
      'The escrow is still locked. You can reclaim it yourself once the locktime passes.';

  @override
  String get lockEscrowClockInvalid =>
      'Your device\'s clock is wrong, so the escrow cannot be timed correctly. Fix the date and try again.';

  @override
  String get lockEscrowRetry => 'Retry sending';

  @override
  String get lockEscrowPendingSubmission =>
      'Your escrow is locked but the node has not confirmed it. Retrying is safe — it will not lock a second time.';

  @override
  String get lockEscrowMintNotSupported =>
      'This node lets each order choose its mint, and this version of the app can only lock an escrow on a node with a single mint.';

  @override
  String get lockEscrowNotRecorded =>
      'The escrow reached the node, but this device could not save a copy of it. The trade can go on, but this device cannot reclaim the escrow.';

  @override
  String get lockEscrowRejectedToken =>
      'The node did not accept this escrow. It was set aside — it comes back to you when its lock expires — and the next attempt locks a new one.';

  @override
  String get lockEscrowRejectedMint =>
      'The node uses a different mint. This escrow was set aside — it comes back to you when its lock expires. Check the node\'s mint before trying again.';

  @override
  String get lockEscrowMintUnavailableAtNode =>
      'The node could not reach the mint to check your escrow. Try again: the same escrow is re-sent, nothing is locked twice.';

  @override
  String get lockEscrowRejectedGeneric =>
      'The node refused the escrow. It stays recorded on this device; try again in a moment.';

  @override
  String get lockEscrowNoAnswer =>
      'The node has not answered yet. Your escrow is recorded; retrying re-sends the same one.';

  @override
  String get lockEscrowOrderMovedOn =>
      'The node says this order is no longer waiting for the escrow. Your escrow stays recorded on this device; the trade\'s status will update when the node reports it.';

  @override
  String get tradeHeadlineWaitingPaymentSellerCashu =>
      'Lock the escrow to start the trade';

  @override
  String get tradeWaitingPaymentSellerInstructionCashu =>
      'Lock your ecash in the escrow at the node\'s mint. That starts the trade, and it comes back to you if the node disappears.';

  @override
  String get tradeBodyWaitingPaymentBuyerCashu =>
      'They\'re locking the sats in escrow. Once it\'s locked, it\'s your turn to pay.';

  @override
  String get shareChatKeyAction => 'Share the chat key with the resolver';

  @override
  String get shareChatKeyTitle => 'Share the chat key with the resolver?';

  @override
  String get shareChatKeyBody =>
      'If you confirm, the resolver of this dispute will be able to read the whole chat between you and your counterpart in this trade, and only that chat: not the chats of your earlier or later trades. This cannot be undone. Sharing is optional, but it helps the resolver settle the dispute faster.';

  @override
  String get shareChatKeyConfirm => 'Share';

  @override
  String get chatKeySharedIndicator => 'Chat key shared with the resolver';

  @override
  String get shareChatKeyUnavailable =>
      'The chat key of this trade is not available on this device.';

  @override
  String get moreReactions => 'More reactions';

  @override
  String messageReactionLabel(String emoji) {
    return 'Reaction: $emoji';
  }

  @override
  String get reactionSendFailed =>
      'Couldn\'t send the reaction. Please try again.';

  @override
  String get messageMenuHint => 'Open the message menu';

  @override
  String get cashuAnyMint => 'Any mint';

  @override
  String get settingsMintLabel => 'Mint';

  @override
  String get settingsMintCopied => 'Mint URL copied';

  @override
  String get pwaInstallTitle => 'Install Mostro';

  @override
  String get pwaInstallBody =>
      'Open it from your home screen, full screen, like any other app.';

  @override
  String get pwaInstallAction => 'Install';

  @override
  String get pwaInstallNotNow => 'Not now';

  @override
  String get pwaInstallSettingTitle => 'Install app';

  @override
  String get pwaInstallStepsTitle => 'Add Mostro to your home screen';

  @override
  String get pwaInstallStepShare =>
      'Tap the Share button in your browser\'s toolbar.';

  @override
  String get pwaInstallStepAdd => 'Choose “Add to Home Screen”.';

  @override
  String get pwaInstallStepsDone => 'Got it';

  @override
  String get myReputationTitle => 'Your reputation';

  @override
  String reputationRatingsCount(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString ratings',
      one: '1 rating',
      zero: 'no ratings',
    );
    return '$_temp0';
  }

  @override
  String reputationSince(String date) {
    return 'since $date';
  }

  @override
  String get myReputationNoReviews =>
      'No ratings yet. Your reputation starts with your first rated trade.';

  @override
  String get myReputationPrivacyMode =>
      'Full privacy mode keeps no reputation. Choose reputation mode below to build one.';

  @override
  String get myReputationLoading => 'Asking your node…';

  @override
  String get myReputationUnavailable => 'Your node has not answered yet.';

  @override
  String myReputationOnNode(String node) {
    return 'On $node';
  }

  @override
  String get orderLinkTitle => 'Order link';

  @override
  String get orderLinkLooking => 'Looking for the order…';

  @override
  String orderLinkSwitching(String nodeName) {
    return 'Changing to $nodeName…';
  }

  @override
  String get orderLinkInvalidTitle => 'This link can\'t be opened';

  @override
  String get orderLinkInvalidBody =>
      'It isn\'t a link to a Mostro order, or part of it is missing.';

  @override
  String get orderLinkNotFoundBody =>
      'No relay answered with this order. Check your connection and try again.';

  @override
  String get orderLinkUnavailableTitle => 'Order no longer available';

  @override
  String get orderLinkUnavailableBody =>
      'Someone already took it, or it was cancelled or expired.';

  @override
  String get orderLinkFailedTitle => 'Couldn\'t open the order';

  @override
  String get orderLinkOtherNodeTitle => 'Order on another node';

  @override
  String orderLinkOtherNodeBody(String nodeName) {
    return 'This order was published on $nodeName. To see it and take it, change to that node.';
  }

  @override
  String get orderLinkUnknownNodeWarning =>
      'This node isn\'t in your list. Change to it only if you trust whoever sent you the link: the node you trade on settles your trades and resolves their disputes.';

  @override
  String get reputationNodeDoesNotExport =>
      'This Mostro does not export reputation.';

  @override
  String get reputationNodeDoesNotImport =>
      'This Mostro does not import reputation.';

  @override
  String get reputationIdentityRequired =>
      'Reputation can only be moved from an account that keeps its reputation. Turn off full privacy mode and try again.';

  @override
  String get reputationNotEligible =>
      'Your account cannot export its reputation yet: it needs at least 10 completed trades and 5 ratings received.';

  @override
  String get reputationBoundToOtherIdentity =>
      'Your reputation there is already bound to another identity. Authorize the move from the identity it is bound to.';

  @override
  String get reputationInvalidRebind =>
      'The authorization to move your reputation is invalid or has expired. Create a new one.';

  @override
  String get reputationExpiredAttestation =>
      'This reputation has expired. Request it again from its source.';

  @override
  String get reputationUntrustedIssuer =>
      'This Mostro does not accept reputation from that source.';

  @override
  String get reputationIdentityMismatch =>
      'This reputation was issued for another identity than the one you are using.';

  @override
  String get reputationAlreadyImported =>
      'This reputation was already imported on this Mostro.';

  @override
  String get reputationInvalidAttestation =>
      'This is not a valid reputation. Request it again from its source.';

  @override
  String get reputationImportTitle => 'Import reputation';

  @override
  String get reputationImportIntro =>
      'Bring the reputation you earned on lnp2pBot or on another Mostro to this one. Importing links the two accounts: the source and this Mostro learn they belong to the same person.';

  @override
  String get reputationOpenLnp2pbot => 'Get it from lnp2pBot';

  @override
  String get reputationPasteHint => 'Paste the reputation you received';

  @override
  String get reputationCheck => 'Check';

  @override
  String get reputationImported => 'Your reputation was imported.';

  @override
  String get reputationImportConfirm => 'Import into this Mostro';

  @override
  String get reputationFiguresNote =>
      'Imported reputation is added to the one you have here; your counterparts see them merged.';

  @override
  String get reputationExportFailed =>
      'This Mostro could not export your reputation. Try again later.';

  @override
  String get reputationExportUnexpectedIssuer =>
      'This Mostro signed the answer with a key other than the one it announced. Switch to another Mostro and back to refresh its info, then try again.';

  @override
  String get reputationOpenLnp2pbotFailed =>
      'Telegram could not be opened. Open lnp2pBot in Telegram yourself and paste here what it sends you.';

  @override
  String get reputationIssuedByLnp2pbot => 'Issued by lnp2pBot';

  @override
  String reputationIssuedByMostro(String name) {
    return 'Issued by the Mostro $name';
  }

  @override
  String get reputationIssuedByUnknownKey =>
      'Issued by a key this app does not know:';

  @override
  String get reputationIdentityHint =>
      'Before confirming in lnp2pBot, check that it shows this same public key:';

  @override
  String get reputationUnavailable =>
      'Unable to check whether reputation can be imported. Try again.';

  @override
  String get reputationIdentityChanged =>
      'Your identity changed. Check the public key shown here before trying again.';

  @override
  String get reputationSettingTitle => 'Reputation';

  @override
  String get reputationImportCardBody =>
      'Bring the reputation you earned on lnp2pBot or on another Mostro to this one.';

  @override
  String get reputationExportTitle => 'Export my reputation';

  @override
  String get reputationExportCardBody =>
      'Get a signed copy of the reputation you earned on this Mostro, to import it on another one.';

  @override
  String get reputationExportConfirmTitle => 'Export to this identity?';

  @override
  String reputationExportConfirmBody(String npub) {
    return 'Your reputation on this Mostro will be exported for this identity:\n\n$npub\n\nOnce exported, it is bound to it: exporting it for another identity later needs an authorization signed with this one.';
  }

  @override
  String get reputationExportConfirmButton => 'Export';

  @override
  String get reputationExported =>
      'Your reputation is ready. Switch to the Mostro where you want it and import it; it is valid for 7 days.';

  @override
  String get reputationRebindTitle => 'Move to a new identity';

  @override
  String get reputationRebindBody =>
      'Sign an authorization for the new identity with the identity your reputation is bound to now: for this Mostro, or for lnp2pBot if you got it from there.';

  @override
  String get reputationNewIdentityHint => 'New identity (npub or hex)';

  @override
  String get reputationRebindSignNode => 'Sign for this Mostro';

  @override
  String get reputationRebindSignBot => 'Sign for lnp2pBot';

  @override
  String get reputationRebindSign => 'Sign authorization';

  @override
  String get reputationRebindSignedForNode =>
      'From the new identity, paste it in the authorization field of the export card and export.';

  @override
  String get reputationRebindSignedForBot =>
      'lnp2pBot takes this only after the new identity asked it for your reputation: if you have not yet, open lnp2pBot from the new identity with \"Get it from lnp2pBot\" on the import screen, and open no other link to it afterwards. Then paste this in that chat and confirm. It is valid for one hour.';

  @override
  String get reputationInvalidIdentity =>
      'That is not a valid npub or hex key.';

  @override
  String get reputationRebindInputHint =>
      'Authorization from your previous identity (optional)';

  @override
  String get reputationRebindConfirmTitle => 'Authorize this identity?';

  @override
  String reputationRebindConfirmBody(String npub) {
    return 'Whoever holds this identity will be able to export your reputation from this Mostro, and your current identity no longer will:\n\n$npub\n\nSign only for an identity that is yours.';
  }

  @override
  String reputationRebindConfirmBodyBot(String npub) {
    return 'Whoever holds this identity will be able to export your reputation from lnp2pBot, and your current identity no longer will:\n\n$npub\n\nSign only for an identity that is yours.';
  }

  @override
  String get payoutPaidToLabel => 'Paid to';

  @override
  String get payoutSendingToLabel => 'Sending to';

  @override
  String get payoutNotPaidLabel => 'Not paid to';

  @override
  String get payoutChosenByLabel => 'Chosen by';

  @override
  String get payoutAmountLabel => 'Amount';

  @override
  String get payoutHashLabel => 'Payment hash';

  @override
  String get payoutTriedBeforeLabel => 'Tried before';

  @override
  String payoutTriedBeforeValue(String destination, String outcome) {
    return '$destination · $outcome';
  }

  @override
  String get payoutNwcWallet => 'Your NWC wallet';

  @override
  String payoutNwcWalletNamed(String name) {
    return '$name (NWC)';
  }

  @override
  String payoutInvoice(String invoice) {
    return 'Invoice $invoice';
  }

  @override
  String get payoutSourceDefaultAddress => 'Your default address';

  @override
  String get payoutSourceNwcWallet => 'Your NWC wallet';

  @override
  String get payoutSourceEntered => 'You, for this trade';

  @override
  String get payoutOutcomeSubmitted => 'Waiting';

  @override
  String get payoutOutcomeRetrying => 'Failed, retrying';

  @override
  String get payoutOutcomeFailed => 'Failed';

  @override
  String payoutOutcomeFailedAttempts(int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Failed after $countString attempts',
      one: 'Failed after 1 attempt',
    );
    return '$_temp0';
  }

  @override
  String get payoutOutcomeRejected => 'Refused by the node';

  @override
  String get payoutOutcomePaid => 'Paid';

  @override
  String get payoutHashCopied => 'Payment hash copied';

  @override
  String get takeOrderPayoutLabel => 'Your sats go to';

  @override
  String get takeOrderPayoutInvoice => 'An invoice you add';

  @override
  String get takeOrderPayoutChangeHint => 'Change where your sats go';

  @override
  String takeOrderPayoutNoteDefault(String address) {
    return 'Your sats will be sent to $address, your default Lightning address.';
  }

  @override
  String takeOrderPayoutNoteAddress(String address) {
    return 'Your sats will be sent to $address, for this trade only.';
  }

  @override
  String get takeOrderPayoutNoteInvoice =>
      'After you take the order, you will add the invoice your sats are paid to.';

  @override
  String get takeOrderPayoutSheetTitle => 'Where your sats go';

  @override
  String get takeOrderPayoutSheetDefault => 'My default Lightning address';

  @override
  String get takeOrderPayoutSheetOther => 'Another Lightning address';

  @override
  String get takeOrderPayoutSheetInvoice => 'An invoice I add after taking';

  @override
  String get takeOrderPayoutSheetApply => 'Use for this trade';

  @override
  String invoicePayoutFailed(String destination) {
    return 'The payment to $destination failed.';
  }

  @override
  String invoicePayoutFailedAttempts(String destination, int count) {
    final intl.NumberFormat countNumberFormat = intl
        .NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The payment to $destination failed after $countString attempts.',
      one: 'The payment to $destination failed after 1 attempt.',
    );
    return '$_temp0';
  }

  @override
  String get invoicePayoutFailedNwc =>
      'Your NWC wallet is making a new invoice for these sats.';

  @override
  String invoicePayoutFailedNwcNamed(String name) {
    return '$name is making a new invoice for these sats.';
  }

  @override
  String get invoicePayoutFailedManual =>
      'Add a new invoice to receive your sats.';

  @override
  String get tradeCardPayoutFailedTitle => 'Mostro could not send your sats';

  @override
  String get tradeCardPayoutFailedMessage =>
      'Mostro could not send your sats to the address or invoice you gave. Open the trade to see which one failed, and add a new invoice if it is still needed.';

  @override
  String get tradeCardOrderPublishedTitle => 'Order published';

  @override
  String get tradeCardOrderPublishedMessage =>
      'Your order is in the order book now, and other users can take it.';

  @override
  String get payoutInvoiceLabel => 'Invoice';

  @override
  String get payoutInvoiceCopied => 'Invoice copied';

  @override
  String get payoutWillGoToLabel => 'Sats will go to';

  @override
  String get payoutMaybePaidToLabel => 'Maybe paid to';

  @override
  String get payoutOutcomeReplaced => 'Replaced by a later one';

  @override
  String get payoutOutcomeMaybePaid =>
      'Paid to this one or another listed here';

  @override
  String otherNodeCardLine(String nodeName) {
    return 'Trade on node: $nodeName';
  }

  @override
  String get otherNodeCardDialogTitle => 'Trade on another node';

  @override
  String otherNodeCardSwitchPrompt(String nodeName) {
    return 'Do you want to switch to node $nodeName?';
  }

  @override
  String get stablecoinsGroupHeader => 'Stablecoins';

  @override
  String get bitcoinNetworksGroupHeader => 'Bitcoin on other networks';

  @override
  String marketPriceNotQuotedByNode(String code) {
    return 'This node doesn\'t quote $code at market price. Set a fixed amount in sats.';
  }
}
