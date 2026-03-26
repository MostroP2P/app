import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'src/rust/api/identity.dart' as rust_identity;
import 'src/rust/api/nostr.dart' as rust_nostr;
import 'src/rust/frb_generated.dart';

const _masterKeyStorageKey = 'mostro_master_key';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the flutter_rust_bridge runtime.
  await RustLib.init();

  // Open (or create) the SQLite database.
  // On web this path is not used (IndexedDB, Phase 4).
  if (!kIsWeb) {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/mostro.db';
    await rust_identity.initialize(dbPath: dbPath);

    // Warm-start: restore session from the persisted master key.
    const storage = FlutterSecureStorage();
    final masterKeyHex = await storage.read(key: _masterKeyStorageKey);
    if (masterKeyHex != null) {
      final unlocked = await rust_identity.unlockWithMasterKey(
          masterKeyHex: masterKeyHex);
      if (unlocked) {
        // Bootstrap relay pool in the background — non-fatal if it fails.
        rust_nostr.initializeNostr(relayUrls: null).ignore();
      }
    }
  }

  runApp(const ProviderScope(child: MostroApp()));
}
