// Production entry point.
//
// Startup lives in `lib/core/app_bootstrap.dart` so the Mortsom
// test-environment entry point (`lib/main_mortsom.dart`) starts the app the
// same way, differing only in the relay seed it passes. This entry point
// never arms `TestEnvironment`.

import 'package:mostro/core/app_bootstrap.dart';

Future<void> main() => bootstrapAndRun();
