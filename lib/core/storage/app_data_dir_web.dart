// Web stub — there is no filesystem path to hand out on web, where Sembast
// keys its database by name and the Rust core uses IndexedDB.
// Mirrors app_data_dir.dart's signature so conditional imports compile; the
// implementation is never called (callers guard with kIsWeb before use).
library;

Future<String> appDataDirPath() async {
  throw UnsupportedError('appDataDirPath is not supported on web');
}
