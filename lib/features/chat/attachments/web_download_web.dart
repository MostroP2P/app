/// Web implementation of `web_download.dart`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// How long the plaintext stays reachable through its object URL: long
/// enough for the browser to start the download, then it is released.
const _kObjectUrlLifetime = Duration(seconds: 10);

/// Starts a download of [bytes] named [fileName] (sanitized by Rust).
void downloadBytes(String fileName, Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor =
      web.HTMLAnchorElement()
        ..href = url
        ..download = fileName;
  anchor.style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(_kObjectUrlLifetime, () => web.URL.revokeObjectURL(url));
}
