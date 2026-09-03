# UI automation contract

[Mortsom](https://github.com/MostroP2P/mortsom) is the end-to-end harness that
drives this app on real emulators against a real Mostro daemon. It is a
black-box driver: it sees what the Android accessibility tree exposes and
nothing else.

Such a driver cannot look for "Continue" or "Skip". That text changes with the
locale, with a redesign, with a copy review. It needs identifiers the app
promises to keep. This document is that promise.

## What an identifier is

Every identifier is declared in `lib/core/automation/automation_ids.dart` and
attached to exactly one control through `.withAutomationId(...)`, which sets
Flutter's `Semantics.identifier` — surfaced on Android as the accessibility
`resource-id`.

```dart
FilledButton(
  onPressed: _submit,
  child: Text(l10n.submitButton),
).withAutomationId(AutomationIds.orderCreateSubmit)
```

Rules:

* Identifiers are namespaced `<area>.<screen-or-flow>.<control>`.
* An identifier is a **product contract**. Renaming or removing one, or moving
  it to a different control, breaks the harness and needs coordinated review
  with the automation owners.
* Where a screen exists in the classic app (`MostroP2P/mobile`) too, the
  identifier is the same string. The two applications speak one vocabulary.
* Dynamic identifiers are built by the helpers in the registry, never by
  string concatenation at the call site.

## Controls, readouts and rows

Three shapes, and picking the wrong one is the usual way this rots:

| Shape | How | Why |
|---|---|---|
| A control | `.withAutomationId(id)` | The identifier, the visible label, the enabled flag and the tap action merge onto one node, which is what the accessibility bridge exposes. |
| A state readout | `.withAutomationId(id, label: machineValue)` | The visible copy is localized, truncated or not a `Text` at all. The label *replaces* it, so the harness asserts on a stable machine value. |
| A composite row | `.withAutomationId(id, merge: false, label: ...)` | The row holds several independent controls (a relay row has a toggle and a delete button). Merging would collapse them into one node and automation could no longer pick one. |

`test/core/automation/automation_contract_test.dart` proves each of these, and
fails the build when an identifier is declared and attached to nothing.

## Readouts and their machine values

| Identifier | Value |
|---|---|
| `order.status` | The kebab-case name of `TradeStatus`: `loading`, `pending`, `waiting-invoice`, `waiting-payment`, `in-progress`, `active`, `fiat-sent`, `completed`, `cancelled`, `disputed`, `pending-rating`, `rated`. Never the localized pill copy. |
| `order.id` | The full order id, where the visible text is shortened. |
| `keys.public_key` | The identity's full public key. |
| `settings.mostro_node.pubkey` | The active daemon's full public key, where the visible subtitle is truncated. |
| `wallet.connection` | `connected` or `disconnected`. |
| `pay.invoice.text` | The hold invoice (`bolt11`), which is otherwise only drawn as a QR code or paid directly by the wallet. |
| `invoice.nwc.text` | The buyer invoice NWC generated, for payment correlation. |
| `settings.relays.item.<url>` | The relay's URL. |

There is deliberately **no** identifier for the seed phrase. A stable readout
would put the mnemonic in the accessibility tree, where any accessibility
service on the device can read it, and no scenario needs it.

## Two naming decisions worth knowing

**The order-book tabs are named by their label, not by what they list.**
`order.book.tab.buy` is the "Buy BTC" tab — which lists *sell* orders, because
the taker is buying. A driver that wants a side picks the tab that lists it.
This matches the classic app.

**A pending order you created opens on `/my_order`, not `/trade_detail`.**
Both screens therefore expose `order.status` and `order.id`, in the same
vocabulary.

## The test environment

A build under test must be impossible to confuse with a real one — by a person
or by the harness.

```sh
flutter build apk -t lib/main_mortsom.dart \
  --dart-define=MORTSOM_TEST_ENV=true \
  --dart-define=MOSTRO_PUB_KEY=<daemon pubkey> \
  --dart-define=MORTSOM_RELAYS=ws://10.0.2.2:7000
```

`lib/main_mortsom.dart` is the only caller of `TestEnvironment.arm()`, and the
environment is active only when arming and the compile-time define agree. The
production entry point never arms it and the release pipeline never passes the
define, so a shipped build cannot enter it by accident.

What the test environment changes:

| | Behaviour |
|---|---|
| Relays | `MORTSOM_RELAYS` **replaces** the relay defaults compiled into the Rust core, rather than extending them. A run whose local relay is unreachable must fail, never quietly succeed against a public relay. |
| Relay scheme | The add-relay dialog accepts `ws://` as well as `wss://`; a local test relay is plain `ws://` on a private address. Outside the test environment the `wss://` requirement is unchanged. |
| Marker | A red `TEST ENVIRONMENT · Mortsom` banner is shown on every screen, carrying `env.marker`. The harness refuses to run against a build without it. |
| Node | `MOSTRO_PUB_KEY` selects the daemon under test, applied before the relay pool starts and only when no node was ever chosen — so a restart keeps whatever the run picked through the UI. Without it the first subscriptions would target the production node, which cannot decrypt them, and the app would look silently idle. A malformed key is ignored rather than passed to the bridge. |
| Startup | Missing `MORTSOM_RELAYS` fails at startup naming the define, instead of starting against the public relays and passing a test that never reached the daemon under test. |

Both entry points go through `bootstrapAndRun` in `lib/core/app_bootstrap.dart`,
so a test build and a production build differ only in what they pass, never in
how they start.

## Behaviour

Attaching an identifier changes no behaviour. The entry point, the relay seed
and the banner apply only to a build that carries the define.
