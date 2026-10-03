import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/reputation/lnp2pbot.dart';

void main() {
  test('the export link carries the identity in 43 base64url characters', () {
    const identity =
        'ab1db593a4d1196eb07335fdc702a314712ed29c631ceaebd84708a17d3bc2f7';
    final uri = lnp2pbotExportUri(identity)!;
    expect(uri.toString(), startsWith('https://t.me/lnp2pbot?start=rep_'));
    final start = uri.queryParameters['start']!;
    expect(start.length, lessThanOrEqualTo(64));
    final encoded = start.substring(4);
    expect(encoded, hasLength(43));
    final bytes = base64Url.decode('$encoded=');
    expect(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      identity,
    );
    expect(lnp2pbotExportUri('npub1nope'), isNull);
  });

  test('finds the attestation inside pasted text', () {
    final vectors = jsonDecode(
      File('rust/tests/fixtures/reputation_v1.json').readAsStringSync(),
    );
    final json = vectors['attestation']['valid']['json'] as String;
    expect(extractAttestationJson(json), json);
    expect(extractAttestationJson('from the bot:\n$json\n'), json);
    expect(extractAttestationJson('nothing'), isNull);
    expect(extractAttestationJson('{broken'), isNull);
  });
}
