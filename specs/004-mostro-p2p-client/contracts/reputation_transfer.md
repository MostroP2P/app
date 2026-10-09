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

## Functions

### get_reputation_support() → ReputationSupportInfo  *(sync)*
What the active node advertises, as of its last capability fetch:
`reputation_issuer` (it exports) and `reputation_import_issuers` (it imports,
from those keys). A fetch without the tags, no info event or a failed fetch
retracts an older answer, so both read `None` until the node is fetched again.

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
`InvalidReputationAttestation`, the node's `CantDoReason` by name, and
`NoIdentity` when the identity was deleted or replaced before the answer
arrived (nothing is stored).

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
authorisation to move that binding to `new_identity` (both hex). Returned as
event JSON, to pass as `rebind` to `export_reputation` from the new identity
or to paste into lnp2pBot. Valid for an hour.

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
