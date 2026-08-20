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
///   else [waitingSinceEpoch] + `expiration_seconds` (the state-change message
///   timestamp plus the window, per the v1 timeout contract), falling back to
///   [kWaitingCountdownFallbackSeconds] for the window when the node omits it.
/// - **Any other state**: no countdown (null).
///
/// The fallback is anchored on [waitingSinceEpoch] (a fixed timestamp such as
/// `TradeInfo.startedAt`) rather than the current time, so the deadline is
/// stable across the per-second rebuilds that drive the ticking UI — otherwise
/// a `now + window` deadline would slide forward every second and never reach
/// zero. This keeps the helper pure (no clock read, no cache).
///
/// The UI only informs — the daemon stays the authority on expiry, so callers
/// never cancel locally at zero.
CountdownDeadline? waitingCountdownDeadline({
  required OrderStatus? status,
  DateTime? pendingExpiresAt,
  int? timeoutAtEpoch,
  int? waitingSinceEpoch,
  int? expirationSeconds,
}) {
  final window = expirationSeconds ?? kWaitingCountdownFallbackSeconds;
  switch (status) {
    case OrderStatus.pending:
      if (pendingExpiresAt == null) return null;
      final deadline = pendingExpiresAt.millisecondsSinceEpoch ~/ 1000;
      return (deadlineEpochSeconds: deadline, totalWindowSeconds: window);
    case OrderStatus.waitingBuyerInvoice:
    case OrderStatus.waitingPayment:
      if (timeoutAtEpoch != null) {
        return (deadlineEpochSeconds: timeoutAtEpoch, totalWindowSeconds: window);
      }
      if (waitingSinceEpoch != null) {
        return (
          deadlineEpochSeconds: waitingSinceEpoch + window,
          totalWindowSeconds: window,
        );
      }
      return null;
    default:
      return null;
  }
}
