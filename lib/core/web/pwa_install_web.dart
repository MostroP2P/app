/// Web implementation of the install offer (#778).
///
/// The browser fires `beforeinstallprompt` when it would install the app,
/// often before Flutter has started, and lets the page show its install dialog
/// once from that event. So `web/index.html` keeps the event in a global and
/// announces every change; this side reads it when the user asks to install.
/// See `pwa_install_bridge.dart`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:mostro/core/web/pwa_install_bridge.dart';
import 'package:web/web.dart' as web;

/// Where `web/index.html` keeps the browser's install event. Equal on both
/// sides; `test/web/pages_bundle_test.dart` holds them together.
const kInstallPromptGlobal = 'mostroInstallPrompt';

/// What `web/index.html` dispatches on `window` when the event is kept or the
/// app gets installed.
const kInstallChangeEvent = 'mostro-install-change';

PwaInstallBridge createPwaInstallBridge() => _Page();

/// The browser's `BeforeInstallPromptEvent`, which no IDL in `package:web`
/// describes: Chromium only.
extension type _InstallPromptEvent._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> prompt();
  external JSPromise<_UserChoice> get userChoice;
}

extension type _UserChoice._(JSObject _) implements JSObject {
  external String get outcome;
}

class _Page implements PwaInstallBridge {
  _Page() {
    web.window.addEventListener(
      kInstallChangeEvent,
      ((web.Event _) => _changes.add(null)).toJS,
    );
  }

  final _changes = StreamController<void>.broadcast();

  @override
  bool get isWeb => true;

  @override
  bool get isStandalone {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    // iOS Safari does not match the media query on every version, but it
    // has always set this non-standard flag on a home-screen app.
    final standalone = web.window.navigator.getProperty<JSAny?>(
      'standalone'.toJS,
    );
    return standalone.dartify() == true;
  }

  JSObject? get _kept =>
      globalContext.getProperty<JSObject?>(kInstallPromptGlobal.toJS);

  @override
  bool get canPromptNatively => _kept != null;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<PwaPromptOutcome> promptNatively() async {
    final kept = _kept;
    if (kept == null) return PwaPromptOutcome.unavailable;
    // Spent once shown, whatever the answer: the browser fires a new event
    // when it would offer the install again.
    globalContext.setProperty(kInstallPromptGlobal.toJS, null);
    final event = _InstallPromptEvent._(kept);
    try {
      await event.prompt().toDart;
      final choice = await event.userChoice.toDart;
      return choice.outcome == 'accepted'
          ? PwaPromptOutcome.accepted
          : PwaPromptOutcome.dismissed;
    } catch (e) {
      // Refused (the tap's activation was gone, the page hidden): the event
      // was not spent, so Settings can still offer it.
      debugPrint('[install] browser install dialog failed: $e');
      globalContext.setProperty(kInstallPromptGlobal.toJS, kept);
      return PwaPromptOutcome.unavailable;
    } finally {
      _changes.add(null);
    }
  }
}
