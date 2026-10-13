@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/deep_links/models/order_link_rules.dart';

/// Guards the registration of `mostro:` order links on every native platform
/// (lib/features/deep_links/, docs/DEEP_LINKS.md).
///
/// Each of these breaks silently: the OS opens nothing, opens a second copy of
/// the app, or hands the link to go_router as a route it cannot match. None of
/// it shows in a unit test or on the web build CI runs, so the files are held
/// here.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('the core and the app agree on the scheme', () {
    expect(
      read('rust/src/nostr/order_link.rs'),
      contains('pub const ORDER_LINK_SCHEME: &str = "$orderLinkScheme";'),
    );
  });

  test(
    'Android: the activity opens the links, Flutter does not route them',
    () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');

      expect(manifest, contains('<data android:scheme="$orderLinkScheme"/>'));
      expect(
        manifest,
        matches(
          RegExp(
            r'android:name="flutter_deeplinking_enabled"\s+'
            r'android:value="false"',
          ),
        ),
      );
    },
  );

  for (final (platform, plist) in [
    ('iOS', 'ios/Runner/Info.plist'),
    ('macOS', 'macos/Runner/Info.plist'),
  ]) {
    test('$platform: the bundle declares the scheme', () {
      expect(
        read(plist),
        matches(
          RegExp(
            r'<key>CFBundleURLSchemes</key>\s*<array>\s*'
            '<string>$orderLinkScheme</string>',
          ),
        ),
      );
    });
  }

  test('iOS: Flutter does not route the links', () {
    expect(
      read('ios/Runner/Info.plist'),
      matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')),
    );
  });

  group('Linux', () {
    test('the desktop entry handles the scheme and passes the link on', () {
      final entry = read('linux/packaging/foundation.mostro.app.desktop');

      expect(entry, contains('MimeType=x-scheme-handler/$orderLinkScheme;'));
      expect(entry, contains('Exec=mostro %u'));
    });

    test('a release build is single-instance and lets the link through', () {
      final runner = read('linux/runner/my_application.cc');
      final release = runner.substring(
        runner.indexOf('#ifdef NDEBUG'),
        runner.indexOf('#else', runner.indexOf('#ifdef NDEBUG')),
      );

      // A unique application forwards a second launch's command line to the
      // running one, and returning FALSE delivers it, to either. A debug
      // build is not unique, but still takes the link it starts with.
      expect(release, isNot(contains('G_APPLICATION_NON_UNIQUE')));
      expect(release, contains('G_APPLICATION_HANDLES_COMMAND_LINE'));
      expect(
        'G_APPLICATION_HANDLES_COMMAND_LINE'.allMatches(runner),
        hasLength(2),
        reason: 'both builds deliver the command line',
      );
      final localCommandLine = runner.substring(
        runner.indexOf('my_application_local_command_line(GApplication'),
      );
      expect(
        localCommandLine.substring(0, localCommandLine.indexOf('\n}\n')),
        endsWith('return FALSE;'),
      );
    });
  });

  test('Windows: a release build registers the scheme and forwards links', () {
    final runner = read('windows/runner/main.cpp');
    final main = runner.substring(runner.indexOf('wWinMain('));

    expect(runner, contains(r'L"Software\\Classes\\mostro"'));
    expect(runner, contains('L"URL Protocol"'));
    expect(runner, contains('SendAppLink(hwnd)'));
    expect(
      main,
      matches(
        RegExp(
          r'#ifndef _DEBUG\s+if \(SendAppLinkToInstance\(\)\)[\s\S]*?'
          r'RegisterOrderLinkScheme\(\);\s+#endif',
        ),
      ),
    );
  });
}
