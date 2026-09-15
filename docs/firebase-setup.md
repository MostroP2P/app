# Firebase Setup

Push notifications ride on Firebase Cloud Messaging (FCM). What a push carries, and
why it carries nothing, is in [`PUSH_NOTIFICATIONS.md`](PUSH_NOTIFICATIONS.md); this
page is only the wiring.

The repository ships the configuration for the Firebase project `mostro-mobile`
(bundle / package `foundation.mostro.app`). These values are public client
configuration, not secrets. A fork that uses its own project regenerates all of them.

## Regenerating the configuration (forks)

1. Create a Firebase project at <https://console.firebase.google.com>.
2. Install the FlutterFire CLI: `dart pub global activate flutterfire_cli`.
3. Run `flutterfire configure --project=YOUR_PROJECT_ID`. It rewrites
   `lib/firebase_options.dart`, `firebase.json`, `android/app/google-services.json`
   and `ios/Runner/GoogleService-Info.plist`.
4. Commit them together. On iOS both the plist and `firebase_options.dart` initialise
   Firebase; if their API keys differ, `Firebase.initializeApp` fails with
   `duplicate-app` and the app runs without push.

## Android

`android/app/google-services.json` is committed. Nothing else to do: FCM needs no
key on Android.

## iOS

FCM delivers to iOS through Apple Push Notification service (APNs). What the
repository carries (docs/PUSH_NOTIFICATIONS.md T4.4):

| Piece | Where |
|---|---|
| Firebase config | `ios/Runner/GoogleService-Info.plist`, bundled through the Runner target's Resources phase |
| Firebase registration | `FirebaseApp.configure()` in `ios/Runner/AppDelegate.swift`, skipped when the plist is absent |
| APNs entitlement | `aps-environment` in `ios/Runner/Runner.entitlements` |
| Background delivery | `remote-notification` in `UIBackgroundModes`, `ios/Runner/Info.plist` |
| Notification delegate | `UNUserNotificationCenter.current().delegate` in `AppDelegate.swift`, for the app's own chat-wake notice |
| APNs before FCM | `lib/features/notifications/services/device_token.dart` waits for the APNs token before asking FCM for its own |

What it cannot carry is the **APNs key**, which lives in the Apple Developer account
and the Firebase console. It is an operator task, done once per Firebase project:

1. **Apple Developer → Certificates, Identifiers & Profiles → Identifiers.** Open the
   App ID `foundation.mostro.app` and enable **Push Notifications**. Regenerate any
   provisioning profile made before that, or signing fails on `aps-environment`.
2. **Keys → +.** Create a key with **Apple Push Notifications service (APNs)**
   enabled. Download the `.p8` (Apple offers it once) and note the **Key ID** and
   your **Team ID**.
3. **Firebase console → Project settings → Cloud Messaging → Apple app configuration**
   for the iOS app `1:375342057498:ios:a5fb156e2042607a86e9a3`. Under **APNs
   Authentication Key**, upload the `.p8` with its Key ID and Team ID. One key serves
   both the sandbox and production APNs environments.

Until the key is uploaded, an iOS build gets an APNs token and an FCM token, the
push server accepts the registration, and FCM then fails every send to the device.
Nothing breaks in the app: trading never depends on push. From the user's side, iOS
push is simply not there yet.

### `aps-environment`

The entitlements file says `development`, which is what a debug build signed with a
development profile needs. Exporting an archive with a distribution profile
(TestFlight, App Store, Ad Hoc) re-signs the app with `production`, so nothing is
changed by hand for a release. `firebase_messaging` tells FCM which environment
the APNs token belongs to from the build configuration (sandbox for Debug,
production otherwise).

### Verifying on a device

Use a physical iPhone signed with a profile that includes Push Notifications.

1. `flutter run -d <iphone>` and allow notifications when asked.
2. The log shows `[push] FCM token acquired (N chars)`. If it shows
   `[push] no APNs token yet — FCM token deferred to refresh` and never a token, the
   device got no APNs token: check the entitlement in the signed app
   (`codesign -d --entitlements :- Runner.app` should list `aps-environment`) and
   the profile's Push Notifications capability.
3. Take an order, background the app, and move the trade from the other side. The
   notification "You have an update on your trade" appears. If the registration
   succeeded but nothing arrives, the APNs key in step 3 above is missing or belongs
   to another team.

## Web

Pending (docs/PUSH_NOTIFICATIONS.md T4.5, issue #133): the push server does not
accept web registrations yet. `web/firebase-messaging-sw.js` still carries
placeholder config and the VAPID key in `push_notification_service.dart` is a
placeholder; both are replaced by that task.
