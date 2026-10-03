/// A 64-character hex public key as an `npub` (NIP-19 bech32), for showing
/// the user which identity they confirm. Returns null for anything else.
String? hexToNpub(String hex) {
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) return null;
  final bytes = [
    for (var i = 0; i < 64; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  // Regroup 8-bit bytes into 5-bit words.
  final words = <int>[];
  var acc = 0, bits = 0;
  for (final b in bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      words.add((acc >> bits) & 31);
    }
  }
  if (bits > 0) words.add((acc << (5 - bits)) & 31);
  const hrp = 'npub';
  const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  int polymod(List<int> values) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final v in values) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (var i = 0; i < 5; i++) {
        if ((top >> i) & 1 == 1) chk ^= gen[i];
      }
    }
    return chk;
  }

  final expanded = [
    for (final c in hrp.codeUnits) c >> 5,
    0,
    for (final c in hrp.codeUnits) c & 31,
  ];
  final mod = polymod([...expanded, ...words, 0, 0, 0, 0, 0, 0]) ^ 1;
  final checksum = [for (var i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
  return '${hrp}1${[...words, ...checksum].map((w) => charset[w]).join()}';
}
