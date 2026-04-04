// IO stub — provides databaseFactoryWeb as an alias for databaseFactoryMemory
// so conditional imports resolve on non-web platforms (never called at runtime
// because the kIsWeb guard directs IO to databaseFactoryIo instead).
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart' as mem;

DatabaseFactory get databaseFactoryWeb => mem.databaseFactoryMemory;
