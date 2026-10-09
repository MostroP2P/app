/// The one countdown of the app (DS-CMP-21): how a time left is printed, how
/// often it repaints and how urgent it reads. Pure Dart, so every rule is
/// unit-testable; the widgets only render what these return.
library;

const _hour = Duration(hours: 1);
const _fiveMinutes = Duration(minutes: 5);
const _oneMinute = Duration(minutes: 1);

/// A window this short (an invoice step) turns urgent at one minute instead
/// of five: five minutes would be a third of it.
const kShortCountdownWindow = Duration(minutes: 15);

/// `12:40` (mm:ss) under an hour; from an hour up, [hours] builds the
/// localized form (`1 h 05`) from the hour count and the two-digit minutes.
/// Never `23:12` for hours, which reads as minutes and seconds.
String formatCountdown(
  Duration remaining, {
  required String Function(String hours, String minutes) hours,
}) {
  final d = remaining.isNegative ? Duration.zero : remaining;
  String two(int n) => n.toString().padLeft(2, '0');
  if (d >= _hour) return hours('${d.inHours}', two(d.inMinutes % 60));
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

/// How long until the displayed value changes: every second up to an hour;
/// above it, one second past the seconds into the current minute — the
/// display floors to whole minutes, so `2:00:15` still reads `2 h 00` after
/// 15 s and turns `1 h 59` one second later (and `2:00:00` after 1 s).
Duration countdownTick(Duration remaining) {
  if (remaining <= _hour) return const Duration(seconds: 1);
  return Duration(seconds: remaining.inSeconds % 60 + 1);
}

/// How urgent a countdown reads, which sets its color.
enum CountdownTone {
  /// An hour or more left: lime on the user's turn, amber while they wait.
  calm,

  /// Under an hour: amber.
  warning,

  /// Under five minutes, or under one in a [kShortCountdownWindow]: coral.
  urgent,
}

/// The tone of [remaining] in a countdown whose whole run is [window], or
/// unknown when null (then it turns urgent at five minutes).
CountdownTone countdownTone(Duration remaining, {Duration? window}) {
  final short = window != null && window <= kShortCountdownWindow;
  if (remaining < (short ? _oneMinute : _fiveMinutes)) {
    return CountdownTone.urgent;
  }
  if (remaining < _hour) return CountdownTone.warning;
  return CountdownTone.calm;
}
