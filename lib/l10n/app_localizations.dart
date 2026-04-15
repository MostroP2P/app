import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'Mostro'**
  String get appName;

  /// Generic loading label
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// Generic error label
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Confirm action
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Done action
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Skip action
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// Timestamp label for messages from yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get chatTimestampYesterday;

  /// Empty state message on the disputes list screen
  ///
  /// In en, this message translates to:
  /// **'Your disputes will appear here'**
  String get disputesEmptyState;

  /// Tooltip for the attach file button in dispute chat
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get disputeAttachFile;

  /// Hint text for the dispute chat message input field
  ///
  /// In en, this message translates to:
  /// **'Write a message…'**
  String get disputeWriteMessageHint;

  /// Tooltip for the send button in dispute chat
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get disputeSend;

  /// Title label for a dispute list item
  ///
  /// In en, this message translates to:
  /// **'Order dispute'**
  String get orderDispute;

  /// Banner shown when an admin is assigned but no messages exist yet
  ///
  /// In en, this message translates to:
  /// **'An administrator has been assigned to your dispute. They will contact you here shortly.'**
  String get disputeAdminAssigned;

  /// Lock banner shown when the dispute is resolved
  ///
  /// In en, this message translates to:
  /// **'This dispute has been resolved. The chat is closed.'**
  String get disputeChatClosed;

  /// Snackbar text after copying a chat message to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get messageCopied;

  /// Error message shown when disputes fail to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load disputes. Please try again.'**
  String get disputeLoadError;

  /// Snackbar shown when user tries to send a dispute message
  ///
  /// In en, this message translates to:
  /// **'Dispute messaging coming soon'**
  String get disputeMessagingComingSoon;

  /// Snackbar shown when user tries to attach a file in dispute chat
  ///
  /// In en, this message translates to:
  /// **'File attachments coming soon'**
  String get disputeAttachmentsComingSoon;

  /// Body text shown when a dispute cannot be found by ID
  ///
  /// In en, this message translates to:
  /// **'Dispute not found.'**
  String get disputeNotFound;

  /// Snackbar shown when no dispute exists for the current trade
  ///
  /// In en, this message translates to:
  /// **'Dispute not found for this order.'**
  String get disputeNotFoundForOrder;

  /// Badge label shown on a resolved dispute banner
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get disputeResolved;

  /// Heading shown when the viewing party won the dispute
  ///
  /// In en, this message translates to:
  /// **'Successfully completed'**
  String get disputeSuccessfullyCompleted;

  /// Body text in the cooperative-cancel resolved banner
  ///
  /// In en, this message translates to:
  /// **'The order was cooperatively cancelled. No funds were transferred.'**
  String get disputeCoopCancelMessage;

  /// Dispute chat screen title when trading as seller (peer is the buyer)
  ///
  /// In en, this message translates to:
  /// **'Dispute with Buyer: {handle}'**
  String disputeWithBuyer(String handle);

  /// Dispute chat screen title when trading as buyer (peer is the seller)
  ///
  /// In en, this message translates to:
  /// **'Dispute with Seller: {handle}'**
  String disputeWithSeller(String handle);

  /// Sub-title showing the truncated order/trade ID
  ///
  /// In en, this message translates to:
  /// **'Order {orderId}'**
  String orderLabel(String orderId);

  /// Status chip label for a newly opened dispute
  ///
  /// In en, this message translates to:
  /// **'Initiated'**
  String get disputeInitiated;

  /// Status chip label for a dispute under admin review
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get disputeInProgress;

  /// Status chip label for a resolved/closed dispute
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get disputeStatusClosed;

  /// Resolution text shown to the seller when admin released funds to the buyer
  ///
  /// In en, this message translates to:
  /// **'The administrator settled the dispute in the buyer\'s favour. The sats were released to the buyer.'**
  String get disputeLostFundsToBuyer;

  /// Resolution text shown to the buyer when admin returned funds to the seller
  ///
  /// In en, this message translates to:
  /// **'The administrator canceled the order and returned the sats to the seller. You did not receive the sats.'**
  String get disputeLostFundsToSeller;

  /// Title for walkthrough slide 1
  ///
  /// In en, this message translates to:
  /// **'Trade Bitcoin freely — no KYC'**
  String get walkthroughSlideOneTitle;

  /// Body text for walkthrough slide 1
  ///
  /// In en, this message translates to:
  /// **'Mostro is a peer-to-peer exchange that lets you trade Bitcoin for any currency and payment method — no KYC, and no need to give your data to anyone. It\'s built on Nostr, which makes it censorship-resistant. No one can stop you from trading.'**
  String get walkthroughSlideOneBody;

  /// Title for walkthrough slide 2
  ///
  /// In en, this message translates to:
  /// **'Privacy by default'**
  String get walkthroughSlideTwoTitle;

  /// Body text for walkthrough slide 2
  ///
  /// In en, this message translates to:
  /// **'Mostro generates a new identity for every exchange, so your trades can\'t be linked. You can also decide how private you want to be:\n• Reputation mode – Lets others see your successful trades and trust level.\n• Full privacy mode – No reputation is built, but your activity is completely anonymous.\nSwitch modes anytime from the Account screen, where you should also save your secret words — they\'re the only way to recover your account.'**
  String get walkthroughSlideTwoBody;

  /// Title for walkthrough slide 3
  ///
  /// In en, this message translates to:
  /// **'Security at every step'**
  String get walkthroughSlideThreeTitle;

  /// Body text for walkthrough slide 3
  ///
  /// In en, this message translates to:
  /// **'Mostro uses Hold Invoices: sats stay in the seller\'s wallet until the end of the trade. This protects both sides. The app is also designed to be intuitive and easy for all kinds of users.'**
  String get walkthroughSlideThreeBody;

  /// Title for walkthrough slide 4
  ///
  /// In en, this message translates to:
  /// **'Fully encrypted chat'**
  String get walkthroughSlideFourTitle;

  /// Body text for walkthrough slide 4
  ///
  /// In en, this message translates to:
  /// **'Each trade has its own private chat, end-to-end encrypted. Only the two users involved can read it. In case of a dispute, you can give the shared key to an admin to help resolve the issue.'**
  String get walkthroughSlideFourBody;

  /// Title for walkthrough slide 5
  ///
  /// In en, this message translates to:
  /// **'Take an offer'**
  String get walkthroughSlideFiveTitle;

  /// Body text for walkthrough slide 5
  ///
  /// In en, this message translates to:
  /// **'Browse the order book, choose an offer that works for you, and follow the trade flow step by step. You\'ll be able to check the other user\'s profile, chat securely, and complete the trade with ease.'**
  String get walkthroughSlideFiveBody;

  /// Title for walkthrough slide 6
  ///
  /// In en, this message translates to:
  /// **'Can\'t find what you need?'**
  String get walkthroughSlideSixTitle;

  /// Body text for walkthrough slide 6
  ///
  /// In en, this message translates to:
  /// **'You can also create your own offer and wait for someone to take it. Set the amount and preferred payment method — Mostro handles the rest.'**
  String get walkthroughSlideSixBody;

  /// Tab label for the buy Bitcoin order book
  ///
  /// In en, this message translates to:
  /// **'BUY BTC'**
  String get tabBuyBtc;

  /// Tab label for the sell Bitcoin order book
  ///
  /// In en, this message translates to:
  /// **'SELL BTC'**
  String get tabSellBtc;

  /// Button label to open order book filter options
  ///
  /// In en, this message translates to:
  /// **'FILTER'**
  String get filterButtonLabel;

  /// Number of offers shown in the order book
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 offer} other{{count} offers}}'**
  String offersCount(int count);

  /// Empty state message when the order book has no orders
  ///
  /// In en, this message translates to:
  /// **'No orders available'**
  String get noOrdersAvailable;

  /// Timestamp label for a very recent event
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// Relative timestamp in minutes
  ///
  /// In en, this message translates to:
  /// **'{m}m ago'**
  String minutesAgo(int m);

  /// Relative timestamp in hours
  ///
  /// In en, this message translates to:
  /// **'{h}h ago'**
  String hoursAgo(int h);

  /// Relative timestamp in days
  ///
  /// In en, this message translates to:
  /// **'{d}d ago'**
  String daysAgo(int d);

  /// Screen title when the user is creating a new order
  ///
  /// In en, this message translates to:
  /// **'CREATING NEW ORDER'**
  String get creatingNewOrderTitle;

  /// Label shown when the order type is buy
  ///
  /// In en, this message translates to:
  /// **'You want to buy Bitcoin'**
  String get youWantToBuyBitcoin;

  /// Label shown when the order type is sell
  ///
  /// In en, this message translates to:
  /// **'You want to sell Bitcoin'**
  String get youWantToSellBitcoin;

  /// Label for a range-amount order toggle
  ///
  /// In en, this message translates to:
  /// **'Range order'**
  String get rangeOrderLabel;

  /// Screen title for the pay Lightning invoice step
  ///
  /// In en, this message translates to:
  /// **'Pay Lightning Invoice'**
  String get payLightningInvoiceTitle;

  /// Snackbar shown after copying a Lightning invoice to clipboard
  ///
  /// In en, this message translates to:
  /// **'Invoice copied'**
  String get invoiceCopied;

  /// Screen title for adding a Lightning invoice
  ///
  /// In en, this message translates to:
  /// **'Add Invoice'**
  String get addInvoiceTitle;

  /// Generic submit button label
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submitButtonLabel;

  /// Error message when attempting to take an already-taken order
  ///
  /// In en, this message translates to:
  /// **'Order has already been taken'**
  String get orderAlreadyTaken;

  /// Snackbar shown after copying an order ID to clipboard
  ///
  /// In en, this message translates to:
  /// **'Order ID copied'**
  String get orderIdCopied;

  /// Screen title for the order/trade details screen
  ///
  /// In en, this message translates to:
  /// **'ORDER DETAILS'**
  String get orderDetailsTitle;

  /// Label preceding the countdown timer in a trade
  ///
  /// In en, this message translates to:
  /// **'Time remaining:'**
  String get timeRemainingLabel;

  /// Button label for the buyer to confirm fiat was sent
  ///
  /// In en, this message translates to:
  /// **'FIAT SENT'**
  String get fiatSentButtonLabel;

  /// Button label to open a dispute for a trade
  ///
  /// In en, this message translates to:
  /// **'DISPUTE'**
  String get disputeButtonLabel;

  /// Button label to open the trade chat
  ///
  /// In en, this message translates to:
  /// **'CONTACT'**
  String get contactButtonLabel;

  /// Button label to rate the trading counterpart
  ///
  /// In en, this message translates to:
  /// **'RATE'**
  String get rateButtonLabel;

  /// Button label to view an active dispute
  ///
  /// In en, this message translates to:
  /// **'VIEW DISPUTE'**
  String get viewDisputeButtonLabel;

  /// Generic coming-soon placeholder message
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoonMessage;

  /// Trade status chip label: active
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get tradeStatusActive;

  /// Trade status chip label: fiat sent
  ///
  /// In en, this message translates to:
  /// **'Fiat Sent'**
  String get tradeStatusFiatSent;

  /// Trade status chip label: completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get tradeStatusCompleted;

  /// Trade status chip label: cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get tradeStatusCancelled;

  /// Trade status chip label: disputed
  ///
  /// In en, this message translates to:
  /// **'Disputed'**
  String get tradeStatusDisputed;

  /// Button label for the seller to release sats
  ///
  /// In en, this message translates to:
  /// **'RELEASE'**
  String get releaseButtonLabel;

  /// Screen title for the Account screen
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountScreenTitle;

  /// Section title for the mnemonic backup card
  ///
  /// In en, this message translates to:
  /// **'Secret Words'**
  String get secretWordsTitle;

  /// Subtitle under the secret words section heading
  ///
  /// In en, this message translates to:
  /// **'To restore your account'**
  String get toRestoreYourAccount;

  /// Section title for the privacy settings card
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyCardTitle;

  /// Subtitle under the privacy section heading
  ///
  /// In en, this message translates to:
  /// **'Control your privacy settings'**
  String get controlPrivacySettings;

  /// Label for reputation privacy mode option
  ///
  /// In en, this message translates to:
  /// **'Reputation Mode'**
  String get reputationMode;

  /// Subtitle for reputation mode option
  ///
  /// In en, this message translates to:
  /// **'Standard privacy with reputation'**
  String get reputationModeSubtitle;

  /// Label for full privacy mode option
  ///
  /// In en, this message translates to:
  /// **'Full Privacy Mode'**
  String get fullPrivacyMode;

  /// Subtitle for full privacy mode option
  ///
  /// In en, this message translates to:
  /// **'Maximum anonymity'**
  String get fullPrivacyModeSubtitle;

  /// Button label to generate a new Mostro identity
  ///
  /// In en, this message translates to:
  /// **'Generate New User'**
  String get generateNewUserButton;

  /// Button label to import an existing Mostro identity via mnemonic
  ///
  /// In en, this message translates to:
  /// **'Import Mostro User'**
  String get importMostroUserButton;

  /// Confirmation dialog title for generating a new user
  ///
  /// In en, this message translates to:
  /// **'Generate New User?'**
  String get generateNewUserDialogTitle;

  /// Confirmation dialog body for generating a new user
  ///
  /// In en, this message translates to:
  /// **'This will create a brand-new identity. Your current secret words will no longer work — make sure they are backed up before continuing.'**
  String get generateNewUserDialogContent;

  /// Continue button label
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButtonLabel;

  /// Dialog title for importing a mnemonic phrase
  ///
  /// In en, this message translates to:
  /// **'Import Mnemonic'**
  String get importMnemonicDialogTitle;

  /// Hint text in the mnemonic import text field
  ///
  /// In en, this message translates to:
  /// **'Enter your 12 or 24 word phrase…'**
  String get importMnemonicHintText;

  /// Button label to confirm mnemonic import
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importButtonLabel;

  /// Dialog title for refreshing user data
  ///
  /// In en, this message translates to:
  /// **'Refresh User?'**
  String get refreshUserDialogTitle;

  /// Dialog body for refreshing user data
  ///
  /// In en, this message translates to:
  /// **'This will re-fetch your trades and orders from the Mostro instance. Use this if you think your data is out of sync or orders are missing.'**
  String get refreshUserDialogContent;

  /// Button label to hide sensitive information
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideButtonLabel;

  /// Button label to reveal sensitive information
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showButtonLabel;

  /// Screen title for the Settings screen
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsScreenTitle;

  /// Settings list item title for language selection
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettingTitle;

  /// Settings list item title for appearance/theme
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSettingTitle;

  /// Dialog title for the appearance/theme picker
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceDialogTitle;

  /// Settings list item title for default fiat currency
  ///
  /// In en, this message translates to:
  /// **'Default Fiat Currency'**
  String get defaultFiatCurrencyTitle;

  /// Option label meaning no currency filter is applied
  ///
  /// In en, this message translates to:
  /// **'All currencies'**
  String get allCurrencies;

  /// Settings list item title for the user's Lightning address
  ///
  /// In en, this message translates to:
  /// **'Lightning Address'**
  String get lightningAddressSettingTitle;

  /// Subtitle shown when a settings value is not yet configured
  ///
  /// In en, this message translates to:
  /// **'Tap to set'**
  String get tapToSetSubtitle;

  /// Settings list item title for NWC wallet connection
  ///
  /// In en, this message translates to:
  /// **'NWC Wallet'**
  String get nwcWalletSettingTitle;

  /// Subtitle prompting the user to connect a wallet via Nostr Wallet Connect
  ///
  /// In en, this message translates to:
  /// **'Connect your Lightning wallet via NWC'**
  String get nwcConnectPrompt;

  /// Settings list item title for Nostr relay management
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get relaysSettingTitle;

  /// Subtitle for the relays settings entry
  ///
  /// In en, this message translates to:
  /// **'Manage relay connections'**
  String get manageRelayConnections;

  /// Settings list item title for push notification preferences
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotificationsSettingTitle;

  /// Subtitle for the push notifications settings entry
  ///
  /// In en, this message translates to:
  /// **'Manage notification preferences'**
  String get manageNotificationPreferences;

  /// Settings list item title for viewing diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'Log Report'**
  String get logReportSettingTitle;

  /// Subtitle for the log report settings entry
  ///
  /// In en, this message translates to:
  /// **'View diagnostic logs'**
  String get viewDiagnosticLogs;

  /// Settings list item title for the Mostro node configuration
  ///
  /// In en, this message translates to:
  /// **'Mostro Node'**
  String get mostroNodeSettingTitle;

  /// Theme option: dark mode
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Theme option: light mode
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Theme option: follow system setting
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystemDefault;

  /// Dialog title for editing the Lightning address
  ///
  /// In en, this message translates to:
  /// **'Lightning Address'**
  String get lightningAddressDialogTitle;

  /// Placeholder text in the Lightning address input field
  ///
  /// In en, this message translates to:
  /// **'user@domain.com'**
  String get lightningAddressHintText;

  /// Validation error for an invalid Lightning address format
  ///
  /// In en, this message translates to:
  /// **'Must be in user@domain format'**
  String get invalidLightningAddressFormat;

  /// Button label to clear a field or value
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearButtonLabel;

  /// Button label to save a settings value
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButtonLabel;

  /// Screen or dialog title for the NWC wallet connection flow
  ///
  /// In en, this message translates to:
  /// **'Connect Wallet'**
  String get connectWalletTitle;

  /// Screen title for the QR code scanner
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCodeTitle;

  /// Hint text for the NWC URI input field / QR scanner fallback
  ///
  /// In en, this message translates to:
  /// **'Paste NWC URI'**
  String get pasteNwcUri;

  /// Dialog or screen title for the language picker
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguageTitle;

  /// Dialog title for the currency picker
  ///
  /// In en, this message translates to:
  /// **'Select Currency'**
  String get selectCurrencyDialogTitle;

  /// Dialog title for adding a new Nostr relay
  ///
  /// In en, this message translates to:
  /// **'Add Relay'**
  String get addRelayDialogTitle;

  /// Generic add action button label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addButtonLabel;

  /// Placeholder hint in the add-relay URL field
  ///
  /// In en, this message translates to:
  /// **'wss://relay.example.com'**
  String get relayHintText;

  /// Validation error when relay URL does not start with wss://
  ///
  /// In en, this message translates to:
  /// **'Must start with wss://'**
  String get relayErrorMustStartWithWss;

  /// Validation error when relay URL is too short
  ///
  /// In en, this message translates to:
  /// **'URL is too short'**
  String get relayErrorUrlTooShort;

  /// Validation error when relay URL is already added
  ///
  /// In en, this message translates to:
  /// **'Relay already in list'**
  String get relayErrorDuplicate;

  /// NWC wallet connected status with balance
  ///
  /// In en, this message translates to:
  /// **'NWC — Connected. Balance: {balance}'**
  String nwcConnectedBalance(String balance);

  /// Heading text on the web QR code paste fallback screen
  ///
  /// In en, this message translates to:
  /// **'Paste QR Code Content'**
  String get pasteQrCodeHeading;

  /// Button label for paste-from-clipboard action
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get pasteButtonLabel;

  /// Error shown when clipboard has no text to paste
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get clipboardEmptyError;

  /// Validation error when QR input field is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter a value'**
  String get enterValueError;

  /// Default hint text for the QR scanner widget
  ///
  /// In en, this message translates to:
  /// **'Paste or scan a QR code'**
  String get pasteOrScanQrCode;

  /// Section title on the Mostro node settings screen
  ///
  /// In en, this message translates to:
  /// **'Mostro Node'**
  String get mostroNodeTitle;

  /// Label for the currently active Mostro node
  ///
  /// In en, this message translates to:
  /// **'Current Node'**
  String get currentNodeLabel;

  /// Badge shown on a verified/trusted Mostro node
  ///
  /// In en, this message translates to:
  /// **'Trusted'**
  String get trustedBadgeLabel;

  /// Button label to reset to the default Mostro node
  ///
  /// In en, this message translates to:
  /// **'Use Default'**
  String get useDefaultButtonLabel;

  /// Button label to confirm a selection or action
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmButtonLabel;

  /// Validation error for an invalid hex pubkey input
  ///
  /// In en, this message translates to:
  /// **'Must be a 64-character hex string'**
  String get invalidHexPubkey;

  /// Screen title for the Notifications screen
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsScreenTitle;

  /// Menu item to mark all notifications as read
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllAsReadMenuItem;

  /// Menu item to delete all notifications
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAllMenuItem;

  /// Notification title prompting the user to back up their account
  ///
  /// In en, this message translates to:
  /// **'You must back up your account'**
  String get youMustBackUpYourAccount;

  /// Notification body prompting the user to view and save secret words
  ///
  /// In en, this message translates to:
  /// **'Tap to view and save your secret words.'**
  String get tapToViewAndSaveSecretWords;

  /// Empty state message on the notifications screen
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// Contextual action to mark a single notification as read
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markAsRead;

  /// Contextual action to delete a single notification
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteNotificationLabel;

  /// Header label on the post-trade rating screen
  ///
  /// In en, this message translates to:
  /// **'RATE'**
  String get rateScreenHeader;

  /// Label shown for a completed order on the rating screen
  ///
  /// In en, this message translates to:
  /// **'Successful order'**
  String get successfulOrder;

  /// Button label to submit a trade rating
  ///
  /// In en, this message translates to:
  /// **'SUBMIT'**
  String get submitRatingButton;

  /// Button label to close the rating screen without rating
  ///
  /// In en, this message translates to:
  /// **'CLOSE'**
  String get closeRatingButton;

  /// Screen title for the About screen
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutScreenTitle;

  /// App tagline shown on the About screen
  ///
  /// In en, this message translates to:
  /// **'Peer-to-peer Bitcoin trading over Nostr'**
  String get mostroTagline;

  /// Button label to open the Mostro documentation
  ///
  /// In en, this message translates to:
  /// **'View Documentation'**
  String get viewDocumentationButton;

  /// Snackbar shown after copying a link to clipboard
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopiedToClipboard;

  /// Section heading for the default Mostro node info
  ///
  /// In en, this message translates to:
  /// **'Default Node'**
  String get defaultNodeSection;

  /// Label for a Nostr public key
  ///
  /// In en, this message translates to:
  /// **'Pubkey'**
  String get pubkeyLabel;

  /// Label for the list of Nostr relays
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get relaysLabel;

  /// Snackbar shown after copying a pubkey to clipboard
  ///
  /// In en, this message translates to:
  /// **'Pubkey copied to clipboard'**
  String get pubkeyCopiedToClipboard;

  /// Footer tagline on the About screen
  ///
  /// In en, this message translates to:
  /// **'Open-source. Non-custodial. Private.'**
  String get footerTagline;

  /// Title shown at the top of the navigation drawer
  ///
  /// In en, this message translates to:
  /// **'MOSTRO'**
  String get drawerTitle;

  /// Badge label indicating the app is in beta
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get betaBadgeLabel;

  /// Drawer menu item navigating to the Account screen
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get drawerAccountMenuItem;

  /// Drawer menu item navigating to the Settings screen
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get drawerSettingsMenuItem;

  /// Drawer menu item navigating to the About screen
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get drawerAboutMenuItem;

  /// Bottom navigation label for the Order Book tab
  ///
  /// In en, this message translates to:
  /// **'Order Book'**
  String get navOrderBook;

  /// Bottom navigation label for the My Trades tab
  ///
  /// In en, this message translates to:
  /// **'My Trades'**
  String get navMyTrades;

  /// Bottom navigation label for the Chat tab
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get navChat;

  /// Accessibility label for the order book shimmer skeleton (DESIGN_SYSTEM §9.1)
  ///
  /// In en, this message translates to:
  /// **'Loading orders…'**
  String get loadingOrders;

  /// Error message shown when the order book fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load orders. Please check your connection.'**
  String get errorLoadingOrders;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Accessibility label for the toggle that disables a relay
  ///
  /// In en, this message translates to:
  /// **'Disable relay {url}'**
  String disableRelayLabel(String url);

  /// Accessibility label for the toggle that enables a relay
  ///
  /// In en, this message translates to:
  /// **'Enable relay {url}'**
  String enableRelayLabel(String url);

  /// Tooltip for the remove-relay icon button
  ///
  /// In en, this message translates to:
  /// **'Remove relay'**
  String get removeRelayTooltip;

  /// SnackBar message shown when adding a relay fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add relay'**
  String get relayAddFailed;

  /// SnackBar message shown when removing a relay fails
  ///
  /// In en, this message translates to:
  /// **'Failed to remove relay'**
  String get relayRemoveFailed;

  /// Label for the backup confirmation checkbox on the Account screen
  ///
  /// In en, this message translates to:
  /// **'I have written down my words and backed them up securely'**
  String get backupConfirmCheckbox;

  /// Title for the cancel-trade confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel trade?'**
  String get cancelTradeDialogTitle;

  /// Body text for the cancel-trade confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Requesting a cooperative cancel. The other party must also agree for the trade to be fully cancelled.'**
  String get cancelTradeDialogContent;

  /// Negative button label in a confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get noButtonLabel;

  /// Affirmative cancel button label in the cancel-trade dialog
  ///
  /// In en, this message translates to:
  /// **'Yes, cancel'**
  String get yesCancelButtonLabel;

  /// Snackbar shown after a cooperative cancel request is sent
  ///
  /// In en, this message translates to:
  /// **'Cancel request sent'**
  String get cancelRequestSent;

  /// Snackbar shown when the cancel request fails
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel. Please try again.'**
  String get cancelRequestFailed;

  /// Snackbar shown when the fiat-sent action fails
  ///
  /// In en, this message translates to:
  /// **'Failed to mark fiat as sent. Please try again.'**
  String get fiatSentFailed;

  /// Snackbar shown when the release-sats action fails
  ///
  /// In en, this message translates to:
  /// **'Failed to release. Please try again.'**
  String get releaseFailed;

  /// Order card pill label when the current user is the maker of a sell order
  ///
  /// In en, this message translates to:
  /// **'YOU ARE SELLING'**
  String get orderPillYouAreSelling;

  /// Order card pill label when the current user is the maker of a buy order
  ///
  /// In en, this message translates to:
  /// **'YOU ARE BUYING'**
  String get orderPillYouAreBuying;

  /// Order card pill label for another user's sell order
  ///
  /// In en, this message translates to:
  /// **'SELLING'**
  String get orderPillSelling;

  /// Order card pill label for another user's buy order
  ///
  /// In en, this message translates to:
  /// **'BUYING'**
  String get orderPillBuying;

  /// Screen title when viewing the maker's own sell order
  ///
  /// In en, this message translates to:
  /// **'YOUR SELL ORDER'**
  String get myOrderSellTitle;

  /// Screen title when viewing the maker's own buy order
  ///
  /// In en, this message translates to:
  /// **'YOUR BUY ORDER'**
  String get myOrderBuyTitle;

  /// Button label to cancel a pending maker order
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrderButton;

  /// Title of the cancel-order confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrderDialogTitle;

  /// Body text of the cancel-order confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to cancel this order? This action cannot be undone.'**
  String get cancelOrderDialogContent;

  /// Snackbar shown when the cancel-order action fails
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel order. Please try again.'**
  String get cancelOrderFailed;

  /// Generic close button label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeButtonLabel;

  /// Generic copy action button label (e.g. in SnackBar actions)
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyButtonLabel;

  /// Status label shown on a pending maker order
  ///
  /// In en, this message translates to:
  /// **'Waiting for a taker'**
  String get orderStatusWaitingForTaker;

  /// Status label when waiting for the buyer to submit an invoice
  ///
  /// In en, this message translates to:
  /// **'Waiting for buyer invoice'**
  String get orderStatusWaitingBuyerInvoice;

  /// Status label when waiting for the Lightning payment
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment'**
  String get orderStatusWaitingPayment;

  /// Status label when a trade is active
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get orderStatusInProgress;

  /// Status label when an order has expired
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get orderStatusExpired;

  /// Tooltip for the copy-order-ID icon button
  ///
  /// In en, this message translates to:
  /// **'Copy order ID'**
  String get copyOrderIdTooltip;

  /// AppBar title when the requested order no longer exists
  ///
  /// In en, this message translates to:
  /// **'Order Not Found'**
  String get orderNotFoundTitle;

  /// Body text shown when the requested order no longer exists
  ///
  /// In en, this message translates to:
  /// **'This order is no longer available.'**
  String get orderNotFoundMessage;

  /// Snackbar shown after a maker successfully cancels their own pending order
  ///
  /// In en, this message translates to:
  /// **'Order cancelled successfully.'**
  String get orderCancelledSuccess;

  /// About screen — App Information card title
  ///
  /// In en, this message translates to:
  /// **'App Information'**
  String get aboutAppInfoTitle;

  /// About screen — Documentation card title
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get aboutDocumentationTitle;

  /// About screen — Mostro Node card title
  ///
  /// In en, this message translates to:
  /// **'Mostro Node'**
  String get aboutMostroNodeTitle;

  /// About screen — Version row label
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersionLabel;

  /// About screen — GitHub Repository row label
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get aboutGithubRepoLabel;

  /// About screen — Commit Hash row label
  ///
  /// In en, this message translates to:
  /// **'Commit Hash'**
  String get aboutCommitHashLabel;

  /// About screen — License row label
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicenseLabel;

  /// About screen — License name value
  ///
  /// In en, this message translates to:
  /// **'MIT'**
  String get aboutLicenseName;

  /// About screen — GitHub repository display name
  ///
  /// In en, this message translates to:
  /// **'mostro-mobile'**
  String get aboutGithubRepoName;

  /// About screen — English user docs link label
  ///
  /// In en, this message translates to:
  /// **'Users (English)'**
  String get aboutDocsUsersEnglish;

  /// About screen — Spanish user docs link label
  ///
  /// In en, this message translates to:
  /// **'Users (Spanish)'**
  String get aboutDocsUsersSpanish;

  /// About screen — Technical docs link label
  ///
  /// In en, this message translates to:
  /// **'Technical'**
  String get aboutDocsTechnical;

  /// About screen — action label for documentation links
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get aboutDocsRead;

  /// Snackbar shown after copying a value to clipboard on the About screen
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get aboutCopiedToClipboard;

  /// Title for the MIT license dialog on the About screen
  ///
  /// In en, this message translates to:
  /// **'MIT License'**
  String get aboutLicenseDialogTitle;

  /// Text shown while the Mostro node info is being fetched
  ///
  /// In en, this message translates to:
  /// **'Loading node information…'**
  String get aboutNodeLoadingText;

  /// Text shown when the Mostro node info cannot be fetched
  ///
  /// In en, this message translates to:
  /// **'Node information unavailable'**
  String get aboutNodeUnavailable;

  /// Button to retry fetching the Mostro node info
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get aboutNodeRetry;

  /// About screen — Mostro Node general info section header
  ///
  /// In en, this message translates to:
  /// **'General Info'**
  String get aboutGeneralInfoSection;

  /// About screen — Mostro Node technical details section header
  ///
  /// In en, this message translates to:
  /// **'Technical Details'**
  String get aboutTechnicalDetailsSection;

  /// About screen — Mostro Node Lightning Network section header
  ///
  /// In en, this message translates to:
  /// **'Lightning Network'**
  String get aboutLightningNetworkSection;

  /// About screen — Mostro Public Key row label
  ///
  /// In en, this message translates to:
  /// **'Mostro Public Key'**
  String get aboutMostroPublicKeyLabel;

  /// About screen — Max Order Amount row label
  ///
  /// In en, this message translates to:
  /// **'Max Order Amount'**
  String get aboutMaxOrderAmountLabel;

  /// About screen — Min Order Amount row label
  ///
  /// In en, this message translates to:
  /// **'Min Order Amount'**
  String get aboutMinOrderAmountLabel;

  /// About screen — Order Lifespan row label
  ///
  /// In en, this message translates to:
  /// **'Order Lifespan'**
  String get aboutOrderLifespanLabel;

  /// About screen — Service Fee row label
  ///
  /// In en, this message translates to:
  /// **'Service Fee'**
  String get aboutServiceFeeLabel;

  /// About screen — Fiat Currencies row label
  ///
  /// In en, this message translates to:
  /// **'Fiat Currencies'**
  String get aboutFiatCurrenciesLabel;

  /// About screen — Mostro Version row label
  ///
  /// In en, this message translates to:
  /// **'Mostro Version'**
  String get aboutMostroVersionLabel;

  /// About screen — Mostro Commit row label
  ///
  /// In en, this message translates to:
  /// **'Mostro Commit'**
  String get aboutMostroCommitLabel;

  /// About screen — Order Expiration row label
  ///
  /// In en, this message translates to:
  /// **'Order Expiration'**
  String get aboutOrderExpirationLabel;

  /// About screen — Hold Invoice Expiration row label
  ///
  /// In en, this message translates to:
  /// **'Hold Invoice Expiration'**
  String get aboutHoldInvoiceExpLabel;

  /// About screen — Hold Invoice CLTV Delta row label
  ///
  /// In en, this message translates to:
  /// **'Hold Invoice CLTV'**
  String get aboutHoldInvoiceCltvLabel;

  /// About screen — Invoice Expiration Window row label
  ///
  /// In en, this message translates to:
  /// **'Invoice Expiration Window'**
  String get aboutInvoiceExpWindowLabel;

  /// About screen — Proof of Work row label
  ///
  /// In en, this message translates to:
  /// **'Proof of Work'**
  String get aboutProofOfWorkLabel;

  /// About screen — Max Orders Per Response row label
  ///
  /// In en, this message translates to:
  /// **'Max Orders/Response'**
  String get aboutMaxOrdersPerResponseLabel;

  /// About screen — LND Version row label
  ///
  /// In en, this message translates to:
  /// **'LND Version'**
  String get aboutLndVersionLabel;

  /// About screen — LND Node Public Key row label
  ///
  /// In en, this message translates to:
  /// **'LND Node Public Key'**
  String get aboutLndNodePublicKeyLabel;

  /// About screen — LND Commit row label
  ///
  /// In en, this message translates to:
  /// **'LND Commit'**
  String get aboutLndCommitLabel;

  /// About screen — LND Node Alias row label
  ///
  /// In en, this message translates to:
  /// **'LND Node Alias'**
  String get aboutLndNodeAliasLabel;

  /// About screen — Supported Chains row label
  ///
  /// In en, this message translates to:
  /// **'Supported Chains'**
  String get aboutSupportedChainsLabel;

  /// About screen — Supported Networks row label
  ///
  /// In en, this message translates to:
  /// **'Supported Networks'**
  String get aboutSupportedNetworksLabel;

  /// About screen — LND Node URI row label
  ///
  /// In en, this message translates to:
  /// **'LND Node URI'**
  String get aboutLndNodeUriLabel;

  /// Suffix appended to sats amounts on the About screen
  ///
  /// In en, this message translates to:
  /// **'Satoshis'**
  String get aboutSatoshisSuffix;

  /// Suffix appended to hour durations on the About screen
  ///
  /// In en, this message translates to:
  /// **'hours'**
  String get aboutHoursSuffix;

  /// Suffix appended to second durations on the About screen
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get aboutSecondsSuffix;

  /// Suffix appended to block counts on the About screen
  ///
  /// In en, this message translates to:
  /// **'blocks'**
  String get aboutBlocksSuffix;

  /// Value shown when the node accepts all fiat currencies
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get aboutFiatCurrenciesAll;

  /// Info dialog explanation for the Mostro Public Key field
  ///
  /// In en, this message translates to:
  /// **'The Nostr public key of the Mostro daemon. All orders and encrypted messages on this instance are published or routed by this key.'**
  String get aboutMostroPublicKeyExplanation;

  /// Info dialog explanation for the Max Order Amount field
  ///
  /// In en, this message translates to:
  /// **'The maximum fiat amount allowed for a single order on this Mostro instance.'**
  String get aboutMaxOrderAmountExplanation;

  /// Info dialog explanation for the Min Order Amount field
  ///
  /// In en, this message translates to:
  /// **'The minimum fiat amount required for a single order on this Mostro instance.'**
  String get aboutMinOrderAmountExplanation;

  /// Info dialog explanation for the Order Lifespan field
  ///
  /// In en, this message translates to:
  /// **'How long a pending order stays open before it automatically expires if no taker is found.'**
  String get aboutOrderLifespanExplanation;

  /// Info dialog explanation for the Service Fee field
  ///
  /// In en, this message translates to:
  /// **'The percentage of the trade amount charged by the Mostro daemon as a service fee.'**
  String get aboutServiceFeeExplanation;

  /// Info dialog explanation for the Fiat Currencies field
  ///
  /// In en, this message translates to:
  /// **'The fiat currencies accepted on this Mostro instance. \'All\' means there are no restrictions.'**
  String get aboutFiatCurrenciesExplanation;

  /// Info dialog explanation for the Mostro Version field
  ///
  /// In en, this message translates to:
  /// **'The version of the Mostro daemon software running this instance.'**
  String get aboutMostroVersionExplanation;

  /// Info dialog explanation for the Mostro Commit field
  ///
  /// In en, this message translates to:
  /// **'The Git commit hash of the Mostro daemon build, used to identify the exact software revision.'**
  String get aboutMostroCommitExplanation;

  /// Info dialog explanation for the Order Expiration field
  ///
  /// In en, this message translates to:
  /// **'The timeout in seconds after which a trade waiting for action (e.g. invoice or payment) is automatically canceled.'**
  String get aboutOrderExpirationExplanation;

  /// Info dialog explanation for the Hold Invoice Expiration field
  ///
  /// In en, this message translates to:
  /// **'The time window in seconds during which the Lightning hold invoice must be settled.'**
  String get aboutHoldInvoiceExpExplanation;

  /// Info dialog explanation for the Hold Invoice CLTV Delta field
  ///
  /// In en, this message translates to:
  /// **'The CLTV delta (block count) used for hold invoices, controlling how long the HTLC can remain locked.'**
  String get aboutHoldInvoiceCltvExplanation;

  /// Info dialog explanation for the Invoice Expiration Window field
  ///
  /// In en, this message translates to:
  /// **'The time window in seconds within which the buyer must submit a Lightning invoice after the trade is initiated.'**
  String get aboutInvoiceExpWindowExplanation;

  /// Info dialog explanation for the Proof of Work field
  ///
  /// In en, this message translates to:
  /// **'The minimum proof-of-work difficulty required for Nostr events on this instance. 0 means no PoW is required.'**
  String get aboutProofOfWorkExplanation;

  /// Info dialog explanation for the Max Orders Per Response field
  ///
  /// In en, this message translates to:
  /// **'The maximum number of orders returned in a single relay response. Limits bandwidth usage.'**
  String get aboutMaxOrdersPerResponseExplanation;

  /// Info dialog explanation for the LND Version field
  ///
  /// In en, this message translates to:
  /// **'The version of the LND (Lightning Network Daemon) node connected to this Mostro instance.'**
  String get aboutLndVersionExplanation;

  /// Info dialog explanation for the LND Node Public Key field
  ///
  /// In en, this message translates to:
  /// **'The public key of the LND node. Used to identify and verify the Lightning Network node.'**
  String get aboutLndNodePublicKeyExplanation;

  /// Info dialog explanation for the LND Commit field
  ///
  /// In en, this message translates to:
  /// **'The Git commit hash of the LND build, identifying the exact software revision of the Lightning node.'**
  String get aboutLndCommitExplanation;

  /// Info dialog explanation for the LND Node Alias field
  ///
  /// In en, this message translates to:
  /// **'The human-readable alias of the LND node as configured by the node operator.'**
  String get aboutLndNodeAliasExplanation;

  /// Info dialog explanation for the Supported Chains field
  ///
  /// In en, this message translates to:
  /// **'The blockchain(s) supported by the LND node (e.g. \'bitcoin\').'**
  String get aboutSupportedChainsExplanation;

  /// Info dialog explanation for the Supported Networks field
  ///
  /// In en, this message translates to:
  /// **'The network(s) the LND node operates on (e.g. \'mainnet\', \'testnet\').'**
  String get aboutSupportedNetworksExplanation;

  /// Info dialog explanation for the LND Node URI field
  ///
  /// In en, this message translates to:
  /// **'The connection URI of the LND node in the format pubkey@host:port. Used to open direct payment channels.'**
  String get aboutLndNodeUriExplanation;

  /// Snackbar shown when opening a dispute fails
  ///
  /// In en, this message translates to:
  /// **'Could not open dispute. Please try again.'**
  String get openDisputeFailed;

  /// Instruction shown to the buyer while waiting to submit their Lightning invoice
  ///
  /// In en, this message translates to:
  /// **'Submit your Lightning invoice so the seller can lock the funds.'**
  String get tradeWaitingInvoiceBuyerInstruction;

  /// Instruction shown to the seller while waiting for the buyer's Lightning invoice
  ///
  /// In en, this message translates to:
  /// **'Waiting for the buyer to submit their Lightning invoice.'**
  String get tradeWaitingInvoiceSellerInstruction;

  /// Instruction shown to the buyer while the seller pays the hold invoice
  ///
  /// In en, this message translates to:
  /// **'The seller is paying the hold invoice. Please wait.'**
  String get tradeWaitingPaymentBuyerInstruction;

  /// Instruction shown to the seller prompting them to pay the hold invoice
  ///
  /// In en, this message translates to:
  /// **'Pay the hold invoice to lock the funds and start the trade.'**
  String get tradeWaitingPaymentSellerInstruction;

  /// Error message shown when a trade fails to load
  ///
  /// In en, this message translates to:
  /// **'An error occurred while loading the trade.'**
  String get tradeLoadError;

  /// Loading message shown while the Mostro daemon has not yet sent the hold invoice
  ///
  /// In en, this message translates to:
  /// **'Waiting for hold invoice...'**
  String get tradeWaitingForHoldInvoice;

  /// Instruction text shown on the pay invoice screen above the QR code
  ///
  /// In en, this message translates to:
  /// **'Pay this hold invoice to start the trade'**
  String get payInvoiceInstruction;

  /// Share action button label on the pay invoice screen
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareButtonLabel;

  /// Snackbar shown when the system share sheet fails
  ///
  /// In en, this message translates to:
  /// **'Could not share the invoice'**
  String get shareFailed;

  /// Text shown while waiting for the Lightning payment to be confirmed after paying the hold invoice
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment confirmation...'**
  String get waitingForPaymentConfirmation;

  /// Button label that opens the hold invoice in an external Lightning wallet via the lightning: URI scheme
  ///
  /// In en, this message translates to:
  /// **'Pay with Lightning wallet'**
  String get payWithLightningWallet;

  /// Snackbar shown when no app can handle the lightning: URI
  ///
  /// In en, this message translates to:
  /// **'No Lightning wallet found on this device'**
  String get noLightningWalletFound;

  /// Neutral notice shown when the order reaches a terminal state (canceled, cooperatively canceled, canceled by admin, or expired) while the user is on the pay invoice screen
  ///
  /// In en, this message translates to:
  /// **'This order is no longer active'**
  String get orderNoLongerActive;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
