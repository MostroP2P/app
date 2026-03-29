# appv2 Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-29

## Active Technologies
- Rust stable 1.94+ (core logic); Dart 3.x / Flutter 3.x (UI) + nostr-sdk 0.44+, mostro-core, flutter_rust_bridge 2.x, Riverpod (state management), go_router (navigation), sqlx (SQLite), indexed_db_futures (web), bip32/bip39 (key derivation), chacha20poly1305 (file encryption) (001-mostro-p2p-client)
- SQLite via sqlx (native platforms), IndexedDB (web) (001-mostro-p2p-client)
- Rust stable (latest, currently 1.94+) (core logic); Dart 3.x / Flutter 3.x (UI) + nostr-sdk 0.44+, mostro-core, flutter_rust_bridge 2.x, Riverpod (state management), go_router (navigation), sqlx (SQLite), indexed_db_futures (web), bip32/bip39 (key derivation), chacha20poly1305 (file encryption) (001-mostro-p2p-client)
- Rust stable 1.94+ (core); Dart 3.x / Flutter 3.x (UI shell) (004-mostro-p2p-client)
- Sembast (Dart, all platforms) for UI-layer state; SQLite via `sqlx` (Rust, native) / IndexedDB via `indexed_db_futures` (Rust, web) for protocol-layer persistence. Feature-gated via `#[cfg(target_arch = "wasm32")]`. (004-mostro-p2p-client)

## Project Structure

```text
lib/
rust/
rust_builder/
test/
specs/
```

## Commands

cargo test && cargo clippy

## Code Style

Rust stable 1.94+ (core logic); Dart 3.x / Flutter 3.x (UI): Follow standard conventions

## Recent Changes
- 004-mostro-p2p-client: Added Rust stable 1.94+ (core); Dart 3.x / Flutter 3.x (UI shell)
- 001-mostro-p2p-client: Added Rust stable (latest, currently 1.94+) (core logic); Dart 3.x / Flutter 3.x (UI) + nostr-sdk 0.44+, mostro-core, flutter_rust_bridge 2.x, Riverpod (state management), go_router (navigation), sqlx (SQLite), indexed_db_futures (web), bip32/bip39 (key derivation), chacha20poly1305 (file encryption)
- 001-mostro-p2p-client: Added Rust stable 1.94+ (core logic); Dart 3.x / Flutter 3.x (UI) + nostr-sdk 0.44+, mostro-core, flutter_rust_bridge 2.x, Riverpod (state management), go_router (navigation), sqlx (SQLite), indexed_db_futures (web), bip32/bip39 (key derivation), chacha20poly1305 (file encryption)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
