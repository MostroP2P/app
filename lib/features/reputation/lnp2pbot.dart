import 'dart:convert';

/// lnp2pBot issues reputation attestations through Telegram
/// (MostroP2P/protocol reputation_attestation.md, "Telegram hand-off").
const lnp2pbotUsername = 'lnp2pbot';

/// The key lnp2pBot signs attestations with (`REPUTATION_ISSUER_SK`, a key of
/// its own, not its Nostr key), as hex. A rebind authorisation for the bot
/// names it as its issuer: the bot refuses one signed for any other key
/// (lnp2pBot/bot#934). The bot announces a rotation through its own channels;
/// this value follows in a release.
const lnp2pbotIssuerKey =
    '000004ac730537f1cf7d91f4f584a498a530a0205d35e816ebbaf23aec61e459';

final _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// The link that asks lnp2pBot to attest the user's reputation for
/// [identityHex], or null for a value that is not a hex key. The identity
/// travels as 43 characters of unpadded base64url so the start parameter
/// fits Telegram's 64-character cap.
Uri? lnp2pbotExportUri(String identityHex) {
  final hex = identityHex.toLowerCase();
  if (!_hexKey.hasMatch(hex)) return null;
  final bytes = [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  final encoded = base64Url.encode(bytes).replaceAll('=', '');
  return Uri.parse('https://t.me/$lnp2pbotUsername?start=rep_$encoded');
}

/// The attestation event JSON inside pasted text: lnp2pBot sends it as a
/// message of its own, but a paste may carry surrounding text or whitespace.
/// Returns null when no JSON object is found.
String? extractAttestationJson(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  final candidate = text.substring(start, end + 1);
  try {
    return jsonDecode(candidate) is Map<String, dynamic> ? candidate : null;
  } on FormatException {
    return null;
  }
}
