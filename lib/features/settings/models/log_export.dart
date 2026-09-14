/// Redact common secrets and keys from a log string before sharing.
///
/// Patterns replaced:
/// - Authorization/Bearer tokens → `[REDACTED_AUTH]`
/// - Key-value secrets (token, apikey, secret, password, …) → `[REDACTED_SECRET]`
/// - Long hex strings ≥32 chars, npub/nsec Bech32 keys → `[REDACTED_KEY]`
///
/// Applied to both the tag and the message of every exported entry: a log
/// report goes to whoever is helping the user, and Rust's own scrubber runs
/// before the buffer, not before the share sheet.
String sanitizeForShare(String text) {
  // Authorization: Bearer <value>
  var out = text.replaceAllMapped(
    RegExp(r'(Authorization\s*:\s*Bearer\s+)\S+', caseSensitive: false),
    (m) => '${m[1]}[REDACTED_AUTH]',
  );
  // Key-value secrets: token=, apikey=, secret=, password=, api_key= (: or = separator)
  out = out.replaceAllMapped(
    RegExp(
      // A quoted value is consumed whole, spaces included; `\S+` alone left
      // everything after the first space in the shared report.
      r'''((?:token|apikey|api_key|secret|password)\s*[=:]\s*)(?:"[^"]*"|'[^']*'|\S+)''',
      caseSensitive: false,
    ),
    (m) => '${m[1]}[REDACTED_SECRET]',
  );
  // Long hex strings (≥32 hex chars) — covers private keys and trade IDs
  out = out.replaceAll(RegExp(r'[0-9a-fA-F]{32,}'), '[REDACTED_KEY]');
  // npub / nsec Bech32 keys
  out = out.replaceAll(
    RegExp(r'n(?:pub|sec)1[02-9ac-hj-np-z]{6,}'),
    '[REDACTED_KEY]',
  );
  return out;
}

/// `14:32:07` for an entry from today, `2026-09-11 14:32:07` for an older one.
String formatLogTimestamp(int unixSeconds, {DateTime? now}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
  final today = now ?? DateTime.now();
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  final time = '$h:$m:$s';
  final sameDay =
      dt.year == today.year && dt.month == today.month && dt.day == today.day;
  if (sameDay) return time;
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$mo-$d $time';
}
