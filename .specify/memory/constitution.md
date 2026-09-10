<!--
  Sync Impact Report
  ==================
  Version change: 1.1.0 → 1.1.1 (PATCH — clarification, no principle added,
  removed or redefined)
  Modified principles:
    - II. Privacy by Design — the chat transport it prescribed (NIP-59 gift
      wrap, Kind 1059) was replaced by the Kind 14 chat envelope in issue #246,
      in both the peer and the dispute-solver direction. The principle itself
      (everything end-to-end encrypted) is unchanged; only the mechanism it
      names is corrected to what the code actually speaks.
  Modified sections:
    - Technical Boundaries → Must Use — same correction, plus nostr-sdk 0.44+
      → 0.45+ (PR #376).
  Added/Removed sections: None
  Templates requiring updates: None — no template references the chat transport.
  Downstream docs synced with this amendment (they still required kind 1059 for
  chat, which would have left two mutually exclusive requirements in the repo):
    - CONTRIBUTING.md "Protocol / Transport Changes"
    - .specify/PROTOCOL.md, .specify/ARCHITECTURE.md, .specify/README.md
    - specs/004: plan.md, data-model.md, contracts/orders.md, and the
      superseding banners on research.md and tasks.md
    - specs/005: a scope note on spec.md (User Story 2, FR-004), plan.md,
      tasks.md and research.md — 005 deliberately migrated the daemon channel
      only, so its chat carve-out is marked as a record of that scope rather
      than rewritten
  The live chat contract is specs/004-mostro-p2p-client/contracts/messages.md.
  .specify/v1-reference/ is untouched on purpose: it is descriptive of v1, which
  did use gift wrap.
  Follow-up TODOs: None

  Earlier: 1.0.0 → 1.1.0 added the Core Principles (7, incl. VII. V1 User
  Experience), Technical Boundaries, Quality Standards and Governance
  sections; the three .specify/templates/*.md were checked, no conflicts.
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

- All Mostro communication MUST be end-to-end encrypted, and this client speaks protocol v2 only: NIP-44 (signed Kind 14) for messages to the Mostro daemon, and the chat envelope (Kind 14 signed with `K_sign`, carrying a NIP-44-encrypted inner Kind 1 signed by the trade key) for peer and dispute chat. (Everything was NIP-59 gift wrap before transport v2; the daemon channel migrated first, and peer/dispute chat followed in issue #246 to close a gift-wrap flood attack. Nothing in this client reads or writes Kind 1059 any more.)
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


### VII. V1 User Experience is Non-Negotiable

- `.specify/v1-reference/V1_FLOW_GUIDE.md` is the **single source of
  truth** for every screen, interaction, and user-facing behavior in
  the app.
- When running `/speckit.specify`, `/speckit.plan`, or `/speckit.tasks`,
  the agent MUST start from `V1_FLOW_GUIDE.md` and replicate it
  exactly — no deviations, no improvisation.
- Every section of `V1_FLOW_GUIDE.md` contains links to detailed
  spec files inside `.specify/v1-reference/`. Those files provide the
  full implementation detail for each screen and MUST be consulted
  before generating tasks for that screen.
- The design system (`V1_FLOW_GUIDE.md` → `DESIGN_SYSTEM.md`) governs
  how screens look. The flow guide governs what screens exist and what
  they do. Both must be followed, in that order of priority:
  **flow first, design second**.

## Technical Boundaries

### Must Use

- **App Bundle ID:** `foundation.mostro.app` (iOS, Android, web, desktop)
- **Flutter** — UI framework, multi-platform rendering
- **Rust via flutter_rust_bridge** — all core logic
- **nostr-sdk 0.45+** — Nostr protocol implementation
- **NIP-44** — daemon messages use NIP-44 (Kind 14); peer/dispute chat uses the Kind 14 chat envelope. Was all-NIP-59 gift wrap before transport v2 and issue #246; Kind 1059 is gone from both directions.
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

**Version**: 1.1.1 | **Ratified**: 2026-03-22 | **Last Amended**: 2026-09-03
