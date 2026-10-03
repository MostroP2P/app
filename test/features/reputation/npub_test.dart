import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/reputation/npub.dart';

void main() {
  test('encodes the NIP-19 example key', () {
    expect(
      hexToNpub(
        '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e',
      ),
      'npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg',
    );
    expect(hexToNpub('nope'), isNull);
  });
}
