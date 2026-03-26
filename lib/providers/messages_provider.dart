/// Messages provider stub.
///
/// Phase 5 T048 replaces this with a real implementation backed by
/// rust/src/api/trades.rs chat methods.
library messages_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder chat message.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.content,
    required this.isMine,
  });

  final String id;
  final String content;
  final bool isMine;
}

class MessagesNotifier extends AsyncNotifier<List<ChatMessage>> {
  @override
  Future<List<ChatMessage>> build() async {
    // Phase 5: subscribe to trade message stream from Rust.
    return [];
  }
}

final messagesProvider =
    AsyncNotifierProvider<MessagesNotifier, List<ChatMessage>>(
  MessagesNotifier.new,
);
