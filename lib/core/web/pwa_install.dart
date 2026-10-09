/// The page's side of the install offer (#778): see `pwa_install_bridge.dart`.
///
/// Off web this is a bridge with nothing to install.
library;

export 'pwa_install_stub.dart'
    if (dart.library.js_interop) 'pwa_install_web.dart';
