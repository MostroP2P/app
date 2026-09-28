/// Hands bytes to the browser as a download (#589 phase 4).
///
/// `file_picker` 8 has no save dialog on the web, so the web build saves an
/// attachment the way any web page does: the browser downloads it where the
/// user's settings say. Off web this is never called.
library;

export 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download_web.dart';
