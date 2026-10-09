import 'dart:async';

import 'package:mostro/core/web/pwa_install_bridge.dart';

/// A browser page for the install offer (#778), driven by the test.
class FakePwaInstallBridge implements PwaInstallBridge {
  FakePwaInstallBridge({
    this.isWeb = true,
    this.isStandalone = false,
    this.canPromptNatively = false,
    this.outcome = PwaPromptOutcome.accepted,
  });

  @override
  final bool isWeb;

  @override
  bool isStandalone;

  @override
  bool canPromptNatively;

  /// What the user answers in the browser's own install dialog.
  PwaPromptOutcome outcome;

  /// How many times the app asked the browser to show its dialog.
  int prompts = 0;

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  /// The browser fired `beforeinstallprompt`.
  void fireInstallable() {
    canPromptNatively = true;
    _changes.add(null);
  }

  /// The browser fired `appinstalled`.
  void fireInstalled() {
    canPromptNatively = false;
    _changes.add(null);
  }

  @override
  Future<PwaPromptOutcome> promptNatively() async {
    if (!canPromptNatively) return PwaPromptOutcome.unavailable;
    prompts++;
    // A saved event can show its dialog once, whatever the answer.
    canPromptNatively = false;
    return outcome;
  }
}
