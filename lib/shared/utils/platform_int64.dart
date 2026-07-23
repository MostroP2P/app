import 'package:flutter/foundation.dart';

/// Helpers for flutter_rust_bridge's `PlatformInt64`.
///
/// Rust `u64`/`i64` fields cross the bridge as `PlatformInt64`, which is a
/// plain `int` on native but a `BigInt` on web (dart2js cannot represent a
/// 64-bit integer as `int`). Dart code that assumes `int` compiles on native
/// and fails to compile — or misbehaves — on web, so route every conversion
/// through these two functions instead of hand-rolling the check.

/// Converts a `PlatformInt64` value to a plain Dart `int`.
///
/// The `else` branch must cast to `int`: without it the expression's static
/// type is the `int`/`BigInt` least upper bound (`Object`), which does not
/// compile where an `int` is expected.
int platformInt64ToInt(dynamic value) =>
    value is BigInt ? value.toInt() : value as int;

/// Converts a Dart `int` to the `PlatformInt64` representation for the current
/// platform: `int` on native, `BigInt` on web. Returns `dynamic` so the result
/// can be passed straight to a bridge parameter typed `PlatformInt64` on either
/// platform without a static-type error.
dynamic intToPlatformInt64(int value) => kIsWeb ? BigInt.from(value) : value;
