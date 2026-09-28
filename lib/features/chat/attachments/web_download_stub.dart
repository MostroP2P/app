/// Non-web implementation of `web_download.dart`: never called.
library;

import 'dart:typed_data';

void downloadBytes(String fileName, Uint8List bytes) {
  throw UnsupportedError('downloadBytes is web-only');
}
