/// Where the app keeps its own persistent files (SQLite / Sembast databases).
///
/// This is deliberately NOT `getApplicationDocumentsDirectory()`: on Linux that
/// resolves to the user's visible Documents folder (`XDG_DOCUMENTS_DIR`), so the
/// identity, trade history and outbox lived one spring-clean away from deletion.
/// Per the XDG Base Directory spec, app state belongs in `$XDG_DATA_HOME`
/// (default `~/.local/share`), which is what this resolves to on Linux.
///
/// Native-only — the web build gets `app_data_dir_web.dart` through a
/// conditional import (Sembast on web is keyed by name, not by path).
library;

import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Directory name used under the resolved data root. Kept short and stable:
/// renaming it strands every existing installation's database.
const _appDirName = 'mostro';

/// Resolves the Linux data directory from [env], per the XDG Base Directory
/// spec: `$XDG_DATA_HOME/mostro`, falling back to `$HOME/.local/share/mostro`
/// when `XDG_DATA_HOME` is unset, empty, or relative (the spec says a relative
/// value must be ignored). Returns `null` when neither variable is usable, so
/// the caller can fall back to path_provider instead of guessing.
/// Uses `p.posix` rather than the ambient path style on purpose: these are
/// Linux paths, and they must not pick up Windows separators when this runs on
/// another host (the analyzer, or the test suite on a developer's machine).
String? resolveLinuxDataDir(Map<String, String> env) {
  final xdgDataHome = env['XDG_DATA_HOME'];
  if (xdgDataHome != null &&
      xdgDataHome.isNotEmpty &&
      p.posix.isAbsolute(xdgDataHome)) {
    return p.posix.join(xdgDataHome, _appDirName);
  }

  final home = env['HOME'];
  if (home != null && home.isNotEmpty && p.posix.isAbsolute(home)) {
    return p.posix.join(home, '.local', 'share', _appDirName);
  }

  return null;
}

/// Absolute path of the app's data directory, created if it does not exist.
///
/// Linux uses the XDG data dir; every other platform keeps
/// `getApplicationDocumentsDirectory()`, which is already app-private there
/// (Android/iOS sandbox). macOS and Windows desktop have the same
/// user-visible-folder problem and are left for their own change.
///
/// [env], [isLinux] and [documentsDirPath] exist only as test seams — they
/// default to the real platform, so callers pass nothing. They let a test drive
/// the Linux branch and observe the fallback on any host, without a filesystem
/// abstraction: an unwritable directory is provoked with a real path instead.
Future<String> appDataDirPath({
  Map<String, String>? env,
  bool? isLinux,
  Future<String> Function()? documentsDirPath,
}) async {
  if (isLinux ?? Platform.isLinux) {
    final resolved = resolveLinuxDataDir(env ?? Platform.environment);
    if (resolved != null) {
      try {
        await Directory(resolved).create(recursive: true);
        return resolved;
      } catch (e) {
        // An unwritable data dir is worth reporting, but not worth failing
        // startup over while a usable fallback exists.
        debugPrint('[storage] cannot create $resolved: $e — falling back');
      }
    } else {
      debugPrint('[storage] no usable XDG_DATA_HOME or HOME — falling back');
    }
  }

  return (documentsDirPath ?? _documentsDirPath)();
}

Future<String> _documentsDirPath() async =>
    (await getApplicationDocumentsDirectory()).path;
