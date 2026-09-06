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
/// - **Waiting states** (buyer-invoice / payment): counts to the trade's
///   [timeoutAtEpoch] when one is present, else **no countdown** (null).
///   There is deliberately no `startedAt`-based fallback: `startedAt` is the
///   order-creation time, so for a maker whose order sat in the book before
///   being taken it yields a deadline already in the past — a countdown born at
///   zero. "No anchor, no countdown" is correct until the daemon stamps
///   `timeout_at` on waiting-state entry from the node's `expiration_seconds`
///   (a follow-up daemon change; #306 review). Today `timeout_at` is a fixed
///   900 written client-side on take, not persisted by the daemon.
/// - **Any other state**: no countdown (null).
///
/// The helper is pure — no clock read, no cache — so its result is stable across
/// the per-second rebuilds that drive the ticking UI.
///
/// The UI only informs — the daemon stays the authority on expiry, so callers
/// never cancel locally at zero.
CountdownDeadline? waitingCountdownDeadline({
  required OrderStatus? status,
  DateTime? pendingExpiresAt,
  int? pendingCreatedAtEpoch,
  int? timeoutAtEpoch,
  int? expirationSeconds,
}) {
  final window = expirationSeconds ?? kWaitingCountdownFallbackSeconds;
  switch (status) {
    case OrderStatus.pending:
      if (pendingExpiresAt == null) return null;
      final deadline = pendingExpiresAt.millisecondsSinceEpoch ~/ 1000;
      // The ring spans the whole pending window (creation -> 24 h expiry), not
      // the waiting window, so the progress ring is meaningful (#306 review).
      final total =
          (pendingCreatedAtEpoch != null && deadline > pendingCreatedAtEpoch)
              ? deadline - pendingCreatedAtEpoch
              : window;
      return (deadlineEpochSeconds: deadline, totalWindowSeconds: total);
    case OrderStatus.waitingBuyerInvoice:
    case OrderStatus.waitingPayment:
      // Only count down when timeout_at is present. The startedAt fallback
      // produced a past deadline for makers (startedAt is creation time), so
      // "no anchor, no countdown" until the daemon stamps timeout_at properly
      // (#306 review).
      if (timeoutAtEpoch != null) {
        return (deadlineEpochSeconds: timeoutAtEpoch, totalWindowSeconds: window);
      }
      return null;
    default:
      return null;
  }
}
