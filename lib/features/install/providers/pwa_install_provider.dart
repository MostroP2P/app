import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/web/pwa_install.dart';
import 'package:mostro/core/web/pwa_install_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Set once the user answered the order book's install card, either way.
const kPwaInstallAnsweredKey = 'pwaInstallAnswered';

/// How this page can install the app (#778).
enum PwaInstallRoute {
  /// Nothing to install: a native build, the installed app itself, or a
  /// browser that has not offered it (Firefox never does).
  none,

  /// The browser's own install dialog.
  native,

  /// Steps to follow by hand: iOS has no install API.
  instructions,
}

@immutable
class PwaInstallState {
  const PwaInstallState({
    required this.route,
    required this.isMobile,
    required this.answered,
    required this.loaded,
  });

  final PwaInstallRoute route;

  /// A phone or tablet browser; the card is offered there only.
  final bool isMobile;

  /// The user answered the card on this device.
  final bool answered;

  /// The stored answer has been read. Until then no card: one that shows and
  /// then vanishes would be worse than none.
  final bool loaded;

  /// Settings offers the install whenever there is a way to do it.
  bool get canInstall => route != PwaInstallRoute.none;

  /// The order book's card: once, on mobile.
  bool get offersCard => loaded && isMobile && canInstall && !answered;

  PwaInstallState copyWith({
    PwaInstallRoute? route,
    bool? answered,
    bool? loaded,
  }) => PwaInstallState(
    route: route ?? this.route,
    isMobile: isMobile,
    answered: answered ?? this.answered,
    loaded: loaded ?? this.loaded,
  );
}

/// The page this build runs in. Overridden in tests.
final pwaInstallBridgeProvider = Provider<PwaInstallBridge>(
  (ref) => createPwaInstallBridge(),
);

/// On web, Flutter derives this from the browser, iPadOS included.
final pwaInstallPlatformProvider = Provider<TargetPlatform>(
  (ref) => defaultTargetPlatform,
);

final pwaInstallProvider =
    StateNotifierProvider<PwaInstallNotifier, PwaInstallState>(
      (ref) => PwaInstallNotifier(
        bridge: ref.watch(pwaInstallBridgeProvider),
        platform: ref.watch(pwaInstallPlatformProvider),
      ),
    );

/// The install offer: whether the page can install the app, and whether the
/// user already answered the card.
///
/// The answer is a device preference, not identity data:
/// `resetIdentityScopedState` leaves it alone, so a new identity on the same
/// phone is not asked again.
class PwaInstallNotifier extends StateNotifier<PwaInstallState> {
  PwaInstallNotifier({
    required PwaInstallBridge bridge,
    required TargetPlatform platform,
    Future<SharedPreferences> Function()? prefs,
  }) : _bridge = bridge,
       _platform = platform,
       _prefs = prefs ?? SharedPreferences.getInstance,
       super(
         PwaInstallState(
           route: _routeFor(bridge, platform),
           isMobile: _isMobile(platform),
           answered: false,
           loaded: false,
         ),
       ) {
    _changes = bridge.changes.listen((_) => _refreshRoute());
    loaded = _load();
  }

  final PwaInstallBridge _bridge;
  final TargetPlatform _platform;
  final Future<SharedPreferences> Function() _prefs;
  late final StreamSubscription<void> _changes;

  /// Completes once the stored answer has been read.
  late final Future<void> loaded;

  static bool _isMobile(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  static PwaInstallRoute _routeFor(
    PwaInstallBridge bridge,
    TargetPlatform platform,
  ) {
    if (!bridge.isWeb || bridge.isStandalone) return PwaInstallRoute.none;
    if (bridge.canPromptNatively) return PwaInstallRoute.native;
    if (platform == TargetPlatform.iOS) return PwaInstallRoute.instructions;
    return PwaInstallRoute.none;
  }

  void _refreshRoute() {
    if (!mounted) return;
    state = state.copyWith(route: _routeFor(_bridge, _platform));
  }

  Future<void> _load() async {
    var answered = false;
    try {
      final prefs = await _prefs();
      answered = prefs.getBool(kPwaInstallAnsweredKey) ?? false;
    } catch (e) {
      // Unreadable: offer the card. Asking once more beats never asking.
      debugPrint('[install] answer load failed: $e');
    }
    if (!mounted) return;
    state = state.copyWith(answered: state.answered || answered, loaded: true);
  }

  /// The user answered the card: it never shows again on this device.
  Future<void> markAnswered() async {
    state = state.copyWith(answered: true);
    try {
      final prefs = await _prefs();
      await prefs.setBool(kPwaInstallAnsweredKey, true);
    } catch (e) {
      // Best effort: the card stays hidden for this session.
      debugPrint('[install] answer save failed: $e');
    }
  }

  /// The user tapped Install: shows the browser's dialog where there is one,
  /// and stores that as the answer to the card.
  ///
  /// Chrome only shows the dialog while the tap's user activation lasts, so
  /// it is asked for before anything is awaited: behind a slow disk write,
  /// `prompt()` would be refused and the card would be gone for nothing.
  Future<PwaPromptOutcome> install() async {
    final prompted =
        state.route == PwaInstallRoute.native ? promptNatively() : null;
    await markAnswered();
    return await prompted ?? PwaPromptOutcome.unavailable;
  }

  /// Shows the browser's install dialog ([PwaInstallRoute.native]).
  Future<PwaPromptOutcome> promptNatively() async {
    final outcome = await _bridge.promptNatively();
    _refreshRoute();
    return outcome;
  }

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }
}
