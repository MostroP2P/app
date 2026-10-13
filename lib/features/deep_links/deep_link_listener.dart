import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/deep_links/models/order_link_rules.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/shared/widgets/trade_action_listener.dart'
    show pushUnlessVisible;

/// Hands the `mostro:` links the OS opens the app with to the order link
/// screen (`OrderLinkScreen`), which does everything else.
///
/// Wraps the app root, like [TradeActionListener], and listens for the whole
/// session. The link that launched the app arrives here too, as the first
/// event: `app_links` keeps it until someone listens.
///
/// A link that arrives during the first run waits for it to end — the router
/// would send the order link screen to the walkthrough and lose it. The same
/// link twice within [duplicateWindow] opens once: a platform may hand the
/// launch link over again, as v1 saw.
class DeepLinkListener extends ConsumerStatefulWidget {
  const DeepLinkListener({
    super.key,
    required this.child,
    this.links,
    this.open,
  });

  final Widget child;

  /// Test seam — production listens to the OS through `app_links`. The web
  /// gets none: a page cannot be the handler of a `mostro:` link.
  final Stream<String>? links;

  /// Test seam — production pushes on the global [appRouter] unless the
  /// destination is already the screen on top.
  final void Function(String destination)? open;

  static const duplicateWindow = Duration(seconds: 2);

  @override
  ConsumerState<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends ConsumerState<DeepLinkListener> {
  StreamSubscription<String>? _subscription;

  /// A link that arrived before the first run ended.
  String? _waiting;

  String? _lastLink;
  DateTime? _lastAt;

  @override
  void initState() {
    super.initState();
    // After the first frame, so the router has its first location before a
    // link pushes on top of it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscription = (widget.links ?? _osLinks()).listen(
        _onLink,
        onError: (Object e) => debugPrint('[deep-link] link stream failed: $e'),
      );
    });
  }

  static Stream<String> _osLinks() =>
      kIsWeb ? const Stream.empty() : AppLinks().stringLinkStream;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onLink(String raw) {
    final link = raw.trim();
    // Only `mostro:` is registered, but a platform may still pass on
    // something else (the web's page address, a desktop argument).
    if (!isOrderLink(link)) return;

    final now = clock.now();
    final lastAt = _lastAt;
    if (link == _lastLink &&
        lastAt != null &&
        now.difference(lastAt) < DeepLinkListener.duplicateWindow) {
      return;
    }
    _lastLink = link;
    _lastAt = now;

    if (ref.read(firstRunProvider).valueOrNull != true) {
      _waiting = link;
      return;
    }
    _openLink(link);
  }

  void _openLink(String link) {
    final destination = AppRoute.orderLinkPath(link);
    final open =
        widget.open ??
        (String destination) => pushUnlessVisible(appRouter, destination);
    try {
      open(destination);
    } catch (e) {
      debugPrint('[deep-link] could not open the order link screen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(firstRunProvider, (_, next) {
      final link = _waiting;
      if (link == null || next.valueOrNull != true) return;
      _waiting = null;
      _openLink(link);
    });
    return widget.child;
  }
}
