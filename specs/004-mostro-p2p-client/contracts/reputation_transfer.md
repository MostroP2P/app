# Contract: Reputation Transfer API

**Module**: `rust/src/api/reputation_transfer.rs`

Reputation portability (MostroP2P/mostro `docs/REPUTATION_PORTABILITY.md`,
phase 5b; MostroP2P/protocol `reputation_transfer.md`): export the reputation
earned on the active node, import an attestation earned elsewhere, and
authorise moving an exported reputation to a new identity.

Both requests act on the **identity key**, so neither runs in privacy mode.
Each goes only to a node whose Kind 38385 info event advertises it
(`mostro::reputation_support`): a node that predates the actions cannot parse
them and would never answer.

After signing and establishing the reply subscription, both requests check
the initiating identity generation and privacy mode again before publishing.
An identity change returns `NoIdentity`; enabling privacy mode returns
`PrivacyModeEnabled`. Neither case publishes the prepared request. Publication
holds the identity guard until the send finishes; the daemon reply wait does
not hold it. Pending-attestation reads and writes remain identity-guarded and
serialize through the same slot lock, so cleanup cannot delete a newer export.

## Functions

### get_reputation_support() → ReputationSupportInfo  *(sync)*
What the active node advertises, as of its last capability fetch:
`reputation_issuer` (it exports) and `reputation_import_issuers` (it imports,
from those keys). A fetch without the tags, no info event or a failed fetch
retracts an older answer, so both read `None` until the node is fetched again.

---

### reputation_identity_npub(identity: String) → String *(sync)*
Encode a public key, given as hex or npub (surrounding whitespace ignored), as
npub in Rust. The import screen displays the complete, selectable value for
comparison with lnp2pBot's confirmation; the bot link uses the same key as hex.
The reputation screen shows it before a rebind authorisation is signed, which
also validates what the user typed. No private key is exposed. Anything else
returns `InvalidPubkey`.

---

### parse_reputation_attestation(json: String) → ReputationAttestationInfo  *(sync)*
Verify a pasted or received attestation locally, without sending anything:
signature, kind, tags, clock and lifetime. Whether a node trusts its issuer is
that node's to say on import.

**Errors**: the `CantDoReason` a destination would answer with, by name
(`InvalidReputationAttestation`, `ExpiredReputationAttestation`).

---

### export_reputation(destination: String?, rebind: String?) → ReputationAttestationInfo
Ask the active node to attest the user's reputation there for `destination`
(hex; the user's own identity when null). The request binds the node's account
to that destination, so the UI confirms it with the user first. `rebind` is an
authorisation from `sign_reputation_rebind`, needed when the account is
already bound to another identity.

**Preconditions**: the node advertises `reputation_issuer`; privacy mode off.

**Side effects**: sends `export-reputation` from a fresh trade key with the
identity proof (Kind 14, NIP-44), correlated by its nonce; waits up to 15 s.
The answer must be signed by the advertised issuer key and name the requested
destination. It is then kept as the **pending attestation**, but only while
the identity that asked is still the active one.

**Errors**: `ReputationExportUnsupported`, `StorageUnavailable` (checked
before anything is sent), `PrivacyModeEnabled`, `InvalidPubkey`,
`NoDaemonResponse`, `InvalidPayload`,
`ReputationIssuerKeyMismatch` (the answer is signed by another key than the
`reputation_issuer` the app read for the node, as after a rotation with a
stale info event; refreshing the node's info is the remedy, #882),
`InvalidReputationAttestation` (it names another identity), the node's
`CantDoReason` by name, and `NoIdentity` when the identity was deleted or
replaced before the answer arrived (nothing is stored). The reputation screen
shows `ReputationIssuerKeyMismatch` with its own text, and every failure
without a text of its own as "This Mostro could not export your reputation",
never as an invalid pasted attestation.

---

### check_reputation_import(attestation_json: String) → ReputationAttestationInfo
Run every local check `import_reputation` makes, without sending anything: the
node advertises `reputation_import_issuers`, privacy mode is off, and the
attestation verifies, names the user's identity and is signed by a key the
node trusts. The import screen calls it on Check, so a refusal shows before
the user commits to the import.

**Errors**: `ReputationImportUnsupported`, `PrivacyModeEnabled`,
`InvalidReputationAttestation`, `ExpiredReputationAttestation`,
`ReputationIdentityMismatch`, `UntrustedReputationIssuer`.

---

### import_reputation(attestation_json: String) → ReputationAttestationInfo
Import an attestation into the active node. Checked locally first: it verifies,
names the user's identity, and is signed by a key the node advertises it
trusts. The node runs the full checks and answers `reputation-imported` or a
refusal.

**Preconditions**: the node advertises `reputation_import_issuers`; privacy
mode off.

**Side effects**: sends `import-reputation` as above. On success, drops the
pending attestation when it is the same event (matched by event id, not by the
JSON text), under the same identity guard as the export.

**Errors**: `ReputationImportUnsupported`, `PrivacyModeEnabled`,
`ReputationIdentityMismatch`, `UntrustedReputationIssuer`,
`InvalidReputationAttestation`, `ExpiredReputationAttestation`,
`NoDaemonResponse`, the node's `CantDoReason` by name (e.g.
`ReputationAlreadyImported`), and `NoIdentity`.

---

### get_pending_reputation_attestation() → ReputationAttestationInfo?
The attestation exported last and not imported yet, while it still verifies.
An expired one is deleted and reads as null; one refused for another reason
(e.g. a local clock behind the issuer's) reads as null but is kept.
Read under the identity guard, so it never returns an identity's attestation
after that identity was deleted or replaced; null when no identity is loaded.

---

### sign_reputation_rebind(issuer: String, new_identity: String) → String
Sign, with the identity the reputation at `issuer` is bound to now, the
authorisation to move that binding to `new_identity`. `issuer` is hex;
`new_identity` is hex or npub. Returned as event JSON, to pass as `rebind` to
`export_reputation` from the new identity, or to paste into lnp2pBot when
`issuer` is the bot's key. Valid for an hour.

**Errors**: `PrivacyModeEnabled`, `InvalidPubkey`, `InvalidReputationRebind`.

## Persistence

| Key | Store | Scope |
|-----|-------|-------|
| `pending_reputation_attestation` | `settings` (SQLite / IndexedDB) | Identity |

A single slot for all nodes: a later export replaces it. It is wiped by
`Storage::clear_identity_data` with the rest of the identity's data, and every
write after a daemon round trip goes through `while_identity_current`, so a
late answer never lands in the next identity's store.

## Types

### ReputationSupportInfo
```text
issuer: String?               # key the node signs attestations with
import_issuers: List<String>? # keys it imports from; empty = imports from nobody yet
```

### ReputationAttestationInfo
```text
id: String
issuer: String       # key that signed it
destination: String  # identity it is addressed to
subject: String      # source account, opaque
reviews: u32
rating: String       # two decimals, e.g. "4.87"
since: i64           # UTC day start of the first completed trade on the source
created_at: i64
expiration: i64
json: String         # the event JSON as received, to import unchanged
```

## Reputation screen

`/reputation`, inside the persistent home shell, is reached from the
**Reputation** row of Settings. It has three parts:

- **Import** opens `/import_reputation` (below).
- **Export**, shown only while the active node advertises `reputation_issuer`.
  The screen rereads `get_reputation_support()` every two seconds, so an issuer
  key that arrives with a capability fetch finishing after the screen opened
  still shows the card. Export first shows the identity as an npub
  (`reputation_identity_npub`) in a confirmation dialog, because the request
  binds the node's account to it. An optional field takes a rebind
  authorisation signed by the identity the account is bound to now; when
  filled, it is passed trimmed as `rebind` to `export_reputation`. The returned
  attestation is shown to select or copy, and Rust keeps it as pending.
- **Moving to a new identity.** The user types the new identity as npub or hex.
  It is validated and encoded through `reputation_identity_npub`, then shown in
  a confirmation dialog stating that whoever holds that key can export the
  reputation from this node. Only after confirmation is
  `sign_reputation_rebind` called with the node's issuer key. The result is
  shown to select or copy, for the new identity to paste in the export field
  above.

In full privacy mode a notice explains why every action is disabled.

Automation identifiers: `settings.reputation`, `reputation.open_import`,
`reputation.export`, `reputation.export.rebind`, `reputation.export.confirm`,
`reputation.export.result`, `reputation.rebind.identity`,
`reputation.rebind.sign`, `reputation.rebind.confirm` and
`reputation.rebind.result`.

## Import screen

`/import_reputation` is a route inside the persistent home shell, reached
from the reputation screen. It imports into the active node and discloses
that importing links the source and destination accounts.

- Actions stay disabled while privacy and identity are loading, on read failure,
  in full privacy mode, or when `import_issuers` is absent. A localized notice
  explains the refusal and Retry rereads the state. An empty issuer list means
  that no issuer is trusted yet; Check rejects every attestation in that case.
- The full identity npub is selectable beside the bot action. The user compares
  it with the key shown by lnp2pBot before confirming the binding there.
  The Telegram URL uses `rep_` plus the same key encoded as 43 unpadded base64url
  characters. Before opening it, the screen rereads identity, privacy and node
  support. A different identity is displayed for review without opening the bot;
  leaving the route cancels the handoff. A failed launch shows a localized error.
- A pending exported attestation prefills an empty field and is checked
  locally. A user paste can contain surrounding prose; only the JSON object is
  passed to Rust. Check verifies signature, kind, tags, expiry, destination and
  the node's issuer trust list without publishing. Failures are localized.
- The verified card shows locale-formatted rating, review count and trading
  age, with plural forms. Checks, refusals and successful imports are announced
  to screen readers as live regions. Editing the field withdraws the card and confirmation; an answer
  to Check that arrives for different text is discarded.
- Import sends exactly the checked event JSON. Its field and actions are disabled
  while awaiting the reply. Rust repeats all checks before sending, then the
  daemon accepts or refuses; only an accepted reply shows success. A refusal or
  timeout remains an error, and retries use the same checked attestation. Pending
  state is cleared by Rust only when its event id matches the imported event.

Automation identifiers: `reputation.import.identity`, `.open_bot`, `.input`,
`.check`, `.figures`, and `.confirm` (each suffix follows `reputation.import`).
