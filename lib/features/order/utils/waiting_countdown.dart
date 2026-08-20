import 'package:mostro/src/rust/api/types.dart';

/// The countdown target for a trade, resolved for #270.
///
/// [deadlineEpochSeconds] is the unix-second instant the countdown runs to;
/// [totalWindowSeconds] sizes the progress ring (the full window).
typedef CountdownDeadline = ({int deadlineEpochSeconds, int totalWindowSeconds});

/// Last-resort waiting-state window (seconds) when the node's instance event
/// omits `expiration_seconds`. Matches the Mostro daemon default (15 min).
const int kWaitingCountdownFallbackSeconds = 900;

/// Chooses the countdown target for a trade (#270):
///
/// - **Pending**: counts to the 24 h pending-order expiry ([pendingExpiresAt]).
/// - **Waiting states** (buyer-invoice / payment): counts to the state-change
///   deadline — the trade's [timeoutAtEpoch] when the daemon persisted one,
///   else `now + expiration_seconds` (falling back to
///   [kWaitingCountdownFallbackSeconds] when the node omits it).
/// - **Any other state**: no countdown (null).
///
/// The UI only informs — the daemon stays the authority on expiry, so callers
/// never cancel locally at zero.
CountdownDeadline? waitingCountdownDeadline({
  required OrderStatus? status,
  DateTime? pendingExpiresAt,
  int? timeoutAtEpoch,
  int? expirationSeconds,
}) {
  final window = expirationSeconds ?? kWaitingCountdownFallbackSeconds;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  switch (status) {
    case OrderStatus.pending:
      if (pendingExpiresAt == null) return null;
      final deadline = pendingExpiresAt.millisecondsSinceEpoch ~/ 1000;
      final total = deadline - now;
      return (
        deadlineEpochSeconds: deadline,
        totalWindowSeconds: total > 0 ? total : window,
      );
    case OrderStatus.waitingBuyerInvoice:
    case OrderStatus.waitingPayment:
      if (timeoutAtEpoch != null) {
        return (deadlineEpochSeconds: timeoutAtEpoch, totalWindowSeconds: window);
      }
      return (deadlineEpochSeconds: now + window, totalWindowSeconds: window);
    default:
      return null;
  }
}
