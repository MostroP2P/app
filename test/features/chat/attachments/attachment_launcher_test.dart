import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/attachments/attachment_launcher.dart';
import 'package:path/path.dart' as p;

import '../../../support/attachment_fixtures.dart';

void main() {
  group('safeTempFileName', () {
    test('keeps a plain name and swaps in the extension of its type', () {
      expect(safeTempFileName('transfer.pdf', 'pdf'), 'transfer.pdf');
      expect(safeTempFileName('receipt.exe', 'jpg'), 'receipt.jpg');
    });

    test('drops anything a Windows shell would read as a command', () {
      final name = safeTempFileName('a&calc|x^"%PATH%".pdf', 'pdf');
      expect(name, matches(RegExp(r'^[A-Za-z0-9 ._-]+\.pdf$')));
      expect(name, isNot(contains('&')));
    });

    test('never starts with a dot or a dash, never empty', () {
      expect(safeTempFileName('--help.pdf', 'pdf'), 'help.pdf');
      expect(safeTempFileName('.hidden.pdf', 'pdf'), 'hidden.pdf');
      expect(safeTempFileName('???.pdf', 'pdf'), 'attachment.pdf');
      expect(safeTempFileName('', 'pdf'), 'attachment.pdf');
    });

    test('never names a copy after a Windows device', () {
      expect(safeTempFileName('CON.pdf', 'pdf'), '_CON.pdf');
      expect(safeTempFileName('aux.docx', 'docx'), '_aux.docx');
      expect(safeTempFileName('COM1.mp4', 'mp4'), '_COM1.mp4');
      expect(safeTempFileName('Lpt9.backup.pdf', 'pdf'), '_Lpt9.backup.pdf');
      // Only the whole first part counts.
      expect(safeTempFileName('console.pdf', 'pdf'), 'console.pdf');
      expect(safeTempFileName('COM10.pdf', 'pdf'), 'COM10.pdf');
    });

    test('caps a long name', () {
      final name = safeTempFileName('${'x' * 300}.pdf', 'pdf');
      expect(name.length, lessThanOrEqualTo(64));
    });
  });

  group('AttachmentLauncher', () {
    late Directory root;
    late AttachmentLauncher launcher;

    setUp(() {
      root = Directory.systemTemp.createTempSync('attachments_test');
      launcher = AttachmentLauncher(tempRoot: () async => root);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('hands off only the types v1 sends', () {
      for (final type in kOpenableTypes.keys) {
        expect(launcher.canHandOffType(type), isTrue, reason: type);
      }
      expect(
        launcher.canHandOffType('application/vnd.android.package-archive'),
        isFalse,
      );
      expect(launcher.canHandOffType('text/html'), isFalse);
      expect(launcher.canHandOffType('application/octet-stream'), isFalse);
    });

    test(
      'writes each copy apart, named safely, and sweep deletes them',
      () async {
        final data = attachmentData(
          [1, 2, 3],
          fileName: 'bank & co.pdf',
          mimeType: 'application/pdf',
        );

        final first = await launcher.writeTempCopy(data);
        final second = await launcher.writeTempCopy(data);

        expect(first, isNot(second));
        expect(
          p.isWithin(p.join(root.path, kAttachmentTempDir), first),
          isTrue,
        );
        expect(p.basename(first), 'bank _ co.pdf');
        expect(File(first).readAsBytesSync(), [1, 2, 3]);

        await launcher.sweep();

        expect(File(first).existsSync(), isFalse);
        expect(
          Directory(p.join(root.path, kAttachmentTempDir)).existsSync(),
          isFalse,
        );
      },
    );

    test('refuses to write a type it would not hand off', () async {
      final data = attachmentData(
        [1],
        fileName: 'x.apk',
        mimeType: 'application/zip',
      );
      await expectLater(launcher.writeTempCopy(data), throwsStateError);
      expect(
        Directory(p.join(root.path, kAttachmentTempDir)).existsSync(),
        isFalse,
      );
    });

    test('a copy no app took is deleted at once', () async {
      final path = await launcher.writeTempCopy(
        attachmentData([1], fileName: 'a.pdf', mimeType: 'application/pdf'),
      );

      launcher.releaseCopy(path, handedOff: false);
      await pumpEventQueue();

      expect(File(path).parent.existsSync(), isFalse);
    });

    test('a handed-off copy expires on its own, without a sweep', () async {
      final shortLived = AttachmentLauncher(
        tempRoot: () async => root,
        copyLifetime: const Duration(milliseconds: 20),
      );
      final path = await shortLived.writeTempCopy(
        attachmentData([1], fileName: 'a.pdf', mimeType: 'application/pdf'),
      );

      shortLived.releaseCopy(path, handedOff: true);
      expect(File(path).existsSync(), isTrue);
      // Polled, not slept on: under a loaded test run the timer and the
      // delete can land well after the lifetime.
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (File(path).parent.existsSync() &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(File(path).parent.existsSync(), isFalse);
    });

    test('never deletes outside its own directory', () async {
      final elsewhere = File(p.join(root.path, 'keep', 'x.pdf'))
        ..createSync(recursive: true);

      launcher.releaseCopy(elsewhere.path, handedOff: false);
      await pumpEventQueue();

      expect(elsewhere.existsSync(), isTrue);
    });

    test('a resume sweep keeps a copy that may still be read', () async {
      final data = attachmentData(
        [1],
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
      );
      final fresh = await launcher.writeTempCopy(data);

      await launcher.sweep(olderThan: const Duration(hours: 1));
      expect(File(fresh).existsSync(), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await launcher.sweep(olderThan: const Duration(milliseconds: 10));
      expect(File(fresh).existsSync(), isFalse);
    });

    test('a sweep and a write never overlap', () async {
      final data = attachmentData(
        [1, 2],
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
      );
      // Not awaited in between, as the start-up, resume and identity sweeps
      // are: whatever order they land in, the write completes and a write
      // queued after the sweep survives it.
      final write1 = launcher.writeTempCopy(data);
      final sweep = launcher.sweep();
      final write2 = launcher.writeTempCopy(data);

      final first = await write1;
      await sweep;
      final second = await write2;

      expect(File(first).existsSync(), isFalse);
      expect(File(second).readAsBytesSync(), [1, 2]);
    });

    test('sweep with nothing to delete is a no-op', () async {
      await launcher.sweep();
    });
  });

  test('the Android app drops the media permissions open_filex declares', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final permission in [
      'READ_EXTERNAL_STORAGE',
      'READ_MEDIA_IMAGES',
      'READ_MEDIA_VIDEO',
      'READ_MEDIA_AUDIO',
    ]) {
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.$permission" '
          'tools:node="remove" />',
        ),
        reason: permission,
      );
    }
  });
}
