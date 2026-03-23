# Quickstart: Mostro Mobile v2

## Prerequisites

- **Flutter** 3.x+ with Dart 3.x+
- **Rust** stable (latest, currently 1.94+) (`rustup install stable`)
- **flutter_rust_bridge codegen**: `dart pub global activate flutter_rust_bridge`
- **WASM target** (for web): `rustup target add wasm32-unknown-unknown`
- **wasm-pack** (for web): `cargo install wasm-pack`
- **SQLite** development libraries (platform-dependent)
- **Xcode** (for iOS/macOS builds)
- **Android SDK/NDK** (for Android builds)

## Setup

```bash
# Clone the repository
git clone <repo-url> mostro-app
cd mostro-app

# Install Flutter dependencies
flutter pub get

# Generate flutter_rust_bridge bindings
flutter_rust_bridge_codegen generate

# Verify Rust builds
cd rust && cargo build && cargo test && cd ..

# Verify Flutter builds
flutter analyze
flutter test
```

## Running

### Mobile (iOS)
```bash
flutter run -d ios
```

### Mobile (Android)
```bash
flutter run -d android
```

### Desktop (macOS)
```bash
flutter run -d macos
```

### Desktop (Windows)
```bash
flutter run -d windows
```

### Desktop (Linux)
```bash
flutter run -d linux
```

### Web
```bash
flutter run -d chrome
```

Note: Web builds require wasm-pack to compile Rust to WASM. The build
system handles this automatically via flutter_rust_bridge's web support.

## Quality Checks

```bash
# Rust linting (must pass with zero warnings)
cd rust && cargo clippy -- -D warnings && cd ..

# Rust tests
cd rust && cargo test && cd ..

# Flutter analysis (must report zero issues)
flutter analyze

# Flutter tests
flutter test
```

## Project Layout

```
lib/           → Flutter UI (screens, widgets, providers, layouts)
rust/          → Rust core (API, protocol, storage, platform)
rust_builder/  → Cargokit build integration
test/          → Flutter tests
rust/tests/    → Rust tests
specs/         → Feature specifications and plans
```

## Key Architecture Rules

1. **All crypto, protocol, and network logic in Rust** — Flutter is UI only.
2. **NIP-59 Gift Wrap** for all Mostro communication — no plaintext.
3. **Offline-first** — local DB is source of truth, queue when offline.
4. **One active trade** at a time (v2.0 scope).
5. **Responsive layouts** — test on mobile (<600px), tablet (600-1200px),
   and desktop (>1200px).

## Development Workflow

1. Define/modify Rust API in `rust/src/api/`
2. Run `flutter_rust_bridge_codegen generate` to update Dart bindings
3. Implement Flutter UI against generated bindings
4. Run quality checks before committing
5. Test on at least one mobile and one desktop breakpoint
