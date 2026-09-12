import 'package:mostro/src/rust/api/types.dart' show RelayInfo, RelayStatus;

/// How a settings row's right-hand value reads.
///
/// The redesign replaced the subtitle (which repeated the title) with the
/// setting's current value, so the value is the only thing on the row that can
/// warn: amber when something is unset or degraded, lime for a good state
/// worth pointing at, neutral otherwise.
enum SettingsValueTone { neutral, good, warn }

/// Live state of one relay row on 10b.
///
/// [slow] is unreachable today: `RelayInfo` carries no latency, and the
/// handoff says to drop the `Lento` label until the connection manager
/// publishes one. It exists so adding latency is a change to [relayHealth]
/// alone.
enum RelayHealth { connected, slow, offline }

/// A relay the user switched off is offline by choice — it has no connection
/// to report, and `Connecting` has not reached one yet either.
RelayHealth relayHealth(RelayInfo relay) {
  if (!relay.isActive) return RelayHealth.offline;
  return switch (relay.status) {
    RelayStatus.connected => RelayHealth.connected,
    RelayStatus.connecting ||
    RelayStatus.disconnected ||
    RelayStatus.error => RelayHealth.offline,
  };
}

/// `wss://relay.damus.io` → `relay.damus.io`.
///
/// The scheme is the same on every row and eats the width the host needs; the
/// full URL stays in the row's accessible label.
String relayDisplayUrl(String url) =>
    url.replaceFirst(RegExp(r'^wss?://', caseSensitive: false), '');

/// Connected / enabled tally behind `Relays → 3 de 4 conectados`.
///
/// [total] counts the relays the user has enabled, not every row: a relay
/// switched off on purpose is not a relay that failed, so counting it would
/// make a deliberate choice read as a fault.
class RelayTally {
  const RelayTally({required this.connected, required this.total});

  factory RelayTally.of(Iterable<RelayInfo> relays) {
    final enabled = relays.where((r) => r.isActive).toList();
    return RelayTally(
      connected:
          enabled.where((r) => relayHealth(r) == RelayHealth.connected).length,
      total: enabled.length,
    );
  }

  final int connected;
  final int total;

  bool get allConnected => total > 0 && connected == total;

  /// Fewer than two connected relays is the point at which the user can stop
  /// seeing new orders, which is what the relay summary card warns about.
  bool get isCritical => connected < 2;

  /// Lime only when every enabled relay is connected — that is the signal
  /// that justified moving the value to the right of the row.
  SettingsValueTone get tone =>
      allConnected ? SettingsValueTone.good : SettingsValueTone.warn;
}

/// Subsystem buckets behind the filter chips of 10e.
///
/// Rust tags an entry with its `log` target, which is a module path for
/// ordinary records and an explicit short tag for the bridge's own. Both are
/// matched on substrings, so a record whose module moves keeps its bucket, and
/// one that matches nothing is still reachable under `Todos`.
enum LogSubsystem { relays, orders, payments }

const _subsystemMarkers = <LogSubsystem, List<String>>{
  LogSubsystem.relays: ['relay', 'nostr', 'pool'],
  LogSubsystem.orders: ['order', 'daemon-msg', 'trade', 'dispute'],
  LogSubsystem.payments: ['nwc', 'invoice', 'payment', 'lightning', 'escrow'],
};

/// The bucket [tag] falls in, or null when it belongs to none.
LogSubsystem? logSubsystem(String tag) {
  final needle = tag.toLowerCase();
  for (final entry in _subsystemMarkers.entries) {
    if (entry.value.any(needle.contains)) return entry.key;
  }
  return null;
}
