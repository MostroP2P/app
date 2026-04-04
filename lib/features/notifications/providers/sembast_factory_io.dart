// IO implementation — re-exports databaseFactoryIo from sembast and provides
// a databaseFactoryWeb stub so the conditional import resolves on native.
export 'package:sembast/sembast_io.dart' show databaseFactoryIo;
export 'package:mostro/features/notifications/providers/sembast_factory_stub.dart'
    show databaseFactoryWeb;
