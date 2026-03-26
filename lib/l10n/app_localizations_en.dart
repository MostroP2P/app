// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Mostro';

  @override
  String get loading => 'Loading…';

  @override
  String get errorUnknown => 'Something went wrong. Please try again.';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get done => 'Done';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String get copyToClipboard => 'Copy';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get offlineBanner => 'You are offline — showing cached data';

  @override
  String get onboardingWelcomeTitle => 'Welcome to Mostro';

  @override
  String get onboardingWelcomeSubtitle =>
      'Peer-to-peer bitcoin trading over Nostr';

  @override
  String get onboardingCreateIdentity => 'Create New Identity';

  @override
  String get onboardingImportIdentity => 'Import Existing Identity';

  @override
  String get createIdentityTitle => 'Your Recovery Phrase';

  @override
  String get createIdentityInstruction =>
      'Write down these 12 words in order and keep them safe. Anyone with these words can access your identity.';

  @override
  String get createIdentityConfirmCheckbox =>
      'I have safely saved my recovery phrase';

  @override
  String get createIdentityCta => 'I\'ve Saved My Phrase';

  @override
  String get importIdentityTitle => 'Import Identity';

  @override
  String get importIdentityMnemonicLabel => 'Recovery Phrase (12 or 24 words)';

  @override
  String get importIdentityNsecLabel => 'Private Key (nsec…)';

  @override
  String get importIdentityInvalidMnemonic =>
      'Invalid recovery phrase — check spelling';

  @override
  String get importIdentityInvalidNsec => 'Invalid private key format';

  @override
  String get importIdentityCta => 'Import';

  @override
  String get pinSetupTitle => 'Set a PIN';

  @override
  String get pinSetupSubtitle => 'Protect your identity with a 4–8 digit PIN';

  @override
  String get pinSetupEnterPin => 'Enter PIN';

  @override
  String get pinSetupConfirmPin => 'Confirm PIN';

  @override
  String get pinSetupMismatch => 'PINs do not match';

  @override
  String get pinSetupEnableBiometric => 'Also enable biometric unlock';

  @override
  String get pinSetupSkip => 'Skip (not recommended)';

  @override
  String get homeTitle => 'Orders';

  @override
  String get homeFilterAll => 'All';

  @override
  String get homeFilterBuy => 'Buy';

  @override
  String get homeFilterSell => 'Sell';

  @override
  String get homeNoOrders => 'No orders found';

  @override
  String get homeSearchPaymentMethod => 'Payment method';

  @override
  String get orderDetailTitle => 'Order Details';

  @override
  String get orderDetailTakeOrder => 'Take Order';

  @override
  String get orderDetailAlreadyInTrade => 'You already have an active trade';

  @override
  String get orderKindBuy => 'Buy';

  @override
  String get orderKindSell => 'Sell';

  @override
  String orderAmount(String amount, String currency) {
    return '$amount $currency';
  }

  @override
  String orderAmountRange(String min, String max, String currency) {
    return '$min–$max $currency';
  }

  @override
  String orderPremium(String premium) {
    return '$premium% premium';
  }

  @override
  String get tradeTitle => 'Active Trade';

  @override
  String get tradeFiatSent => 'I Sent the Fiat';

  @override
  String get tradeRelease => 'Release Bitcoin';

  @override
  String get tradeCancel => 'Cancel Trade';

  @override
  String get tradeDispute => 'Open Dispute';

  @override
  String get tradeAddInvoice => 'Add Lightning Invoice';

  @override
  String tradeTimeout(String time) {
    return 'Trade expires in $time';
  }

  @override
  String get chatInputHint => 'Message…';

  @override
  String get chatSend => 'Send';

  @override
  String get disputeTitle => 'Dispute';

  @override
  String get historyTitle => 'Trade History';

  @override
  String get historyNoTrades => 'No completed trades yet';

  @override
  String get historyOutcomeSuccess => 'Completed';

  @override
  String get historyOutcomeCanceled => 'Canceled';

  @override
  String get historyOutcomeDisputed => 'Disputed';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsRelays => 'Relays';

  @override
  String get settingsWallet => 'Lightning Wallet';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsPrivacyMode => 'Privacy Mode';

  @override
  String get relayStatusConnected => 'Connected';

  @override
  String get relayStatusConnecting => 'Connecting…';

  @override
  String get relayStatusDisconnected => 'Disconnected';

  @override
  String get relayStatusError => 'Connection error';

  @override
  String get walletConnectCta => 'Connect Wallet';

  @override
  String get walletNwcUriLabel =>
      'Wallet connect URI (nostr+walletconnect://…)';

  @override
  String get walletNwcUriInvalid => 'Invalid wallet connect URI';

  @override
  String get rateCounterparty => 'Rate your trade partner';

  @override
  String get rateSubmit => 'Submit Rating';

  @override
  String get aboutTitle => 'About Mostro';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get sharedOrderTitle => 'Shared Order';

  @override
  String get qrScanTitle => 'Scan QR Code';

  @override
  String get qrScanPermissionDenied =>
      'Camera permission is required to scan QR codes';

  @override
  String get attachmentPickerTitle => 'Add Attachment';

  @override
  String get attachmentUploadFailed => 'Upload failed — try again';

  @override
  String get pinUnlockTitle => 'Enter PIN to unlock';

  @override
  String get pinUnlockWrong => 'Incorrect PIN';

  @override
  String get pinUnlockBiometric => 'Use biometrics';

  @override
  String get recoveryTitle => 'Recover Session';

  @override
  String get recoveryInstruction =>
      'Enter your recovery phrase to restore your identity';
}
