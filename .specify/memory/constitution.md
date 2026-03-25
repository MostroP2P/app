<!--
  Sync Impact Report
  ==================
  Version change: 0.0.0 → 1.0.0 (initial ratification)
  Modified principles: N/A (first version)
  Added sections:
    - Core Principles (6 principles)
    - Technical Boundaries
    - Quality Standards
    - Governance
  Removed sections: None
  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ no conflicts
    - .specify/templates/spec-template.md ✅ no conflicts
    - .specify/templates/tasks-template.md ✅ no conflicts
  Follow-up TODOs: None
-->

# Mostro Mobile v2 Constitution

## Core Principles

### I. Rust Core, Flutter Shell

- ALL Nostr logic, cryptographic operations, and protocol handling
  MUST live in Rust (via nostr-sdk).
- Flutter handles ONLY UI rendering and platform integration.
- Zero cryptographic operations in Dart — no exceptions.
- `flutter_rust_bridge` is the sole bridge between Rust and Dart.
- Network calls to relays MUST originate from Rust, never from
  Flutter/Dart directly.

### II. Privacy by Design

- All Mostro communication MUST use NIP-59 Gift Wrap encryption.
- No analytics, telemetry, or tracking of any kind.
- Cryptographic keys MUST never leave the device unencrypted.
- Ephemeral trade data MUST be cleared after trade completion.
- The application MUST NOT phone home to any non-relay server.

### III. Protocol Compliance

- The client MUST strictly adhere to the Mostro protocol
  specification.
- The client MUST be compatible with any conforming Mostro daemon,
  not only a specific instance.
- Protocol version differences MUST be handled gracefully with
  clear user feedback when incompatibilities arise.

### IV. Offline-First Architecture

- The local database (SQLite or equivalent) is the source of truth.
- The client MUST sync with relays when connectivity is available.
- Outgoing messages MUST be queued when offline and sent upon
  reconnection.
- User data MUST never be lost due to connectivity issues.

### V. Multi-Platform from Day One

- The client MUST target mobile (iOS, Android), web (PWA), and
  desktop (macOS, Windows, Linux) from the start.
- Layouts MUST be responsive, adapting to mobile, tablet, and
  desktop screen sizes.
- Platform-specific features (camera, notifications, QR scanning)
  MUST degrade gracefully with fallbacks on unsupported platforms.
- Code MUST NOT assume a single screen size or input method.

### VI. Simplicity Over Features

- One screen, one purpose — no multipurpose views.
- Progressive disclosure: show complexity only when the user needs
  it.
- A clear trade progress indicator MUST be visible at all times
  during an active trade.
- Sensible defaults with minimal required configuration.
- Fast startup and responsive UI are non-negotiable.

## Technical Boundaries

### Must Use

- **Flutter** — UI framework, multi-platform rendering
- **Rust via flutter_rust_bridge** — all core logic
- **nostr-sdk 0.44+** — Nostr protocol implementation
- **NIP-59** — encryption for all Mostro messages
- **SQLite or equivalent** — local persistence
- **Platform-aware components** — camera/QR with web fallback
- **Responsive layout system** — mobile, tablet, desktop

### Must Not

- Implement cryptographic operations in Dart
- Store unencrypted keys on disk or in memory beyond immediate use
- Make network calls from Flutter/Dart directly
- Depend on a specific Mostro daemon instance
- Phone home to any non-relay server
- Assume a single screen size or platform

## Quality Standards

- `cargo clippy -- -D warnings` MUST pass with zero warnings
- `cargo test` MUST pass — all Rust tests green
- `flutter analyze` MUST report zero issues
- `flutter test` MUST pass — all Flutter tests green
- All public Rust API functions MUST be documented
- UI MUST be tested on mobile, tablet, and desktop breakpoints

### Non-Goals (v2.0 Scope)

These are explicitly out of scope for the initial release:

- Fiat payment integration
- Built-in Lightning wallet (use NWC or external wallet)

## Governance

- This constitution supersedes all other development practices
  and conventions for the Mostro Mobile v2 project.
- All pull requests and code reviews MUST verify compliance with
  these principles before merge.
- Amendments to this constitution require:
  1. A written proposal documenting the change and rationale.
  2. Review and approval by project maintainers.
  3. A migration plan if existing code is affected.
  4. Version bump following semantic versioning (MAJOR for
     principle removals/redefinitions, MINOR for additions,
     PATCH for clarifications).
- Complexity beyond what these principles allow MUST be explicitly
  justified and documented.

**Version**: 1.0.0 | **Ratified**: 2026-03-22 | **Last Amended**: 2026-03-25
