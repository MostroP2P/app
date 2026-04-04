// Web implementation — re-exports databaseFactoryWeb from sembast_web and
// provides a databaseFactoryIo stub so both symbols resolve on web.
import 'package:sembast/sembast.dart';

export 'package:sembast_web/sembast_web.dart' show databaseFactoryWeb;

/// Stub — never called on web (guarded by kIsWeb check).
DatabaseFactory get databaseFactoryIo =>
    throw UnsupportedError('databaseFactoryIo is not available on web');
