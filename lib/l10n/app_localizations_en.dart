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
  String get tabBuyBtc => 'BUY BTC';

  @override
  String get tabSellBtc => 'SELL BTC';

  @override
  String get filterButtonLabel => 'FILTER';

  @override
  String offersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offers',
      one: '1 offer',
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
  String get creatingNewOrderTitle => 'CREATING NEW ORDER';

  @override
  String get youWantToBuyBitcoin => 'You want to buy Bitcoin';

  @override
  String get youWantToSellBitcoin => 'You want to sell Bitcoin';

  @override
  String get rangeOrderLabel => 'Range order';

  @override
  String get payLightningInvoiceTitle => 'Pay Lightning Invoice';

  @override
  String get invoiceCopied => 'Invoice copied';

  @override
  String get addInvoiceTitle => 'Add Invoice';

  @override
  String get submitButtonLabel => 'Submit';

  @override
  String get orderAlreadyTaken => 'Order has already been taken';

  @override
  String get bondRequired =>
      'This node requires an anti-abuse bond, which is not supported yet';

  @override
  String addInvoiceAmount(String sats) {
    return 'Amount to receive: $sats sats';
  }

  @override
  String payInvoiceAmount(String sats) {
    return 'Amount to pay: $sats sats';
  }

  @override
  String get orderIdCopied => 'Order ID copied';

  @override
  String get orderDetailsTitle => 'ORDER DETAILS';

  @override
  String get timeRemainingLabel => 'Time remaining:';

  @override
  String get fiatSentButtonLabel => 'FIAT SENT';

  @override
  String get disputeButtonLabel => 'DISPUTE';

  @override
  String get contactButtonLabel => 'CONTACT';

  @override
  String get rateButtonLabel => 'RATE';

  @override
  String get viewDisputeButtonLabel => 'VIEW DISPUTE';

  @override
  String get comingSoonMessage => 'Coming soon';

  @override
  String get tradeStatusActive => 'Active';

  @override
  String get tradeStatusFiatSent => 'Fiat Sent';

  @override
  String get tradeStatusCompleted => 'Completed';

  @override
  String get tradeStatusCancelled => 'Cancelled';

  @override
  String get tradeStatusDisputed => 'Disputed';

  @override
  String get releaseButtonLabel => 'RELEASE';

  @override
  String get accountScreenTitle => 'Account';

  @override
  String get secretWordsTitle => 'Secret Words';

  @override
  String get toRestoreYourAccount => 'To restore your account';

  @override
  String get privacyCardTitle => 'Privacy';

  @override
  String get controlPrivacySettings => 'Control your privacy settings';

  @override
  String get reputationMode => 'Reputation Mode';

  @override
  String get reputationModeSubtitle => 'Standard privacy with reputation';

  @override
  String get fullPrivacyMode => 'Full Privacy Mode';

  @override
  String get fullPrivacyModeSubtitle => 'Maximum anonymity';

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
  String get showButtonLabel => 'Show';

  @override
  String get settingsScreenTitle => 'Settings';

  @override
  String get languageSettingTitle => 'Language';

  @override
  String get appearanceSettingTitle => 'Appearance';

  @override
  String get appearanceDialogTitle => 'Appearance';

  @override
  String get defaultFiatCurrencyTitle => 'Default Fiat Currency';

  @override
  String get allCurrencies => 'All currencies';

  @override
  String get lightningAddressSettingTitle => 'Lightning Address';

  @override
  String get tapToSetSubtitle => 'Tap to set';

  @override
  String get nwcWalletSettingTitle => 'NWC Wallet';

  @override
  String get nwcConnectPrompt => 'Connect your Lightning wallet via NWC';

  @override
  String get relaysSettingTitle => 'Relays';

  @override
  String get manageRelayConnections => 'Manage relay connections';

  @override
  String get pushNotificationsSettingTitle => 'Push Notifications';

  @override
  String get manageNotificationPreferences => 'Manage notification preferences';

  @override
  String get logReportSettingTitle => 'Log Report';

  @override
  String get viewDiagnosticLogs => 'View diagnostic logs';

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
  String get connectWalletTitle => 'Connect Wallet';

  @override
  String get scanQrCodeTitle => 'Scan QR Code';

  @override
  String get pasteNwcUri => 'Paste NWC URI';

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
  String nwcConnectedBalance(String balance) {
    return 'NWC — Connected. Balance: $balance';
  }

  @override
  String get pasteQrCodeHeading => 'Paste QR Code Content';

  @override
  String get pasteButtonLabel => 'Paste';

  @override
  String get clipboardEmptyError => 'Clipboard is empty';

  @override
  String get enterValueError => 'Please enter a value';

  @override
  String get pasteOrScanQrCode => 'Paste or scan a QR code';

  @override
  String get mostroNodeTitle => 'Mostro Node';

  @override
  String get currentNodeLabel => 'Current Node';

  @override
  String get trustedBadgeLabel => 'Trusted';

  @override
  String get useDefaultButtonLabel => 'Use Default';

  @override
  String get confirmButtonLabel => 'Confirm';

  @override
  String get invalidHexPubkey => 'Must be a 64-character hex string';

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
  String get submitRatingButton => 'SUBMIT';

  @override
  String get closeRatingButton => 'CLOSE';

  @override
  String get aboutScreenTitle => 'About';

  @override
  String get mostroTagline => 'Peer-to-peer Bitcoin trading over Nostr';

  @override
  String get viewDocumentationButton => 'View Documentation';

  @override
  String get linkCopiedToClipboard => 'Link copied to clipboard';

  @override
  String get defaultNodeSection => 'Default Node';

  @override
  String get pubkeyLabel => 'Pubkey';

  @override
  String get relaysLabel => 'Relays';

  @override
  String get pubkeyCopiedToClipboard => 'Pubkey copied to clipboard';

  @override
  String get footerTagline => 'Open-source. Non-custodial. Private.';

  @override
  String get drawerTitle => 'MOSTRO';

  @override
  String get betaBadgeLabel => 'Beta';

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
  String get backupConfirmCheckbox =>
      'I have written down my words and backed them up securely';

  @override
  String get cancelTradeDialogTitle => 'Cancel trade?';

  @override
  String get cancelTradeDialogContent =>
      'Requesting a cooperative cancel. The other party must also agree for the trade to be fully cancelled.';

  @override
  String get noButtonLabel => 'No';

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
  String get orderPillYouAreSelling => 'YOU ARE SELLING';

  @override
  String get orderPillYouAreBuying => 'YOU ARE BUYING';

  @override
  String get orderPillSelling => 'SELLING';

  @override
  String get orderPillBuying => 'BUYING';

  @override
  String get myOrderSellTitle => 'YOUR SELL ORDER';

  @override
  String get myOrderBuyTitle => 'YOUR BUY ORDER';

  @override
  String get cancelOrderButton => 'Cancel order';

  @override
  String get cancelOrderDialogTitle => 'Cancel order';

  @override
  String get cancelOrderDialogContent =>
      'Are you sure you want to cancel this order? This action cannot be undone.';

  @override
  String get cancelOrderFailed => 'Failed to cancel order. Please try again.';

  @override
  String get closeButtonLabel => 'Close';

  @override
  String get copyButtonLabel => 'Copy';

  @override
  String get orderStatusWaitingForTaker => 'Waiting for a taker';

  @override
  String get orderStatusWaitingBuyerInvoice => 'Waiting for buyer invoice';

  @override
  String get orderStatusWaitingPayment => 'Waiting for payment';

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
  String get aboutAppInfoTitle => 'App Information';

  @override
  String get aboutDocumentationTitle => 'Documentation';

  @override
  String get aboutMostroNodeTitle => 'Mostro Node';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String get aboutGithubRepoLabel => 'GitHub Repository';

  @override
  String get aboutCommitHashLabel => 'Commit Hash';

  @override
  String get aboutLicenseLabel => 'License';

  @override
  String get aboutLicenseName => 'MIT';

  @override
  String get aboutGithubRepoName => 'mostro-mobile';

  @override
  String get aboutDocsUsersEnglish => 'Users (English)';

  @override
  String get aboutDocsUsersSpanish => 'Users (Spanish)';

  @override
  String get aboutDocsTechnical => 'Technical';

  @override
  String get aboutDocsRead => 'Read';

  @override
  String get aboutCopiedToClipboard => 'Copied to clipboard';

  @override
  String get aboutLicenseDialogTitle => 'MIT License';

  @override
  String get aboutNodeLoadingText => 'Loading node information…';

  @override
  String get aboutNodeUnavailable => 'Node information unavailable';

  @override
  String get aboutNodeRetry => 'Retry';

  @override
  String get aboutGeneralInfoSection => 'General Info';

  @override
  String get aboutTechnicalDetailsSection => 'Technical Details';

  @override
  String get aboutLightningNetworkSection => 'Lightning Network';

  @override
  String get aboutMostroPublicKeyLabel => 'Mostro Public Key';

  @override
  String get aboutMaxOrderAmountLabel => 'Max Order Amount';

  @override
  String get aboutMinOrderAmountLabel => 'Min Order Amount';

  @override
  String get aboutOrderLifespanLabel => 'Order Lifespan';

  @override
  String get aboutServiceFeeLabel => 'Service Fee';

  @override
  String get aboutFiatCurrenciesLabel => 'Fiat Currencies';

  @override
  String get aboutMostroVersionLabel => 'Mostro Version';

  @override
  String get aboutMostroCommitLabel => 'Mostro Commit';

  @override
  String get aboutOrderExpirationLabel => 'Order Expiration';

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
  String get aboutLndNodePublicKeyLabel => 'LND Node Public Key';

  @override
  String get aboutLndCommitLabel => 'LND Commit';

  @override
  String get aboutLndNodeAliasLabel => 'LND Node Alias';

  @override
  String get aboutSupportedChainsLabel => 'Supported Chains';

  @override
  String get aboutSupportedNetworksLabel => 'Supported Networks';

  @override
  String get aboutLndNodeUriLabel => 'LND Node URI';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutHoursSuffix => 'hours';

  @override
  String get aboutSecondsSuffix => 'seconds';

  @override
  String get aboutBlocksSuffix => 'blocks';

  @override
  String get aboutFiatCurrenciesAll => 'All';

  @override
  String get aboutMostroPublicKeyExplanation =>
      'The Nostr public key of the Mostro daemon. All orders and encrypted messages on this instance are published or routed by this key.';

  @override
  String get aboutMaxOrderAmountExplanation =>
      'The maximum fiat amount allowed for a single order on this Mostro instance.';

  @override
  String get aboutMinOrderAmountExplanation =>
      'The minimum fiat amount required for a single order on this Mostro instance.';

  @override
  String get aboutOrderLifespanExplanation =>
      'How long a pending order stays open before it automatically expires if no taker is found.';

  @override
  String get aboutServiceFeeExplanation =>
      'The percentage of the trade amount charged by the Mostro daemon as a service fee.';

  @override
  String get aboutFiatCurrenciesExplanation =>
      'The fiat currencies accepted on this Mostro instance. \'All\' means there are no restrictions.';

  @override
  String get aboutMostroVersionExplanation =>
      'The version of the Mostro daemon software running this instance.';

  @override
  String get aboutMostroCommitExplanation =>
      'The Git commit hash of the Mostro daemon build, used to identify the exact software revision.';

  @override
  String get aboutOrderExpirationExplanation =>
      'The timeout in seconds after which a trade waiting for action (e.g. invoice or payment) is automatically canceled.';

  @override
  String get aboutHoldInvoiceExpExplanation =>
      'The time window in seconds during which the Lightning hold invoice must be settled.';

  @override
  String get aboutHoldInvoiceCltvExplanation =>
      'The CLTV delta (block count) used for hold invoices, controlling how long the HTLC can remain locked.';

  @override
  String get aboutInvoiceExpWindowExplanation =>
      'The time window in seconds within which the buyer must submit a Lightning invoice after the trade is initiated.';

  @override
  String get aboutProofOfWorkExplanation =>
      'The minimum proof-of-work difficulty required for Nostr events on this instance. 0 means no PoW is required.';

  @override
  String get aboutMaxOrdersPerResponseExplanation =>
      'The maximum number of orders returned in a single relay response. Limits bandwidth usage.';

  @override
  String get aboutLndVersionExplanation =>
      'The version of the LND (Lightning Network Daemon) node connected to this Mostro instance.';

  @override
  String get aboutLndNodePublicKeyExplanation =>
      'The public key of the LND node. Used to identify and verify the Lightning Network node.';

  @override
  String get aboutLndCommitExplanation =>
      'The Git commit hash of the LND build, identifying the exact software revision of the Lightning node.';

  @override
  String get aboutLndNodeAliasExplanation =>
      'The human-readable alias of the LND node as configured by the node operator.';

  @override
  String get aboutSupportedChainsExplanation =>
      'The blockchain(s) supported by the LND node (e.g. \'bitcoin\').';

  @override
  String get aboutSupportedNetworksExplanation =>
      'The network(s) the LND node operates on (e.g. \'mainnet\', \'testnet\').';

  @override
  String get aboutLndNodeUriExplanation =>
      'The connection URI of the LND node in the format pubkey@host:port. Used to open direct payment channels.';

  @override
  String get openDisputeFailed => 'Could not open dispute. Please try again.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Submit your Lightning invoice so the seller can lock the funds.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'Waiting for the buyer to submit their Lightning invoice.';

  @override
  String get tradeWaitingPaymentBuyerInstruction =>
      'The seller is paying the hold invoice. Please wait.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Pay the hold invoice to lock the funds and start the trade.';

  @override
  String get tradeLoadError => 'An error occurred while loading the trade.';

  @override
  String get tradeWaitingForHoldInvoice => 'Waiting for hold invoice...';

  @override
  String get payInvoiceInstruction =>
      'Pay this hold invoice to start the trade';

  @override
  String get shareButtonLabel => 'Share';

  @override
  String get shareFailed => 'Could not share the invoice';

  @override
  String get waitingForPaymentConfirmation =>
      'Waiting for payment confirmation...';

  @override
  String get payWithLightningWallet => 'Pay with Lightning wallet';

  @override
  String get noLightningWalletFound =>
      'No Lightning wallet found on this device';

  @override
  String get orderNoLongerActive => 'This order is no longer active';

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
  String get failedToConfirmBackupMessage =>
      'Failed to confirm backup. Please try again.';

  @override
  String get secretWordsInfoContent =>
      'Your 12 secret words are the only way to recover your account. Back them up in a safe place — never share them with anyone.';

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
      'These words will be hidden when you leave this screen';

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
  String get allWordsCorrectMessage => 'All 3 words correct!';

  @override
  String get showWordsAgainButton => 'Show words again';

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
  String get remindMeTomorrowButton => 'Remind me tomorrow';

  @override
  String get nwcConnectionFailedMessage =>
      'Connection failed. Please check your NWC URI and try again.';

  @override
  String get connectWalletDescription =>
      'Connect your Lightning wallet using a\nNostr Wallet Connect (NWC) URI.';

  @override
  String get nwcUriLabel => 'NWC URI';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'Clipboard does not contain a valid NWC URI.';

  @override
  String get scanQrButtonLabel => 'Scan QR';

  @override
  String get connectButtonLabel => 'Connect';

  @override
  String get walletConfigurationTitle => 'Wallet Configuration';

  @override
  String get walletDisconnectedMessage => 'Wallet disconnected';

  @override
  String get connectedBadgeLabel => 'Connected';

  @override
  String get balanceLabel => 'Balance';

  @override
  String get relayLabel => 'Relay';

  @override
  String get noWalletConnectedTitle => 'No wallet connected';

  @override
  String get connectWalletPrompt =>
      'Connect a wallet to enable automatic Lightning payments.';

  @override
  String get disconnectButtonLabel => 'Disconnect';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count more)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Choose which events trigger push notifications.';

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
  String get failedToResetNodeMessage => 'Failed to reset node';

  @override
  String get invalidPubkeyOrBridgeErrorMessage =>
      'Invalid pubkey or bridge error';

  @override
  String get currentNodePublicKeyLabel => 'Current node public key';

  @override
  String get useCustomNodePubkeyLabel => 'Use a custom node pubkey';

  @override
  String get enterHexPubkeyHint => 'Enter 64-char hex pubkey';

  @override
  String get shareLogsTooltip => 'Share logs';

  @override
  String get noLogsToShareTooltip => 'No logs to share';

  @override
  String get disableLoggingTooltip => 'Disable logging';

  @override
  String get enableLoggingTooltip => 'Enable logging';

  @override
  String get loggingEnabledStatus => 'Logging enabled';

  @override
  String get loggingDisabledStatus => 'Logging disabled';

  @override
  String get noLogEntriesMessage => 'No log entries';

  @override
  String get failedToShareLogsMessage => 'Failed to share logs';

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
  String get tradeStatusFilterPrefix => 'Status';

  @override
  String get noTradesTitle => 'No trades';

  @override
  String get noTradesSubtitle =>
      'Your active and completed trades will appear here.';

  @override
  String get couldNotLoadTradesMessage => 'Could not load trades';

  @override
  String get releaseBitcoinTitle => 'Release Bitcoin';

  @override
  String get releaseBitcoinConfirmation =>
      'Are you sure you want to release the Satoshis to the buyer?';

  @override
  String get yesButtonLabel => 'Yes';

  @override
  String get sellingBitcoin => 'Selling Bitcoin';

  @override
  String get buyingBitcoin => 'Buying Bitcoin';

  @override
  String get createdByYou => 'Created by you';

  @override
  String get takenByYou => 'Taken by you';

  @override
  String get timeAgoNow => 'now';

  @override
  String timeAgoMinutes(int count) {
    return '${count}m';
  }

  @override
  String timeAgoHours(int count) {
    return '${count}h';
  }

  @override
  String timeAgoDays(int count) {
    return '${count}d';
  }

  @override
  String get tradeStatusLoading => 'Loading';

  @override
  String get tradeStatusRate => 'Rate';

  @override
  String get tradeStatusRated => 'Rated';

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
  String get tradeInstructionPendingRating =>
      'The trade completed successfully. Rate your counterpart to help build trust in the community.';

  @override
  String get tradeInstructionRated => 'Thank you for your rating!';

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
  String get tradeHeadlineComplete => 'Trade complete!';

  @override
  String get tradeHeadlineCompleteRated => 'Trade complete';

  @override
  String get tradeHeadlineCancelled => 'Order cancelled';

  @override
  String get tradeHeadlineLoading => 'Loading trade…';

  @override
  String get tradeTimerPendingLabel =>
      'Time for this order to stay in the book';

  @override
  String get tradeTimerPendingConsequence =>
      'If it expires, the order is removed from the book. It won\'t affect your reputation.';

  @override
  String get tradeTimerWaitingInvoiceLabelBuyer => 'Time to share your invoice';

  @override
  String get tradeTimerWaitingInvoiceLabelSeller =>
      'Time for the buyer to share an invoice';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'If it expires, the trade is cancelled and the order returns to the book.';

  @override
  String get tradeTimerWaitingPaymentLabelBuyer =>
      'Time for the seller to lock the sats';

  @override
  String get tradeTimerWaitingPaymentLabelSeller =>
      'Time to pay the hold invoice';

  @override
  String get tradeTimerActiveLabelBuyer => 'Time to send the fiat payment';

  @override
  String get tradeTimerActiveLabelSeller =>
      'Time for the buyer to send the fiat';

  @override
  String get tradeTimerActiveConsequence =>
      'If it expires, the trade can be cancelled. Coordinate in the chat if more time is needed.';

  @override
  String get tradeTimerFiatSentLabelBuyer =>
      'Time for the seller to confirm receipt';

  @override
  String get tradeTimerFiatSentLabelSeller =>
      'Time to confirm receipt and release';

  @override
  String get tradeTimerFiatSentConsequence =>
      'If something looks wrong, open a dispute from the ⋮ menu.';

  @override
  String get tradeStepOrderTaken => 'Order taken';

  @override
  String get tradeStepInvoiceBuyer =>
      'You share an invoice · seller locks the sats';

  @override
  String get tradeStepInvoiceSeller =>
      'Buyer shares an invoice · you lock the sats';

  @override
  String get tradeStepFiatBuyer => 'You send the fiat payment';

  @override
  String get tradeStepFiatSeller => 'Buyer sends the fiat payment';

  @override
  String get tradeStepReleaseBuyer => 'Seller confirms and releases your sats';

  @override
  String get tradeStepReleaseSeller =>
      'You confirm receipt and release the sats';

  @override
  String get tradeStepRate => 'Rate your counterpart';

  @override
  String get activeTradeTitle => 'ACTIVE TRADE';

  @override
  String tradeIdShortLabel(String id) {
    return 'ID $id';
  }

  @override
  String tradeCreatedAtLabel(String date) {
    return 'created $date';
  }

  @override
  String get releaseSatsMenuItem => 'Release sats';

  @override
  String get cancelOrderMenuItem => 'Cancel order';

  @override
  String get openDisputeMenuItem => 'Open dispute';

  @override
  String get stepDoneLabel => 'DONE';

  @override
  String stepIndicator(int current, int total) {
    return 'STEP $current OF $total';
  }

  @override
  String get addLightningInvoiceButton => 'Add Lightning invoice';

  @override
  String get payHoldInvoiceButton => 'Pay hold invoice';

  @override
  String get markFiatSentButton => 'Mark fiat sent';

  @override
  String get confirmReleaseSatsButton => 'Confirm & release sats';

  @override
  String get viewDisputeButton => 'View dispute';

  @override
  String get waitingForBuyer => 'Waiting for the buyer…';

  @override
  String get waitingForSeller => 'Waiting for the seller…';

  @override
  String get waitingForFiatPayment => 'Waiting for the fiat payment…';

  @override
  String get waitingForCounterpart => 'Waiting for a counterpart…';

  @override
  String get yourTradeTimelineTitle => 'YOUR TRADE';

  @override
  String get yourCounterpartFallback => 'your counterpart';

  @override
  String secureChatUnread(int count) {
    return 'Secure chat · $count new';
  }

  @override
  String get secureChatEncrypted => 'Secure chat · end-to-end encrypted';

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
  String get activeTradeConversations => 'Your active trade conversations';

  @override
  String get noMessagesAvailable => 'No messages available';

  @override
  String get disputesAndAdminChat => 'Disputes and admin chat';

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
  String sellingSatsTo(String handle) {
    return 'You are selling sats to $handle';
  }

  @override
  String buyingSatsFrom(String handle) {
    return 'You are buying sats from $handle';
  }

  @override
  String youMessagePrefix(String message) {
    return 'You: $message';
  }

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
  String get enterLightningInvoiceInstruction =>
      'Enter a Lightning Invoice to receive your sats';

  @override
  String get lightningInvoiceLabel => 'Lightning Invoice';

  @override
  String get submitButton => 'Submit';

  @override
  String get sellOrderDetailsTitle => 'SELL ORDER DETAILS';

  @override
  String get buyOrderDetailsTitle => 'BUY ORDER DETAILS';

  @override
  String get buyTheseSatsButton => 'BUY THESE SATS';

  @override
  String get sellSatsButton => 'SELL SATS';

  @override
  String get someoneSellingSats => 'Someone is selling sats';

  @override
  String get someoneBuyingSats => 'Someone is buying sats';

  @override
  String get takeOrderForPrefix => 'for ';

  @override
  String get takeOrderAtMarketPrice => ' at market price';

  @override
  String premiumLabel(String premium) {
    return 'Premium: $premium%';
  }

  @override
  String get creatorReputation => 'Creator reputation';

  @override
  String get ratingStatLabel => 'rating';

  @override
  String get tradesStatLabel => 'trades';

  @override
  String get daysActiveStatLabel => 'days active';

  @override
  String get timeToTakeOrder => 'TIME TO TAKE THIS ORDER';

  @override
  String get orderExpiryRemovedNote =>
      'If it expires, the order is removed from the book. ';

  @override
  String get orderExpiryNoReputationNote => 'It won\'t affect your reputation.';

  @override
  String get minHint => 'Min';

  @override
  String get maxHint => 'Max';

  @override
  String get fiatAmountHint => 'Fiat amount';

  @override
  String get enterAmountForPreview => 'Enter an amount to see a live preview.';

  @override
  String get previewLabel => 'PREVIEW';

  @override
  String previewBuyMarket(String amount, String price) {
    return 'You buy BTC for *$amount* at *$price* · live for *24 h*';
  }

  @override
  String previewSellMarket(String amount, String price) {
    return 'You sell BTC for *$amount* at *$price* · live for *24 h*';
  }

  @override
  String previewReceiveFixed(String sats, String amount) {
    return 'You receive *$sats sats* for *$amount* · live for *24 h*';
  }

  @override
  String previewSellFixed(String sats, String amount) {
    return 'You sell *$sats sats* for *$amount* · live for *24 h*';
  }

  @override
  String get marketPriceLabel => 'market price';

  @override
  String marketPricePremium(String premium) {
    return 'market $premium%';
  }

  @override
  String get priceTypeLabel => 'Price Type';

  @override
  String get priceTypeMarket => 'Market';

  @override
  String get priceTypeFixed => 'Fixed';

  @override
  String get priceTypeInfoTooltip => 'Price type info';

  @override
  String get premiumSectionLabel => 'Premium';

  @override
  String get amountInSatsHint => 'Amount in sats';

  @override
  String get priceTypesDialogTitle => 'Price Types';

  @override
  String get priceTypesDialogContent =>
      'Market Price: Your order price follows the market rate with a premium/discount percentage applied.\n\nFixed Price: You set an exact price in satoshis.';

  @override
  String get startFromPreset => 'START FROM A PRESET';

  @override
  String get presetExpressTitle => 'Express';

  @override
  String get recommendedTag => 'RECOMMENDED';

  @override
  String get presetConservativeTitle => 'Conservative';

  @override
  String get presetConservativeSubtitle =>
      'Market price · 0% premium · you choose amount & methods';

  @override
  String get presetCustomTitle => 'Custom';

  @override
  String get presetCustomSubtitle =>
      'All fields — amount, range, methods, premium, fixed or market price';

  @override
  String expressPresetSubtitle(String details) {
    return 'Same as your last successful order — $details';
  }

  @override
  String expressPremiumSuffix(String premium) {
    return '$premium% premium';
  }

  @override
  String get paymentMethodsLabel => 'Payment Methods';

  @override
  String get addPaymentMethod => 'Add payment method';

  @override
  String get customPaymentMethodHint => 'Custom payment method...';

  @override
  String get customMethodAppendedNote =>
      'Custom method will be appended to selection';

  @override
  String get selectPaymentMethodsTitle => 'Select Payment Methods';

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
  String get buyLabel => 'Buy';

  @override
  String get sellLabel => 'Sell';

  @override
  String get unableToOpenNotification => 'Unable to open notification details.';

  @override
  String get reasonBestPremium => '⚡ Best premium';

  @override
  String get reasonMostReputable => '⭐ Most reputable';

  @override
  String get reasonJustPublished => '🆕 Just published';

  @override
  String get marketPriceCaption => 'Market price';

  @override
  String orderReputationStats(int trades, int days) {
    return ' · $trades trades · $days days';
  }

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
  String marketPricePremiumLabel(String premium) {
    return 'Market Price ($premium%)';
  }

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
  String get lightningInvoiceQrLabel => 'Lightning invoice QR code';
}
