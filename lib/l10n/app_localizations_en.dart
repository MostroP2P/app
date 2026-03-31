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
    return '$count offers';
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
  String get selectLanguageTitle => 'Select Language';

  @override
  String get selectCurrencyDialogTitle => 'Select Currency';

  @override
  String get addRelayDialogTitle => 'Add Relay';

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
}
