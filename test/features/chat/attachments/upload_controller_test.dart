import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/upload_controller.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

import '../../../support/attachment_fixtures.dart';
import '../../../support/provider_harness.dart';

const _trade = 'order-chat';

void main() {
  late FakeAttachmentGateway gateway;

  ChatUploadsNotifier notifier() {
    final container = createContainer(
      overrides: [attachmentGatewayProvider.overrideWithValue(gateway)],
    );
    // Keep the autoDispose family alive for the test.
    container.listen(chatUploadsProvider(_trade), (_, _) {});
    return container.read(chatUploadsProvider(_trade).notifier);
  }

  test(
    'the dispute chat sends to the solver, the P2P chat to the peer',
    () async {
      final sent = attachmentMessage(id: 'evt', attachment: imageInfo());
      gateway = FakeAttachmentGateway(sendResult: (_) async => sent);
      final container = createContainer(
        overrides: [attachmentGatewayProvider.overrideWithValue(gateway)],
      );
      container
        ..listen(disputeUploadsProvider(_trade), (_, _) {})
        ..listen(chatUploadsProvider(_trade), (_, _) {});

      await container
          .read(disputeUploadsProvider(_trade).notifier)
          .send('receipt.png', Uint8List(3));
      expect(gateway.solverSends.single.tradeId, _trade);
      expect(gateway.sends, isEmpty);

      await container
          .read(chatUploadsProvider(_trade).notifier)
          .send('receipt.png', Uint8List(3));
      expect(gateway.sends.single.tradeId, _trade);
      expect(gateway.solverSends, hasLength(1));
    },
  );

  test('shows the upload while it runs and drops it once sent', () async {
    final done = Completer<rust_types.ChatMessage>();
    gateway = FakeAttachmentGateway(sendResult: (_) => done.future);
    final uploads = notifier();

    final result = uploads.send('receipt.png', Uint8List(3));

    expect(uploads.state, hasLength(1));
    expect(uploads.state.single.status, UploadStatus.uploading);
    expect(gateway.sends.single.tradeId, _trade);
    expect(gateway.sends.single.fileName, 'receipt.png');

    final sent = attachmentMessage(id: 'evt', attachment: imageInfo());
    done.complete(sent);

    expect(await result, sent);
    expect(uploads.state, isEmpty);
  });

  test('reports progress under the id it sent with', () async {
    final done = Completer<rust_types.ChatMessage>();
    gateway = FakeAttachmentGateway(sendResult: (_) => done.future);
    final uploads = notifier();

    unawaited(uploads.send('receipt.png', Uint8List(3)));
    final id = uploads.state.single.id;
    expect(gateway.sends.single.id, id);

    gateway.progressControllers[id]!
      ..add(0.3)
      ..add(0.1); // a late, smaller value never moves the bar back
    await pumpEventQueue();

    expect(uploads.state.single.progress, 0.3);
    done.complete(attachmentMessage(id: 'evt', attachment: imageInfo()));
  });

  test('keeps a failed upload with its error until retried', () async {
    var attempt = 0;
    final sent = attachmentMessage(id: 'evt', attachment: imageInfo());
    gateway = FakeAttachmentGateway(
      sendResult: (_) async {
        if (attempt++ == 0) throw Exception('UploadFailed: no server');
        return sent;
      },
    );
    final uploads = notifier();

    expect(await uploads.send('receipt.png', Uint8List(3)), isNull);
    final failed = uploads.state.single;
    expect(failed.status, UploadStatus.failed);
    expect(failed.error.toString(), contains('UploadFailed'));

    expect(await uploads.retry(failed.id), sent);
    expect(uploads.state, isEmpty);
    // Same id both times, so the progress stream follows the retry.
    expect(gateway.sends.map((s) => s.id).toSet(), {failed.id});
  });

  test('discard drops a failed upload and its bytes', () async {
    gateway = FakeAttachmentGateway(
      sendResult: (_) async => throw Exception('SendFailed: x'),
    );
    final uploads = notifier();
    await uploads.send('receipt.png', Uint8List(3));

    uploads.discard(uploads.state.single.id);

    expect(uploads.state, isEmpty);
  });

  test('retry ignores an upload that is not failed', () async {
    final done = Completer<rust_types.ChatMessage>();
    gateway = FakeAttachmentGateway(sendResult: (_) => done.future);
    final uploads = notifier();
    unawaited(uploads.send('receipt.png', Uint8List(3)));

    expect(await uploads.retry(uploads.state.single.id), isNull);
    expect(gateway.sends, hasLength(1));
    done.complete(attachmentMessage(id: 'evt', attachment: imageInfo()));
  });
}
