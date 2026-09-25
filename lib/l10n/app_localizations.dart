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
import 'app_localizations_nl.dart';

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
    Locale('nl'),
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

  /// Screen-reader-only announcement when a button action fails and the button enters its cooldown state
  ///
  /// In en, this message translates to:
  /// **'Action failed'**
  String get actionFailedAnnouncement;

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
  /// **'Buy BTC'**
  String get tabBuyBtc;

  /// Tab label for the sell Bitcoin order book
  ///
  /// In en, this message translates to:
  /// **'Sell BTC'**
  String get tabSellBtc;

  /// Button label to open order book filter options
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterButtonLabel;

  /// Screen-reader addition to the order-book filter chip when filters narrow the book; the chip itself shows only the number in a badge. Read after the chip label, e.g. 'Filter, 2 filters on'
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 filter on} other{{count} filters on}}'**
  String filtersActiveCount(int count);

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

  /// Inline error on the add-invoice screen after the Mostro daemon refused the submitted invoice (CantDo InvalidInvoice)
  ///
  /// In en, this message translates to:
  /// **'The node rejected this invoice. Check its amount and expiry and add a new one.'**
  String get invoiceRejected;

  /// Snackbar shown after copying a Lightning invoice to clipboard
  ///
  /// In en, this message translates to:
  /// **'Invoice copied'**
  String get invoiceCopied;

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

  /// Error shown when the selected Mostro node advertises a protocol version this v2-native client does not speak, so it would never read the request
  ///
  /// In en, this message translates to:
  /// **'This Mostro node uses a protocol version this app does not support. Pick another node in Settings, or check for an app update'**
  String get nodeProtocolUnsupported;

  /// Error shown when a send fails closed because the selected node's capability fetch (PoW, protocol version) has not completed yet — retrying shortly usually succeeds
  ///
  /// In en, this message translates to:
  /// **'Still checking what the selected Mostro node supports. Try again in a moment'**
  String get nodeCapabilitiesUnknown;

  /// Error shown when the selected Mostro node answers CantDo(MaintenanceMode): it is draining (for example before a Lightning node migration) and refuses new orders and takes until it is back
  ///
  /// In en, this message translates to:
  /// **'The Mostro node you are connected to is under maintenance. Try again later, or connect to a different Mostro node in Settings'**
  String get mostroMaintenanceMode;

  /// Error shown when a trade key cannot be derived because the local database is unavailable, so orders cannot be created or taken
  ///
  /// In en, this message translates to:
  /// **'The app cannot create or take orders while its local database is unavailable. Restart the app and try again'**
  String get storageUnavailable;

  /// Snackbar shown after copying an order ID to clipboard
  ///
  /// In en, this message translates to:
  /// **'Order ID copied'**
  String get orderIdCopied;

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

  /// Section title for the privacy settings card
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyCardTitle;

  /// Label for reputation privacy mode option
  ///
  /// In en, this message translates to:
  /// **'Reputation Mode'**
  String get reputationMode;

  /// Subtitle for reputation mode option
  ///
  /// In en, this message translates to:
  /// **'Your trades count toward your public reputation'**
  String get reputationModeSubtitle;

  /// Label for full privacy mode option
  ///
  /// In en, this message translates to:
  /// **'Full Privacy Mode'**
  String get fullPrivacyMode;

  /// Subtitle for full privacy mode option
  ///
  /// In en, this message translates to:
  /// **'Each trade uses a new identity, no reputation'**
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
  /// **'Import secret words'**
  String get importMnemonicDialogTitle;

  /// Hint text in the mnemonic import text field
  ///
  /// In en, this message translates to:
  /// **'Enter your 12 secret words'**
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

  /// Account: reveals the 12 masked secret words
  ///
  /// In en, this message translates to:
  /// **'Show words'**
  String get showWordsButton;

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

  /// Settings list item title for NWC wallet connection
  ///
  /// In en, this message translates to:
  /// **'NWC Wallet'**
  String get nwcWalletSettingTitle;

  /// Settings list item title for Nostr relay management
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get relaysSettingTitle;

  /// Settings list item title for push notification preferences
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotificationsSettingTitle;

  /// Settings list item title for viewing diagnostic logs
  ///
  /// In en, this message translates to:
  /// **'Log Report'**
  String get logReportSettingTitle;

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

  /// Screen title for the QR code scanner
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCodeTitle;

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

  /// Badge shown on a verified/trusted Mostro node
  ///
  /// In en, this message translates to:
  /// **'Trusted'**
  String get trustedBadgeLabel;

  /// Button label to confirm a selection or action
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmButtonLabel;

  /// Title of the Mostro node selector bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Choose a node'**
  String get selectMostroNode;

  /// Button and dialog title for adding a custom node
  ///
  /// In en, this message translates to:
  /// **'Add your own node'**
  String get addCustomNode;

  /// Label of the pubkey input in the add-custom-node dialog
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get nodePubkeyFieldLabel;

  /// Hint of the pubkey input in the add-custom-node dialog
  ///
  /// In en, this message translates to:
  /// **'64-char hex or npub…'**
  String get nodePubkeyFieldHint;

  /// Label of the optional display-name input in the add-custom-node dialog
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get nodeNameOptionalLabel;

  /// Validation error for a malformed node pubkey
  ///
  /// In en, this message translates to:
  /// **'Enter a valid public key (64-char hex or npub)'**
  String get invalidPubkeyFormat;

  /// Validation error when the user pastes an nsec private key
  ///
  /// In en, this message translates to:
  /// **'That is a private key — never share it. Enter the node\'s public key instead'**
  String get privateKeyNotAllowed;

  /// Error when adding a node that is already trusted or already added
  ///
  /// In en, this message translates to:
  /// **'This node is already in the list'**
  String get nodeAlreadyExists;

  /// Snackbar after a custom node was added
  ///
  /// In en, this message translates to:
  /// **'Node added'**
  String get nodeAddedSuccess;

  /// Snackbar after switching the active Mostro node
  ///
  /// In en, this message translates to:
  /// **'Now using {nodeName}'**
  String nodeSwitchedSuccess(String nodeName);

  /// Snackbar when activating a node fails
  ///
  /// In en, this message translates to:
  /// **'Failed to switch node'**
  String get errorSwitchingNode;

  /// Error when trying to delete the currently active node
  ///
  /// In en, this message translates to:
  /// **'The active node can\'t be removed — switch to another node first'**
  String get cannotRemoveActiveNode;

  /// Title of the remove-custom-node confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Remove node'**
  String get deleteCustomNodeTitle;

  /// Body of the remove-custom-node confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Remove this custom node from your list?'**
  String get deleteCustomNodeMessage;

  /// Confirm button of the remove-custom-node dialog
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get deleteCustomNodeConfirm;

  /// Snackbar after a custom node was removed
  ///
  /// In en, this message translates to:
  /// **'Node removed'**
  String get nodeRemovedSuccess;

  /// Error when a node registry action fails because local storage is not initialized
  ///
  /// In en, this message translates to:
  /// **'The local database isn\'t ready. Restart the app and try again'**
  String get nodeStorageUnavailable;

  /// Subtitle of the node selector; {code} is the user's fiat currency and is highlighted in the UI, so it must appear verbatim exactly once
  ///
  /// In en, this message translates to:
  /// **'Orders and currencies for {code}, your currency'**
  String nodeSelectorSubtitle(String code);

  /// Subtitle of the node selector when the user has no preferred fiat currency
  ///
  /// In en, this message translates to:
  /// **'Open orders on each node'**
  String get nodeSelectorSubtitleNoCurrency;

  /// Amber chip on a node card when the node does not accept the user's currency
  ///
  /// In en, this message translates to:
  /// **'NO {code}'**
  String nodeMissingCurrencyChip(String code);

  /// Label under the open-orders figure on a node card
  ///
  /// In en, this message translates to:
  /// **'orders now'**
  String get nodeOrdersNowLabel;

  /// Label under the open-orders figure when the node has none
  ///
  /// In en, this message translates to:
  /// **'no orders'**
  String get nodeNoOrdersLabel;

  /// Unit next to the open-orders figure: how many are in the user's currency
  ///
  /// In en, this message translates to:
  /// **'· {count} in {code}'**
  String nodeOrdersInCurrency(int count, String code);

  /// Label under the fee figure on a node card
  ///
  /// In en, this message translates to:
  /// **'fee'**
  String get nodeFeeLabel;

  /// Tooltip on the fee column of a node card
  ///
  /// In en, this message translates to:
  /// **'Mostro splits the fee between both parties.'**
  String get nodeFeeTooltip;

  /// Label under the sats range figure on a node card
  ///
  /// In en, this message translates to:
  /// **'per trade'**
  String get nodePerTradeLabel;

  /// Trust row of a node card: the node holds sats in a Lightning hold invoice
  ///
  /// In en, this message translates to:
  /// **'Lightning custody'**
  String get nodeCustodyLightning;

  /// Trust row of a node card: Cashu escrow at the given mint
  ///
  /// In en, this message translates to:
  /// **'Cashu custody · {mint}'**
  String nodeCustodyCashu(String mint);

  /// Trust row of a node card when the node publishes no escrow backend
  ///
  /// In en, this message translates to:
  /// **'Custody —'**
  String get nodeCustodyUnknown;

  /// Trust row of a node card: the anti-abuse bond the node requires
  ///
  /// In en, this message translates to:
  /// **'Bond {pct}%'**
  String nodeBondPct(String pct);

  /// Trust row of a node card: the node requires no bond
  ///
  /// In en, this message translates to:
  /// **'No bond'**
  String get nodeBondNone;

  /// Availability line of a node card
  ///
  /// In en, this message translates to:
  /// **'Online · {count, plural, =1{1 order} other{{count} orders}}'**
  String nodeStatusOnline(int count);

  /// Availability line of a node card: reachable but nothing in the user's currencies
  ///
  /// In en, this message translates to:
  /// **'No orders in your currencies'**
  String get nodeStatusNoUsefulOrders;

  /// Availability line of a node card; {ago} is a compact relative time such as '2h ago'
  ///
  /// In en, this message translates to:
  /// **'Not responding · last seen {ago}'**
  String nodeStatusUnreachable(String ago);

  /// Availability line of a node card that never answered
  ///
  /// In en, this message translates to:
  /// **'Not responding'**
  String get nodeStatusUnreachableNoSignal;

  /// Two-line operator disclaimer at the foot of the node selector
  ///
  /// In en, this message translates to:
  /// **'Each node is run by an independent third party. Mostro is not responsible for their conduct or for your trades.'**
  String get nodeDisclaimerShort;

  /// Warning box in the add-own-node dialog
  ///
  /// In en, this message translates to:
  /// **'Verify the key with the operator. A fake node can see your orders.'**
  String get nodeVerifyKeyWarning;

  /// Inline error under the public-key field of the add-own-node dialog
  ///
  /// In en, this message translates to:
  /// **'This is not a valid public key.'**
  String get nodeInvalidPubkeyShort;

  /// Placeholder of the optional name field of the add-own-node dialog
  ///
  /// In en, this message translates to:
  /// **'Local Mostro'**
  String get nodeNameFieldHint;

  /// Snackbar after tapping a node's public key
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get nodePubkeyCopied;

  /// Snackbar when tapping a node card that is not responding
  ///
  /// In en, this message translates to:
  /// **'This node is not responding'**
  String get nodeNotSelectableOffline;

  /// Accessibility label of the shimmer skeleton while a node's figures load
  ///
  /// In en, this message translates to:
  /// **'Loading node data'**
  String get nodeStatsLoading;

  /// Title of the sheet asking to confirm a node switch while a trade is in progress
  ///
  /// In en, this message translates to:
  /// **'Change node?'**
  String get nodeSwitchConfirmTitle;

  /// Body of the node-switch confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'You have a trade in progress on {currentNode}. It stays there; the order book will now show {newNode}.'**
  String nodeSwitchConfirmBody(String currentNode, String newNode);

  /// Confirm button of the node-switch confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Change node'**
  String get nodeSwitchConfirmAction;

  /// Snackbar when the node selector could not read the local trades to decide whether a switch needs confirmation
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your trades. Try again.'**
  String get nodeTradesCheckFailed;

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

  /// Snackbar shown after copying a link to clipboard
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopiedToClipboard;

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

  /// Footer tagline on the About screen
  ///
  /// In en, this message translates to:
  /// **'Open-source. Non-custodial. Private.'**
  String get footerTagline;

  /// Title shown at the top of the navigation drawer
  ///
  /// In en, this message translates to:
  /// **'Mostro'**
  String get drawerTitle;

  /// Subtitle under the Mostro wordmark in the drawer header (rendered uppercase)
  ///
  /// In en, this message translates to:
  /// **'P2P exchange'**
  String get drawerTagline;

  /// Release-stage chip in the drawer header (rendered uppercase). Single source for the stage label — change it here when the app leaves alpha
  ///
  /// In en, this message translates to:
  /// **'Alpha'**
  String get drawerStageBadge;

  /// App version line in the drawer footer
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String drawerVersion(String version);

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

  /// Shown when the user picks a wrong word a second time during backup verification; sends them back to review the words and restart verification
  ///
  /// In en, this message translates to:
  /// **'That was incorrect again. Please review and back up your secret words, then verify from the start.'**
  String get backupRitualSecondFailureMessage;

  /// Title for the cancel-trade confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel trade?'**
  String get cancelTradeDialogTitle;

  /// Body text for the cancel-trade confirmation dialog once the trade is active: the cancel is a cooperative request
  ///
  /// In en, this message translates to:
  /// **'Requesting a cooperative cancel. The other party must also agree for the trade to be fully cancelled.'**
  String get cancelTradeDialogContent;

  /// Body text for the cancel-trade confirmation dialog before the trade is active (pending, waiting for the invoice or the hold-invoice payment): the daemon cancels at once
  ///
  /// In en, this message translates to:
  /// **'The trade has not started yet, so it is cancelled right away. The other party does not need to agree.'**
  String get cancelTradeDialogContentNotStarted;

  /// Body text for the cancel-trade confirmation dialog while the order is only known to be taken (in progress): the trade may or may not be active yet
  ///
  /// In en, this message translates to:
  /// **'If the trade has not started yet, it is cancelled right away. If it has, the other party must also agree.'**
  String get cancelTradeDialogContentMaybeStarted;

  /// Negative button label in a confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get noButtonLabel;

  /// Generic Yes button label
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yesButtonLabel;

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

  /// Notifications card title on the daemon confirming this user's cooperative-cancel request (protocol cancel.md); the trade stays open until the other party also cancels
  ///
  /// In en, this message translates to:
  /// **'Cancel requested'**
  String get tradeCardCancelRequestedByMeTitle;

  /// Notifications card body on the daemon confirming this user's cooperative-cancel request
  ///
  /// In en, this message translates to:
  /// **'You asked to cancel this trade. It stays open until the other party also cancels. If they do not respond, you can open a dispute.'**
  String get tradeCardCancelRequestedByMeMessage;

  /// Notifications card title when the counterparty asked to cancel an active trade (protocol cancel.md); this user decides whether to accept
  ///
  /// In en, this message translates to:
  /// **'The other party wants to cancel'**
  String get tradeCardCancelRequestedByPeerTitle;

  /// Notifications card body when the counterparty asked to cancel an active trade
  ///
  /// In en, this message translates to:
  /// **'They asked to cancel this trade. Accept to end it with no funds moved, or keep trading.'**
  String get tradeCardCancelRequestedByPeerMessage;

  /// Notice on the trade screen while this user's cooperative-cancel request waits for the other party
  ///
  /// In en, this message translates to:
  /// **'You asked to cancel this trade. It stays open until the other party also cancels. If they do not respond, you can open a dispute.'**
  String get tradeCancelRequestedByMeNotice;

  /// Notice on the trade screen while the counterparty's cooperative-cancel request waits for this user
  ///
  /// In en, this message translates to:
  /// **'The other party asked to cancel this trade. Accept to end it with no funds moved, or keep trading.'**
  String get tradeCancelRequestedByPeerNotice;

  /// Label of the cancel button once the counterparty asked to cancel: this user's cancel accepts theirs and ends the trade
  ///
  /// In en, this message translates to:
  /// **'Accept cancel'**
  String get acceptCancelButton;

  /// Body text for the cancel-trade confirmation dialog when the counterparty already asked to cancel: this cancel accepts theirs
  ///
  /// In en, this message translates to:
  /// **'The other party asked to cancel. Cancelling now ends the trade for both of you and no funds are moved.'**
  String get cancelTradeDialogContentAccept;

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

  /// Button label to cancel an in-progress trade (secondary action row)
  ///
  /// In en, this message translates to:
  /// **'Cancel trade'**
  String get cancelTradeButton;

  /// Primary CTA for the seller to open the pay hold invoice screen
  ///
  /// In en, this message translates to:
  /// **'Pay hold invoice'**
  String get payHoldInvoiceButton;

  /// Button label to open a dispute on an in-progress trade
  ///
  /// In en, this message translates to:
  /// **'Open dispute'**
  String get openDisputeButton;

  /// Button label for the seller to release sats during an active dispute (secondary action row)
  ///
  /// In en, this message translates to:
  /// **'Release sats'**
  String get releaseSatsButton;

  /// Primary CTA button label for the seller to confirm and release sats
  ///
  /// In en, this message translates to:
  /// **'Confirm & release sats'**
  String get confirmReleaseSatsButton;

  /// Menu item label to share the current order (not yet implemented — shows a coming-soon message)
  ///
  /// In en, this message translates to:
  /// **'Share order'**
  String get shareOrderButton;

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

  /// Screen title when viewing the maker's own sell order
  ///
  /// In en, this message translates to:
  /// **'Your sell order'**
  String get myOrderSellTitle;

  /// Screen title when viewing the maker's own buy order
  ///
  /// In en, this message translates to:
  /// **'Your buy order'**
  String get myOrderBuyTitle;

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
  /// **'AGPLv3+'**
  String get aboutLicenseName;

  /// About screen — GitHub repository display name
  ///
  /// In en, this message translates to:
  /// **'MostroP2P/app'**
  String get aboutGithubRepoName;

  /// Snackbar shown after copying a value to clipboard on the About screen
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get aboutCopiedToClipboard;

  /// Title for the AGPLv3 license dialog on the About screen
  ///
  /// In en, this message translates to:
  /// **'GNU Affero General Public License v3'**
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

  /// About screen — Mostro Node Lightning Network section header
  ///
  /// In en, this message translates to:
  /// **'Lightning Network'**
  String get aboutLightningNetworkSection;

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

  /// Suffix appended to sats amounts on the About screen
  ///
  /// In en, this message translates to:
  /// **'Satoshis'**
  String get aboutSatoshisSuffix;

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

  /// About screen — anti-abuse bond section header
  ///
  /// In en, this message translates to:
  /// **'Anti-abuse Bond'**
  String get aboutAntiAbuseBondSection;

  /// About screen — value shown when a bond setting is on
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get aboutBondEnabledValue;

  /// About screen — value shown when a bond setting is off
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get aboutBondDisabledValue;

  /// About screen — value shown when the daemon predates the anti-abuse bond feature
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get aboutBondUnsupportedValue;

  /// About screen — bond status row label
  ///
  /// In en, this message translates to:
  /// **'Bond status'**
  String get aboutBondStatusLabel;

  /// About screen — bond applies-to row label
  ///
  /// In en, this message translates to:
  /// **'Applies to'**
  String get aboutBondAppliesToLabel;

  /// About screen — bond applies to takers only
  ///
  /// In en, this message translates to:
  /// **'Takers'**
  String get aboutBondAppliesToTakers;

  /// About screen — bond applies to makers only
  ///
  /// In en, this message translates to:
  /// **'Makers'**
  String get aboutBondAppliesToMakers;

  /// About screen — bond applies to both sides of a trade
  ///
  /// In en, this message translates to:
  /// **'Makers and takers'**
  String get aboutBondAppliesToBoth;

  /// About screen — bond amount percentage row label
  ///
  /// In en, this message translates to:
  /// **'Bond amount'**
  String get aboutBondAmountLabel;

  /// About screen — minimum bond row label
  ///
  /// In en, this message translates to:
  /// **'Minimum bond'**
  String get aboutBondBaseAmountLabel;

  /// About screen — node share of a slashed bond row label
  ///
  /// In en, this message translates to:
  /// **'Node share on slash'**
  String get aboutBondNodeShareLabel;

  /// About screen — slash on waiting timeout row label
  ///
  /// In en, this message translates to:
  /// **'Slash on waiting timeout'**
  String get aboutBondSlashOnTimeoutLabel;

  /// About screen — bond payout claim window row label
  ///
  /// In en, this message translates to:
  /// **'Payout claim window'**
  String get aboutBondClaimWindowLabel;

  /// About screen — bond payout claim window value with a pluralized day count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} day} other{{count} days}}'**
  String aboutBondClaimWindowValue(int count);

  /// Snackbar shown when opening a dispute fails
  ///
  /// In en, this message translates to:
  /// **'Could not open dispute. Please try again.'**
  String get openDisputeFailed;

  /// Title of the open-dispute confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Open dispute'**
  String get openDisputeTitle;

  /// Body of the open-dispute confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to open a dispute? This escalates the trade to an admin and cannot be undone.'**
  String get openDisputeConfirmation;

  /// Snackbar shown when a dispute is opened for a trade that already has one, or while a previous attempt is still in flight
  ///
  /// In en, this message translates to:
  /// **'A dispute for this trade is already open.'**
  String get disputeAlreadyOpen;

  /// Snackbar shown when a dispute is attempted before the trade reaches a disputable state
  ///
  /// In en, this message translates to:
  /// **'A dispute can only be opened once the funds are locked for this trade.'**
  String get tradeNotDisputable;

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

  /// Neutral notice shown when the order reaches a terminal state (canceled, cooperatively canceled, canceled by admin, or expired) while the user is on the add-invoice or pay-invoice screen
  ///
  /// In en, this message translates to:
  /// **'This order is no longer active'**
  String get orderNoLongerActive;

  /// Notice when the trade screen closes because the user no longer has a trade on this order: a take lost before it went active (their own cancel, a waiting timeout, the maker cancelling), or a later visit to such a trade from a notification. Neutral on purpose: the order may be back in the book or gone for good
  ///
  /// In en, this message translates to:
  /// **'You\'re no longer part of this trade'**
  String get tradeNoLongerYours;

  /// Snackbar shown when the Mostro node does not respond to a new order within the timeout — the order was not created
  ///
  /// In en, this message translates to:
  /// **'No response received, check your connection and try again later'**
  String get sessionTimeoutMessage;

  /// Snackbar shown on the Account screen when no stored identity can be loaded
  ///
  /// In en, this message translates to:
  /// **'No identity found — try restarting the app.'**
  String get noIdentityFoundMessage;

  /// Snackbar shown when loading the secret words fails on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Failed to load secret words. Please try again.'**
  String get failedToLoadSecretWordsMessage;

  /// Title of the privacy modes info dialog on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Privacy Modes'**
  String get privacyModesInfoTitle;

  /// Body of the privacy modes info dialog on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Reputation mode lets others see your successful trades.\n\nFull privacy mode keeps your activity completely anonymous — no reputation is built.'**
  String get privacyModesInfoContent;

  /// Snackbar shown when generating a new identity fails on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Failed to generate identity. Please try again.'**
  String get failedToGenerateIdentityMessage;

  /// Snackbar shown when an imported mnemonic is invalid on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Invalid secret words. Please check your words and try again.'**
  String get invalidMnemonicMessage;

  /// Validation error shown in the import mnemonic dialog when the phrase is not 12 or 24 words
  ///
  /// In en, this message translates to:
  /// **'Enter your 12 secret words.'**
  String get enterValidMnemonicError;

  /// Snackbar confirming the order book was refreshed from the Account screen
  ///
  /// In en, this message translates to:
  /// **'Order book refreshed'**
  String get orderBookRefreshedMessage;

  /// Snackbar shown when refreshing the order book fails on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Refresh failed'**
  String get refreshFailedMessage;

  /// Label for the refresh action in the Refresh User dialog
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshButtonLabel;

  /// Generic OK button label for info dialogs
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okButtonLabel;

  /// Tooltip for the info icon buttons on the Account screen
  ///
  /// In en, this message translates to:
  /// **'More information'**
  String get moreInformationTooltip;

  /// Badge shown in the Secret Words card header once the backup is complete
  ///
  /// In en, this message translates to:
  /// **'Backed up'**
  String get backedUpBadgeLabel;

  /// Title of the backup reminder banner on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Secure your reputation'**
  String get backupBannerTitle;

  /// Subtitle of the backup reminder banner on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Back up your 12 words — it takes 60 seconds.'**
  String get backupBannerSubtitle;

  /// Title of the Account screen warning shown while a failed identity wipe is pending retry (issue #555)
  ///
  /// In en, this message translates to:
  /// **'Previous user\'s data is still on this device'**
  String get pendingWipeBannerTitle;

  /// Body of the pending-wipe warning on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Deleting the previous identity could not remove its trades and chats from this device. The app will retry the next time a new user is generated.'**
  String get pendingWipeBannerBody;

  /// Snackbar shown when persisting the backup-complete status fails in the backup ritual
  ///
  /// In en, this message translates to:
  /// **'Failed to save backup status. Please try again.'**
  String get failedToSaveBackupStatusMessage;

  /// App bar title for step 1 of the backup ritual
  ///
  /// In en, this message translates to:
  /// **'Step 1 of 3 · Write down your words'**
  String get backupRitualStep1Title;

  /// App bar title for step 2 of the backup ritual
  ///
  /// In en, this message translates to:
  /// **'Step 2 of 3 · Verify'**
  String get backupRitualStep2Title;

  /// App bar title for step 3 of the backup ritual
  ///
  /// In en, this message translates to:
  /// **'Step 3 of 3 · Done'**
  String get backupRitualStep3Title;

  /// Bold lead-in of the warning card on the show-words step
  ///
  /// In en, this message translates to:
  /// **'Write them on paper. '**
  String get backupRitualWarningTitle;

  /// Body of the warning card on the show-words step
  ///
  /// In en, this message translates to:
  /// **'Don\'t store them in photos, screenshots or the cloud — anyone with these 12 words can steal your reputation.'**
  String get backupRitualWarningBody;

  /// Note reminding the user the words are hidden when leaving the ritual
  ///
  /// In en, this message translates to:
  /// **'They will be hidden when you leave this screen'**
  String get wordsHiddenOnLeaveNote;

  /// Primary button on the show-words step that starts verification
  ///
  /// In en, this message translates to:
  /// **'I wrote them down — verify'**
  String get wroteThemDownVerifyButton;

  /// Title of the verification step
  ///
  /// In en, this message translates to:
  /// **'Tap the correct words'**
  String get tapCorrectWordsTitle;

  /// Instructions shown on the verification step
  ///
  /// In en, this message translates to:
  /// **'We ask for 3 at random. If you get them right, we know they\'re safely written down.'**
  String get verifyInstructionsBody;

  /// Label above the option grid for the challenged word
  ///
  /// In en, this message translates to:
  /// **'OPTIONS FOR WORD #{number}'**
  String optionsForWordLabel(int number);

  /// Error shown when the user taps a wrong verification option
  ///
  /// In en, this message translates to:
  /// **'Not quite — check your paper and try again.'**
  String get wrongPickMessage;

  /// Success message shown when all challenged words are verified
  ///
  /// In en, this message translates to:
  /// **'All 3 words correct'**
  String get allWordsCorrectMessage;

  /// Backup verification: back to the 12 words without losing solved slots
  ///
  /// In en, this message translates to:
  /// **'View words'**
  String get reviewWordsButton;

  /// Title of the final done step of the backup ritual
  ///
  /// In en, this message translates to:
  /// **'Your account is backed up'**
  String get accountBackedUpTitle;

  /// Body of the final done step of the backup ritual
  ///
  /// In en, this message translates to:
  /// **'Your reputation is safe. If you ever lose your phone, restore your account with your 12 words.'**
  String get accountBackedUpBody;

  /// Label for a challenged word slot, showing its position in the mnemonic
  ///
  /// In en, this message translates to:
  /// **'Word #{number}'**
  String wordNumberLabel(int number);

  /// Lead-in body text of the backup trigger bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Your reputation lives in a key only you hold. If you lose your phone, you lose that reputation — '**
  String get backupTriggerBody;

  /// Highlighted trailing phrase of the backup trigger body
  ///
  /// In en, this message translates to:
  /// **'back it up in 60 seconds.'**
  String get backupTriggerBodyHighlight;

  /// Step 1 label in the backup trigger sheet preview
  ///
  /// In en, this message translates to:
  /// **'Write your 12 words down on paper'**
  String get backupStepWriteDown;

  /// Step 2 label in the backup trigger sheet preview
  ///
  /// In en, this message translates to:
  /// **'We ask for 3 at random to confirm'**
  String get backupStepVerifyRandom;

  /// Step 3 label in the backup trigger sheet preview
  ///
  /// In en, this message translates to:
  /// **'Done — your account is secured'**
  String get backupStepSecured;

  /// Primary button in the backup trigger sheet
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNowButton;

  /// Link in the backup sheet that closes it; the banner stays on Account
  ///
  /// In en, this message translates to:
  /// **'I\'ll do it later'**
  String get backupLaterButton;

  /// Snackbar shown when connecting a wallet via NWC fails
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Please check your NWC URI and try again.'**
  String get nwcConnectionFailedMessage;

  /// Snackbar shown when the clipboard has no valid NWC URI to paste
  ///
  /// In en, this message translates to:
  /// **'Clipboard does not contain a valid NWC URI.'**
  String get clipboardInvalidNwcUriMessage;

  /// Button that opens the QR scanner on the Connect Wallet screen
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQrButtonLabel;

  /// Primary button on the Connect Wallet screen
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectButtonLabel;

  /// Snackbar shown after disconnecting the wallet
  ///
  /// In en, this message translates to:
  /// **'Wallet disconnected'**
  String get walletDisconnectedMessage;

  /// Label for a single relay row on the Wallet Settings screen
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get relayLabel;

  /// Button that disconnects the wallet
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectButtonLabel;

  /// Suffix showing how many additional relays exist beyond the first
  ///
  /// In en, this message translates to:
  /// **'(+{count} more)'**
  String relaysMoreSuffix(int count);

  /// Subtitle on the notification settings screen
  ///
  /// In en, this message translates to:
  /// **'Choose which events show a notification in the app.'**
  String get chooseNotificationEventsSubtitle;

  /// Title of the trade updates notification toggle
  ///
  /// In en, this message translates to:
  /// **'Trade updates'**
  String get notifTradeUpdatesTitle;

  /// Subtitle of the trade updates notification toggle
  ///
  /// In en, this message translates to:
  /// **'Status changes in your active trades'**
  String get notifTradeUpdatesSubtitle;

  /// Title of the new messages notification toggle
  ///
  /// In en, this message translates to:
  /// **'New messages'**
  String get notifNewMessagesTitle;

  /// Subtitle of the new messages notification toggle
  ///
  /// In en, this message translates to:
  /// **'Messages from your trade counterparty'**
  String get notifNewMessagesSubtitle;

  /// Title of the payment alerts notification toggle
  ///
  /// In en, this message translates to:
  /// **'Payment alerts'**
  String get notifPaymentAlertsTitle;

  /// Subtitle of the payment alerts notification toggle
  ///
  /// In en, this message translates to:
  /// **'Lightning payment confirmations and failures'**
  String get notifPaymentAlertsSubtitle;

  /// Title of the dispute updates notification toggle
  ///
  /// In en, this message translates to:
  /// **'Dispute updates'**
  String get notifDisputeUpdatesTitle;

  /// Subtitle of the dispute updates notification toggle
  ///
  /// In en, this message translates to:
  /// **'Admin actions and dispute resolutions'**
  String get notifDisputeUpdatesSubtitle;

  /// Hint text of the currency search field
  ///
  /// In en, this message translates to:
  /// **'Search currencies…'**
  String get searchCurrenciesHint;

  /// Message shown when no currencies match the search
  ///
  /// In en, this message translates to:
  /// **'No currencies found'**
  String get noCurrenciesFoundMessage;

  /// Tooltip for the share logs action
  ///
  /// In en, this message translates to:
  /// **'Share logs'**
  String get shareLogsTooltip;

  /// Tooltip for the share action when there are no logs
  ///
  /// In en, this message translates to:
  /// **'No logs to share'**
  String get noLogsToShareTooltip;

  /// Message shown when there are no log entries
  ///
  /// In en, this message translates to:
  /// **'No log entries'**
  String get noLogEntriesMessage;

  /// Snackbar shown when sharing logs fails
  ///
  /// In en, this message translates to:
  /// **'Failed to share logs'**
  String get failedToShareLogsMessage;

  /// First line of the log report text handed to the share sheet
  ///
  /// In en, this message translates to:
  /// **'Mostro log report'**
  String get logReportShareHeading;

  /// My Trades status filter: all
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tradeFilterAll;

  /// My Trades status filter: pending
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get tradeFilterPending;

  /// My Trades status filter: waiting invoice
  ///
  /// In en, this message translates to:
  /// **'Waiting Invoice'**
  String get tradeFilterWaitingInvoice;

  /// My Trades status filter: waiting payment
  ///
  /// In en, this message translates to:
  /// **'Waiting Payment'**
  String get tradeFilterWaitingPayment;

  /// My Trades status filter: active
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get tradeFilterActive;

  /// My Trades status filter: fiat sent
  ///
  /// In en, this message translates to:
  /// **'Fiat Sent'**
  String get tradeFilterFiatSent;

  /// My Trades status filter: success
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get tradeFilterSuccess;

  /// My Trades status filter: canceled
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get tradeFilterCanceled;

  /// My Trades status filter: dispute
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get tradeFilterDispute;

  /// Tooltip for the drawer menu button
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menuTooltip;

  /// Title of the empty My Trades state
  ///
  /// In en, this message translates to:
  /// **'No trades'**
  String get noTradesTitle;

  /// Subtitle of the empty My Trades state
  ///
  /// In en, this message translates to:
  /// **'Your active and completed trades will appear here.'**
  String get noTradesSubtitle;

  /// Error shown when the trades list fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load trades'**
  String get couldNotLoadTradesMessage;

  /// Trade card title when the user is selling Bitcoin
  ///
  /// In en, this message translates to:
  /// **'Selling Bitcoin'**
  String get sellingBitcoin;

  /// Trade card title when the user is buying Bitcoin
  ///
  /// In en, this message translates to:
  /// **'Buying Bitcoin'**
  String get buyingBitcoin;

  /// Instruction for buyer while trade is active
  ///
  /// In en, this message translates to:
  /// **'Once you have sent the money, mark it below. Only open a dispute if the seller stops responding.'**
  String get tradeInstructionActiveBuyer;

  /// Instruction for buyer after marking fiat sent
  ///
  /// In en, this message translates to:
  /// **'Fiat payment marked as sent. Waiting for the seller to confirm receipt and release your sats.'**
  String get tradeInstructionFiatSentBuyer;

  /// Instruction for seller while trade is active
  ///
  /// In en, this message translates to:
  /// **'Contact the buyer with payment instructions via the chat above.'**
  String get tradeInstructionActiveSeller;

  /// Instruction for seller after buyer marks fiat sent
  ///
  /// In en, this message translates to:
  /// **'The buyer has confirmed they sent the fiat payment. Once you verify receipt, release the sats.'**
  String get tradeInstructionFiatSentSeller;

  /// Instruction while a dispute is in progress
  ///
  /// In en, this message translates to:
  /// **'A dispute resolver has been assigned. They will contact you through the app.'**
  String get tradeInstructionDisputed;

  /// Instruction while the order is pending a taker
  ///
  /// In en, this message translates to:
  /// **'Your order is published and waiting for a counterpart to take it. You can cancel it at any time.'**
  String get tradeInstructionPending;

  /// Instruction when the trade was cancelled
  ///
  /// In en, this message translates to:
  /// **'This trade was cancelled. No funds were exchanged.'**
  String get tradeInstructionCancelled;

  /// Generic in-progress instruction fallback
  ///
  /// In en, this message translates to:
  /// **'Trade in progress.'**
  String get tradeInstructionInProgress;

  /// Fallback for the trade amount when the order is unknown
  ///
  /// In en, this message translates to:
  /// **'the agreed amount'**
  String get theAgreedAmount;

  /// Headline while the order is pending
  ///
  /// In en, this message translates to:
  /// **'Waiting for someone to take your order'**
  String get tradeHeadlinePending;

  /// Headline while the order is taken but the trade state is not known in detail
  ///
  /// In en, this message translates to:
  /// **'The trade is being set up'**
  String get tradeHeadlineInProgress;

  /// Headline for buyer while waiting for invoice
  ///
  /// In en, this message translates to:
  /// **'Share a Lightning invoice to receive your sats'**
  String get tradeHeadlineWaitingInvoiceBuyer;

  /// Headline for seller while waiting for invoice
  ///
  /// In en, this message translates to:
  /// **'Waiting for the buyer to share an invoice'**
  String get tradeHeadlineWaitingInvoiceSeller;

  /// Headline for buyer while waiting for payment
  ///
  /// In en, this message translates to:
  /// **'Waiting for the seller to lock the sats'**
  String get tradeHeadlineWaitingPaymentBuyer;

  /// Headline for seller while waiting for payment
  ///
  /// In en, this message translates to:
  /// **'Pay the hold invoice to lock the sats'**
  String get tradeHeadlineWaitingPaymentSeller;

  /// Headline for buyer to send fiat
  ///
  /// In en, this message translates to:
  /// **'Send {amount} to the seller'**
  String tradeHeadlineActiveBuyer(String amount);

  /// Headline for seller waiting for fiat
  ///
  /// In en, this message translates to:
  /// **'Waiting for the buyer to send {amount}'**
  String tradeHeadlineActiveSeller(String amount);

  /// Headline for buyer waiting for release
  ///
  /// In en, this message translates to:
  /// **'Waiting for the seller to release your sats'**
  String get tradeHeadlineFiatSentBuyer;

  /// Headline for seller to confirm receipt
  ///
  /// In en, this message translates to:
  /// **'Confirm you received {amount}'**
  String tradeHeadlineFiatSentSeller(String amount);

  /// Headline while a dispute is in progress
  ///
  /// In en, this message translates to:
  /// **'Dispute in progress'**
  String get tradeHeadlineDisputed;

  /// Headline when the order was cancelled
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get tradeHeadlineCancelled;

  /// Headline while the trade is loading
  ///
  /// In en, this message translates to:
  /// **'Loading trade…'**
  String get tradeHeadlineLoading;

  /// Timer consequence while the order is pending
  ///
  /// In en, this message translates to:
  /// **'If it expires, the order is removed from the book. It won\'t affect your reputation.'**
  String get tradeTimerPendingConsequence;

  /// Timer consequence for the waiting-invoice/payment state
  ///
  /// In en, this message translates to:
  /// **'If it expires, the trade is cancelled and the order returns to the book.'**
  String get tradeTimerWaitingInvoiceConsequence;

  /// Timeline step: order taken
  ///
  /// In en, this message translates to:
  /// **'Order taken'**
  String get tradeStepOrderTaken;

  /// Timeline step for buyer: share invoice
  ///
  /// In en, this message translates to:
  /// **'The seller locks the sats'**
  String get tradeStepInvoiceBuyer;

  /// Timeline step for seller: lock sats
  ///
  /// In en, this message translates to:
  /// **'You lock the sats'**
  String get tradeStepInvoiceSeller;

  /// Timeline step for buyer: send fiat
  ///
  /// In en, this message translates to:
  /// **'You send the fiat payment'**
  String get tradeStepFiatBuyer;

  /// Timeline step for seller: buyer sends fiat
  ///
  /// In en, this message translates to:
  /// **'The buyer sends the fiat payment'**
  String get tradeStepFiatSeller;

  /// Timeline step for buyer: seller releases sats
  ///
  /// In en, this message translates to:
  /// **'The seller releases your sats'**
  String get tradeStepReleaseBuyer;

  /// Timeline step for seller: confirm and release
  ///
  /// In en, this message translates to:
  /// **'You confirm and release the sats'**
  String get tradeStepReleaseSeller;

  /// Timeline step and CTA: rate your counterpart
  ///
  /// In en, this message translates to:
  /// **'Rate the trade'**
  String get tradeStepRate;

  /// Created-at label in the meta footer
  ///
  /// In en, this message translates to:
  /// **'created {date}'**
  String tradeCreatedAtLabel(String date);

  /// Step pill showing progress
  ///
  /// In en, this message translates to:
  /// **'STEP {current} OF {total}'**
  String stepIndicator(int current, int total);

  /// Primary CTA: add Lightning invoice
  ///
  /// In en, this message translates to:
  /// **'Add Lightning invoice'**
  String get addLightningInvoiceButton;

  /// Primary CTA: view dispute
  ///
  /// In en, this message translates to:
  /// **'View dispute'**
  String get viewDisputeButton;

  /// Header of the trade step timeline
  ///
  /// In en, this message translates to:
  /// **'YOUR TRADE'**
  String get yourTradeTimelineTitle;

  /// Snackbar shown when sending a chat message fails
  ///
  /// In en, this message translates to:
  /// **'Failed to send message. Please try again.'**
  String get messageSendFailed;

  /// Shown when the chat room has no valid trade ID
  ///
  /// In en, this message translates to:
  /// **'Invalid trade ID'**
  String get invalidTradeId;

  /// Side panel hint on tablet/desktop chat when no panel is selected
  ///
  /// In en, this message translates to:
  /// **'Select ℹ or 👤\nfor details'**
  String get selectForDetailsHint;

  /// Empty state inside a chat room
  ///
  /// In en, this message translates to:
  /// **'No messages yet.\nSay hello to {handle}!'**
  String noMessagesYet(String handle);

  /// Tooltip for the trade info toggle in the chat room
  ///
  /// In en, this message translates to:
  /// **'Exchange Info'**
  String get exchangeInfoTooltip;

  /// Tooltip for the user info toggle in the chat room
  ///
  /// In en, this message translates to:
  /// **'User Info'**
  String get userInfoTooltip;

  /// App bar subtitle in a chat room
  ///
  /// In en, this message translates to:
  /// **'You are chatting with {handle}'**
  String chattingWith(String handle);

  /// Fallback handle when the peer is unknown
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownPeerHandle;

  /// Chat screen tab: messages
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messagesTab;

  /// Chat screen tab: disputes
  ///
  /// In en, this message translates to:
  /// **'Disputes'**
  String get disputesTab;

  /// Title of the trade information panel
  ///
  /// In en, this message translates to:
  /// **'Trade Information'**
  String get tradeInformationTitle;

  /// Label for the order ID field
  ///
  /// In en, this message translates to:
  /// **'Order ID'**
  String get orderIdLabel;

  /// Label for the fiat amount field
  ///
  /// In en, this message translates to:
  /// **'Fiat Amount'**
  String get fiatAmountLabel;

  /// Label for the sats amount field
  ///
  /// In en, this message translates to:
  /// **'Sats Amount'**
  String get satsAmountLabel;

  /// Label for the status field
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// Label for the payment method field
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethodLabel;

  /// Label for the created date field
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createdLabel;

  /// Placeholder note in the trade information panel
  ///
  /// In en, this message translates to:
  /// **'Details wired when trade provider available (Phase 10+)'**
  String get tradeDetailsPlaceholder;

  /// Title of the user information panel
  ///
  /// In en, this message translates to:
  /// **'User Information'**
  String get userInformationTitle;

  /// Label for the peer public key
  ///
  /// In en, this message translates to:
  /// **'Peer\'s Public Key'**
  String get peerPublicKeyLabel;

  /// Label for the shared key
  ///
  /// In en, this message translates to:
  /// **'Your Shared Key'**
  String get yourSharedKeyLabel;

  /// Placeholder note for the shared key
  ///
  /// In en, this message translates to:
  /// **'Available after bridge integration (Phase 10+)'**
  String get sharedKeyPlaceholder;

  /// Safety note about the shared key
  ///
  /// In en, this message translates to:
  /// **'Keep your shared key safe — it is needed for dispute resolution'**
  String get sharedKeySafetyNote;

  /// Label shown on a chat bubble that has a file attachment
  ///
  /// In en, this message translates to:
  /// **'[Attachment]'**
  String get attachmentLabel;

  /// Tooltip for the file download button
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadTooltip;

  /// Placeholder snackbar for file download (not yet wired)
  ///
  /// In en, this message translates to:
  /// **'File download wired in Phase 10+'**
  String get fileDownloadPlaceholder;

  /// File type chip: video
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get fileTypeVideo;

  /// File type chip: image
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get fileTypeImage;

  /// File type chip: archive
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get fileTypeArchive;

  /// File type chip: generic file
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fileTypeFile;

  /// Hint on an encrypted image placeholder
  ///
  /// In en, this message translates to:
  /// **'Tap to download'**
  String get tapToDownload;

  /// Placeholder snackbar for image download (not yet wired)
  ///
  /// In en, this message translates to:
  /// **'Image download wired in Phase 10+'**
  String get imageDownloadPlaceholder;

  /// Trade state header amount when buying
  ///
  /// In en, this message translates to:
  /// **'Buying {sats} sats'**
  String buyingSatsAmount(String sats);

  /// Trade state header amount when selling
  ///
  /// In en, this message translates to:
  /// **'Selling {sats} sats'**
  String sellingSatsAmount(String sats);

  /// Link in the trade state header to view the order
  ///
  /// In en, this message translates to:
  /// **'View order'**
  String get viewOrderLink;

  /// Countdown label showing remaining time
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String timeLeftLabel(String time);

  /// Add-invoice screen: the daemon answered NotAllowedByStatus — the order moved on (usually an earlier submission was accepted) and the app is re-reading its state
  ///
  /// In en, this message translates to:
  /// **'This order is no longer waiting for an invoice. Updating its status…'**
  String get invoiceNoLongerExpected;

  /// Add-invoice screen: a second submission was refused because an earlier one for the same trade is still waiting for the daemon's reply (Rust marker InvoiceSubmitInFlight)
  ///
  /// In en, this message translates to:
  /// **'An invoice for this order is already being sent. Wait for the reply.'**
  String get invoiceSubmitInFlight;

  /// Snackbar when submitting an LN address before the sats amount is known
  ///
  /// In en, this message translates to:
  /// **'Waiting for trade amount — please try again shortly.'**
  String get waitingForTradeAmount;

  /// Loading text while resolving the trade amount
  ///
  /// In en, this message translates to:
  /// **'Fetching trade amount…'**
  String get fetchingTradeAmount;

  /// Button to switch to manual invoice entry
  ///
  /// In en, this message translates to:
  /// **'Enter invoice manually'**
  String get enterInvoiceManually;

  /// Generic submit button label
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submitButton;

  /// Title of the counterpart reputation card when the taker is the buyer
  ///
  /// In en, this message translates to:
  /// **'Buyer reputation'**
  String get buyerReputation;

  /// Title of the counterpart reputation card when the taker is the seller
  ///
  /// In en, this message translates to:
  /// **'Seller reputation'**
  String get sellerReputation;

  /// Reputation stat label: rating
  ///
  /// In en, this message translates to:
  /// **'rating'**
  String get ratingStatLabel;

  /// Reputation stat label: trades
  ///
  /// In en, this message translates to:
  /// **'trades'**
  String get tradesStatLabel;

  /// Reputation stat label: days active
  ///
  /// In en, this message translates to:
  /// **'days active'**
  String get daysActiveStatLabel;

  /// Countdown label below the take-order timer
  ///
  /// In en, this message translates to:
  /// **'Time remaining: {time}'**
  String timeRemainingLabel(String time);

  /// Shown when a fixed-sats order amount is outside the node min/max order amount
  ///
  /// In en, this message translates to:
  /// **'Amount must be between {min} and {max} sats for this Mostro node'**
  String orderAmountOutOfRange(int min, int max);

  /// Shown when a market-price order amount converts outside the node min/max order amount, with the range expressed in the user's fiat currency
  ///
  /// In en, this message translates to:
  /// **'Amount must be between {min} and {max} {currency} for this Mostro node'**
  String orderAmountOutOfRangeFiat(int min, int max, String currency);

  /// Price type value: market
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get priceTypeMarket;

  /// Price type value: fixed
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get priceTypeFixed;

  /// Tooltip for the price type info button
  ///
  /// In en, this message translates to:
  /// **'Price type info'**
  String get priceTypeInfoTooltip;

  /// Label of the premium slider section
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get premiumSectionLabel;

  /// Explains why the fixed-price toggle is disabled while a range order is being created
  ///
  /// In en, this message translates to:
  /// **'Fixed price isn\'t available for range orders. Turn off the range to use a fixed price.'**
  String get fixedPriceRangeNotAvailable;

  /// Title of the price types info dialog
  ///
  /// In en, this message translates to:
  /// **'Price Types'**
  String get priceTypesDialogTitle;

  /// Body of the price types info dialog
  ///
  /// In en, this message translates to:
  /// **'Market Price: Your order price follows the market rate with a premium/discount percentage applied.\n\nFixed Price: You set an exact price in satoshis.'**
  String get priceTypesDialogContent;

  /// Create-order screen title (sentence case, not caps)
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get newOrderTitle;

  /// Amount card title when selling
  ///
  /// In en, this message translates to:
  /// **'How much you sell'**
  String get amountSectionSell;

  /// Amount card title when buying
  ///
  /// In en, this message translates to:
  /// **'How much you buy'**
  String get amountSectionBuy;

  /// Segment: one fiat amount
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get amountModeSingle;

  /// Segment: min/max fiat range
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get amountModeRange;

  /// Label of the range minimum field (rendered uppercase)
  ///
  /// In en, this message translates to:
  /// **'Minimum'**
  String get amountMinLabel;

  /// Label of the range maximum field (rendered uppercase)
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get amountMaxLabel;

  /// Counter in the payment-methods card header
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{none chosen} =1{1 chosen} other{{count} chosen}}'**
  String paymentMethodsChosenCount(int count);

  /// Chip that opens the payment-method picker; also the button that turns the custom text into a chip
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get paymentMethodAdd;

  /// Search field hint on the payment-method picker screen
  ///
  /// In en, this message translates to:
  /// **'Search methods'**
  String get paymentMethodSearchHint;

  /// Heading of the free-text method field on the picker screen
  ///
  /// In en, this message translates to:
  /// **'Custom payment method'**
  String get customPaymentMethodLabel;

  /// Price card title
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get priceSectionTitle;

  /// Slider caption: selling with a positive premium
  ///
  /// In en, this message translates to:
  /// **'You sell {premium}% above market price'**
  String premiumSellAbove(String premium);

  /// Slider caption: selling with a negative premium
  ///
  /// In en, this message translates to:
  /// **'You sell {premium}% below market'**
  String premiumSellBelow(String premium);

  /// Slider caption: buying with a negative premium
  ///
  /// In en, this message translates to:
  /// **'You pay {premium}% less than market'**
  String premiumBuyBelow(String premium);

  /// Slider caption: buying with a positive premium
  ///
  /// In en, this message translates to:
  /// **'You pay {premium}% more'**
  String premiumBuyAbove(String premium);

  /// Slider caption at 0% premium
  ///
  /// In en, this message translates to:
  /// **'Exact market price'**
  String get premiumExactMarket;

  /// Note under the fixed sats field
  ///
  /// In en, this message translates to:
  /// **'At a fixed price the order does not follow the market: the sats amount stays exactly as you write it.'**
  String get fixedPriceNote;

  /// Preview line while no amount has been entered
  ///
  /// In en, this message translates to:
  /// **'Write an amount and you\'ll see here how the order looks.'**
  String get previewHintNoAmount;

  /// Preview: market sell with premium. active is the optional expiry suffix
  ///
  /// In en, this message translates to:
  /// **'You sell BTC for {amount} at market price {premium}{active}'**
  String previewSellMarket(String amount, String premium, String active);

  /// Preview: market sell at 0% premium
  ///
  /// In en, this message translates to:
  /// **'You sell BTC for {amount} at market price{active}'**
  String previewSellMarketExact(String amount, String active);

  /// Preview: market buy with premium
  ///
  /// In en, this message translates to:
  /// **'You buy BTC for {amount} at market price {premium}{active}'**
  String previewBuyMarket(String amount, String premium, String active);

  /// Preview: market buy at 0% premium
  ///
  /// In en, this message translates to:
  /// **'You buy BTC for {amount} at market price{active}'**
  String previewBuyMarketExact(String amount, String active);

  /// Preview: fixed-price sell. sats already carries the unit
  ///
  /// In en, this message translates to:
  /// **'You sell {sats} for {amount} at a fixed price{active}'**
  String previewSellFixed(String sats, String amount, String active);

  /// Preview: fixed-price buy
  ///
  /// In en, this message translates to:
  /// **'You buy {sats} for {amount} at a fixed price{active}'**
  String previewBuyFixed(String sats, String amount, String active);

  /// Expiry suffix appended to the preview; hours already carries the unit (24 h)
  ///
  /// In en, this message translates to:
  /// **' · active {hours}'**
  String previewActiveSuffix(String hours);

  /// Primary action of the create-order screen
  ///
  /// In en, this message translates to:
  /// **'Publish order'**
  String get publishOrder;

  /// Accessibility label of the × on a chosen payment-method chip
  ///
  /// In en, this message translates to:
  /// **'Remove {method}'**
  String removePaymentMethod(String method);

  /// Unit suffix of the fixed sats field
  ///
  /// In en, this message translates to:
  /// **'sats'**
  String get satsUnitLabel;

  /// A sats figure; amount is already grouped for the locale
  ///
  /// In en, this message translates to:
  /// **'{amount} sats'**
  String satsAmount(String amount);

  /// Order expiry in hours, as shown in the preview
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String durationHours(int hours);

  /// Label of the payment methods section
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get paymentMethodsLabel;

  /// Hint for the custom payment method input
  ///
  /// In en, this message translates to:
  /// **'Custom payment method...'**
  String get customPaymentMethodHint;

  /// Validation error when the amount is out of range
  ///
  /// In en, this message translates to:
  /// **'Amount must be between {min} and {max}'**
  String amountRangeError(String min, String max);

  /// Title of the range amount dialog
  ///
  /// In en, this message translates to:
  /// **'Enter Amount'**
  String get enterAmountTitle;

  /// Range bounds label in the amount dialog
  ///
  /// In en, this message translates to:
  /// **'Min: {min} – Max: {max} {currency}'**
  String minMaxRangeLabel(String min, String max, String currency);

  /// Snackbar shown when submitting a rating fails
  ///
  /// In en, this message translates to:
  /// **'Rating failed. Please try again.'**
  String get ratingFailed;

  /// Uppercase submit button on the rate screen
  ///
  /// In en, this message translates to:
  /// **'SUBMIT'**
  String get submitUppercaseButton;

  /// Tooltip for a star in the rating selector
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Select 1 star} other{Select {count} stars}}'**
  String selectStarTooltip(int count);

  /// Title of the dispute info card
  ///
  /// In en, this message translates to:
  /// **'Dispute Details'**
  String get disputeDetailsTitle;

  /// Label for the dispute ID field
  ///
  /// In en, this message translates to:
  /// **'Dispute ID'**
  String get disputeIdLabel;

  /// Label showing the dispute reason
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String disputeReasonLabel(String reason);

  /// Sender label for administrator messages in a dispute
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get adminLabel;

  /// App bar title of the dispute chat screen
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get disputeScreenTitle;

  /// Title of the order filter dialog
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filtersDialogTitle;

  /// Button that resets all filters
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetButton;

  /// Section label for the currency filter
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyLabel;

  /// Section label for the rating filter
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get ratingLabel;

  /// Button that applies the filters and closes the dialog
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyButton;

  /// Accessibility label for a reactive button in the success state
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get successLabel;

  /// Button that copies the Lightning invoice
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyButton;

  /// Button that shares the Lightning invoice
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareButton;

  /// Prompt above a Lightning address confirmation
  ///
  /// In en, this message translates to:
  /// **'Send {sats} sats to:'**
  String sendSatsToAddress(String sats);

  /// Button that returns to edit the Lightning address
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeButton;

  /// Snackbar shown when a notification has no linked detail to open
  ///
  /// In en, this message translates to:
  /// **'Unable to open notification details.'**
  String get unableToOpenNotification;

  /// Order-book reason badge: best premium
  ///
  /// In en, this message translates to:
  /// **'Best premium'**
  String get reasonBestPremium;

  /// Order-book reason badge: most reputable
  ///
  /// In en, this message translates to:
  /// **'Most reputable'**
  String get reasonMostReputable;

  /// Caption under an order-book card amount
  ///
  /// In en, this message translates to:
  /// **'Market price'**
  String get marketPriceCaption;

  /// Unit word after the trade count in the order-book reputation row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{trade} other{trades}}'**
  String reputationTradesLabel(int count);

  /// Unit word after the active-days count in the order-book reputation row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day} other{days}}'**
  String reputationDaysLabel(int count);

  /// Sort caption on the order-book filter row; must describe the ordering actually applied (newest first)
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get sortNewest;

  /// Number of orders listed on the order-book filter row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 order} other{{count} orders}}'**
  String ordersCount(int count);

  /// Order-book sort option: the premium that favours the taker most first (lowest when buying BTC, highest when selling)
  ///
  /// In en, this message translates to:
  /// **'Best premium'**
  String get sortBestPremium;

  /// Order-book sort option: highest maker rating first, then most trades
  ///
  /// In en, this message translates to:
  /// **'Best reputation'**
  String get sortBestReputation;

  /// Title of the order-book sort picker
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortSheetTitle;

  /// Small caption under the premium percentage on an order-book card
  ///
  /// In en, this message translates to:
  /// **'premium'**
  String get orderCardPremiumCaption;

  /// Caption under a fixed-sats order amount. {sats} is the already formatted figure with its unit (satsAmount); place it wherever the language needs it
  ///
  /// In en, this message translates to:
  /// **'Fixed amount · for {sats}'**
  String orderFixedAmount(String sats);

  /// Replaces the rating on an order-book card when the maker has no trades yet
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get reputationNew;

  /// Replaces the trade count on an order-book card when the maker has no trades yet
  ///
  /// In en, this message translates to:
  /// **'no trades'**
  String get reputationNoTrades;

  /// Bottom navigation label for the order book tab (short)
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get bottomNavBook;

  /// Bottom navigation label for the my-trades tab (short)
  ///
  /// In en, this message translates to:
  /// **'Trades'**
  String get bottomNavTrades;

  /// Hint under the Buy/Sell buttons of the open create-order button
  ///
  /// In en, this message translates to:
  /// **'Tap outside to close'**
  String get fabDismissHint;

  /// Accessibility label of the round create-order button
  ///
  /// In en, this message translates to:
  /// **'Create order'**
  String get addOrderFabLabel;

  /// Order-book empty state line when no filter is active
  ///
  /// In en, this message translates to:
  /// **'New orders appear here as soon as they are published.'**
  String get ordersEmptyHint;

  /// Order-book empty state line when filters hide every order
  ///
  /// In en, this message translates to:
  /// **'No orders match your filters.'**
  String get ordersEmptyFilteredHint;

  /// Order-book empty state action that resets every filter
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFiltersButton;

  /// Notification group action to collapse earlier events
  ///
  /// In en, this message translates to:
  /// **'Hide earlier events'**
  String get hideEarlierEvents;

  /// Notification group action to expand earlier events
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{View 1 earlier event} other{View {count} earlier events}}'**
  String viewEarlierEvents(int count);

  /// Notification group footer link to the trade
  ///
  /// In en, this message translates to:
  /// **'Go to trade'**
  String get goToTrade;

  /// Word 'Dispute' used in a notification group title
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get disputeWord;

  /// Word 'Trade' used in a notification group title
  ///
  /// In en, this message translates to:
  /// **'Trade'**
  String get tradeWord;

  /// Notifications filter chip: all
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notifFilterAll;

  /// Notifications filter chip: disputes
  ///
  /// In en, this message translates to:
  /// **'Disputes'**
  String get notifFilterDisputes;

  /// Notifications filter chip: disputes with count
  ///
  /// In en, this message translates to:
  /// **'Disputes · {count}'**
  String notifFilterDisputesCount(int count);

  /// Notifications filter chip: system
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get notifFilterSystem;

  /// Notifications filter chip: system with count
  ///
  /// In en, this message translates to:
  /// **'System · {count}'**
  String notifFilterSystemCount(int count);

  /// NWC pay button label while paying
  ///
  /// In en, this message translates to:
  /// **'Paying...'**
  String get payingStatus;

  /// NWC pay button label
  ///
  /// In en, this message translates to:
  /// **'Pay with Wallet'**
  String get payWithWalletButton;

  /// Status while auto-generating a Lightning invoice via NWC
  ///
  /// In en, this message translates to:
  /// **'Generating invoice via NWC...'**
  String get generatingInvoiceNwc;

  /// Error when NWC invoice auto-generation fails
  ///
  /// In en, this message translates to:
  /// **'Unable to generate invoice automatically'**
  String get unableToGenerateInvoice;

  /// Accessibility label for the peer avatar icon
  ///
  /// In en, this message translates to:
  /// **'Avatar icon'**
  String get avatarIconLabel;

  /// Dispute list-item summary: resolved in the buyer's favour
  ///
  /// In en, this message translates to:
  /// **'Dispute resolved in buyer\'s favour'**
  String get disputeDescResolvedBuyerFavour;

  /// Dispute list-item summary: resolved in the viewing user's favour
  ///
  /// In en, this message translates to:
  /// **'Dispute resolved in your favour'**
  String get disputeDescResolvedYourFavour;

  /// Dispute list-item summary: resolved in the seller's favour
  ///
  /// In en, this message translates to:
  /// **'Dispute resolved in seller\'s favour'**
  String get disputeDescResolvedSellerFavour;

  /// Dispute list-item summary: order cancelled cooperatively
  ///
  /// In en, this message translates to:
  /// **'Order cancelled cooperatively'**
  String get disputeDescCooperativeCancel;

  /// Dispute list-item summary: generic resolved outcome
  ///
  /// In en, this message translates to:
  /// **'Dispute resolved'**
  String get disputeDescResolved;

  /// Dispute list-item summary: the viewing user opened the dispute
  ///
  /// In en, this message translates to:
  /// **'You opened this dispute'**
  String get disputeDescYouOpened;

  /// Dispute list-item summary: the counterpart opened the dispute
  ///
  /// In en, this message translates to:
  /// **'Counterpart opened this dispute'**
  String get disputeDescCounterpartOpened;

  /// Notification bell accessibility label when there are no unread notifications
  ///
  /// In en, this message translates to:
  /// **'Notifications, no unread notifications'**
  String get notificationsBellNoUnread;

  /// Notification bell accessibility label when the backup reminder is active
  ///
  /// In en, this message translates to:
  /// **'Notifications, backup reminder active'**
  String get notificationsBellBackupActive;

  /// Notification bell accessibility label with the unread count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Notifications, 1 unread} other{Notifications, {count} unread}}'**
  String notificationsBellUnread(int count);

  /// Drawer menu item badge accessibility hint with the number of new items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new} other{{count} new}}'**
  String drawerBadgeNewCount(int count);

  /// Bond-slashed dialog button: opens the About screen with the node's bond policy
  ///
  /// In en, this message translates to:
  /// **'View policy'**
  String get bondSlashedViewPolicy;

  /// Bond-slashed dialog button: opens the trade
  ///
  /// In en, this message translates to:
  /// **'View trade'**
  String get bondSlashedViewTrade;

  /// Trade detail durable notice after a dispute-cause slash; sats formatted
  ///
  /// In en, this message translates to:
  /// **'The node slashed your {sats}-sat bond in this dispute.'**
  String bondSlashedTradeNoticeDispute(String sats);

  /// Trade detail durable notice after a timeout slash; sats formatted
  ///
  /// In en, this message translates to:
  /// **'The node slashed your {sats}-sat bond after a step timed out.'**
  String bondSlashedTradeNoticeTimeout(String sats);

  /// Title of the notification shown when the user's anti-abuse bond is slashed
  ///
  /// In en, this message translates to:
  /// **'Bond slashed'**
  String get bondSlashedTitle;

  /// Bond-slashed notification body when the slash was caused by a waiting-state timeout
  ///
  /// In en, this message translates to:
  /// **'Your {amount}-sat anti-abuse bond for order {orderId} was forfeited after a waiting-state timeout. Your order status is unchanged.'**
  String bondSlashedMessageTimeout(String amount, String orderId);

  /// Bond-slashed notification body when the slash was caused by a dispute resolution
  ///
  /// In en, this message translates to:
  /// **'Your {amount}-sat anti-abuse bond for order {orderId} was forfeited after a dispute resolution. Your order status is unchanged.'**
  String bondSlashedMessageDispute(String amount, String orderId);

  /// Bond-slashed detail value: the slash cause was a waiting-state timeout
  ///
  /// In en, this message translates to:
  /// **'Waiting-state timeout'**
  String get bondSlashedCauseTimeout;

  /// Bond-slashed detail value: the slash cause was a dispute resolution
  ///
  /// In en, this message translates to:
  /// **'Dispute resolution'**
  String get bondSlashedCauseDispute;

  /// Bond-slashed detail label for the order id
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get bondSlashedDetailOrder;

  /// Bond-slashed detail label for the slashed bond amount
  ///
  /// In en, this message translates to:
  /// **'Bond amount'**
  String get bondSlashedDetailAmount;

  /// Bond-slashed detail label for the slash cause
  ///
  /// In en, this message translates to:
  /// **'Cause'**
  String get bondSlashedDetailCause;

  /// Bond-slashed detail label for the fiat amount and currency
  ///
  /// In en, this message translates to:
  /// **'Fiat'**
  String get bondSlashedDetailFiat;

  /// Bond-slashed detail label for the payment method
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get bondSlashedDetailPaymentMethod;

  /// About screen — a pluralized day count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} day} other{{count} days}}'**
  String aboutDaysValue(int count);

  /// About screen — section header shown when the node settles trades with Cashu ecash instead of Lightning
  ///
  /// In en, this message translates to:
  /// **'Cashu escrow'**
  String get aboutCashuEscrowSection;

  /// About screen — Cashu mint URL row label
  ///
  /// In en, this message translates to:
  /// **'Mint'**
  String get aboutCashuMintUrlLabel;

  /// About screen — shown when a node says it runs Cashu but publishes no mint, which means trades cannot run
  ///
  /// In en, this message translates to:
  /// **'Not advertised'**
  String get aboutCashuMintNotAdvertised;

  /// About screen — Cashu escrow locktime row label
  ///
  /// In en, this message translates to:
  /// **'Escrow locktime'**
  String get aboutCashuLocktimeLabel;

  /// About screen — Cashu settlement margin row label
  ///
  /// In en, this message translates to:
  /// **'Settlement margin'**
  String get aboutCashuSettlementMarginLabel;

  /// Name of the Lightning settlement backend
  ///
  /// In en, this message translates to:
  /// **'Lightning'**
  String get escrowModeLightning;

  /// Name of the Cashu ecash settlement backend
  ///
  /// In en, this message translates to:
  /// **'Cashu'**
  String get escrowModeCashu;

  /// Shown when the node publishes no settlement backend, which is not the same as knowing it uses Lightning
  ///
  /// In en, this message translates to:
  /// **'Not advertised'**
  String get escrowModeUnknown;

  /// Settings — title of the debug-only card that forces the escrow backend
  ///
  /// In en, this message translates to:
  /// **'Escrow backend (developer)'**
  String get settingsEscrowOverrideTitle;

  /// Settings — subtitle of the debug-only escrow backend override card
  ///
  /// In en, this message translates to:
  /// **'Test Cashu against a node that does not advertise it yet. Debug builds only.'**
  String get settingsEscrowOverrideSubtitle;

  /// Settings — switch that makes the app treat the node as running Cashu regardless of what it advertises
  ///
  /// In en, this message translates to:
  /// **'Force Cashu escrow'**
  String get settingsForceCashuLabel;

  /// Settings — text field for a mint URL to use instead of the node's
  ///
  /// In en, this message translates to:
  /// **'Mint URL override'**
  String get settingsCashuMintOverrideLabel;

  /// Settings — button that saves the mint URL override
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get settingsCashuMintOverrideApply;

  /// Settings — error shown when the entered mint URL is rejected
  ///
  /// In en, this message translates to:
  /// **'That is not a valid mint URL. Use http or https with a host.'**
  String get settingsCashuMintOverrideInvalid;

  /// Settings — the backend the app is actually acting on, overrides included
  ///
  /// In en, this message translates to:
  /// **'Effective backend: {mode}'**
  String settingsEscrowEffectiveMode(String mode);

  /// Settings — the mint the app is actually acting on, overrides included
  ///
  /// In en, this message translates to:
  /// **'Effective mint: {mint}'**
  String settingsEscrowEffectiveMint(String mint);

  /// Settings — warning shown when Cashu mode is on but no mint is available, so no Cashu path can run
  ///
  /// In en, this message translates to:
  /// **'Cashu cannot run without a mint — set one below.'**
  String get settingsEscrowCashuUnavailable;

  /// No description provided for @tradeStatusPayoutPending.
  ///
  /// In en, this message translates to:
  /// **'Payout pending'**
  String get tradeStatusPayoutPending;

  /// No description provided for @tradeHeadlinePayoutPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the buyer payout'**
  String get tradeHeadlinePayoutPending;

  /// No description provided for @tradeInstructionPayoutPending.
  ///
  /// In en, this message translates to:
  /// **'The seller released the escrow. Waiting for the Lightning payment to the buyer to succeed.'**
  String get tradeInstructionPayoutPending;

  /// App bar title of the trade screen
  ///
  /// In en, this message translates to:
  /// **'Your trade'**
  String get tradeScreenTitle;

  /// Status chip while the user waits on the counterpart (uppercase)
  ///
  /// In en, this message translates to:
  /// **'WAITING'**
  String get tradeChipWaiting;

  /// Status chip of an active trade while the counterpart acts (uppercase)
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get tradeChipActive;

  /// Status chip when the user has something to do (uppercase)
  ///
  /// In en, this message translates to:
  /// **'YOUR TURN'**
  String get tradeChipYourTurn;

  /// Status chip of a disputed trade (uppercase)
  ///
  /// In en, this message translates to:
  /// **'DISPUTE'**
  String get tradeChipDispute;

  /// Line shown in place of the chat card until the trade is active
  ///
  /// In en, this message translates to:
  /// **'No chat yet: until the trade is active, neither party knows who the other is.'**
  String get tradeChatLockedNote;

  /// Subtitle of the chat card under the counterpart alias
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted chat'**
  String get tradeChatEncrypted;

  /// Step body for the buyer while the seller pays the hold invoice
  ///
  /// In en, this message translates to:
  /// **'They\'re paying the hold invoice. Once the sats are locked, it\'s your turn to pay the fiat.'**
  String get tradeBodyWaitingPaymentBuyer;

  /// Step body for the seller of an active trade; {method} is the payment method
  ///
  /// In en, this message translates to:
  /// **'Share your {method} details in the chat above.'**
  String tradeBodyActiveSeller(String method);

  /// Step body for the buyer of an active trade; {method} is the payment method
  ///
  /// In en, this message translates to:
  /// **'Via {method}, with the details they shared in the chat. Once you\'ve sent it, mark it below.'**
  String tradeBodyActiveBuyer(String method);

  /// Step body for the seller once the buyer marked the fiat as sent; {method} is the payment method
  ///
  /// In en, this message translates to:
  /// **'The buyer marked the payment as sent. Check your {method} account before releasing.'**
  String tradeBodyFiatSentSeller(String method);

  /// Warning inside the step block before releasing
  ///
  /// In en, this message translates to:
  /// **'Releasing the sats cannot be undone.'**
  String get tradeReleaseIrreversible;

  /// Countdown label when the user must act
  ///
  /// In en, this message translates to:
  /// **'You have'**
  String get tradeTimerYouHave;

  /// Countdown label when the counterpart must act
  ///
  /// In en, this message translates to:
  /// **'They have'**
  String get tradeTimerTheyHave;

  /// Countdown label of a pending order's time in the book
  ///
  /// In en, this message translates to:
  /// **'Time left'**
  String get tradeTimerOrderHas;

  /// Note under the countdown of an active trade
  ///
  /// In en, this message translates to:
  /// **'If you need more time, coordinate in the chat before it expires.'**
  String get tradeTimerNoteCoordinate;

  /// Counterpart role on the reputation row
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get tradeRoleBuyer;

  /// Counterpart role on the reputation row
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get tradeRoleSeller;

  /// Number of trades on the reputation row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trade} other{{count} trades}}'**
  String reputationTradesCount(int count);

  /// Account age on the reputation row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day on Mostro} other{{count} days on Mostro}}'**
  String reputationDaysOnMostro(int count);

  /// Primary action of the buyer once the fiat is sent
  ///
  /// In en, this message translates to:
  /// **'I\'ve sent the payment'**
  String get tradeFiatSentAction;

  /// Closes the trade screen
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get tradeCloseAction;

  /// Submits the counterpart rating from the completed card
  ///
  /// In en, this message translates to:
  /// **'Send rating'**
  String get tradeSendRatingAction;

  /// Title of the completed card
  ///
  /// In en, this message translates to:
  /// **'Trade completed'**
  String get tradeCompletedTitle;

  /// Rating row of the completed card; {alias} is the counterpart, {score} 1–5
  ///
  /// In en, this message translates to:
  /// **'You rated {alias} with {score}'**
  String tradeRatedCounterpart(String alias, String score);

  /// Label before the shortened order id
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get tradeIdLabel;

  /// Creation time of an order created today; {time} is HH:mm
  ///
  /// In en, this message translates to:
  /// **'created today {time}'**
  String tradeCreatedTodayLabel(String time);

  /// Title of the release confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Release the sats?'**
  String get releaseSheetTitle;

  /// Body of the release confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone. Only release once the money is in your account.'**
  String get releaseSheetBody;

  /// Confirms the release from the sheet
  ///
  /// In en, this message translates to:
  /// **'Yes, release'**
  String get releaseSheetConfirm;

  /// Dismisses the release sheet
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get releaseSheetBack;

  /// Uppercase side chip on the maker's own sell order (order detail 6a)
  ///
  /// In en, this message translates to:
  /// **'Selling BTC'**
  String get orderSideChipSell;

  /// Uppercase side chip on the maker's own buy order (order detail 6a)
  ///
  /// In en, this message translates to:
  /// **'Buying BTC'**
  String get orderSideChipBuy;

  /// Price line under the amount on the maker's own order; {premium} is the signed percent, e.g. +2.0%
  ///
  /// In en, this message translates to:
  /// **'Market price · {premium} premium'**
  String orderDetailMarketPremium(String premium);

  /// Note under the waiting-for-taker status; {ago} is a relative time such as '3m ago'
  ///
  /// In en, this message translates to:
  /// **'Published {ago}. We\'ll let you know as soon as someone takes it: you can close this screen.'**
  String myOrderWaitingNote(String ago);

  /// Status of the maker's own order once taken, while the buyer's invoice is pending
  ///
  /// In en, this message translates to:
  /// **'Taken · waiting for invoice'**
  String get orderStatusTakenWaitingInvoice;

  /// Status of the maker's own order once taken, while the seller's hold invoice is pending
  ///
  /// In en, this message translates to:
  /// **'Taken · waiting for payment'**
  String get orderStatusTakenWaitingPayment;

  /// Label of the creation date row on the order detail
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get orderDetailCreatedLabel;

  /// Label of the order id row on the order detail
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get orderDetailIdLabel;

  /// Payment methods row when the order accepts more than two: the first method and how many more
  ///
  /// In en, this message translates to:
  /// **'{first} +{count}'**
  String paymentMethodsMore(String first, int count);

  /// Title of the sheet listing every payment method of an order
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get paymentMethodsSheetTitle;

  /// Title of the cancel-order confirmation sheet on the maker's own order
  ///
  /// In en, this message translates to:
  /// **'Cancel the order?'**
  String get cancelOrderSheetTitle;

  /// Body of the cancel-order confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'It is removed from the order book and this cannot be undone.'**
  String get cancelOrderSheetBody;

  /// Text action that dismisses the cancel-order sheet without cancelling
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBackButtonLabel;

  /// Label over the fiat amount when the taker buys BTC (take order 7a)
  ///
  /// In en, this message translates to:
  /// **'You pay'**
  String get takeOrderYouPay;

  /// Label of what the taker receives: the fiat amount when selling BTC, the sats when buying
  ///
  /// In en, this message translates to:
  /// **'You receive'**
  String get takeOrderYouReceive;

  /// Label over the sats the taker hands over when selling BTC
  ///
  /// In en, this message translates to:
  /// **'You send'**
  String get takeOrderYouSend;

  /// Sats row of a range order: the estimate for the minimum amount, e.g. 'from ≈ 8,420 sats'
  ///
  /// In en, this message translates to:
  /// **'from {sats}'**
  String takeOrderSatsFrom(String sats);

  /// Footer of the amount card on a market-price order seen by the taker; {premium} is the signed percent
  ///
  /// In en, this message translates to:
  /// **'Market price · {premium} premium. The final figure is set when you take it.'**
  String takeOrderMarketFooter(String premium);

  /// Footer of the amount card on a fixed-sats sell order seen by the taker; {sats} like '8,420 sats'
  ///
  /// In en, this message translates to:
  /// **'Fixed amount · the seller asks for {sats}'**
  String takeOrderFixedFooterSeller(String sats);

  /// Footer of the amount card on a fixed-sats buy order seen by the taker; {sats} like '8,420 sats'
  ///
  /// In en, this message translates to:
  /// **'Fixed amount · the buyer offers {sats}'**
  String takeOrderFixedFooterBuyer(String sats);

  /// Role of the maker on the counterparty card when they sell BTC
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get counterpartySeller;

  /// Role of the maker on the counterparty card when they buy BTC
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get counterpartyBuyer;

  /// Completed trades of the maker on the counterparty card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} trade} other{{count} trades}}'**
  String counterpartyTrades(int count);

  /// Seniority of the maker on the counterparty card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} day on Mostro} other{{count} days on Mostro}}'**
  String counterpartyDaysOnMostro(int count);

  /// Payment-method row label when the taker buys BTC
  ///
  /// In en, this message translates to:
  /// **'You pay with'**
  String get takeOrderPayWithLabel;

  /// Payment-method row label when the taker sells BTC
  ///
  /// In en, this message translates to:
  /// **'You get paid with'**
  String get takeOrderPaidWithLabel;

  /// Label of the relative publication time row on the take-order screen
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get takeOrderPublishedLabel;

  /// Note above 'Take order' when the taker buys BTC
  ///
  /// In en, this message translates to:
  /// **'When you take it, the seller locks the sats in Mostro. You only pay once they are locked.'**
  String get takeOrderNoteBuyer;

  /// Note above 'Take order' when the taker sells BTC
  ///
  /// In en, this message translates to:
  /// **'When you take it, you lock the sats in Mostro. The buyer pays afterwards.'**
  String get takeOrderNoteSeller;

  /// Primary button of the take-order screen
  ///
  /// In en, this message translates to:
  /// **'Take order'**
  String get takeOrderButton;

  /// 'Take order' while the relay answers
  ///
  /// In en, this message translates to:
  /// **'Taking…'**
  String get takeOrderTaking;

  /// 'Take order' once the order was taken by someone else or expired
  ///
  /// In en, this message translates to:
  /// **'No longer available'**
  String get takeOrderUnavailable;

  /// Replaces the countdown in the app bar once the order is gone
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get takeOrderClosed;

  /// Easter egg shown when the mascot is tapped on 31 October, the whitepaper's anniversary — and Halloween, which Mostro being a monster makes its own joke
  ///
  /// In en, this message translates to:
  /// **'31 October 2008: nine pages, nobody\'s permission. Happy Halloween.'**
  String get easterEggWhitepaper;

  /// Easter egg shown when the mascot is tapped on 3 January: the headline Satoshi embedded in the genesis block. A quotation from The Times — keep it in English, unchanged, in every locale
  ///
  /// In en, this message translates to:
  /// **'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks'**
  String get easterEggGenesis;

  /// Easter egg shown when the mascot is tapped on 22 May, Bitcoin Pizza Day
  ///
  /// In en, this message translates to:
  /// **'22 May 2010: 10,000 BTC for two pizzas. Hope they were good.'**
  String get easterEggPizzaDay;

  /// Uppercase header of the Application group on settings
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get settingsGroupApp;

  /// Uppercase header of the Payments group on settings
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get settingsGroupPayments;

  /// Uppercase header of the Network group on settings
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsGroupNetwork;

  /// Uppercase header of the Help group on settings
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get settingsGroupHelp;

  /// Settings row label for the default fiat currency
  ///
  /// In en, this message translates to:
  /// **'Fiat currency'**
  String get fiatCurrencySettingTitle;

  /// How many push events are on, on the settings row
  ///
  /// In en, this message translates to:
  /// **'{count} of {total}'**
  String notificationsEnabledOfTotal(int count, int total);

  /// Settings value when every push event is off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get notificationsAllOff;

  /// Settings value when no Lightning address is set
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get lightningAddressUnset;

  /// Settings value when no NWC wallet is connected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get nwcWalletNotConnected;

  /// Settings value: how many enabled relays are connected
  ///
  /// In en, this message translates to:
  /// **'{connected} of {total} connected'**
  String relaysConnectedOfTotal(int connected, int total);

  /// Relay summary card subtitle when enough relays are connected
  ///
  /// In en, this message translates to:
  /// **'You receive orders and messages normally'**
  String get relaysSummaryHealthy;

  /// Relay summary card subtitle with fewer than two relays connected
  ///
  /// In en, this message translates to:
  /// **'You may stop seeing new orders'**
  String get relaysSummaryAtRisk;

  /// Per-relay status label, connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get relayStatusConnected;

  /// Per-relay status label, not connected
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get relayStatusOffline;

  /// Dashed full-width button that opens the add-relay dialog
  ///
  /// In en, this message translates to:
  /// **'Add relay'**
  String get addRelayButtonLabel;

  /// Footnote below the relay list
  ///
  /// In en, this message translates to:
  /// **'Relays carry your orders and messages. With fewer than two connected you may stop seeing new orders.'**
  String get relaysFootnote;

  /// Shown instead of disabling or removing the last active relay, which the core refuses
  ///
  /// In en, this message translates to:
  /// **'Keep at least one relay active: without relays you cannot see or publish orders.'**
  String get lastRelayBlockedMessage;

  /// Title of the NWC explanation card
  ///
  /// In en, this message translates to:
  /// **'Connect your wallet'**
  String get nwcExplainerTitle;

  /// Subtitle of the NWC explanation card
  ///
  /// In en, this message translates to:
  /// **'With Nostr Wallet Connect'**
  String get nwcExplainerSubtitle;

  /// Body of the NWC explanation card: what the wallet is used for
  ///
  /// In en, this message translates to:
  /// **'Mostro will collect and pay your trade invoices from this wallet, so you never have to copy an invoice by hand.'**
  String get nwcExplainerBody;

  /// Uppercase label above the NWC URI field
  ///
  /// In en, this message translates to:
  /// **'Connection URI'**
  String get nwcUriFieldLabel;

  /// Placeholder of the NWC URI field, showing the real scheme
  ///
  /// In en, this message translates to:
  /// **'nostr+walletconnect://…'**
  String get nwcUriPlaceholder;

  /// Footnote answering where the NWC URI is stored
  ///
  /// In en, this message translates to:
  /// **'The URI is stored only on this device and is never published to Nostr.'**
  String get nwcStorageFootnote;

  /// Snackbar after the wallet connects
  ///
  /// In en, this message translates to:
  /// **'Wallet connected'**
  String get walletConnectedMessage;

  /// Status line of a connected wallet
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get nwcConnectedStatus;

  /// Wallet balance in sats
  ///
  /// In en, this message translates to:
  /// **'{sats} sats'**
  String nwcBalanceSats(String sats);

  /// Banner when the OS notification permission is denied
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off in your system settings.'**
  String get notificationsSystemDenied;

  /// Action of the denied-permission banner
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSystemSettingsAction;

  /// Footnote: what a push notification does not carry, and the one true sentence about how it travels. Must not claim the token is encrypted.
  ///
  /// In en, this message translates to:
  /// **'Notifications carry no amounts and no counterparties. A push travels through Google\'s or Apple\'s servers and says only that there is something to see.'**
  String get notificationsPrivacyFootnote;

  /// Title of the master push toggle on the notification settings screen
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get pushMasterToggleTitle;

  /// Description under the master push toggle: a push is a content-free wake-up
  ///
  /// In en, this message translates to:
  /// **'Wakes the app when a trade or chat message arrives. The notification itself carries nothing.'**
  String get pushMasterToggleSubtitle;

  /// Status line under the master push toggle when push is turned off
  ///
  /// In en, this message translates to:
  /// **'Off — nothing is registered with the push server'**
  String get pushStatusOff;

  /// Push is off locally, but the server has not confirmed removing these registrations
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Off — removal of 1 push registration is pending} other{Off — removal of {count} push registrations is pending}}'**
  String pushStatusCleanupPending(int count);

  /// Status line when push is on but the device has not produced a push token yet
  ///
  /// In en, this message translates to:
  /// **'Waiting for this device\'s push token'**
  String get pushStatusNoToken;

  /// Status line when push is on, nothing failed, and there is no open trade to register
  ///
  /// In en, this message translates to:
  /// **'On — no open trades to register'**
  String get pushStatusIdle;

  /// Status line: how many open trades the push server holds this device's token for
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Registered for 1 trade} other{Registered for {count} trades}}'**
  String pushStatusRegistered(int count);

  /// Appended to pushStatusRegistered after ' · '; {ago} is a relative time such as '3 h ago' or 'yesterday'
  ///
  /// In en, this message translates to:
  /// **'last registered {ago}'**
  String pushStatusLastRegistered(String ago);

  /// Status line when the last registration attempt failed and will be retried
  ///
  /// In en, this message translates to:
  /// **'Push server unreachable — retrying'**
  String get pushStatusUnreachable;

  /// Status line when the push server operator refuses trades from the active Mostro node
  ///
  /// In en, this message translates to:
  /// **'This Mostro node is not accepted by the push server'**
  String get pushStatusNodeRefused;

  /// Status line when the push server asked the app to slow down
  ///
  /// In en, this message translates to:
  /// **'Push request limit reached — retrying shortly'**
  String get pushStatusRateLimited;

  /// Info row replacing the master push toggle on platforms that cannot receive a push (desktop, web for now)
  ///
  /// In en, this message translates to:
  /// **'Push notifications are not available on this platform'**
  String get pushUnsupportedPlatform;

  /// Snackbar when the master push toggle could not be saved
  ///
  /// In en, this message translates to:
  /// **'Could not change push notifications'**
  String get pushToggleSaveFailed;

  /// Body of the system notification shown when a peer's chat message wakes the app in the background. Content-free on purpose: it never names the trade, the peer or the message.
  ///
  /// In en, this message translates to:
  /// **'You have a new message'**
  String get pushNewMessageBody;

  /// Snackbar when a notification preference could not be saved
  ///
  /// In en, this message translates to:
  /// **'Could not save that preference'**
  String get notificationPrefSaveFailed;

  /// App bar title of the log report screen
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logsScreenTitle;

  /// Log filter chip: every subsystem
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get logFilterAll;

  /// Log filter chip: relay records
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get logFilterRelays;

  /// Log filter chip: order and trade records
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get logFilterOrders;

  /// Log filter chip: payment and wallet records
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get logFilterPayments;

  /// Label of the verbose-logging toggle at the foot of the logs screen
  ///
  /// In en, this message translates to:
  /// **'Verbose logging'**
  String get verboseLoggingTitle;

  /// Consequence of turning verbose logging on
  ///
  /// In en, this message translates to:
  /// **'More detail, more battery'**
  String get verboseLoggingSubtitle;

  /// Floating chip that scrolls the log list back to the newest entry
  ///
  /// In en, this message translates to:
  /// **'New logs'**
  String get newLogsChipLabel;

  /// Empty state when the active filter matches no entry
  ///
  /// In en, this message translates to:
  /// **'No entries for this filter'**
  String get noLogsForFilter;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get aboutAppSection;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCodeLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'User guide'**
  String get aboutUserGuideLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Technical documentation'**
  String get aboutTechnicalDocsLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get aboutLanguageSpanish;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get aboutLanguageEnglish;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Connected node'**
  String get aboutConnectedNodeTitle;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Min order'**
  String get aboutMinOrderCell;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Max order'**
  String get aboutMaxOrderCell;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get aboutFeeCell;

  /// About screen — node fee figure; value is the locale-formatted percentage number
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String aboutFeeValue(String value);

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Limits in satoshis per order'**
  String get aboutLimitsFootnote;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Node technical data'**
  String get aboutNodeTechnicalDataRow;

  /// About screen — number of node fields listed on the technical data screen
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} field} other{{count} fields}}'**
  String aboutFieldCount(int count);

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Technical data'**
  String get aboutTechnicalDataTitle;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get aboutPublicKeyLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Order expiration'**
  String get aboutOrderExpiryLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Waiting timeout'**
  String get aboutWaitingTimeoutLabel;

  /// About screen — a duration in hours, abbreviated
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String aboutHoursShort(int count);

  /// About screen — a duration in seconds, abbreviated
  ///
  /// In en, this message translates to:
  /// **'{count} s'**
  String aboutSecondsShort(int count);

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get aboutAliasLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Node public key'**
  String get aboutNodePublicKeyLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Node URI'**
  String get aboutNodeUriLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get aboutCommitLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Chain and network'**
  String get aboutChainNetworkLabel;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'These details identify the node you trade with. Useful for support, or to verify it before sending funds.'**
  String get aboutTechnicalFootnote;

  /// About screen redesign (12a/12b)
  ///
  /// In en, this message translates to:
  /// **'Copy all data'**
  String get aboutCopyAllData;

  /// Group header of trades whose next step is the user's
  ///
  /// In en, this message translates to:
  /// **'Needs your action'**
  String get tradesGroupNeedsAction;

  /// Group header of trades waiting on the counterpart or the relay
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get tradesGroupInProgress;

  /// Group header of completed, cancelled and expired trades
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get tradesGroupClosed;

  /// First words of a trade card: the user sells bitcoin
  ///
  /// In en, this message translates to:
  /// **'You sell'**
  String get tradesDirectionSell;

  /// My Trades row heading for a payout claim whose trade row is gone: the side of the trade is unknown, so no buy/sell direction is shown
  ///
  /// In en, this message translates to:
  /// **'Bond claim'**
  String get tradesDirectionBondClaim;

  /// First words of a trade card: the user buys bitcoin
  ///
  /// In en, this message translates to:
  /// **'You buy'**
  String get tradesDirectionBuy;

  /// Counterparty after 'You sell'
  ///
  /// In en, this message translates to:
  /// **'to {handle}'**
  String tradesCounterpartyTo(String handle);

  /// Counterparty after 'You buy'
  ///
  /// In en, this message translates to:
  /// **'from {handle}'**
  String tradesCounterpartyFrom(String handle);

  /// Status chip on a trade card: the next step is the user's
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get tradeListChipYourTurn;

  /// Status chip: the user's order is in the book, not taken yet
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get tradeListChipPublished;

  /// Status chip: taken, exact state not known yet
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get tradeListChipInProgress;

  /// Status chip: the seller waits for the buyer's Lightning invoice
  ///
  /// In en, this message translates to:
  /// **'Awaiting invoice'**
  String get tradeListChipWaitingInvoice;

  /// Status chip: waiting for the counterpart to pay (hold invoice or fiat)
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get tradeListChipWaitingPayment;

  /// Status chip: the buyer waits for the sats to arrive
  ///
  /// In en, this message translates to:
  /// **'Awaiting sats'**
  String get tradeListChipWaitingSats;

  /// Status chip: a dispute is open
  ///
  /// In en, this message translates to:
  /// **'In dispute'**
  String get tradeListChipDispute;

  /// Status chip: the trade finished successfully
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get tradeListChipCompleted;

  /// Status chip: the trade was cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get tradeListChipCancelled;

  /// Status chip: the order expired
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get tradeListChipExpired;

  /// Action on a trade card; opens the add-invoice step
  ///
  /// In en, this message translates to:
  /// **'Add invoice'**
  String get tradeVerbAddInvoice;

  /// Trade list verb / trade detail primary action: pay the anti-abuse deposit that parks the take
  ///
  /// In en, this message translates to:
  /// **'Pay deposit'**
  String get tradeVerbPayBond;

  /// Trade detail headline while the taker's anti-abuse deposit is unpaid
  ///
  /// In en, this message translates to:
  /// **'Lock your deposit to continue'**
  String get tradeHeadlineWaitingBond;

  /// Trade detail body while the taker's anti-abuse deposit is unpaid
  ///
  /// In en, this message translates to:
  /// **'The node holds this take until the refundable deposit is paid. The order stays open to others meanwhile.'**
  String get tradeInstructionWaitingBond;

  /// Take screen note on a bond-enabled node when no estimate is available
  ///
  /// In en, this message translates to:
  /// **'This node asks takers to lock a refundable deposit first; it comes back when the trade ends honestly.'**
  String get takeOrderBondNotice;

  /// Take screen note on a bond-enabled node with the core's estimate; sats is a formatted figure
  ///
  /// In en, this message translates to:
  /// **'This node asks takers to lock a refundable deposit of ≈ {sats} sats first; it comes back when the trade ends honestly.'**
  String takeOrderBondNoticeEstimate(String sats);

  /// Action on a trade card; opens the hold-invoice payment step
  ///
  /// In en, this message translates to:
  /// **'Pay invoice'**
  String get tradeVerbPayInvoice;

  /// Action on a trade card; opens the trade screen to confirm the fiat payment
  ///
  /// In en, this message translates to:
  /// **'Send payment'**
  String get tradeVerbSendPayment;

  /// Action on a trade card; opens the trade screen to release the sats
  ///
  /// In en, this message translates to:
  /// **'Release sats'**
  String get tradeVerbReleaseSats;

  /// Action on a trade card; opens the rating of the counterpart
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get tradeVerbRate;

  /// Trades filter value: no filter
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tradeListFilterAll;

  /// Trades filter value: trades not closed
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get tradeListFilterActive;

  /// Trades filter value: completed trades
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get tradeListFilterCompleted;

  /// Trades filter value: cancelled and expired trades
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get tradeListFilterCancelled;

  /// Title of the sheet that picks the trades filter
  ///
  /// In en, this message translates to:
  /// **'Show trades'**
  String get tradeListFilterTitle;

  /// Relative time under a minute
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get relativeTimeNow;

  /// Relative time in minutes, always in the past
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String relativeTimeMinutes(int count);

  /// Relative time in hours, always in the past
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String relativeTimeHours(int count);

  /// Relative time: the previous calendar day
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get relativeTimeYesterday;

  /// Estimated sats of a trade whose amount is not fixed yet; sats is already formatted
  ///
  /// In en, this message translates to:
  /// **'≈ {sats} sats'**
  String satsFigureEstimate(String sats);

  /// Fixed sats of a trade; sats is already formatted
  ///
  /// In en, this message translates to:
  /// **'{sats} sats'**
  String satsFigureExact(String sats);

  /// Chat list group of conversations whose trade is still open
  ///
  /// In en, this message translates to:
  /// **'Active trades'**
  String get chatGroupActive;

  /// Which trade a conversation belongs to, while it is open; amount is formatted
  ///
  /// In en, this message translates to:
  /// **'You sell {amount} {currency}'**
  String chatContextSellActive(String amount, String currency);

  /// Which trade a conversation belongs to, while it is open; amount is formatted
  ///
  /// In en, this message translates to:
  /// **'You buy {amount} {currency}'**
  String chatContextBuyActive(String amount, String currency);

  /// Which trade a conversation belongs to, once it has closed; amount is formatted
  ///
  /// In en, this message translates to:
  /// **'You sold {amount} {currency}'**
  String chatContextSellClosed(String amount, String currency);

  /// Which trade a conversation belongs to, once it has closed; amount is formatted
  ///
  /// In en, this message translates to:
  /// **'You bought {amount} {currency}'**
  String chatContextBuyClosed(String amount, String currency);

  /// After the trade context in a conversation row: the user must add their invoice
  ///
  /// In en, this message translates to:
  /// **'your turn to add the invoice'**
  String get chatTurnAddInvoice;

  /// After the trade context: the user must pay the anti-abuse deposit
  ///
  /// In en, this message translates to:
  /// **'your turn to pay the deposit'**
  String get chatTurnPayBond;

  /// After the trade context: the user must pay the hold invoice
  ///
  /// In en, this message translates to:
  /// **'your turn to pay the invoice'**
  String get chatTurnPayInvoice;

  /// After the trade context: the user must send the fiat
  ///
  /// In en, this message translates to:
  /// **'your turn to pay'**
  String get chatTurnSendPayment;

  /// After the trade context: the user must release the sats
  ///
  /// In en, this message translates to:
  /// **'your turn to release'**
  String get chatTurnRelease;

  /// After the trade context: the user can rate the counterpart
  ///
  /// In en, this message translates to:
  /// **'your turn to rate'**
  String get chatTurnRate;

  /// Prefix of a last-message preview the user sent
  ///
  /// In en, this message translates to:
  /// **'You:'**
  String get chatYouLabel;

  /// Footnote under the chat list: each conversation is tied to one trade, is end-to-end encrypted, and stays readable after the trade ends
  ///
  /// In en, this message translates to:
  /// **'Each conversation belongs to one trade and is end-to-end encrypted. Once the trade ends, it stays here to read.'**
  String get chatListFootnote;

  /// Empty chat list title
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get chatListEmptyTitle;

  /// Empty chat list body
  ///
  /// In en, this message translates to:
  /// **'A chat opens when a trade becomes active.'**
  String get chatListEmptyBody;

  /// Replaces the composer of a conversation whose trade has closed
  ///
  /// In en, this message translates to:
  /// **'This trade has ended. The conversation stays here to read.'**
  String get chatClosedNotice;

  /// Dispute row context: the user opened the dispute; time is a relative time like '2 h ago'
  ///
  /// In en, this message translates to:
  /// **'You opened it {time}'**
  String disputeOpenedByYou(String time);

  /// Dispute row context: the counterpart opened the dispute; time is a relative time
  ///
  /// In en, this message translates to:
  /// **'The counterpart opened it {time}'**
  String disputeOpenedByPeer(String time);

  /// 13a app bar title: the buyer gives where to receive the sats
  ///
  /// In en, this message translates to:
  /// **'Receive your sats'**
  String get invoiceReceiveTitle;

  /// 13b app bar title: the seller pays the hold invoice that locks the sats
  ///
  /// In en, this message translates to:
  /// **'Lock your sats'**
  String get invoiceLockTitle;

  /// 14 app bar title: the anti-abuse bond the taker locks before the trade starts
  ///
  /// In en, this message translates to:
  /// **'Anti-abuse deposit'**
  String get bondTitle;

  /// 14a hero label above the bond amount
  ///
  /// In en, this message translates to:
  /// **'REFUNDABLE DEPOSIT'**
  String get bondRefundableLabel;

  /// 14a hero context line without a fiat rate
  ///
  /// In en, this message translates to:
  /// **'comes back to you when the trade completes'**
  String get bondComesBack;

  /// 14a hero context line; fiat is the bond's equivalent with its currency code
  ///
  /// In en, this message translates to:
  /// **'≈ {fiat} · comes back to you when the trade completes'**
  String bondFiatComesBack(String fiat);

  /// 14 screen reader label of the hero amount
  ///
  /// In en, this message translates to:
  /// **'Refundable deposit of {sats} sats'**
  String bondPaySemantics(String sats);

  /// 14a time band: says the consequence, not only the number; time is mm:ss
  ///
  /// In en, this message translates to:
  /// **'The order is released if you don\'t pay in {time}'**
  String bondReleasesIn(String time);

  /// 14a consequence row 1; bold is bondRowHeldBold
  ///
  /// In en, this message translates to:
  /// **'The sats stay {bold}, they are not spent'**
  String bondRowHeld(String bold);

  /// 14a bold part of row 1
  ///
  /// In en, this message translates to:
  /// **'held in your wallet'**
  String get bondRowHeldBold;

  /// 14a consequence row 2; bold is bondRowReleasedBold
  ///
  /// In en, this message translates to:
  /// **'If the trade ends well, {bold}'**
  String bondRowReleased(String bold);

  /// 14a bold part of row 2
  ///
  /// In en, this message translates to:
  /// **'it is released on its own'**
  String get bondRowReleasedBold;

  /// 14a consequence row 3 on a node that does not slash on timeout; bold is bondRowLostBold
  ///
  /// In en, this message translates to:
  /// **'You only lose it if there is a dispute and {bold}'**
  String bondRowLost(String bold);

  /// 14a consequence row 3 on a node whose policy slashes on a waiting-step timeout; bold is bondRowLostBold
  ///
  /// In en, this message translates to:
  /// **'You lose it if you let a step time out, or if there is a dispute and {bold}'**
  String bondRowLostTimeout(String bold);

  /// 14a bold part of row 3
  ///
  /// In en, this message translates to:
  /// **'you lose it'**
  String get bondRowLostBold;

  /// 14 explainer accordion header
  ///
  /// In en, this message translates to:
  /// **'Why Mostro asks for a deposit'**
  String get bondWhyTitle;

  /// 14b explainer paragraph 1
  ///
  /// In en, this message translates to:
  /// **'Mostro does not hold funds, so it cannot penalise whoever abandons a trade; the deposit does that job, and protects every user against scammers.'**
  String get bondWhyCustody;

  /// 14b explainer paragraph 2; hold is the protocol term, rendered bold and left untranslated
  ///
  /// In en, this message translates to:
  /// **'It is a {hold} invoice: your wallet reserves the sats without sending them; when the trade completes, the reservation is cancelled on its own.'**
  String bondWhyHold(String hold);

  /// 14b explainer paragraph 3 on a node that does not slash on timeout
  ///
  /// In en, this message translates to:
  /// **'If you open a dispute and win, you get it back too. It is only charged when you lose a dispute.'**
  String get bondWhyDispute;

  /// 14b explainer paragraph 3 on a node whose policy slashes on a waiting-step timeout
  ///
  /// In en, this message translates to:
  /// **'If you open a dispute and win, you get it back too. It is only charged when you lose a dispute or let a waiting step time out.'**
  String get bondWhyDisputeTimeout;

  /// 14b link at the foot of the explainer
  ///
  /// In en, this message translates to:
  /// **'Read the documentation'**
  String get bondReadDocs;

  /// 14b context card row label
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get bondContextOrder;

  /// 14b context card: the taker buys sats for this fiat amount
  ///
  /// In en, this message translates to:
  /// **'You buy {fiat}'**
  String bondContextBuy(String fiat);

  /// 14b context card: the taker sells sats for this fiat amount
  ///
  /// In en, this message translates to:
  /// **'You sell {fiat}'**
  String bondContextSell(String fiat);

  /// 14b context card row label
  ///
  /// In en, this message translates to:
  /// **'Deposit equals'**
  String get bondContextEquals;

  /// 14b context card: the node's bond percentage of the order amount
  ///
  /// In en, this message translates to:
  /// **'{pct} % of the amount'**
  String bondContextPercent(String pct);

  /// Pay-bond screen, maker variant: abandon the unpublished order (local wipe)
  ///
  /// In en, this message translates to:
  /// **'Don\'t publish the order'**
  String get bondDontPublish;

  /// Snackbar after a maker abandons their bond
  ///
  /// In en, this message translates to:
  /// **'Order dropped. Nothing was published and nothing was charged.'**
  String get bondAbandoned;

  /// Pay-bond time band, maker variant; time is the formatted countdown
  ///
  /// In en, this message translates to:
  /// **'Not published yet: the order is dropped if you don\'t pay in {time}'**
  String bondPublishesIn(String time);

  /// Pay-bond screen, maker row restored without its bolt11 (no re-request upstream)
  ///
  /// In en, this message translates to:
  /// **'This device has no copy of the deposit invoice and the node does not resend it for an order you created. Drop the order and create it again.'**
  String get bondInvoiceMissingMaker;

  /// Pay-bond expired view body, maker variant
  ///
  /// In en, this message translates to:
  /// **'It was not paid in time: the order was never published and no sats left your wallet.'**
  String get bondExpiredBodyMaker;

  /// Snackbar when a maker's bond window expires while the screen is open
  ///
  /// In en, this message translates to:
  /// **'The deposit invoice expired; the order was not published'**
  String get bondExpiredNoticeMaker;

  /// My Order status while the maker's anti-abuse deposit is outstanding
  ///
  /// In en, this message translates to:
  /// **'Waiting for your deposit — not published yet'**
  String get orderStatusWaitingBond;

  /// Error for the BondCancelNotAllowed marker
  ///
  /// In en, this message translates to:
  /// **'This order can\'t be cancelled while its deposit is pending. Drop it from the deposit screen instead.'**
  String get bondCancelNotAllowed;

  /// Create-order preview notice on a maker-bond node with the core estimate; sats is a formatted figure
  ///
  /// In en, this message translates to:
  /// **'This node asks you to lock a refundable deposit of ≈ {sats} sats before the order is published; it comes back when the trade ends honestly.'**
  String createOrderBondNoticeEstimate(String sats);

  /// Create-order preview notice on a node whose bond applies to makers
  ///
  /// In en, this message translates to:
  /// **'This node asks you to lock a refundable deposit before the order is published; it comes back when the trade ends honestly.'**
  String get createOrderBondNotice;

  /// Claim screen title (payout of a slashed bond's counterparty share)
  ///
  /// In en, this message translates to:
  /// **'Claim your share'**
  String get bondClaimTitle;

  /// Claim screen hero label, upper case
  ///
  /// In en, this message translates to:
  /// **'YOUR SHARE'**
  String get bondClaimShareLabel;

  /// Semantics of the claim hero
  ///
  /// In en, this message translates to:
  /// **'Share of {sats} sats to claim'**
  String bondClaimShareSemantics(String sats);

  /// Claim hero context line; context is fiat amount · payment method
  ///
  /// In en, this message translates to:
  /// **'From the trade of {context}'**
  String bondClaimContext(String context);

  /// Claim deadline line; date is formatted
  ///
  /// In en, this message translates to:
  /// **'Claim before {date}'**
  String bondClaimDeadline(String date);

  /// Claim screen explainer while pending
  ///
  /// In en, this message translates to:
  /// **'The other party\'s deposit was forfeited in your favour. Add an invoice for exactly this amount and the node pays it to you.'**
  String get bondClaimExplainer;

  /// Claim invoice field label
  ///
  /// In en, this message translates to:
  /// **'Lightning invoice'**
  String get bondClaimFieldLabel;

  /// Claim invoice field hint
  ///
  /// In en, this message translates to:
  /// **'lnbc… for exactly the share'**
  String get bondClaimFieldHint;

  /// Claim submit button
  ///
  /// In en, this message translates to:
  /// **'Send invoice'**
  String get bondClaimSubmit;

  /// Snackbar after a claim submission was acknowledged
  ///
  /// In en, this message translates to:
  /// **'Invoice sent to the node'**
  String get bondClaimSent;

  /// Claim state title while submitted
  ///
  /// In en, this message translates to:
  /// **'Invoice sent'**
  String get bondClaimSubmittedTitle;

  /// Claim state body while submitted
  ///
  /// In en, this message translates to:
  /// **'Waiting for the node to confirm it.'**
  String get bondClaimSubmittedBody;

  /// Claim state title once acknowledged
  ///
  /// In en, this message translates to:
  /// **'Payout in progress'**
  String get bondClaimAcknowledgedTitle;

  /// Claim state body once acknowledged
  ///
  /// In en, this message translates to:
  /// **'The node accepted your invoice and is paying it. If it cannot be routed, you will be asked for a new one.'**
  String get bondClaimAcknowledgedBody;

  /// Claim state title once completed
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get bondClaimCompletedTitle;

  /// Claim state body once completed; sats is formatted
  ///
  /// In en, this message translates to:
  /// **'{sats} sats reached your wallet.'**
  String bondClaimCompletedBody(String sats);

  /// Claim expired title
  ///
  /// In en, this message translates to:
  /// **'The claim window ended'**
  String get bondClaimExpiredTitle;

  /// Claim expired body; date is formatted
  ///
  /// In en, this message translates to:
  /// **'It closed on {date}. The share can no longer be claimed.'**
  String bondClaimExpiredBody(String date);

  /// Claim screen without a claim
  ///
  /// In en, this message translates to:
  /// **'No claim found for this order.'**
  String get bondClaimMissing;

  /// InvoiceAmountMismatch marker
  ///
  /// In en, this message translates to:
  /// **'The invoice must be for exactly the share shown.'**
  String get bondClaimErrorAmount;

  /// BondClaimExpired marker
  ///
  /// In en, this message translates to:
  /// **'The claim window ended; the share can no longer be claimed.'**
  String get bondClaimErrorExpired;

  /// BondClaimRejected marker
  ///
  /// In en, this message translates to:
  /// **'The node did not accept the invoice. Try another one.'**
  String get bondClaimErrorRejected;

  /// ClaimNotClaimable / ClaimNotFound markers
  ///
  /// In en, this message translates to:
  /// **'This claim is not open for an invoice right now.'**
  String get bondClaimErrorNotClaimable;

  /// TradeKeyMissing marker
  ///
  /// In en, this message translates to:
  /// **'This device has no key for that trade, so it cannot claim the share.'**
  String get bondClaimErrorNoKey;

  /// My Trades verb: open the payout claim screen
  ///
  /// In en, this message translates to:
  /// **'Claim payout'**
  String get tradeVerbClaimPayout;

  /// Chat list turn line for a pending payout claim
  ///
  /// In en, this message translates to:
  /// **'your turn to claim the payout'**
  String get chatTurnClaimPayout;

  /// My Trades badge: a slashed bond's share waits for the user's invoice
  ///
  /// In en, this message translates to:
  /// **'Payout pending'**
  String get tradeBadgePayoutPending;

  /// My Trades badge: the payout invoice was sent or accepted
  ///
  /// In en, this message translates to:
  /// **'Payout in progress'**
  String get tradeBadgePayoutInProgress;

  /// My Trades badge: the share was paid
  ///
  /// In en, this message translates to:
  /// **'Payout paid'**
  String get tradeBadgePayoutPaid;

  /// Trade detail banner title while a claim is pending; sats is formatted
  ///
  /// In en, this message translates to:
  /// **'{sats} sats are ready to come back to you'**
  String bondBannerPendingTitle(String sats);

  /// Trade detail banner body while a claim is pending; sats is formatted
  ///
  /// In en, this message translates to:
  /// **'The other party\'s deposit was forfeited in your favour. Add any Lightning invoice for {sats} sats to claim it.'**
  String bondBannerPendingBody(String sats);

  /// Trade detail banner button while pending
  ///
  /// In en, this message translates to:
  /// **'Add payout invoice'**
  String get bondBannerAddInvoice;

  /// Trade detail banner button while in progress
  ///
  /// In en, this message translates to:
  /// **'View claim'**
  String get bondBannerView;

  /// Trade detail banner title once the invoice was sent or accepted
  ///
  /// In en, this message translates to:
  /// **'Payout in progress'**
  String get bondBannerInProgressTitle;

  /// Trade detail banner body once the invoice was sent or accepted; sats is formatted
  ///
  /// In en, this message translates to:
  /// **'The node is paying your {sats}-sat share.'**
  String bondBannerInProgressBody(String sats);

  /// Trade detail banner title once paid
  ///
  /// In en, this message translates to:
  /// **'Payout received'**
  String get bondBannerPaidTitle;

  /// Trade detail banner body once paid; sats formatted, date formatted
  ///
  /// In en, this message translates to:
  /// **'{sats} sats were paid to you on {date}.'**
  String bondBannerPaidBody(String sats, String date);

  /// Trade detail muted line once the claim window closed; date formatted
  ///
  /// In en, this message translates to:
  /// **'The claim on the other party\'s deposit closed on {date}.'**
  String bondBannerExpired(String date);

  /// Notification title for a new or re-prompted payout claim
  ///
  /// In en, this message translates to:
  /// **'Bond payout to claim'**
  String get bondClaimNewTitle;

  /// Notification message for a new payout claim; sats is a plain number
  ///
  /// In en, this message translates to:
  /// **'You can claim {sats} sats from a slashed bond. Add a Lightning invoice to receive them.'**
  String bondClaimNewMessage(String sats);

  /// Notification title once a payout was paid
  ///
  /// In en, this message translates to:
  /// **'Bond payout received'**
  String get bondClaimPaidTitle;

  /// Notification message once a payout was paid; sats is a plain number
  ///
  /// In en, this message translates to:
  /// **'Bond payout of {sats} sats received.'**
  String bondClaimPaidMessage(String sats);

  /// 14 footer link: cancels the take; nothing is committed yet, so it is not styled as destructive
  ///
  /// In en, this message translates to:
  /// **'Don\'t take the order'**
  String get bondDontTake;

  /// Snackbar when a seller-as-taker's bond locks and the trade hold invoice follows
  ///
  /// In en, this message translates to:
  /// **'Deposit locked. Now lock the trade amount.'**
  String get bondLockedNowEscrow;

  /// Snackbar when the bond window ends because another taker locked first
  ///
  /// In en, this message translates to:
  /// **'Another user took this order before your deposit was paid'**
  String get bondLostRace;

  /// Snackbar when the bond window ends because the maker cancelled
  ///
  /// In en, this message translates to:
  /// **'The maker cancelled this order'**
  String get bondMakerCanceled;

  /// Snackbar when the bond bolt11 expired unpaid while the screen was not open
  ///
  /// In en, this message translates to:
  /// **'The deposit invoice expired; the order went back to the book'**
  String get bondExpiredNotice;

  /// 14 terminal state title when the bond bolt11 ran out
  ///
  /// In en, this message translates to:
  /// **'The deposit invoice expired'**
  String get bondExpiredTitle;

  /// 14 terminal state explanation
  ///
  /// In en, this message translates to:
  /// **'It was not paid in time: the order went back to the book and no sats left your wallet.'**
  String get bondExpiredBody;

  /// 14 state after a fresh-device restore: the row has no bolt11
  ///
  /// In en, this message translates to:
  /// **'This device has no copy of the deposit invoice. Ask the node for it again to keep taking the order.'**
  String get bondInvoiceMissing;

  /// 14 action: same-take re-request of the bond bolt11
  ///
  /// In en, this message translates to:
  /// **'Request the invoice again'**
  String get bondRequestAgain;

  /// Snackbar when the re-request fails
  ///
  /// In en, this message translates to:
  /// **'The node did not resend the deposit invoice'**
  String get bondRequestFailed;

  /// Snackbar after tapping the order id in the invoice app bar
  ///
  /// In en, this message translates to:
  /// **'Order ID copied'**
  String get invoiceOrderIdCopied;

  /// 13a hero card label above the amount (rendered uppercase)
  ///
  /// In en, this message translates to:
  /// **'You will receive'**
  String get invoiceYouReceiveLabel;

  /// 13b hero card label above the amount (rendered uppercase)
  ///
  /// In en, this message translates to:
  /// **'To pay'**
  String get invoiceToPayLabel;

  /// 13a screen reader label of the hero amount
  ///
  /// In en, this message translates to:
  /// **'{sats} satoshis to receive'**
  String invoiceReceiveSemantics(String sats);

  /// 13b screen reader label of the hero amount
  ///
  /// In en, this message translates to:
  /// **'{sats} satoshis to pay'**
  String invoicePaySemantics(String sats);

  /// 13b hero context line: the Mostro fee contained in the hold invoice amount
  ///
  /// In en, this message translates to:
  /// **'Includes {sats} sats of Mostro fee'**
  String invoiceFeeIncluded(String sats);

  /// 13a time band; time is a countdown like 14:38
  ///
  /// In en, this message translates to:
  /// **'You have {time} to send it'**
  String invoiceTimeToSend(String time);

  /// 13b time band; time is a countdown like 09:12
  ///
  /// In en, this message translates to:
  /// **'The invoice expires in {time}'**
  String invoiceExpiresIn(String time);

  /// 13a invoice field header (rendered uppercase)
  ///
  /// In en, this message translates to:
  /// **'Lightning invoice or address'**
  String get invoiceFieldLabel;

  /// 13a invoice field placeholder: says it accepts both an invoice and an address
  ///
  /// In en, this message translates to:
  /// **'lnbc… or user@domain'**
  String get invoiceFieldHint;

  /// 17a label of the empty invoice field, in the imperative, so the buyer sees where to write
  ///
  /// In en, this message translates to:
  /// **'Paste your invoice here'**
  String get invoiceFieldPromptLabel;

  /// 17b label of the invoice field once it holds something; also the title of the full-invoice sheet
  ///
  /// In en, this message translates to:
  /// **'Lightning invoice'**
  String get invoiceFieldFilledLabel;

  /// 17b label of the invoice field when it holds a valid Lightning address; also its screen reader label and the full-value sheet title
  ///
  /// In en, this message translates to:
  /// **'Lightning address'**
  String get invoiceFieldAddressLabel;

  /// 17a/17b button under the invoice field that scans a QR code
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get invoiceScanButton;

  /// 17b button that replaces the invoice with the clipboard content
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get invoiceReplaceButton;

  /// Screen reader label of the invoice text field
  ///
  /// In en, this message translates to:
  /// **'Lightning invoice or address, required'**
  String get invoiceFieldSemantics;

  /// Screen reader label of the filled invoice field: the decoded amount, not the whole string
  ///
  /// In en, this message translates to:
  /// **'Lightning invoice for {sats} sats'**
  String invoiceFilledSemantics(String sats);

  /// 13a validation row for a Lightning address or LNURL
  ///
  /// In en, this message translates to:
  /// **'Valid address · the invoice will be requested on sending'**
  String get invoiceValidAddress;

  /// 13a validation row for a BOLT11 invoice with the right amount
  ///
  /// In en, this message translates to:
  /// **'Valid invoice · {sats} sats'**
  String invoiceValidInvoice(String sats);

  /// 13a validation error: the invoice amount differs from the trade's
  ///
  /// In en, this message translates to:
  /// **'The invoice is for {actual} sats, it must be {expected}'**
  String invoiceErrorWrongAmount(String actual, String expected);

  /// 13a validation error: the invoice expiry has passed
  ///
  /// In en, this message translates to:
  /// **'The invoice has already expired'**
  String get invoiceErrorExpired;

  /// 13a validation error: the invoice is unexpired but has less lifetime left than the node's invoice_expiration_window
  ///
  /// In en, this message translates to:
  /// **'The invoice expires in less than {minutes} minutes, the node needs more time to pay it'**
  String invoiceErrorExpiresTooSoon(String minutes);

  /// 13a validation error: starts like an invoice but does not decode
  ///
  /// In en, this message translates to:
  /// **'This invoice is incomplete or mistyped'**
  String get invoiceErrorMalformed;

  /// 13a validation error: neither an invoice nor a Lightning address
  ///
  /// In en, this message translates to:
  /// **'Not an invoice (lnbc…) or a Lightning address (user@domain)'**
  String get invoiceErrorUnrecognized;

  /// 13a counterpart card row label
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get invoiceSellerLabel;

  /// 13b counterpart card row label
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get invoiceBuyerLabel;

  /// 13a counterpart card row label for the fiat the buyer pays
  ///
  /// In en, this message translates to:
  /// **'You pay'**
  String get invoiceYouPayLabel;

  /// 13b counterpart card row label for the fiat the seller receives
  ///
  /// In en, this message translates to:
  /// **'You receive'**
  String get invoiceYouGetLabel;

  /// Counterpart reputation when they have no rated trade (instead of 0.0 stars)
  ///
  /// In en, this message translates to:
  /// **'no trades'**
  String get invoiceNoTrades;

  /// 13a primary action
  ///
  /// In en, this message translates to:
  /// **'Send invoice'**
  String get invoiceSendButton;

  /// 13a/13b cancel link below the actions
  ///
  /// In en, this message translates to:
  /// **'Cancel trade'**
  String get invoiceCancelTrade;

  /// 13b primary action: opens the hold invoice as a lightning: deep link
  ///
  /// In en, this message translates to:
  /// **'Open in my wallet'**
  String get invoiceOpenWallet;

  /// 13b note explaining the hold invoice; hold is the protocol term 'hold', rendered bold and deliberately left untranslated in every locale (as in 'factura hold') — move the placeholder, do not replace it
  ///
  /// In en, this message translates to:
  /// **'This is a {hold} invoice: the sats are held, they don\'t leave your wallet until you confirm the buyer\'s payment.'**
  String invoiceHoldNote(String hold);

  /// 13b screen reader label of the QR: the whole invoice
  ///
  /// In en, this message translates to:
  /// **'Lightning invoice QR code: {invoice}'**
  String invoiceQrSemantics(String invoice);

  /// 13b terminal state when the hold invoice ran out
  ///
  /// In en, this message translates to:
  /// **'The invoice expired'**
  String get invoiceExpiredTitle;

  /// 13b terminal state explanation
  ///
  /// In en, this message translates to:
  /// **'It was not paid in time: Mostro cancels the trade and no sats left your wallet.'**
  String get invoiceExpiredBody;

  /// 13b terminal state action
  ///
  /// In en, this message translates to:
  /// **'Back to the order book'**
  String get invoiceBackToBook;

  /// 13a terminal state when the buyer's invoice window ran out
  ///
  /// In en, this message translates to:
  /// **'Time is up'**
  String get invoiceTimeUpTitle;

  /// 13a terminal state explanation
  ///
  /// In en, this message translates to:
  /// **'The invoice was not sent in time: Mostro cancels the trade. Nothing was committed on your side.'**
  String get invoiceTimeUpBody;

  /// 13a validation error: the invoice is for another chain than the node's; both are LND network names like mainnet or testnet
  ///
  /// In en, this message translates to:
  /// **'The invoice is for {invoice}, the node uses {node}'**
  String invoiceErrorWrongNetwork(String invoice, String node);

  /// Invoice time band countdown above one hour; hours is a whole number, minutes is always two digits (e.g. 1 h 05). Keep it short: it sits inside a sentence
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes}'**
  String invoiceCountdownHours(String hours, String minutes);

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Waiting for the buyer\'s invoice'**
  String get tradeCardWaitingBuyerInvoiceTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The trade continues once the buyer adds a Lightning invoice.'**
  String get tradeCardWaitingBuyerInvoiceMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Waiting for the seller\'s payment'**
  String get tradeCardWaitingPaymentTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The trade continues once the seller pays the hold invoice.'**
  String get tradeCardWaitingPaymentMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Bond payment pending'**
  String get tradeCardWaitingTakerBondTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The taker\'s anti-abuse bond must be paid before the trade starts.'**
  String get tradeCardWaitingTakerBondMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Trade active'**
  String get tradeCardActiveTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The sats are locked. The buyer can now send the fiat payment.'**
  String get tradeCardActiveMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Fiat marked as sent'**
  String get tradeCardFiatSentTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The buyer marked the fiat payment as sent.'**
  String get tradeCardFiatSentMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Sats released'**
  String get tradeCardSettledHoldInvoiceTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The seller released the sats. The buyer\'s payout is on its way.'**
  String get tradeCardSettledHoldInvoiceMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Trade completed'**
  String get tradeCardSuccessTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The trade finished successfully.'**
  String get tradeCardSuccessMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Trade canceled'**
  String get tradeCardCanceledTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The trade was canceled.'**
  String get tradeCardCanceledMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Order expired'**
  String get tradeCardExpiredTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The order expired before the trade could continue.'**
  String get tradeCardExpiredMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Trade canceled by agreement'**
  String get tradeCardCooperativelyCanceledTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Both parties agreed to cancel the trade.'**
  String get tradeCardCooperativelyCanceledMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Dispute opened'**
  String get tradeCardDisputeTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'A dispute was opened on this trade.'**
  String get tradeCardDisputeMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Canceled by the resolver'**
  String get tradeCardCanceledByAdminTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The dispute resolver canceled the trade.'**
  String get tradeCardCanceledByAdminMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Settled by the resolver'**
  String get tradeCardSettledByAdminTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The dispute resolver released the sats to the buyer.'**
  String get tradeCardSettledByAdminMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Completed by the resolver'**
  String get tradeCardCompletedByAdminTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The dispute resolver completed the trade.'**
  String get tradeCardCompletedByAdminMessage;

  /// Notifications card title for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'Trade updated'**
  String get tradeCardUpdatedTitle;

  /// Notifications card body for a trade status change (issue #474); role-neutral, both sides see it
  ///
  /// In en, this message translates to:
  /// **'The status of this trade changed.'**
  String get tradeCardUpdatedMessage;

  /// Notifications card copy for trades and chat (issue #474)
  ///
  /// In en, this message translates to:
  /// **'The maker canceled the order.'**
  String get tradeCardCanceledByMakerMessage;

  /// Notifications card copy for trades and chat (issue #474)
  ///
  /// In en, this message translates to:
  /// **'Another user took this order before the bond was paid.'**
  String get tradeCardCanceledBondLostRaceMessage;

  /// Notifications card copy for trades and chat (issue #474)
  ///
  /// In en, this message translates to:
  /// **'The bond invoice expired unpaid.'**
  String get tradeCardCanceledBondExpiredMessage;

  /// Notifications card copy for trades and chat (issue #474)
  ///
  /// In en, this message translates to:
  /// **'New messages'**
  String get chatCardTitle;

  /// Notifications card copy for trades and chat (issue #474)
  ///
  /// In en, this message translates to:
  /// **'Messages from the resolver'**
  String get chatCardSolverTitle;

  /// Notifications chat card body; count is the number of unread messages
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new message from your trade partner} other{{count} new messages from your trade partner}}'**
  String chatCardMessage(int count);

  /// Notifications chat card body; count is the number of unread messages
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new message from the dispute resolver} other{{count} new messages from the dispute resolver}}'**
  String chatCardSolverMessage(int count);

  /// Error shown when the Mostro node refuses a new order or take with CantDo(InvalidTradeIndex) even after the app resynced its trade-key counter and retried once
  ///
  /// In en, this message translates to:
  /// **'Your account is out of sync with this Mostro node, so it refused the order. Try again in a moment'**
  String get invalidTradeIndexError;

  /// Snackbar shown on the Account screen right after a mnemonic import, while the app asks Mostro for the identity's trades in progress
  ///
  /// In en, this message translates to:
  /// **'Account imported. Recovering your trades from Mostro…'**
  String get recoveringTradesMessage;

  /// Snackbar shown after a mnemonic import once Mostro returned the identity's trades in progress; count is how many orders and disputes came back
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Account imported. You had no trades in progress} =1{Account imported. 1 trade recovered} other{Account imported. {count} trades recovered}}'**
  String recoveredTradesMessage(int count);

  /// Snackbar shown after a mnemonic import when Mostro did not answer the recovery request; the import itself succeeded
  ///
  /// In en, this message translates to:
  /// **'Account imported, but Mostro did not answer, so your trades in progress were not recovered'**
  String get recoverTradesFailedMessage;

  /// Label in front of the chips summarising the methods chosen so far on the payment-method picker screen
  ///
  /// In en, this message translates to:
  /// **'Chosen'**
  String get paymentMethodsChosenLabel;

  /// Count line above the confirm button of the payment-method picker screen
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Choose at least one method} =1{1 method selected} other{{count} methods selected}}'**
  String paymentMethodsSelectedCount(int count);

  /// Button that saves the payment-method selection and closes the picker screen
  ///
  /// In en, this message translates to:
  /// **'Confirm methods'**
  String get paymentMethodsConfirm;

  /// Dashed row at the end of the payment-method list that opens the custom-method sheet
  ///
  /// In en, this message translates to:
  /// **'Add custom payment method'**
  String get paymentMethodAddCustom;

  /// Title of the dialog shown when leaving the payment-method picker with unconfirmed changes
  ///
  /// In en, this message translates to:
  /// **'Discard the changes?'**
  String get paymentMethodsDiscardTitle;

  /// Dialog action that leaves the payment-method picker without saving
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get paymentMethodsDiscardConfirm;

  /// Dialog action that stays on the payment-method picker screen
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get paymentMethodsKeepEditing;

  /// Title of the warning shown before generating a new user or importing a seed while the current identity has escrow, bonds, payout claims or trades in flight
  ///
  /// In en, this message translates to:
  /// **'This user still has sats in play'**
  String get fundsAtRiskTitle;

  /// Body of the funds-at-risk warning, above the list of what is still in flight
  ///
  /// In en, this message translates to:
  /// **'If you continue, this user\'s keys are replaced and nothing listed here can be finished or recovered from this device. This is not recommended: you can lose these sats.'**
  String get fundsAtRiskBody;

  /// Funds-at-risk list entry: the user is the seller and the hold invoice is paid and held
  ///
  /// In en, this message translates to:
  /// **'Sats locked in escrow for a sale'**
  String get fundsAtRiskSellerEscrow;

  /// Funds-at-risk list entry: an anti-abuse bond is locked until its trade ends
  ///
  /// In en, this message translates to:
  /// **'Bond locked'**
  String get fundsAtRiskBondLocked;

  /// Funds-at-risk list entry: the user won a share of a slashed bond and has not been paid yet
  ///
  /// In en, this message translates to:
  /// **'Bond payout not collected yet'**
  String get fundsAtRiskPayoutClaim;

  /// Funds-at-risk list entry: a live trade with none of the user's sats locked
  ///
  /// In en, this message translates to:
  /// **'Trade in progress'**
  String get fundsAtRiskTradeInProgress;

  /// Funds-at-risk list entry: a bond invoice that has not been paid and has not expired
  ///
  /// In en, this message translates to:
  /// **'Bond invoice still payable'**
  String get fundsAtRiskBondInvoicePending;

  /// Safe, primary action of the funds-at-risk warning: abandon the generation or import
  ///
  /// In en, this message translates to:
  /// **'Keep this user'**
  String get fundsAtRiskKeep;

  /// Destructive action of the funds-at-risk warning: go on with the generation or import
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get fundsAtRiskContinue;

  /// Restore sheet (design 20a/20b) title while an imported account asks its node for its orders
  ///
  /// In en, this message translates to:
  /// **'Restoring your account'**
  String get restoreSheetTitle;

  /// Restore sheet subtitle before the node answered (20a)
  ///
  /// In en, this message translates to:
  /// **'This may take a few seconds'**
  String get restoreSheetWaiting;

  /// Restore sheet subtitle while order details load (20b); done and total are order counts
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} orders recovered'**
  String restoreSheetLoading(int done, int total);

  /// Restore stage 1 while the request has not reached a relay yet
  ///
  /// In en, this message translates to:
  /// **'Connecting to the Mostro node'**
  String get restoreStageConnecting;

  /// Restore stage 1 once the request reached a relay
  ///
  /// In en, this message translates to:
  /// **'Connected to the Mostro node'**
  String get restoreStageConnected;

  /// Restore stage 2 while waiting for the node to answer
  ///
  /// In en, this message translates to:
  /// **'Requesting your orders'**
  String get restoreStageRequesting;

  /// Restore stage 2 once the node answered; count is every order and dispute it returned
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 order found} other{{count} orders found}}'**
  String restoreStageFound(int count);

  /// Restore stage 3: loading each order's details
  ///
  /// In en, this message translates to:
  /// **'Loading details'**
  String get restoreStageLoading;

  /// Tag on the restore stage that failed (20c)
  ///
  /// In en, this message translates to:
  /// **'No response'**
  String get restoreStageNoResponse;

  /// Screen-reader form of the n/N counter of restore stage 3
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} orders'**
  String restoreLoadingCountSemantics(int done, int total);

  /// Restore sheet title when the restore failed (20c)
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t restore your orders'**
  String get restoreFailedTitle;

  /// Restore sheet subtitle when it failed: the account import itself is kept
  ///
  /// In en, this message translates to:
  /// **'Your account was imported'**
  String get restoreFailedSubtitle;

  /// Restore failure paragraph; place is the Account screen name, shown in bold
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again. You can retry any time from {place}.'**
  String restoreFailedBody(String place);

  /// Secondary action of the failed restore: close and keep the imported account without orders
  ///
  /// In en, this message translates to:
  /// **'Continue without restoring'**
  String get restoreContinueWithout;

  /// Restore sheet title once it finished (20d)
  ///
  /// In en, this message translates to:
  /// **'Account restored'**
  String get restoreDoneTitle;

  /// Restore sheet subtitle once it finished with orders
  ///
  /// In en, this message translates to:
  /// **'We recovered everything the node had'**
  String get restoreDoneSubtitle;

  /// Restore sheet subtitle once it finished and the node had no orders for the account
  ///
  /// In en, this message translates to:
  /// **'This account had no orders on the node'**
  String get restoreDoneEmptySubtitle;

  /// Label of the restored-orders count in the restore summary
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get restoreSummaryOrders;

  /// Label of the trades-in-progress count in the restore summary
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get restoreSummaryInProgress;

  /// Restore summary notice: trades waiting for the user's next step
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have 1 active order waiting for you} other{You have {count} active orders waiting for you}}'**
  String restoreActionNotice(int count);

  /// Restore summary warning when some orders' details did not load; missing and total are counts
  ///
  /// In en, this message translates to:
  /// **'{missing} of {total} orders couldn\'t be loaded'**
  String restorePartialNotice(int missing, int total);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'nl',
  ].contains(locale.languageCode);

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
    case 'nl':
      return AppLocalizationsNl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
