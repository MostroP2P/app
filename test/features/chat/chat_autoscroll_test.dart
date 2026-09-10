import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/screens/chat_room_screen.dart';

void main() {
  group('isPinnedToBottom', () {
    test('follows the conversation when already at the end', () {
      expect(isPinnedToBottom(offset: 1000, maxScrollExtent: 1000), isTrue);
    });

    test('still follows within one bubble of the end', () {
      expect(
        isPinnedToBottom(
          offset: 1000 - kFollowThresholdPixels,
          maxScrollExtent: 1000,
        ),
        isTrue,
      );
    });

    test('leaves a reader who has scrolled up where they are', () {
      expect(
        isPinnedToBottom(offset: 400, maxScrollExtent: 1000),
        isFalse,
        reason: 'an arriving message must not yank the reader to the bottom',
      );
    });

    test('treats an unscrollable list as pinned', () {
      expect(isPinnedToBottom(offset: 0, maxScrollExtent: 0), isTrue);
    });
  });
}
