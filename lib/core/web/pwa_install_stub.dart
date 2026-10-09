/// Non-web install offer: a native build has nothing to install.
///
/// See `pwa_install_bridge.dart`.
library;

import 'package:mostro/core/web/pwa_install_bridge.dart';

PwaInstallBridge createPwaInstallBridge() => const _NativeBuild();

class _NativeBuild implements PwaInstallBridge {
  const _NativeBuild();

  @override
  bool get isWeb => false;

  @override
  bool get isStandalone => false;

  @override
  bool get canPromptNatively => false;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<PwaPromptOutcome> promptNatively() async =>
      PwaPromptOutcome.unavailable;
}
