import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api.dart' as rust_api;

/// Provides the app version string from the Rust layer.
final appVersionProvider = FutureProvider<String>((ref) async {
  return rust_api.getAppVersion();
});

/// The commit this build was made from, passed as `--dart-define=GIT_COMMIT`;
/// empty when the build set none.
const appGitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: '');
