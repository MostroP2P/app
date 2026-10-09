/// What the page knows about installing the web app (#778).
///
/// The browser decides whether the app can be installed and owns the dialog
/// that does it; the order book only offers it at a good moment. Off web
/// every answer is "nothing to install": a native build already is installed.
library;

/// How the user answered the browser's own install dialog.
enum PwaPromptOutcome {
  accepted,
  dismissed,

  /// No dialog to show: the browser never offered one, or it was spent.
  unavailable,
}

abstract interface class PwaInstallBridge {
  /// Whether this is the web build at all.
  bool get isWeb;

  /// The page already runs as the installed app (`display-mode: standalone`,
  /// or `navigator.standalone` on iOS).
  bool get isStandalone;

  /// The browser fired `beforeinstallprompt` and the page kept it, so
  /// [promptNatively] can show the browser's dialog. Chromium does not fire it
  /// while the app is already installed.
  bool get canPromptNatively;

  /// Fires when [canPromptNatively] may have changed: the browser offered the
  /// install, or the app was installed.
  Stream<void> get changes;

  /// Shows the browser's install dialog. A kept event shows it once, whatever
  /// the answer, so [canPromptNatively] is false afterwards.
  Future<PwaPromptOutcome> promptNatively();
}
