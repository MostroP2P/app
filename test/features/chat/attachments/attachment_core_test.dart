import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/attachments/attachment_errors.dart';
import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/attachment_picker.dart';
import 'package:mostro/features/chat/attachments/attachment_providers.dart';
import 'package:mostro/features/chat/widgets/encrypted_image_message.dart';
import 'package:mostro/l10n/app_localizations_en.dart';

import '../../../support/attachment_fixtures.dart';
import '../../../support/provider_harness.dart';

void main() {
  group('DecryptedAttachmentCache', () {
    test('evicts the least recently used entry past its budget', () {
      final cache = DecryptedAttachmentCache(maxBytes: 10);
      cache.put('a', attachmentData(List.filled(4, 1)));
      cache.put('b', attachmentData(List.filled(4, 2)));
      // Reading `a` makes `b` the oldest.
      expect(cache.get('a'), isNotNull);

      cache.put('c', attachmentData(List.filled(4, 3)));

      expect(cache.get('b'), isNull);
      expect(cache.get('a'), isNotNull);
      expect(cache.get('c'), isNotNull);
      expect(cache.sizeInBytes, 8);
    });

    test('serves but never keeps a file larger than the whole budget', () {
      final cache = DecryptedAttachmentCache(maxBytes: 10);
      cache.put('small', attachmentData(List.filled(4, 1)));

      cache.put('huge', attachmentData(List.filled(11, 1)));

      expect(cache.get('huge'), isNull);
      expect(cache.get('small'), isNotNull);
    });

    test('replacing an entry does not count its old size twice', () {
      final cache = DecryptedAttachmentCache(maxBytes: 10);
      cache.put('a', attachmentData(List.filled(6, 1)));
      cache.put('a', attachmentData(List.filled(2, 1)));
      expect(cache.sizeInBytes, 2);
    });

    test('is emptied when the provider is invalidated (identity reset)', () {
      final container = createContainer();
      final cache = container.read(decryptedAttachmentCacheProvider);
      cache.put('a', attachmentData([1, 2, 3]));

      container.invalidate(decryptedAttachmentCacheProvider);

      expect(cache.sizeInBytes, 0);
      expect(container.read(decryptedAttachmentCacheProvider).get('a'), isNull);
    });
  });

  group('loadAttachment', () {
    test('decrypts once, then serves from memory', () async {
      final gateway = FakeAttachmentGateway(
        downloadResult: (_) async => attachmentData([1, 2, 3]),
      );
      final cache = DecryptedAttachmentCache();

      await loadAttachment(cache: cache, gateway: gateway, messageId: 'm');
      final again = await loadAttachment(
        cache: cache,
        gateway: gateway,
        messageId: 'm',
      );

      expect(gateway.downloads, ['m']);
      expect(again.bytes, [1, 2, 3]);
    });

    test('does not cache a failure, so the next call retries', () async {
      var calls = 0;
      final gateway = FakeAttachmentGateway(
        downloadResult: (_) async {
          if (calls++ == 0) throw Exception('DownloadFailed: timeout');
          return attachmentData([9]);
        },
      );
      final cache = DecryptedAttachmentCache();

      await expectLater(
        loadAttachment(cache: cache, gateway: gateway, messageId: 'm'),
        throwsException,
      );
      final data = await loadAttachment(
        cache: cache,
        gateway: gateway,
        messageId: 'm',
      );

      expect(data.bytes, [9]);
    });
  });

  group('attachmentErrorMessage', () {
    final l10n = AppLocalizationsEn();

    test('maps each Rust marker, wrapped in context, to its message', () {
      final cases = {
        'FileTooLarge: 30000000 bytes': l10n.attachmentTooLarge,
        'UnsupportedFileType: image/webp': l10n.attachmentUnsupported,
        'InvalidImage: truncated': l10n.attachmentInvalidImage,
        'PeerUnknown: the counterpart has not taken the order yet':
            l10n.attachmentPeerUnknown,
        'UploadFailed: every server refused': l10n.attachmentUploadFailed,
        'DecryptionFailed: aead': l10n.attachmentDecryptFailed,
        'DownloadFailed: 404': l10n.attachmentDownloadFailed,
        'AttachmentNotFound: message x': l10n.attachmentDownloadFailed,
        'SendFailed: no relay': l10n.attachmentSendFailed,
        'something else': l10n.attachmentSendFailed,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          attachmentErrorMessage(l10n, Exception('AnyhowException($key)')),
          value,
          reason: key,
        );
      }
    });

    test('offers a retry only where one can succeed', () {
      expect(isRetryableAttachmentError('UploadFailed: x'), isTrue);
      expect(isRetryableAttachmentError('DownloadFailed: x'), isTrue);
      expect(isRetryableAttachmentError('SendFailed: x'), isTrue);
      expect(isRetryableAttachmentError('FileTooLarge: x'), isFalse);
      expect(isRetryableAttachmentError('UnsupportedFileType: x'), isFalse);
      expect(isRetryableAttachmentError('InvalidImage: x'), isFalse);
      expect(isRetryableAttachmentError('DecryptionFailed: x'), isFalse);
    });
  });

  test('checkPicked refuses a file over 25 MB before reading it', () {
    var reads = 0;
    PickedAttachment file(int size) => PickedAttachment(
      name: 'big.pdf',
      size: size,
      read: () async {
        reads++;
        throw StateError('must not be read');
      },
    );

    expect(checkPicked(file(kMaxAttachmentBytes)), isA<Picked>());
    expect(checkPicked(file(kMaxAttachmentBytes + 1)), isA<PickTooLarge>());
    expect(reads, 0);
  });

  test('collectBytes joins a web read stream in order', () async {
    // Arrange: the slices file_picker hands over on the web.
    final stream = Stream<List<int>>.fromIterable([
      [1, 2],
      [3],
      [4, 5, 6],
    ]);

    // Act
    final bytes = await collectBytes(stream);

    // Assert
    expect(bytes, [1, 2, 3, 4, 5, 6]);
  });

  test('formatAttachmentSize shows KB below a megabyte, MB above', () {
    expect(formatAttachmentSize(1), '1 KB');
    expect(formatAttachmentSize(524288), '512 KB');
    expect(formatAttachmentSize(1468006), '1.4 MB');
  });

  test('imageBubbleAspectRatio clamps what the peer declared', () {
    expect(imageBubbleAspectRatio(1200, 900), closeTo(4 / 3, 1e-9));
    expect(imageBubbleAspectRatio(1, 10000), 0.5);
    expect(imageBubbleAspectRatio(10000, 1), 2.0);
    expect(imageBubbleAspectRatio(null, 900), closeTo(4 / 3, 1e-9));
    expect(imageBubbleAspectRatio(0, 0), closeTo(4 / 3, 1e-9));
  });
}
