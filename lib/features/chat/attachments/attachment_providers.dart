import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/src/rust/api/messages.dart' as messages_api;

/// How many decrypted bytes stay in memory across bubbles.
///
/// Enough for a conversation's worth of receipts; past it the oldest go and
/// are decrypted again from the encrypted disk cache when scrolled back to.
const int kDecryptedCacheBytes = 64 * 1024 * 1024;

/// Decrypted attachments, in memory only, least recently used first out.
///
/// The disk holds the encrypted blob (Rust's `attachment_blobs`); this keeps
/// a bubble scrolled off and back from decrypting it again. Identity-scoped:
/// `resetIdentityScopedState` drops it with the rest of the user's chats.
class DecryptedAttachmentCache {
  DecryptedAttachmentCache({this.maxBytes = kDecryptedCacheBytes});

  final int maxBytes;

  // Insertion order is recency: a hit is removed and added back at the end.
  final LinkedHashMap<String, messages_api.AttachmentData> _entries =
      LinkedHashMap();
  int _bytes = 0;

  int get sizeInBytes => _bytes;

  messages_api.AttachmentData? get(String messageId) {
    final hit = _entries.remove(messageId);
    if (hit != null) _entries[messageId] = hit;
    return hit;
  }

  void put(String messageId, messages_api.AttachmentData data) {
    final previous = _entries.remove(messageId);
    if (previous != null) _bytes -= previous.bytes.length;
    // One file larger than the whole budget is served, never kept.
    if (data.bytes.length > maxBytes) return;
    _entries[messageId] = data;
    _bytes += data.bytes.length;
    while (_bytes > maxBytes) {
      final oldest = _entries.keys.first;
      _bytes -= _entries.remove(oldest)!.bytes.length;
    }
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}

final decryptedAttachmentCacheProvider = Provider<DecryptedAttachmentCache>((
  ref,
) {
  final cache = DecryptedAttachmentCache();
  ref.onDispose(cache.clear);
  return cache;
});

/// The decrypted attachment of [messageId], from [cache] or through Rust.
///
/// A failure is not cached, so calling again is the retry.
Future<messages_api.AttachmentData> loadAttachment({
  required DecryptedAttachmentCache cache,
  required AttachmentGateway gateway,
  required String messageId,
}) async {
  final hit = cache.get(messageId);
  if (hit != null) return hit;
  final data = await gateway.download(messageId);
  cache.put(messageId, data);
  return data;
}

/// [loadAttachment] for a widget that shows the file as soon as it arrives:
/// an image bubble, the viewer. `ref.invalidate` is the retry.
final attachmentDataProvider = FutureProvider.autoDispose
    .family<messages_api.AttachmentData, String>(
      (ref, messageId) => loadAttachment(
        cache: ref.watch(decryptedAttachmentCacheProvider),
        gateway: ref.read(attachmentGatewayProvider),
        messageId: messageId,
      ),
    );
