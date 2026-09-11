/// Where the Rust core keeps its persistent store.
///
/// On native platforms `init_db` takes a file path inside the app data
/// directory. On the web there is no file system: the same argument names the
/// IndexedDB database, so the store must still be opened, only with a plain
/// name. Skipping it on the web left `db()` unset and every trade the Web
/// client created or took unpersisted, so "My trades" stayed empty.
const String webDatabaseName = 'mostro';

/// The `init_db` argument for this platform. `dataDir` is required off the web.
String databaseLocation({required bool isWeb, String? dataDir}) {
  if (isWeb) {
    return webDatabaseName;
  }
  final dir = dataDir;
  if (dir == null || dir.isEmpty) {
    throw ArgumentError.value(dataDir, 'dataDir', 'required off the web');
  }
  return '$dir/mostro.db';
}
