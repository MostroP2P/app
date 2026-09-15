import FirebaseCore
import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Firebase from GoogleService-Info.plist, before any plugin registers,
    // so firebase_messaging never depends on the registrant's order. A fork
    // without the plist skips it: Dart then initialises Firebase from
    // lib/firebase_options.dart, or runs without push (docs/firebase-setup.md).
    if FirebaseApp.app() == nil, FirebaseOptions.defaultOptions() != nil {
      FirebaseApp.configure()
    }
    // flutter_local_notifications renders the chat-wake notice and reports
    // its tap through this delegate. FlutterAppDelegate forwards to every
    // plugin, and firebase_messaging keeps a delegate that does so.
    UNUserNotificationCenter.current().delegate = self
    GeneratedPluginRegistrant.register(with: self)
    // The push registration refresh (lib/features/notifications/services/
    // push_refresh_job.dart): the identifier must match the Dart constant
    // and the entry in Info.plist. Registered before the app finishes
    // launching, as BGTaskScheduler requires; Dart schedules it.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "network.mostro.app.pushRefresh",
      earliestBeginInSeconds: 12 * 60 * 60
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
