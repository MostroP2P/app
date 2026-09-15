import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/models/push_status_line.dart';
import 'package:mostro/src/rust/api/types.dart' show PushStatus;

final _now = DateTime.utc(2026, 9, 14, 12);
int _secs(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

PushStatus _status({
  bool enabled = true,
  bool hasToken = true,
  int registered = 0,
  int wanted = 0,
  DateTime? lastSuccessAt,
  String? lastError,
  DateTime? nodeRefusedUntil,
}) => PushStatus(
  enabled: enabled,
  hasToken: hasToken,
  registered: registered,
  wanted: wanted,
  lastSuccessAt: lastSuccessAt == null ? null : _secs(lastSuccessAt),
  lastError: lastError,
  nodeRefusedUntil: nodeRefusedUntil == null ? null : _secs(nodeRefusedUntil),
);

void main() {
  group('pushStatusLine', () {
    test('off retains outstanding server cleanup as a warning', () {
      final line = pushStatusLine(
        _status(
          enabled: false,
          registered: 3,
          lastError: 'PushServerUnreachable',
        ),
        now: _now,
      );

      expect(line.kind, PushStatusLineKind.cleanupPending);
      expect(line.count, 3);
      expect(line.isWarning, isTrue);
    });

    test('off reports cleanup even after the device token was cleared', () {
      final line = pushStatusLine(
        _status(enabled: false, hasToken: false, registered: 1),
        now: _now,
      );
      expect(line.kind, PushStatusLineKind.cleanupPending);
    });

    test('off reports completed cleanup only when no registrations remain', () {
      final line = pushStatusLine(
        _status(enabled: false, lastError: 'PushServerUnreachable'),
        now: _now,
      );
      expect(line.kind, PushStatusLineKind.off);
      expect(line.isWarning, isFalse);
    });

    test('a refusal still in force reads as refused', () {
      final line = pushStatusLine(
        _status(
          registered: 1,
          nodeRefusedUntil: _now.add(const Duration(hours: 3)),
        ),
        now: _now,
      );

      expect(line.kind, PushStatusLineKind.refused);
    });

    test('a refusal that already expired is not shown', () {
      final line = pushStatusLine(
        _status(nodeRefusedUntil: _now.subtract(const Duration(minutes: 1))),
        now: _now,
      );

      expect(line.kind, isNot(PushStatusLineKind.refused));
    });

    test('no token yet says so instead of blaming the server', () {
      final line = pushStatusLine(
        _status(hasToken: false, lastError: 'PushServerUnreachable'),
        now: _now,
      );

      expect(line.kind, PushStatusLineKind.noToken);
    });

    test('maps the failure markers to their lines', () {
      expect(
        pushStatusLine(
          _status(lastError: 'PushServerUnreachable'),
          now: _now,
        ).kind,
        PushStatusLineKind.unreachable,
      );
      expect(
        pushStatusLine(_status(lastError: 'PushRateLimited'), now: _now).kind,
        PushStatusLineKind.rateLimited,
      );
      // A malformed request is a client bug; to the user it is one more
      // failed attempt that will be retried.
      expect(
        pushStatusLine(_status(lastError: 'PushBadRequest'), now: _now).kind,
        PushStatusLineKind.unreachable,
      );
    });

    test('a refusal marker for another node is not this node refused', () {
      // `node_refused_until` is scoped to the active node; the marker alone
      // may come from a trade on a node the user switched away from.
      final line = pushStatusLine(
        _status(registered: 2, lastError: 'PushNodeRefused'),
        now: _now,
      );

      expect(line.kind, PushStatusLineKind.registered);
      expect(line.count, 2);
    });

    test('registered carries the count and when it last succeeded', () {
      final at = _now.subtract(const Duration(hours: 3));
      final line = pushStatusLine(
        _status(registered: 2, wanted: 2, lastSuccessAt: at),
        now: _now,
      );

      expect(line.kind, PushStatusLineKind.registered);
      expect(line.count, 2);
      expect(line.lastSuccessAt, at);
    });

    test('nothing registered and nothing failing is idle', () {
      final line = pushStatusLine(_status(), now: _now);

      expect(line.kind, PushStatusLineKind.idle);
      expect(line.isWarning, isFalse);
    });

    test('only the failure lines are warnings', () {
      for (final kind in PushStatusLineKind.values) {
        final warning = switch (kind) {
          PushStatusLineKind.refused ||
          PushStatusLineKind.cleanupPending ||
          PushStatusLineKind.unreachable ||
          PushStatusLineKind.rateLimited => true,
          _ => false,
        };
        expect(PushStatusLine(kind).isWarning, warning, reason: kind.name);
      }
    });
  });
}
