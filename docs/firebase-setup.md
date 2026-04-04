# Firebase Setup

1. Create a Firebase project at https://console.firebase.google.com
2. Install FlutterFire CLI: `dart pub global activate flutterfire_cli`
3. Run: `flutterfire configure --project=YOUR_PROJECT_ID`
   This generates `lib/firebase_options.dart` automatically.
4. For Android: ensure `google-services.json` is in `android/app/`.
5. For iOS: ensure `GoogleService-Info.plist` is in `ios/Runner/`.
6. For Web: copy `firebase-messaging-sw.js` (see below) to `web/`.
