@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the iOS build job in CI.
///
/// Nothing else compiles the iOS target: the Swift in `ios/Runner/`, the
/// CocoaPods graph (Firebase, workmanager, the cargokit pod that builds the
/// Rust core for `aarch64-apple-ios`) and `project.pbxproj` edits all pass
/// `flutter analyze` and `flutter test` on Linux, and only fail on a Mac.
/// These checks keep the job from being dropped or quietly weakened.
void main() {
  final ci = File('.github/workflows/ci.yml');

  /// The `ios:` job's block: from its key to the next top-level job, or EOF.
  String iosJob() {
    final yaml = ci.readAsStringSync();
    final start = yaml.indexOf('\n  ios:\n');
    expect(start, greaterThanOrEqualTo(0), reason: 'ci.yml has no `ios` job');
    final next = RegExp(r'\n  [a-z][a-z0-9_-]*:\n')
        .allMatches(yaml, start + 1)
        .map((m) => m.start)
        .firstWhere((i) => i > start, orElse: () => yaml.length);
    return yaml.substring(start, next);
  }

  group('CI iOS job', () {
    test('runs on a macOS runner', () {
      // Arrange / Act
      final job = iosJob();

      // Assert — Xcode and the iOS SDK exist only on macOS runners.
      expect(job, contains('runs-on: macos-'));
    });

    test('compiles the app for iOS without a signing identity', () {
      // Arrange / Act
      final job = iosJob();

      // Assert — a device build (not only analysis) is what exercises Swift,
      // the pods and the Rust staticlib; CI has no Apple certificate, so it
      // must not try to sign. The flag must be an argument of that `run:`
      // line, not text elsewhere in the job or in a trailing `#` comment.
      final buildCommand = RegExp(
        r'^\s*run:\s+flutter build ios\b[^#\r\n]*\s--no-codesign\b',
        multiLine: true,
      );
      expect(
        buildCommand.hasMatch(job),
        isTrue,
        reason: 'the ios job has no `run: flutter build ios ... --no-codesign`',
      );
    });

    test('uses the same Flutter as every other job', () {
      // Arrange / Act
      final job = iosJob();

      // Assert — a different Flutter would test a different toolchain than
      // the one the flutter job and the web build pin.
      expect(job, contains(r'flutter-version: ${{ env.FLUTTER_VERSION }}'));
    });
  });

  group('iOS deployment target', () {
    test('is one value across the Podfile and the Xcode project, at least 14.0',
        () {
      // Arrange
      final podfile = File('ios/Podfile').readAsStringSync();
      final pbxproj =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

      // Act
      final values = <String>{
        ...RegExp(r"platform :ios, '([0-9.]+)'")
            .allMatches(podfile)
            .map((m) => m.group(1)!),
        ...RegExp(r"\['IPHONEOS_DEPLOYMENT_TARGET'\] = '([0-9.]+)'")
            .allMatches(podfile)
            .map((m) => m.group(1)!),
        ...RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);')
            .allMatches(pbxproj)
            .map((m) => m.group(1)!),
      };

      // Assert — `pod install` refuses a platform below any pod's minimum,
      // which only shows on a Mac. workmanager_apple (the push refresh job)
      // requires 14.0, the highest of the current pods; raise this floor
      // with the pod that needs it.
      expect(values, hasLength(1), reason: 'deployment targets: $values');
      final major = int.parse(values.single.split('.').first);
      expect(major, greaterThanOrEqualTo(14), reason: values.single);
    });
  });
}
