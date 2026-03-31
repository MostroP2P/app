import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/app.dart';
import 'package:mostro/src/rust/frb_generated.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // Initialize the Nostr relay pool with default relays (from config.rs).
  // This must happen before any Nostr/order API calls.
  await nostr_api.initialize(relays: null);
  debugPrint('[main] Nostr relay pool initialized');
  runApp(const ProviderScope(child: MostroApp()));
}
