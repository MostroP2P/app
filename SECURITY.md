# Security Policy

Mostro App is a non-custodial client that handles private keys, Lightning payments, and
end-to-end encrypted messages. Security reports are taken seriously and are handled through
coordinated disclosure.

## Reporting a Vulnerability

**Do not open a public issue, pull request, or discussion for a security vulnerability.**

Report it privately by email to <security@mostro.network>.

If you would like to encrypt your report, ask for a public key at that address before sending
details.

### What to Include

The more of this you can provide, the faster the issue can be triaged:

- A description of the vulnerability and its impact (what an attacker can achieve).
- Steps to reproduce, or a proof of concept.
- Affected platform (Android, iOS, Web, macOS, Windows, Linux) and app version or commit hash.
- Affected layer, if known: Flutter UI (`lib/`) or Rust core (`rust/`).
- Any relevant logs, with keys, mnemonics, and invoices redacted.

Please do not test against other users, live trades, or third-party relays and Mostro nodes
you do not operate. Use your own instance or testnet where possible.

## Response Process

- **Acknowledgement:** within 72 hours of the report.
- **Initial assessment:** severity and affected versions confirmed, normally within 7 days.
- **Fix:** critical issues are targeted for a fix within 30 days. Lower-severity issues are
  scheduled into the normal release cycle.
- **Updates:** you will be kept informed of progress until the issue is resolved.
- **Disclosure:** details are published only after a fix is available. Reporters are credited
  when the fix is announced, unless they ask to remain anonymous.

## Supported Versions

Security fixes are applied to the latest released version and to the `main` branch. Older
releases do not receive backports; the web client at <https://mostro.network/app/> always
serves the latest build of `main`.

## Scope

**In scope** — this repository, the Mostro client:

- The Rust core (`rust/`): Nostr protocol handling, cryptography, key derivation and storage,
  relay I/O, the Mostro state machine, Nostr Wallet Connect, and the offline message queue.
- The Flutter shell (`lib/`): UI, navigation, local state, and device/OS integration.
- Build and release tooling in this repository (`scripts/`, `.github/workflows/`), including
  the web bundle and its cross-origin isolation setup.

**Out of scope** — report these to their own projects:

- The Mostro daemon and its escrow logic: [MostroP2P/mostro](https://github.com/MostroP2P/mostro).
- Protocol types and the state machine shared with other clients:
  [mostro-core](https://github.com/MostroP2P/mostro-core).
- Third-party Nostr relays, Lightning wallets and NWC providers, and Mostro nodes operated by
  others.
- Upstream dependencies (`nostr-sdk`, Flutter, Rust crates) — report those upstream, though a
  heads-up is welcome if this app is exploitable through them.

The following are generally **not** treated as vulnerabilities:

- Automated scanner output with no demonstrated impact.
- Attacks that require a compromised, rooted, or jailbroken device, or physical access to an
  unlocked device.
- Social engineering, phishing, or a user voluntarily disclosing their seed phrase.
- Denial of service against public relays or a third party's infrastructure.
- Inherent properties of the Mostro protocol itself, such as a counterparty behaving
  dishonestly during a trade. Those are protocol design discussions, not client bugs.

## Security Model

A summary of the client's security properties — device-held keys, per-trade key derivation,
and end-to-end encrypted messaging — is in the
[Security section of the README](README.md#security). Architectural details, including which
logic belongs to the Rust core, are in [AGENTS.md](AGENTS.md) and `.specify/ARCHITECTURE.md`.

## User Advisory

Your BIP-39 seed phrase is the only way to recover your identity and trade history. Nobody
from the Mostro project will ever ask for it, for a private key, or for a Nostr Wallet Connect
connection string. Any such request is an attempt to steal your funds.
