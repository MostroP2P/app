@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android manifest's opt-out of Auto Backup (#873).
///
/// `android:allowBackup` defaults to `true`: Android then uploads the app's
/// data directory to Google Drive and restores it at every reinstall. That
/// brought back `firstRunComplete` (no walkthrough on a fresh install) and the
/// trade rows of an identity whose Keystore-held secrets were not restored,
/// and copied trade data off the device. Nothing in a build checks it, so
/// this does.
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const resXml = 'android/app/src/main/res/xml';

  /// Every domain Android's backup rules can name, the device-protected
  /// storage ones included: all must be excluded.
  const domains = {
    'root',
    'file',
    'database',
    'sharedpref',
    'external',
    'device_root',
    'device_file',
    'device_database',
    'device_sharedpref',
  };

  String manifest() => File(manifestPath).readAsStringSync();

  String applicationTag() {
    final match = RegExp(r'<application\b[^>]*>').firstMatch(manifest());
    expect(match, isNotNull, reason: '$manifestPath has no <application>');
    return match!.group(0)!;
  }

  /// The `@xml/<name>` resource an application attribute points at.
  String resourceOf(String attribute) {
    final match = RegExp(
      'android:$attribute="@xml/([A-Za-z0-9_]+)"',
    ).firstMatch(applicationTag());
    expect(
      match,
      isNotNull,
      reason: '<application> sets no android:$attribute="@xml/..."',
    );
    return File('$resXml/${match!.group(1)}.xml').readAsStringSync();
  }

  Set<String> excludedDomains(String section) {
    final excludes = RegExp(
      r'<exclude\s+domain="([a-z_]+)"',
    ).allMatches(section);
    return excludes.map((m) => m.group(1)!).toSet();
  }

  test('the application opts out of backup', () {
    // Arrange
    final tag = applicationTag();

    // Act / Assert
    expect(tag, contains('android:allowBackup="false"'));
  });

  test('the API 31+ extraction rules exclude every domain from cloud backup '
      'and device transfer', () {
    // Arrange
    final rules = resourceOf('dataExtractionRules');

    // Act
    final cloud = RegExp(
      r'<cloud-backup\b[\s\S]*?</cloud-backup>',
    ).firstMatch(rules)?.group(0);
    final transfer = RegExp(
      r'<device-transfer\b[\s\S]*?</device-transfer>',
    ).firstMatch(rules)?.group(0);

    // Assert
    expect(cloud, isNotNull, reason: 'no <cloud-backup> section');
    expect(transfer, isNotNull, reason: 'no <device-transfer> section');
    expect(excludedDomains(cloud!), domains);
    expect(excludedDomains(transfer!), domains);
    expect(rules, isNot(contains('<include')));
  });

  test('the pre-31 full backup content excludes every domain', () {
    // Arrange
    final content = resourceOf('fullBackupContent');

    // Act / Assert
    expect(excludedDomains(content), domains);
    expect(content, isNot(contains('<include')));
  });
}
