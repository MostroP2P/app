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
  String get error => 'Error';

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
  String get disputeAdminAssigned =>
      'An administrator has been assigned to your dispute. They will contact you here shortly.';

  @override
  String get disputeChatClosed =>
      'This dispute has been resolved. The chat is closed.';

  @override
  String get messageCopied => 'Copied';

  @override
  String get disputeLoadError => 'Failed to load disputes. Please try again.';

  @override
  String get disputeMessagingComingSoon => 'Dispute messaging coming soon';

  @override
  String get disputeAttachmentsComingSoon => 'File attachments coming soon';

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
  String disputeWithBuyer(String handle) {
    return 'Dispute with Buyer: $handle';
  }

  @override
  String disputeWithSeller(String handle) {
    return 'Dispute with Seller: $handle';
  }

  @override
  String orderLabel(String orderId) {
    return 'Order $orderId';
  }

  @override
  String get disputeInitiated => 'Initiated';

  @override
  String get disputeInProgress => 'In progress';

  @override
  String get disputeStatusClosed => 'Closed';

  @override
  String get disputeLostFundsToBuyer =>
      'The administrator settled the dispute in the buyer\'s favour. The sats were released to the buyer.';

  @override
  String get disputeLostFundsToSeller =>
      'The administrator canceled the order and returned the sats to the seller. You did not receive the sats.';

  @override
  String get walkthroughSlideOneTitle => 'Trade Bitcoin freely — no KYC';

  @override
  String get walkthroughSlideOneBody =>
      'Mostro is a peer-to-peer exchange that lets you trade Bitcoin for any currency and payment method — no KYC, and no need to give your data to anyone. It\'s built on Nostr, which makes it censorship-resistant. No one can stop you from trading.';

  @override
  String get walkthroughSlideTwoTitle => 'Privacy by default';

  @override
  String get walkthroughSlideTwoBody =>
      'Mostro generates a new identity for every exchange, so your trades can\'t be linked. You can also decide how private you want to be:\n• Reputation mode – Lets others see your successful trades and trust level.\n• Full privacy mode – No reputation is built, but your activity is completely anonymous.\nSwitch modes anytime from the Account screen, where you should also save your secret words — they\'re the only way to recover your account.';

  @override
  String get walkthroughSlideThreeTitle => 'Security at every step';

  @override
  String get walkthroughSlideThreeBody =>
      'Mostro uses Hold Invoices: sats stay in the seller\'s wallet until the end of the trade. This protects both sides. The app is also designed to be intuitive and easy for all kinds of users.';

  @override
  String get walkthroughSlideFourTitle => 'Fully encrypted chat';

  @override
  String get walkthroughSlideFourBody =>
      'Each trade has its own private chat, end-to-end encrypted. Only the two users involved can read it. In case of a dispute, you can give the shared key to an admin to help resolve the issue.';

  @override
  String get walkthroughSlideFiveTitle => 'Take an offer';

  @override
  String get walkthroughSlideFiveBody =>
      'Browse the order book, choose an offer that works for you, and follow the trade flow step by step. You\'ll be able to check the other user\'s profile, chat securely, and complete the trade with ease.';

  @override
  String get walkthroughSlideSixTitle => 'Can\'t find what you need?';

  @override
  String get walkthroughSlideSixBody =>
      'You can also create your own offer and wait for someone to take it. Set the amount and preferred payment method — Mostro handles the rest.';

  @override
  String get tabBuyBtc => 'Buy BTC';

  @override
  String get tabSellBtc => 'Sell BTC';

  @override
  String get filterButtonLabel => 'Filter';

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
  String get mostroMaintenanceMode =>
      'The Mostro node you are connected to is under maintenance. Try again later, or connect to a different Mostro node in Settings';

  @override
  String get storageUnavailable =>
      'The app cannot create or take orders while its local database is unavailable. Restart the app and try again';

  @override
  String get orderIdCopied => 'Order ID copied';

  @override
  String get comingSoonMessage => 'Coming soon';

  @override
  String get tradeStatusActive => 'Active';

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
  String get importMnemonicDialogTitle => 'Import Mnemonic';

  @override
  String get importMnemonicHintText => 'Enter your 12 or 24 word phrase…';

  @override
  String get importButtonLabel => 'Import';

  @override
  String get refreshUserDialogTitle => 'Refresh User?';

  @override
  String get refreshUserDialogContent =>
      'This will re-fetch your trades and orders from the Mostro instance. Use this if you think your data is out of sync or orders are missing.';

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
    return 'Bond $pct%';
  }

  @override
  String get nodeBondNone => 'No bond';

  @override
  String nodeStatusOnline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders',
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
  String get nodeDisclaimerShort =>
      'Each node is run by an independent third party. Mostro is not responsible for their conduct or for your trades.';

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
  String get drawerStageBadge => 'Alpha';

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
      'Requesting a cooperative cancel. The other party must also agree for the trade to be fully cancelled.';

  @override
  String get cancelTradeDialogContentNotStarted =>
      'The trade has not started yet, so it is cancelled right away. The other party does not need to agree.';

  @override
  String get cancelTradeDialogContentMaybeStarted =>
      'If the trade has not started yet, it is cancelled right away. If it has, the other party must also agree.';

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
  String get fiatSentFailed => 'Failed to mark fiat as sent. Please try again.';

  @override
  String get releaseFailed => 'Failed to release. Please try again.';

  @override
  String get cancelTradeButton => 'Cancel trade';

  @override
  String get payHoldInvoiceButton => 'Pay hold invoice';

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
  String get aboutAntiAbuseBondSection => 'Anti-abuse Bond';

  @override
  String get aboutBondEnabledValue => 'Enabled';

  @override
  String get aboutBondDisabledValue => 'Disabled';

  @override
  String get aboutBondUnsupportedValue => 'Not supported';

  @override
  String get aboutBondStatusLabel => 'Bond status';

  @override
  String get aboutBondAppliesToLabel => 'Applies to';

  @override
  String get aboutBondAppliesToTakers => 'Takers';

  @override
  String get aboutBondAppliesToMakers => 'Makers';

  @override
  String get aboutBondAppliesToBoth => 'Makers and takers';

  @override
  String get aboutBondAmountLabel => 'Bond amount';

  @override
  String get aboutBondBaseAmountLabel => 'Minimum bond';

  @override
  String get aboutBondNodeShareLabel => 'Node share on slash';

  @override
  String get aboutBondSlashOnTimeoutLabel => 'Slash on waiting timeout';

  @override
  String get aboutBondClaimWindowLabel => 'Payout claim window';

  @override
  String aboutBondClaimWindowValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String get openDisputeFailed => 'Could not open dispute. Please try again.';

  @override
  String get openDisputeTitle => 'Open dispute';

  @override
  String get openDisputeConfirmation =>
      'Are you sure you want to open a dispute? This escalates the trade to an admin and cannot be undone.';

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
      'Pay the hold invoice to lock the funds and start the trade.';

  @override
  String get tradeLoadError => 'An error occurred while loading the trade.';

  @override
  String get tradeWaitingForHoldInvoice => 'Waiting for hold invoice...';

  @override
  String get shareButtonLabel => 'Share';

  @override
  String get shareFailed => 'Could not share the invoice';

  @override
  String get waitingForPaymentConfirmation =>
      'Waiting for payment confirmation...';

  @override
  String get orderNoLongerActive => 'This order is no longer active';

  @override
  String get tradeNoLongerYours => 'You\'re no longer part of this trade';

  @override
  String get sessionTimeoutMessage =>
      'No response received, check your connection and try again later';

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
  String get invalidMnemonicMessage =>
      'Invalid mnemonic. Please check your words and try again.';

  @override
  String get enterValidMnemonicError => 'Enter a valid 12 or 24 word phrase.';

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
  String get notifNewMessagesSubtitle =>
      'Messages from your trade counterparty';

  @override
  String get notifPaymentAlertsTitle => 'Payment alerts';

  @override
  String get notifPaymentAlertsSubtitle =>
      'Lightning payment confirmations and failures';

  @override
  String get notifDisputeUpdatesTitle => 'Dispute updates';

  @override
  String get notifDisputeUpdatesSubtitle =>
      'Admin actions and dispute resolutions';

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
  String get tradeFilterCanceled => 'Canceled';

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
      'Fiat payment marked as sent. Waiting for the seller to confirm receipt and release your sats.';

  @override
  String get tradeInstructionActiveSeller =>
      'Contact the buyer with payment instructions via the chat above.';

  @override
  String get tradeInstructionFiatSentSeller =>
      'The buyer has confirmed they sent the fiat payment. Once you verify receipt, release the sats.';

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
      'Pay the hold invoice to lock the sats';

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
  String get tradeTimerWaitingInvoiceConsequence =>
      'If it expires, the trade is cancelled and the order returns to the book.';

  @override
  String get tradeStepOrderTaken => 'Order taken';

  @override
  String get tradeStepInvoiceBuyer => 'The seller locks the sats';

  @override
  String get tradeStepInvoiceSeller => 'You lock the sats';

  @override
  String get tradeStepFiatBuyer => 'You send the fiat payment';

  @override
  String get tradeStepFiatSeller => 'The buyer sends the fiat payment';

  @override
  String get tradeStepReleaseBuyer => 'The seller releases your sats';

  @override
  String get tradeStepReleaseSeller => 'You confirm and release the sats';

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
  String get exchangeInfoTooltip => 'Exchange Info';

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
  String get statusLabel => 'Status';

  @override
  String get paymentMethodLabel => 'Payment Method';

  @override
  String get createdLabel => 'Created';

  @override
  String get tradeDetailsPlaceholder =>
      'Details wired when trade provider available (Phase 10+)';

  @override
  String get userInformationTitle => 'User Information';

  @override
  String get peerPublicKeyLabel => 'Peer\'s Public Key';

  @override
  String get yourSharedKeyLabel => 'Your Shared Key';

  @override
  String get sharedKeyPlaceholder =>
      'Available after bridge integration (Phase 10+)';

  @override
  String get sharedKeySafetyNote =>
      'Keep your shared key safe — it is needed for dispute resolution';

  @override
  String get attachmentLabel => '[Attachment]';

  @override
  String get downloadTooltip => 'Download';

  @override
  String get fileDownloadPlaceholder => 'File download wired in Phase 10+';

  @override
  String get fileTypeVideo => 'Video';

  @override
  String get fileTypeImage => 'Image';

  @override
  String get fileTypeArchive => 'Archive';

  @override
  String get fileTypeFile => 'File';

  @override
  String get tapToDownload => 'Tap to download';

  @override
  String get imageDownloadPlaceholder => 'Image download wired in Phase 10+';

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
  String get waitingForTradeAmount =>
      'Waiting for trade amount — please try again shortly.';

  @override
  String get fetchingTradeAmount => 'Fetching trade amount…';

  @override
  String get enterInvoiceManually => 'Enter invoice manually';

  @override
  String get submitButton => 'Submit';

  @override
  String get buyerReputation => 'Buyer reputation';

  @override
  String get sellerReputation => 'Seller reputation';

  @override
  String get ratingStatLabel => 'rating';

  @override
  String get tradesStatLabel => 'trades';

  @override
  String get daysActiveStatLabel => 'days active';

  @override
  String timeRemainingLabel(String time) {
    return 'Time remaining: $time';
  }

  @override
  String orderAmountOutOfRange(int min, int max) {
    return 'Amount must be between $min and $max sats for this Mostro node';
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
      'Market Price: Your order price follows the market rate with a premium/discount percentage applied.\n\nFixed Price: You set an exact price in satoshis.';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chosen',
      one: '1 chosen',
      zero: 'none chosen',
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
  String get customPaymentMethodHint => 'Custom payment method...';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Select $count stars',
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
  String get adminLabel => 'Admin';

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
  String reputationTradesLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'trades',
      one: 'trade',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'Newest';

  @override
  String ordersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders',
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
  String orderFixedAmount(String sats) {
    return 'Fixed amount · for $sats';
  }

  @override
  String get reputationNew => 'New';

  @override
  String get reputationNoTrades => 'no trades';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View $count earlier events',
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
  String get notifFilterAll => 'All';

  @override
  String get notifFilterDisputes => 'Disputes';

  @override
  String notifFilterDisputesCount(int count) {
    return 'Disputes · $count';
  }

  @override
  String get notifFilterSystem => 'System';

  @override
  String notifFilterSystemCount(int count) {
    return 'System · $count';
  }

  @override
  String get payingStatus => 'Paying...';

  @override
  String get payWithWalletButton => 'Pay with Wallet';

  @override
  String get generatingInvoiceNwc => 'Generating invoice via NWC...';

  @override
  String get unableToGenerateInvoice =>
      'Unable to generate invoice automatically';

  @override
  String get avatarIconLabel => 'Avatar icon';

  @override
  String get disputeDescResolvedBuyerFavour =>
      'Dispute resolved in buyer\'s favour';

  @override
  String get disputeDescResolvedYourFavour => 'Dispute resolved in your favour';

  @override
  String get disputeDescResolvedSellerFavour =>
      'Dispute resolved in seller\'s favour';

  @override
  String get disputeDescCooperativeCancel => 'Order cancelled cooperatively';

  @override
  String get disputeDescResolved => 'Dispute resolved';

  @override
  String get disputeDescYouOpened => 'You opened this dispute';

  @override
  String get disputeDescCounterpartOpened => 'Counterpart opened this dispute';

  @override
  String get notificationsBellNoUnread =>
      'Notifications, no unread notifications';

  @override
  String get notificationsBellBackupActive =>
      'Notifications, backup reminder active';

  @override
  String notificationsBellUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notifications, $count unread',
      one: 'Notifications, 1 unread',
    );
    return '$_temp0';
  }

  @override
  String drawerBadgeNewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new',
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
    return 'The node slashed your $sats-sat bond in this dispute.';
  }

  @override
  String bondSlashedTradeNoticeTimeout(String sats) {
    return 'The node slashed your $sats-sat bond after a step timed out.';
  }

  @override
  String get bondSlashedTitle => 'Bond slashed';

  @override
  String bondSlashedMessageTimeout(String amount, String orderId) {
    return 'Your $amount-sat anti-abuse bond for order $orderId was forfeited after a waiting-state timeout. Your order status is unchanged.';
  }

  @override
  String bondSlashedMessageDispute(String amount, String orderId) {
    return 'Your $amount-sat anti-abuse bond for order $orderId was forfeited after a dispute resolution. Your order status is unchanged.';
  }

  @override
  String get bondSlashedCauseTimeout => 'Waiting-state timeout';

  @override
  String get bondSlashedCauseDispute => 'Dispute resolution';

  @override
  String get bondSlashedDetailOrder => 'Order';

  @override
  String get bondSlashedDetailAmount => 'Bond amount';

  @override
  String get bondSlashedDetailCause => 'Cause';

  @override
  String get bondSlashedDetailFiat => 'Fiat';

  @override
  String get bondSlashedDetailPaymentMethod => 'Payment method';

  @override
  String aboutDaysValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String get aboutCashuEscrowSection => 'Cashu escrow';

  @override
  String get aboutCashuMintUrlLabel => 'Mint';

  @override
  String get aboutCashuMintNotAdvertised => 'Not advertised';

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
  String get tradeHeadlinePayoutPending => 'Waiting for the buyer payout';

  @override
  String get tradeInstructionPayoutPending =>
      'The seller released the escrow. Waiting for the Lightning payment to the buyer to succeed.';

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
  String get tradeChatEncrypted => 'End-to-end encrypted chat';

  @override
  String get tradeBodyWaitingPaymentBuyer =>
      'They\'re paying the hold invoice. Once the sats are locked, it\'s your turn to pay the fiat.';

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
  String get tradeReleaseIrreversible => 'Releasing the sats cannot be undone.';

  @override
  String get tradeTimerYouHave => 'You have';

  @override
  String get tradeTimerTheyHave => 'They have';

  @override
  String get tradeTimerOrderHas => 'Time left';

  @override
  String get tradeTimerNoteCoordinate =>
      'If you need more time, coordinate in the chat before it expires.';

  @override
  String get tradeRoleBuyer => 'Buyer';

  @override
  String get tradeRoleSeller => 'Seller';

  @override
  String reputationTradesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades',
      one: '1 trade',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days on Mostro',
      one: '1 day on Mostro',
    );
    return '$_temp0';
  }

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
  String counterpartyTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades',
      one: '$count trade',
    );
    return '$_temp0';
  }

  @override
  String counterpartyDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days on Mostro',
      one: '$count day on Mostro',
    );
    return '$_temp0';
  }

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
  String get notificationsPrivacyFootnote =>
      'Notifications carry no amounts and no counterparties. A push travels through Google\'s or Apple\'s servers and says only that there is something to see.';

  @override
  String get pushMasterToggleTitle => 'Push notifications';

  @override
  String get pushMasterToggleSubtitle =>
      'Wakes the app when a trade or chat message arrives. The notification itself carries nothing.';

  @override
  String get pushStatusOff =>
      'Off — nothing is registered with the push server';

  @override
  String pushStatusCleanupPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Off — removal of $count push registrations is pending',
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Registered for $count trades',
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
  String get aboutLimitsFootnote => 'Limits in satoshis per order';

  @override
  String get aboutNodeTechnicalDataRow => 'Node technical data';

  @override
  String aboutFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fields',
      one: '$count field',
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
    return '$count h';
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
  String get tradesDirectionBondClaim => 'Bond claim';

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
  String get bondRefundableLabel => 'REFUNDABLE DEPOSIT';

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
    return 'The sats stay $bold, they are not spent';
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
  String bondWhyHold(String hold) {
    return 'It is a $hold invoice: your wallet reserves the sats without sending them; when the trade completes, the reservation is cancelled on its own.';
  }

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
    return '$pct % of the amount';
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
  String get bondCancelNotAllowed =>
      'This order can\'t be cancelled while its deposit is pending. Drop it from the deposit screen instead.';

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
  String get bondClaimShareLabel => 'YOUR SHARE';

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
      'The other party\'s deposit was forfeited in your favour. Add an invoice for exactly this amount and the node pays it to you.';

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
    return 'The other party\'s deposit was forfeited in your favour. Add any Lightning invoice for $sats sats to claim it.';
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
    return 'The claim on the other party\'s deposit closed on $date.';
  }

  @override
  String get bondClaimNewTitle => 'Bond payout to claim';

  @override
  String bondClaimNewMessage(String sats) {
    return 'You can claim $sats sats from a slashed bond. Add a Lightning invoice to receive them.';
  }

  @override
  String get bondClaimPaidTitle => 'Bond payout received';

  @override
  String bondClaimPaidMessage(String sats) {
    return 'Bond payout of $sats sats received.';
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
  String get invoiceOrderIdCopied => 'Order ID copied';

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
  String get invoiceFieldLabel => 'Lightning invoice or address';

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
    return 'The invoice is for $actual sats, it must be $expected';
  }

  @override
  String get invoiceErrorExpired => 'The invoice has already expired';

  @override
  String invoiceErrorExpiresTooSoon(String minutes) {
    return 'The invoice expires in less than $minutes minutes, the node needs more time to pay it';
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
  String get invoiceNoTrades => 'no trades';

  @override
  String get invoiceSendButton => 'Send invoice';

  @override
  String get invoiceCancelTrade => 'Cancel trade';

  @override
  String get invoiceOpenWallet => 'Open in my wallet';

  @override
  String invoiceHoldNote(String hold) {
    return 'This is a $hold invoice: the sats are held, they don\'t leave your wallet until you confirm the buyer\'s payment.';
  }

  @override
  String invoiceQrSemantics(String invoice) {
    return 'Lightning invoice QR code: $invoice';
  }

  @override
  String get invoiceExpiredTitle => 'The invoice expired';

  @override
  String get invoiceExpiredBody =>
      'It was not paid in time: Mostro cancels the trade and no sats left your wallet.';

  @override
  String get invoiceBackToBook => 'Back to the order book';

  @override
  String get invoiceTimeUpTitle => 'Time is up';

  @override
  String get invoiceTimeUpBody =>
      'The invoice was not sent in time: Mostro cancels the trade. Nothing was committed on your side.';

  @override
  String invoiceErrorWrongNetwork(String invoice, String node) {
    return 'The invoice is for $invoice, the node uses $node';
  }

  @override
  String invoiceCountdownHours(String hours, String minutes) {
    return '$hours h $minutes';
  }

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
      'The trade continues once the seller pays the hold invoice.';

  @override
  String get tradeCardWaitingTakerBondTitle => 'Bond payment pending';

  @override
  String get tradeCardWaitingTakerBondMessage =>
      'The taker\'s anti-abuse bond must be paid before the trade starts.';

  @override
  String get tradeCardActiveTitle => 'Trade active';

  @override
  String get tradeCardActiveMessage =>
      'The sats are locked. The buyer can now send the fiat payment.';

  @override
  String get tradeCardFiatSentTitle => 'Fiat marked as sent';

  @override
  String get tradeCardFiatSentMessage =>
      'The buyer marked the fiat payment as sent.';

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
  String get tradeCardCanceledTitle => 'Trade canceled';

  @override
  String get tradeCardCanceledMessage => 'The trade was canceled.';

  @override
  String get tradeCardExpiredTitle => 'Order expired';

  @override
  String get tradeCardExpiredMessage =>
      'The order expired before the trade could continue.';

  @override
  String get tradeCardCooperativelyCanceledTitle =>
      'Trade canceled by agreement';

  @override
  String get tradeCardCooperativelyCanceledMessage =>
      'Both parties agreed to cancel the trade.';

  @override
  String get tradeCardDisputeTitle => 'Dispute opened';

  @override
  String get tradeCardDisputeMessage => 'A dispute was opened on this trade.';

  @override
  String get tradeCardCanceledByAdminTitle => 'Canceled by the resolver';

  @override
  String get tradeCardCanceledByAdminMessage =>
      'The dispute resolver canceled the trade.';

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
  String get tradeCardCanceledByMakerMessage => 'The maker canceled the order.';

  @override
  String get tradeCardCanceledBondLostRaceMessage =>
      'Another user took this order before the bond was paid.';

  @override
  String get tradeCardCanceledBondExpiredMessage =>
      'The bond invoice expired unpaid.';

  @override
  String get chatCardTitle => 'New messages';

  @override
  String get chatCardSolverTitle => 'Messages from the resolver';

  @override
  String chatCardMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new messages from your trade partner',
      one: '1 new message from your trade partner',
    );
    return '$_temp0';
  }

  @override
  String chatCardSolverMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new messages from the dispute resolver',
      one: '1 new message from the dispute resolver',
    );
    return '$_temp0';
  }
}
