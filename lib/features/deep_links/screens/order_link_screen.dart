import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/deep_links/models/order_link_rules.dart';
import 'package:mostro/features/deep_links/providers/order_link_providers.dart';
import 'package:mostro/features/deep_links/widgets/order_link_node_dialog.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart'
    show showOrderDetailSnackBar;
import 'package:mostro/features/settings/models/node_display.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/mascot/mostro_mascot.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/order_link.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Opens a `mostro:` order link: finds the order, changes to its node when the
/// user agrees, and hands over to the screen the order belongs on — the take
/// screen of its side, or the trade when the user already takes part in it.
///
/// This screen is the link's waiting room and the place its failures are
/// told: it replaces itself with the destination, so the back arrow there
/// returns to wherever the user was when the link arrived.
class OrderLinkScreen extends ConsumerStatefulWidget {
  const OrderLinkScreen({super.key, required this.link});

  /// The link as the OS handed it over.
  final String link;

  @override
  ConsumerState<OrderLinkScreen> createState() => _OrderLinkScreenState();
}

class _OrderLinkScreenState extends ConsumerState<OrderLinkScreen> {
  OrderLinkFailure? _failure;

  /// The node being changed to, while that happens.
  String? _changingTo;

  @override
  void initState() {
    super.initState();
    _open();
  }

  /// Finds the order and goes where the link leads. [afterNodeChange]: the
  /// user just changed to the order's node, so a link that still points off
  /// the active node means the change did not take — asking again would
  /// loop.
  Future<void> _open({bool afterNodeChange = false}) async {
    final OrderLinkTarget target;
    try {
      target = await ref.read(orderLinkResolverProvider)(widget.link);
    } catch (e) {
      debugPrint('[order-link] lookup failed: $e');
      _fail(orderLinkFailureOf(e));
      return;
    }
    if (!mounted) return;
    if (!target.onActiveNode) {
      if (afterNodeChange) {
        _fail(OrderLinkFailure.nodeChangeFailed);
      } else {
        await _offerNodeChange(target);
      }
      return;
    }

    final role = await ref.read(tradeRoleLookupProvider)(target.order.id);
    if (!mounted) return;
    final destination = orderLinkDestination(
      target.order,
      participates: role != null,
    );
    if (destination == null) {
      _fail(OrderLinkFailure.unavailable);
      return;
    }
    // The take screen reads the order from the live book.
    if (role == null) await _untilInBook(target.order.id);
    if (!mounted) return;
    context.pushReplacement(destination);
  }

  /// How long the order may take to reach the live book before the take
  /// screen opens anyway. The lookup filed it there, and the book publishes it
  /// within its coalescing window, a few hundred milliseconds.
  static const _bookWait = Duration(seconds: 2);

  /// Waits for [orderId] in the live book, so the take screen opens on the
  /// order rather than on "not found" until the book catches up.
  Future<void> _untilInBook(String orderId) async {
    final arrived = Completer<void>();
    final subscription = ref.listenManual<OrderItem?>(
      orderByIdProvider(orderId),
      (_, order) {
        if (order != null && !arrived.isCompleted) arrived.complete();
      },
      fireImmediately: true,
    );
    try {
      await arrived.future.timeout(_bookWait, onTimeout: () {});
    } finally {
      subscription.close();
    }
  }

  /// The order lives on another node: change to it, if the user says so.
  Future<void> _offerNodeChange(OrderLinkTarget target) async {
    final nodes = await _registry();
    if (!mounted) return;
    final inProgress = await ref.read(tradeInProgressLookupProvider)();
    if (!mounted) return;
    if (inProgress == null) {
      _fail(OrderLinkFailure.tradesUnreadable);
      return;
    }

    final nodeName = nodeNameOf(target.nodePubkey, nodes);
    final confirmed = await showOrderLinkNodeDialog(
      context,
      nodeName: nodeName,
      isKnown: nodes.any((node) => node.pubkey == target.nodePubkey),
      tradeLeftOn:
          inProgress ? nodeNameOf(ref.read(mostroPubkeyProvider), nodes) : null,
    );
    if (!mounted) return;
    if (!confirmed) {
      _leave();
      return;
    }

    setState(() => _changingTo = nodeName);
    try {
      // The Settings path: persists the choice and re-targets every
      // subscription before it returns.
      await ref
          .read(mostroNodesProvider.notifier)
          .selectNode(target.nodePubkey);
    } catch (e) {
      debugPrint('[order-link] node change failed: $e');
      _fail(OrderLinkFailure.nodeChangeFailed);
      return;
    }
    if (!mounted) return;
    showOrderDetailSnackBar(
      context,
      AppLocalizations.of(context).nodeSwitchedSuccess(nodeName),
    );
    setState(() => _changingTo = null);
    await _open(afterNodeChange: true);
  }

  /// The node registry, or none when it cannot be read: every node then reads
  /// as unknown, which errs on the side of the warning.
  Future<List<MostroNodeEntry>> _registry() async {
    try {
      return await ref.read(mostroNodesProvider.future);
    } catch (e) {
      debugPrint('[order-link] node registry unavailable: $e');
      return const [];
    }
  }

  void _fail(OrderLinkFailure failure) {
    if (!mounted) return;
    setState(() {
      _failure = failure;
      _changingTo = null;
    });
  }

  void _retry() {
    setState(() => _failure = null);
    _open();
  }

  void _leave() => context.canPop() ? context.pop() : context.go(AppRoute.home);

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final failure = _failure;

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.orderLinkTitle,
        onBack: _leave,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child:
              failure == null
                  ? _Waiting(
                    text:
                        _changingTo == null
                            ? l10n.orderLinkLooking
                            : l10n.orderLinkSwitching(_changingTo!),
                  )
                  : _Failed(
                    failure: failure,
                    onRetry: _canRetry(failure) ? _retry : null,
                  ),
        ),
      ),
    );
  }

  /// Whether trying again may change the answer: a missing relay or a failed
  /// node change may, a broken link or a gone order never.
  static bool _canRetry(OrderLinkFailure failure) => switch (failure) {
    OrderLinkFailure.invalidLink || OrderLinkFailure.unavailable => false,
    OrderLinkFailure.notFound ||
    OrderLinkFailure.nodeChangeFailed ||
    OrderLinkFailure.tradesUnreadable => true,
  };
}

/// The screen while it works: a spinner and what it is doing.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: book.lime),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: book.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Why the link led nowhere: the mascot, a title, the reason, and a retry
/// when trying again may help.
class _Failed extends StatelessWidget {
  const _Failed({required this.failure, required this.onRetry});

  final OrderLinkFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final (mood, title, reason) = switch (failure) {
      OrderLinkFailure.invalidLink => (
        MostroMood.refused,
        l10n.orderLinkInvalidTitle,
        l10n.orderLinkInvalidBody,
      ),
      OrderLinkFailure.notFound => (
        MostroMood.asleep,
        l10n.orderNotFoundTitle,
        l10n.orderLinkNotFoundBody,
      ),
      OrderLinkFailure.unavailable => (
        MostroMood.canceled,
        l10n.orderLinkUnavailableTitle,
        l10n.orderLinkUnavailableBody,
      ),
      OrderLinkFailure.nodeChangeFailed => (
        MostroMood.refused,
        l10n.orderLinkFailedTitle,
        l10n.errorSwitchingNode,
      ),
      OrderLinkFailure.tradesUnreadable => (
        MostroMood.refused,
        l10n.orderLinkFailedTitle,
        l10n.nodeTradesCheckFailed,
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: MostroMascot(height: 64, mood: mood)),
        const SizedBox(height: 16),
        // Replaces the spinner while the user watches (DS-A11Y-2).
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: book.textBody,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          reason,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: book.textSecondary,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: book.limeText),
            child: Text(l10n.retry),
          ),
        ],
      ],
    );
  }
}
