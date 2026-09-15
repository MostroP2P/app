import 'package:flutter/foundation.dart';

import 'package:mostro/src/rust/api/types.dart' show PushStatus;

/// What the line under 10d's master toggle says (docs/PUSH_NOTIFICATIONS.md
/// §9.1), resolved to copy by the screen.
enum PushStatusLineKind {
  /// The master toggle is off.
  off,

  /// Off locally, but the server has not confirmed every removal yet.
  cleanupPending,

  /// The operator's `403` for the active node is still in force.
  refused,

  /// On, but the device has not handed a token over yet.
  noToken,

  /// The last attempt failed and is being retried.
  unreachable,

  /// The server asked to slow down.
  rateLimited,

  /// The server holds the token for [PushStatusLine.count] trades.
  registered,

  /// On, nothing failing, and no open trade to register.
  idle,
}

@immutable
class PushStatusLine {
  const PushStatusLine(this.kind, {this.count = 0, this.lastSuccessAt});

  final PushStatusLineKind kind;

  /// Registered trade pubkeys; meaningful for [PushStatusLineKind.registered].
  final int count;

  /// When the server last accepted a registration.
  final DateTime? lastSuccessAt;

  /// Whether the line reports something the user may want to know is wrong.
  bool get isWarning => switch (kind) {
    PushStatusLineKind.refused ||
    PushStatusLineKind.cleanupPending ||
    PushStatusLineKind.unreachable ||
    PushStatusLineKind.rateLimited => true,
    _ => false,
  };
}

/// Reads a [PushStatus] into one line, most important fact first.
///
/// The refusal comes from `node_refused_until`, never from the
/// `PushNodeRefused` marker alone: the date is scoped to the active node,
/// while the marker may be a trade on a node the user switched away from.
/// No token is checked before the failure markers, so a device still waiting
/// for its token is not reported as a server problem.
PushStatusLine pushStatusLine(PushStatus status, {required DateTime now}) {
  if (!status.enabled) {
    return status.registered > 0
        ? PushStatusLine(
          PushStatusLineKind.cleanupPending,
          count: status.registered,
        )
        : const PushStatusLine(PushStatusLineKind.off);
  }
  final refusedUntil = status.nodeRefusedUntil;
  if (refusedUntil != null && _fromSecs(refusedUntil.toInt()).isAfter(now)) {
    return const PushStatusLine(PushStatusLineKind.refused);
  }
  if (!status.hasToken) {
    return const PushStatusLine(PushStatusLineKind.noToken);
  }
  switch (status.lastError) {
    case 'PushServerUnreachable' || 'PushBadRequest':
      return const PushStatusLine(PushStatusLineKind.unreachable);
    case 'PushRateLimited':
      return const PushStatusLine(PushStatusLineKind.rateLimited);
  }
  if (status.registered > 0) {
    final last = status.lastSuccessAt;
    return PushStatusLine(
      PushStatusLineKind.registered,
      count: status.registered,
      lastSuccessAt: last == null ? null : _fromSecs(last.toInt()),
    );
  }
  return const PushStatusLine(PushStatusLineKind.idle);
}

DateTime _fromSecs(int secs) =>
    DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
