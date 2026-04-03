// Web stub — path_provider is not available on web.
// Provides a no-op signature so conditional imports compile without errors.
// The implementation is never called: callers guard with kIsWeb before use.

class StubDirectory {
  final String path = '';
}

Future<StubDirectory> getApplicationDocumentsDirectory() async {
  throw UnsupportedError('getApplicationDocumentsDirectory is not supported on web');
}
