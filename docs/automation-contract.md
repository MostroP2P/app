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
| `order.status` | The kebab-case name of `TradeStatus`: `loading`, `pending`, `waiting-invoice`, `waiting-payment`, `waiting-bond`, `in-progress`, `active`, `fiat-sent`, `payout-pending`, `completed`, `cancelled`, `disputed`, `pending-rating`, `rated`. Never the localized chip copy. `waiting-bond` is the anti-abuse bond window (`docs/ANTI_ABUSE_BOND.md`): the daemon is waiting for the user's bond bolt11 before the trade flow starts. |
| `order.id` | The full order id, where the visible text is shortened. |
| `keys.public_key` | The identity's full public key. |
| `settings.mostro_node.pubkey` | The active daemon's full public key, where the visible subtitle is truncated. |
| `wallet.connection` | `connected` or `disconnected`. |
| `pay.invoice.text` | The hold invoice (`bolt11`), which is otherwise only drawn as a QR code or paid directly by the wallet. |
| `pay.order_id` | The exact order ID shown in the seller invoice screen's app bar, including while its invoice is loading. |
| `bond.invoice.text` | The anti-abuse bond bolt11 (`docs/ANTI_ABUSE_BOND.md`), otherwise only drawn as a QR code or paid by the wallet. |
| `bond.order_id` | The exact order ID shown in the pay-bond screen's app bar. |
| `bond.claim.amount` | The share of a slashed bond on offer to this user, in sats (`docs/ANTI_ABUSE_BOND.md` §6.4). |
| `bond.claim.status` | The claim's phase as the screen renders it: `pending`, `submitted`, `acknowledged`, `completed`, `expired` (a pending claim past its window reads `expired`). |
| `bond.claim.order_id` | The exact order ID shown in the claim screen's app bar. |
| `trade.bondSlashed` | The durable line on the trade detail once this user's own bond was slashed, labelled with the cause (`dispute` / `timeout`); absent otherwise. |
| `trade.cancelRequest` | The pending cooperative-cancel request on the trade detail (protocol `cancel.md`), this side's or the counterparty's, while the trade is `active` or `fiat-sent`; absent otherwise. |
| `invoice.nwc.text` | The buyer invoice NWC generated, for payment correlation. |
| `invoice.check` | The app's **own** verdict on what is in the invoice field, as a stable word: `expires-too-soon`, `wrong-amount`, `wrong-network`, `expired`, `malformed`, `unrecognized`, `valid`, `address`. Any word but the last two also means `invoice.submit` is disabled — the invoice is never sent. **Absent is never "fine."** It is absent with nothing typed, while the check is running, and while a word's own dependency is missing — a **pass** needs both the trade amount and the node's capabilities, so `valid` is the last word to become available, whereas `malformed`, `unrecognized`, `expired` and `address` need neither and appear straight away (the full table is under *Manual buyer invoice readouts*). It is absent too whenever `invoice.error` is present, which takes the same slot and hides this readout even after the local verdict resolves. So: wait for the word expected, never read once, never treat absence as acceptance — and do not wait for a word at all while `invoice.error` is on screen. |
| `invoice.error` | The reason the daemon refused the last submitted buyer invoice. Present after a rejection until the next submission **or any edit of the invoice field**, whichever comes first — the verdict was about the text that was sent, so typing clears it; the manual form stays open behind it. In the wallet-generated (NWC) branch, which has no form, the readout comes with `invoice.manual` so the buyer can switch to manual entry. Unlike every other readout here its label is **translated prose**, not a machine word, so assert that it exists — never what it says. `invoice.check` and this are drawn in the same slot and never together. |
| `settings.relays.item.<url>` | The relay's URL. |

There is deliberately **no** identifier for the seed phrase. A stable readout
would put the mnemonic in the accessibility tree, where any accessibility
service on the device can read it, and no scenario needs it.

## Two naming decisions worth knowing

**The order-book tabs are named by their label, not by what they list.**
`order.book.tab.buy` is the "Buy BTC" tab — which lists *sell* orders, because
the taker is buying. A driver that wants a side picks the tab that lists it.
This matches the classic app.

**The order form starts on market price, and a range locks it there.**
The form's switches are segmented controls with both options always visible.
`order.create.price_type` names the `Market | Fixed` control as a whole; its
segments are `order.create.price.market` and `order.create.price.fixed`, and a
driver taps a segment, not the control. The sats field
(`order.create.sats_amount`) exists only on fixed. Likewise
`order.create.range` names the `Single | Range` control, with segments
`order.create.amount.single` and `order.create.amount.range`; range swaps the
single `order.create.fiat_amount` for `order.create.fiat_min` and
`order.create.fiat_max`, and disables the fixed segment: the protocol prices a
range at market only. `order.create.fiat_amount` names the amount's text field
alone; the currency selector drawn inside the same row is its own node
(`order.create.currency`), never merged into the field's. Both the form and the
payment-method screen leave through `appbar.back`. The side can be switched on the form too
(`order.create.side.buy`, `order.create.side.sell`); it starts on the side the
order-book button was tapped with. The premium figure
(`order.create.premium`) opens a numeric field in place when tapped.

**Payment methods are chosen on their own screen.** `order.create.payment_method.add`
on the form opens it. There, `order.create.payment_method.search` narrows the
per-currency list, `order.create.payment_method.<method>` toggles one method,
and the free-text field `order.create.payment_method` plus
`order.create.payment_method.custom_add` turn an arbitrary method into a chip.
Going back keeps every choice; the form shows them as chips.

**The take-order screen has one action.** `order.take.confirm` is `Take order`;
there is no close button — `appbar.back` returns to the book. Once the order
is taken by someone else or expires while the screen is open, the same node
stays but reads as disabled (`No longer available`); the screen never
navigates away on its own. Taking a range order asks its amount in a dialog
(`order.take.amount`, `order.take.amount.confirm`) right after
`order.take.confirm`; a fixed order never shows the dialog.

**My Trades says which state it is in.** Loaded with rows, each row is
`trades.item.<orderId>`. Loaded with nothing to show under the current filter,
the list shows `trades.empty`; a list that failed to load shows `trades.error`,
whose retry keeps its own node. With none of these on screen the list is still
loading. A trade that never went active leaves the list once the daemon
cancels it (`specs/004-mostro-p2p-client/contracts/orders.md`), so a driver
proving that reads a missing row as gone only on a loaded list: next to
`trades.empty` or other rows, never while loading or on `trades.error`.

**A take parked on the anti-abuse bond offers `trade.payBond` (`Pay deposit`)
and `trade.cancel`.** While `order.status` reads `waiting-bond`
(`docs/ANTI_ABUSE_BOND.md`), `trade.payBond` opens `/pay_bond/:orderId`; the
My Trades row carries the same verb and files the trade under "your turn".

**An order parked on the maker's own deposit is not published yet.** While
`order.status` reads `waiting-bond` on `/my_order` (`docs/ANTI_ABUSE_BOND.md`
§6.2), the screen offers `order.payBond` (`Pay deposit`), which opens
`/pay_bond/:orderId`, and no `trade.cancel`: the daemon refuses a cancel in
this window. On that screen `bond.cancel` reads `Don't publish the order` and
drops the order locally (nothing was published, nothing charged); a taker's
reads `Don't take the order` and is a daemon cancel. Once the deposit is
paid the daemon publishes the order and `/my_order` reads `pending`.

**A slashed bond is explained on tap.** Tapping a bond-slashed notification opens a
dialog with the cause, the amount and the order; `bond.slashed.viewPolicy` (`View policy`)
leads to the About screen, `bond.slashed.viewTrade` (`View trade`) opens the trade
detail and is present only while the trade row still exists (a timeout slash wipes
it), `bond.slashed.close` dismisses it. The trade keeps `trade.bondSlashed`
afterwards.

**A claimable share reaches the user from three places.** The trade detail
carries `trade.bondClaim` (labelled with the claim's phase) with
`trade.bondClaim.open` while the claim is pending or in progress; the My
Trades row shows a `Payout pending` / `Payout in progress` / `Payout paid`
badge next to its chip, a pending one files the row under *Your turn* with the
verb `Claim payout`, and a claim whose trade row is gone renders a row of its
own; a notification (`bond.claim` type) opens the claim screen.

**Claiming a slashed bond's share happens on `/bond_payout/:orderId`.**
While `bond.claim.status` reads `pending`, the screen offers `bond.claim.text`
(the bolt11 field, paste and scan) and `bond.claim.submit` (`Send invoice`),
or — with a wallet connected — the same NWC widget the add-invoice screen
uses, with `bond.claim.manual` as the way to the field. The invoice must be
for exactly `bond.claim.amount`; a refused submission keeps the form and
states the reason. Every other phase is read-only.

**The maker's own order ends on `order.confirm.home` (`Close`) and
`trade.cancel`.** `trade.cancel` opens a confirmation sheet whose affirmative
is `trade.cancel.confirm`; the button is absent once the order is expired,
cancelled or completed.

**Rating is one star and a submit, on the trade itself.** After a successful
trade the completed card of the trade detail carries `trade.rate.star.<n>` for
each of its five stars, `trade.rate.submit` (enabled once a star is chosen) and
`trade.rate.close`. Submitting stays on the same trade, whose `order.status`
then reads `rated`; `trade.rate.close` then closes it. The standalone rating
screen (`/rate_user/:orderId`, reached from a notification) keeps the same
identifiers. A disputed trade offers `trade.dispute.view`; a cancelled one
`trade.close`.

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
| Order expiry | `MORTSOM_ORDER_EXPIRY_SECS` (optional) makes every order this build creates ask the daemon to expire it that many seconds after creation, the way the protocol lets any maker do; the daemon caps it by its `max_expiration_days`. Without it the daemon's own default applies (an hour), which is what a scenario about the daemon's pending-order clock cannot wait out. Ignored outside the test environment. |

Both entry points go through `bootstrapAndRun` in `lib/core/app_bootstrap.dart`,
so a test build and a production build differ only in what they pass, never in
how they start.

## Behaviour

Attaching an identifier changes no behaviour. The entry point, the relay seed
and the banner apply only to a build that carries the define.

## Linux and Web execution

Web exposes `Semantics.identifier` as `flt-semantics-identifier` in the
rendered semantics DOM. The test entry point enables semantics from startup.
Build the Rust core with `scripts/build-web.sh --release` before Flutter Web
and serve cross-origin isolation headers.

The current Flutter Linux engine does not forward `Semantics.identifier` to
AT-SPI. Only in an armed Mortsom build, `AutomationId` prefixes its accessible
name with `[mortsom:<identifier>]`. Flutter can merge parent metadata ahead of
that name: a native tab exposes `Tab 2 of 2\n[mortsom:order.book.tab.sell]\nSell BTC`.
The marker therefore starts a line, which is not necessarily the first line
of the final AT-SPI name. Mortsom recognizes exactly one marker at a line
boundary and invokes the merged node's public AT-SPI action; it never matches
an identifier embedded in ordinary prose. An explicit readout follows the
closing bracket exactly; ordinary controls retain their merged descendant
labels. Production builds retain their original accessible labels.

Each Linux actor must have its own DBus session, Secret Service and XDG
directories. XDG isolation alone does not isolate FlutterSecureStorage.

### Buyer payout completion

`payout-pending` is nonterminal: the seller escrow has settled but the buyer payout has not yet been confirmed. Continue observing until the protocol status is `OrderStatus::Success`; only then may the UI expose `pending-rating` or completion. A released escrow alone never authorizes rating or a completed-trade assertion.


### Buyer payout failure

The daemon settles the seller's escrow at release and then pays the buyer's invoice. When that payment
fails it retries on its own schedule (`payment_attempts` every `payment_retries_interval`); the first
failure reaches the buyer as `payment-failed`, which changes nothing on screen: the trade stays
`payout-pending`. Once the retries are exhausted the daemon asks the buyer for a new invoice with an
`add-invoice` whose order still reads `settled-hold-invoice`. The app treats that message exactly as the
first request for an invoice: the trade shows `waiting-invoice`, the add-invoice screen opens for the
buyer and `trade.addInvoice` is offered on the trade detail. The replacement goes through the same manual
form (or the NWC generator when a wallet is connected); the daemon's `invoice-updated` returns the trade to
`payout-pending`, and `completed` follows only when the daemon publishes `success`. A rejected replacement is
reported through `invoice.error` like any other rejection.

### Manual buyer invoice readouts

`invoice.amount` exposes the positive unsigned number of sats requested by the daemon, alongside the
ordinary amount shown on the manual invoice form. `invoice.order_id` exposes the visible order reference on
that same form. Automation must verify the requested order and amount before generating an invoice, retain
its exact hash and amount before submission, and verify field readback before pressing submit. The manual
submission returns to the matching trade detail (`order.id` and `order.status`).

**The app judges the invoice before the daemon does.** Amount, network, expiry and the node's
`invoice_expiration_window` are checked locally, and a failure disables `invoice.submit`: that invoice is
never sent, so no `invoice.error` follows and nothing changes on the relay. A scenario for one of those
rules asserts `invoice.check`, not the daemon's refusal.

Some of those rules need facts that arrive asynchronously: the **trade's amount**, and the **expiry floor
and network** from the node's Kind 38385 capabilities, whose fetch the screen starts on entry. What is
withheld until they settle is a local **pass** — a rule that could not run did not pass — and the words
that depend on the missing fact. The classifications that need neither appear straight away:

| Word | Needs |
|---|---|
| `unrecognized`, `malformed` | nothing — published immediately |
| `expired` | nothing but the clock — published immediately |
| `address` | nothing; note submission is *held* until the amount resolves the address |
| `wrong-amount` | the trade's amount |
| `wrong-network`, `expires-too-soon` | the node's capabilities |
| `valid` | both — the last word to become available |

So absence of `valid` is never evidence of a problem, and the presence of `malformed` this early is not a
sign the facts arrived. A node whose capabilities never load — a failed fetch, not merely a slow one —
never gets a pass published for it at all; the daemon stays the backstop and submission stays *allowed*,
exactly as for an invoice this side cannot judge. While the check itself is running, and while a refusal
stands, submission is instead held.

A harness therefore waits for the word it expects rather than reading once, and accepts that on a cold
entry a daemon rejection is still reachable. It must not read a missing word as a pass, and it must not
conclude anything from the button alone: enabled means "judged good", "an address whose amount has
arrived", or "not judged at all" — three states one bit cannot tell apart.

A refusal by either side, while both parties are still at the invoice step, leaves the order at
`waiting-invoice` and the buyer free to submit again. One daemon refusal is different: when the daemon
reports it no longer expects an invoice, the app starts state recovery and the status that comes back is
what takes the buyer off the screen. Do not wait for `waiting-invoice` after that one.

Taking a sell order without a configured Lightning address opens the buyer invoice form directly;
taking a buy order opens the seller's hold-invoice screen directly. These routes need not expose
`order.status`. For the desktop manual-wallet checkpoint, automation may normalize the visible
`invoice.text` form to `Taken` with raw label `waiting-invoice`, or the visible `pay.invoice.text`
form to `Taken` with raw label `waiting-payment`, only after its `invoice.order_id` or `pay.order_id`
exactly matches the requested order. A form for another order never proves a state or authorizes payment.
Automation retains the matching form for the next action rather than reopening it. After buyer submission,
or after the seller screen automatically observes accepted payment, the app returns to trade detail;
subsequent state assertions read its normal status. Both invoice screens expose `appbar.back` on their
ordinary BackButton when navigation can pop; this action never invokes the order-cancellation control.

The release action stays on trade detail while payment finalizes. An early rating notification or direct
rating route also waits for final success.
