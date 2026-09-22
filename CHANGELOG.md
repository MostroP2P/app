# Changelog

All notable changes to Mostro are documented here, newest first. This file is
written by the release workflow (docs/RELEASING.md) — do not edit it by hand.
Versions follow [Semantic Versioning](https://semver.org/).

## [2.0.4] - 2026-09-21

### ✨ Features

- **ui:** standardize the modals — phases 4-6 ([#536](https://github.com/MostroP2P/app/pull/536)) by @grunch
- **ui:** standardize the modals — phases 1-3 ([#535](https://github.com/MostroP2P/app/pull/535)) by @grunch
- **order:** payment-method picker per handoff 18a ([#532](https://github.com/MostroP2P/app/pull/532)) by @grunch

### 🐛 Bug Fixes

- **account:** an imported seed is already backed up ([#531](https://github.com/MostroP2P/app/pull/531)) by @grunch
- **relays:** repair CLOSEd subscriptions and release a finished trade's REQs ([#527](https://github.com/MostroP2P/app/pull/527)) by @grunch

### 📚 Documentation

- **design-system:** v2 is a redesign, not a copy of v1 ([#538](https://github.com/MostroP2P/app/pull/538)) by @grunch

## [2.0.3] - 2026-09-20

### 🐛 Bug Fixes

- **restore:** retry a silent restore once and ignore replayed replies ([#525](https://github.com/MostroP2P/app/pull/525)) by @grunch
- **logging:** keep relay traffic in a ring of its own ([#526](https://github.com/MostroP2P/app/pull/526)) by @grunch
- **restore:** settle replayed history instead of listing it as in progress ([#524](https://github.com/MostroP2P/app/pull/524)) by @grunch

## [2.0.2] - 2026-09-19

### ✨ Features

- **order-book:** swipe between Buy and Sell ([#518](https://github.com/MostroP2P/app/pull/518)) by @grunch

### 🐛 Bug Fixes

- **restore:** recover after a seed import and resync a stale trade index ([#519](https://github.com/MostroP2P/app/pull/519)) by @grunch

## [2.0.1] - 2026-09-18

### ✨ Features

- **settings:** cache node kind 38385 info and fix the double radio on switch ([#508](https://github.com/MostroP2P/app/pull/508)) by @grunch
- **nodes:** add MostroEuropa to the trusted node registry ([#509](https://github.com/MostroP2P/app/pull/509)) by @grunch

### 🐛 Bug Fixes

- **invoice:** one add-invoice screen and one submission after a bond locks ([#514](https://github.com/MostroP2P/app/pull/514)) by @grunch
- **node-selector:** list every accepted currency on a node card ([#512](https://github.com/MostroP2P/app/pull/512)) by @grunch
- **nav:** centre the bottom nav bar's icons and labels vertically ([#511](https://github.com/MostroP2P/app/pull/511)) by @grunch
- **orders:** tell both sides about a cooperative cancel request ([#505](https://github.com/MostroP2P/app/pull/505)) by @grunch
- **invoice:** follow the trade status off the add-invoice screen ([#499](https://github.com/MostroP2P/app/pull/499)) by @grunch

### ⚡ Performance

- **startup:** the order book no longer waits for the capability fetch ([#507](https://github.com/MostroP2P/app/pull/507)) by @grunch
- **startup:** PR 3.7 — measured cold start: 2.3 s → 0.5–0.8 s to runApp, first Online 2.5 s → 1.0 s ([#494](https://github.com/MostroP2P/app/pull/494)) by @grunch
- **ui:** PR 3.3 — the order book follows deltas; one mapping per changed order ([#498](https://github.com/MostroP2P/app/pull/498)) by @grunch

### 👷 Build & CI

- **release:** attach the Android App Bundle for the Play Console ([#506](https://github.com/MostroP2P/app/pull/506)) by @grunch
- **release:** check the keystore password and alias before building ([#503](https://github.com/MostroP2P/app/pull/503)) by @grunch
- **release:** attach Linux, Windows, macOS and iOS builds to a release ([#501](https://github.com/MostroP2P/app/pull/501)) by @grunch

### 🧹 Chores

- ignore keystores and key.properties from the repo root ([#502](https://github.com/MostroP2P/app/pull/502)) by @grunch

## [2.0.0] - 2026-09-18

### ✨ Features

- **bridge:** PR 3.2 — order-book delta stream over FRB ([#496](https://github.com/MostroP2P/app/pull/496)) by @grunch
- **core:** PR 3.1 — map-backed order book with revisioned deltas ([#495](https://github.com/MostroP2P/app/pull/495)) by @grunch
- **push:** PR-4c — web push client, behind the server ([#484](https://github.com/MostroP2P/app/pull/484)) by @grunch
- **push:** PR-4b — iOS push configuration ([#483](https://github.com/MostroP2P/app/pull/483)) by @grunch
- **push:** add master toggle, status and safe opt-out ([#479](https://github.com/MostroP2P/app/pull/479)) by @grunch
- **invoice:** prefill the saved Lightning address on the add-invoice screen ([#482](https://github.com/MostroP2P/app/pull/482)) by @grunch
- **invoice:** invoice field that asks to be filled (campo_factura) ([#480](https://github.com/MostroP2P/app/pull/480)) by @grunch
- single-owner registry for per-trade subscriptions ([#407](https://github.com/MostroP2P/app/pull/407)) by @Forte11Cuba
- **notifications:** in-app cards for trade updates and chat messages (#474) ([#475](https://github.com/MostroP2P/app/pull/475)) by @grunch
- **push:** PR-3b — a content-free notice for a peer's chat wake ([#473](https://github.com/MostroP2P/app/pull/473)) by @grunch
- **push:** PR-3a — wake the peer after a chat message ([#472](https://github.com/MostroP2P/app/pull/472)) by @grunch
- **push:** PR-2 — wake handling, display-only ([#471](https://github.com/MostroP2P/app/pull/471)) by @grunch
- **push:** PR-1d — OS-scheduled registration refresh ([#470](https://github.com/MostroP2P/app/pull/470)) by @grunch
- **push:** PR-1c — Dart hands the token to Rust; push contract ([#468](https://github.com/MostroP2P/app/pull/468)) by @grunch
- **push:** PR-1b — Rust-owned registration against the push server ([#467](https://github.com/MostroP2P/app/pull/467)) by @grunch
- **push:** PR-1a — registration rules, pure ([#466](https://github.com/MostroP2P/app/pull/466)) by @grunch
- **push:** PR-0b — app lifecycle service and resume hydration ([#464](https://github.com/MostroP2P/app/pull/464)) by @grunch
- **push:** PR-0a — resync() after a suspended process ([#463](https://github.com/MostroP2P/app/pull/463)) by @grunch
- **bond:** PR-5 — web store smoke, push gap, docs and dead l10n ([#461](https://github.com/MostroP2P/app/pull/461)) by @grunch
- **bond:** PR-4b — restart coverage verified, bond rows from restore ([#460](https://github.com/MostroP2P/app/pull/460)) by @grunch
- **bond:** PR-4a — bond-slashed dialog and durable trade notice ([#459](https://github.com/MostroP2P/app/pull/459)) by @grunch
- **bond:** PR-3d — payout claim entry points (list, detail, notifications) ([#452](https://github.com/MostroP2P/app/pull/452)) by @grunch
- **bond:** PR-3c — payout claim screen ([#451](https://github.com/MostroP2P/app/pull/451)) by @grunch
- **bond:** PR-3b — payout claim protocol (dispatch, submission, filter) ([#450](https://github.com/MostroP2P/app/pull/450)) by @grunch
- **bond:** PR-3a — bond payout claim store (SQLite and IndexedDB) ([#449](https://github.com/MostroP2P/app/pull/449)) by @grunch
- **account:** redesign Account and the backup flow (15a–16d) ([#447](https://github.com/MostroP2P/app/pull/447)) by @grunch
- **bond:** PR-2b — maker bond flow in the create form, pay-bond screen and My Order ([#446](https://github.com/MostroP2P/app/pull/446)) by @grunch
- **bond:** PR-2a — maker bond correlation, expiry, abandon (Rust) ([#445](https://github.com/MostroP2P/app/pull/445)) by @grunch
- **bond:** PR-1c — flip the taker gate, pay-bond action in trades ([#444](https://github.com/MostroP2P/app/pull/444)) by @grunch
- **bond:** phase 1b — pay-bond screen (handoff 14a/14b) ([#443](https://github.com/MostroP2P/app/pull/443)) by @grunch
- **bond:** phase 1a — taker bond lifecycle in the Rust core ([#442](https://github.com/MostroP2P/app/pull/442)) by @grunch
- **bond:** phase 0 foundation — statuses, bond types, node policy ([#440](https://github.com/MostroP2P/app/pull/440)) by @grunch
- **invoice:** redesign the add-invoice and pay-invoice screens (handoff 13a/13b) ([#438](https://github.com/MostroP2P/app/pull/438)) by @grunch
- **trades,chat:** redesign the trades and chat tabs (handoff 11a/11b) ([#436](https://github.com/MostroP2P/app/pull/436)) by @grunch
- **about:** redesign About per design_handoff_acerca_de (12a/12b) ([#435](https://github.com/MostroP2P/app/pull/435)) by @grunch
- **settings:** redesign settings, relays, NWC wallet, notifications and logs ([#433](https://github.com/MostroP2P/app/pull/433)) by @grunch
- **mascot:** give Mostro a pulse (easter eggs) ([#431](https://github.com/MostroP2P/app/pull/431)) by @grunch
- **settings:** redesign the node selector (design_handoff_selector_nodo 9a/9b) ([#430](https://github.com/MostroP2P/app/pull/430)) by @grunch
- **trades:** redesign the trade screen (handoff 8a–8e) ([#429](https://github.com/MostroP2P/app/pull/429)) by @grunch
- **order:** redesign own-order and take-order screens (handoffs 6a/6b, 7a) ([#428](https://github.com/MostroP2P/app/pull/428)) by @grunch
- **order:** redesign the create-order screen (handoff 5a/5b/5c) ([#425](https://github.com/MostroP2P/app/pull/425)) by @grunch
- **home:** redesign the order book (handoff 4b card, 4d create button) ([#424](https://github.com/MostroP2P/app/pull/424)) by @grunch
- **drawer:** redesign the drawer (handoff 3b dark / 3c light) ([#421](https://github.com/MostroP2P/app/pull/421)) by @grunch
- ask the buyer for a new invoice when the payout fails, and keep a rejection on screen ([#420](https://github.com/MostroP2P/app/pull/420)) by @grunch
- mostro node selector with trusted registry and kind 0 metadata ([#384](https://github.com/MostroP2P/app/pull/384)) by @Forte11Cuba
- **cashu:** C4 — escrow primitives (2-of-3 NUT-11 lock, sign, redeem, reclaim) ([#236](https://github.com/MostroP2P/app/pull/236)) by @grunch
- tag the dispute screen back button for automation ([#414](https://github.com/MostroP2P/app/pull/414)) by @grunch
- Linux accessibility contract and Web persistence for Mortsom ([#408](https://github.com/MostroP2P/app/pull/408)) by @grunch
- generate the launcher icons from the Mostro artwork ([#400](https://github.com/MostroP2P/app/pull/400)) by @Pivii
- **#328:** source restore trade-key resync from Action::LastTradeIndex ([#333](https://github.com/MostroP2P/app/pull/333)) by @Forte11Cuba
- **disputes:** make the dispute chat survive a restart ([#256](https://github.com/MostroP2P/app/pull/256)) by @grunch
- **cashu:** C2 — embedded Cashu wallet over cdk (native), typed stub on web ([#235](https://github.com/MostroP2P/app/pull/235)) by @grunch
- **nostr:** discover relays from the Mostro node's kind 10002 list ([#385](https://github.com/MostroP2P/app/pull/385)) by @grunch
- **core:** mostro-core 0.14.6 and a maintenance-mode message ([#376](https://github.com/MostroP2P/app/pull/376)) by @grunch
- **take-order:** improve order details UX ([#372](https://github.com/MostroP2P/app/pull/372)) by @Forte11Cuba
- **#337:** validate market-price orders against the node's sats limits ([#343](https://github.com/MostroP2P/app/pull/343)) by @AndreaDiazCorreia
- **#282:** validate fixed-sats order amount against the node's min/max before submitting ([#302](https://github.com/MostroP2P/app/pull/302)) by @codaMW
- **#217:** resync trade_key_index to the max recovered index ([#239](https://github.com/MostroP2P/app/pull/239)) by @codaMW
- show taker reputation on invoice and trade-detail screens ([#320](https://github.com/MostroP2P/app/pull/320)) by @Forte11Cuba
- Mortsom automation contract ([#307](https://github.com/MostroP2P/app/pull/307)) by @grunch
- **#281:** currency-aware payment method suggestions in create-order form ([#297](https://github.com/MostroP2P/app/pull/297)) by @codaMW
- **#280:** confirm before opening a dispute ([#296](https://github.com/MostroP2P/app/pull/296)) by @codaMW
- **navigation:** auto-open invoice screens on daemon request ([#289](https://github.com/MostroP2P/app/pull/289)) by @Catrya
- **logging:** instrument core flows with an end-to-end debug trace ([#279](https://github.com/MostroP2P/app/pull/279)) by @Catrya
- **assets:** real walkthrough illustrations and Mostro logo across app bars ([#264](https://github.com/MostroP2P/app/pull/264)) by @AndreaDiazCorreia
- **order-book:** night-contrast refresh + selective glow on offer cards ([#257](https://github.com/MostroP2P/app/pull/257)) by @grunch
- **disputes:** move the dispute chat onto the kind-14 envelope ([#254](https://github.com/MostroP2P/app/pull/254)) by @grunch
- **disputes:** route admin-took-dispute so the app learns the solver ([#253](https://github.com/MostroP2P/app/pull/253)) by @grunch
- **protocol:** tell the user when a node speaks a protocol we don't ([#252](https://github.com/MostroP2P/app/pull/252)) by @grunch
- **pow:** honor pow_first_contact when mining first-contact events ([#251](https://github.com/MostroP2P/app/pull/251)) by @grunch
- **chat:** migrate P2P chat to the gift-wrap-free envelope ([#247](https://github.com/MostroP2P/app/pull/247)) by @grunch
- **cashu:** C1b — persist escrow-mode overrides and surface the backend in About ([#234](https://github.com/MostroP2P/app/pull/234)) by @grunch
- **orderbook:** wire maker reputation from the Kind 38383 rating tag ([#245](https://github.com/MostroP2P/app/pull/245)) by @grunch
- **#215:** RestoreSession handshake, send, correlate reply, subscribe ([#225](https://github.com/MostroP2P/app/pull/225)) by @codaMW
- **orderbook:** pixel-exact Order Book screen from Claude Design mock #3 ([#243](https://github.com/MostroP2P/app/pull/243)) by @grunch
- **logging:** platform sinks, tracing bridge, and retroactive log buffer ([#242](https://github.com/MostroP2P/app/pull/242)) by @AndreaDiazCorreia
- **cashu:** C1a — detect the node's escrow mode from its 38385 tags ([#230](https://github.com/MostroP2P/app/pull/230)) by @grunch
- **cashu:** C0 — upgrade mostro-core to 0.14 and pin the Cashu wire form ([#229](https://github.com/MostroP2P/app/pull/229)) by @grunch
- **web:** deploy the web client to GitHub Pages on every merge to main ([#214](https://github.com/MostroP2P/app/pull/214)) by @grunch
- display the active node's bond policy in the About screen ([#207](https://github.com/MostroP2P/app/pull/207)) by @AndreaDiazCorreia
- handle bond-slashed forfeiture notices ([#200](https://github.com/MostroP2P/app/pull/200)) by @AndreaDiazCorreia
- **trades:** surface cancel/dispute/release as visible buttons ([#199](https://github.com/MostroP2P/app/pull/199)) by @BraCR10
- parse anti-abuse bond policy from kind-38385 info event ([#198](https://github.com/MostroP2P/app/pull/198)) by @AndreaDiazCorreia
- add Zapstore manifest for v2 (#156) ([#188](https://github.com/MostroP2P/app/pull/188)) by @codaMW
- make Rust crate wasm32-compatible ([#180](https://github.com/MostroP2P/app/pull/180)) by @AndreaDiazCorreia
- **transport:** switch Mostro protocol traffic to NIP-44 direct (kind 14) ([#111](https://github.com/MostroP2P/app/pull/111)) by @Catrya
- **ui:** apply Mostro UX redesign from design handoff ([#106](https://github.com/MostroP2P/app/pull/106)) by @grunch
- **nip59:** migrate gift-wrap transport to mostro-core 0.10 ([#103](https://github.com/MostroP2P/app/pull/103)) by @grunch
- **nip59:** migrate gift-wrap transport to mostro-core 0.9 ([#102](https://github.com/MostroP2P/app/pull/102)) by @grunch
- **trades:** show maker orders in My Trades after creation ([`a3e68be`](https://github.com/MostroP2P/app/commit/a3e68be))
- wire P2P chat bridge (send, receive, chat rooms list) ([#95](https://github.com/MostroP2P/app/pull/95)) by @app/mostronatorcoder
- **notifications:** wire Firebase/FCM push notifications and sembast ([#94](https://github.com/MostroP2P/app/pull/94)) by @grunch
- **settings:** persist Mostro node selection and skip rating in priv… ([#93](https://github.com/MostroP2P/app/pull/93)) by @grunch
- **disputes:** derive adminSharedKey and implement evidence submission ([#92](https://github.com/MostroP2P/app/pull/92)) by @grunch
- **messages:** implement Blossom upload/download with Kind-24242 auth ([#91](https://github.com/MostroP2P/app/pull/91)) by @grunch
- wire relay toggle, mostro node selector, log stream, and disput… ([#90](https://github.com/MostroP2P/app/pull/90)) by @grunch
- **nwc:** wire payment and invoice widgets to Rust bridge ([#89](https://github.com/MostroP2P/app/pull/89)) by @grunch
- **nwc:** implement real NIP-47 Nostr Wallet Connect client ([#88](https://github.com/MostroP2P/app/pull/88)) by @grunch
- implement V1 flow gaps — dispute, invoice, countdown, UI polish ([#87](https://github.com/MostroP2P/app/pull/87)) by @grunch
- **about:** implement About screen per v1 spec ([#84](https://github.com/MostroP2P/app/pull/84)) by @grunch
- implement all wired TODOs across Rust and Dart layers ([#82](https://github.com/MostroP2P/app/pull/82)) by @grunch
- **desktop:** add primary navigation to persistent sidebar ([#79](https://github.com/MostroP2P/app/pull/79)) by @grunch
- **theme:** remove screen transition animations ([`1699b62`](https://github.com/MostroP2P/app/commit/1699b62))
- **trades:** wire My Trades screen to real DB data with live status ([#77](https://github.com/MostroP2P/app/pull/77)) by @grunch
- **orders:** implement take-sell order flow with LN address support ([#75](https://github.com/MostroP2P/app/pull/75)) by @grunch
- **account:** wire mnemonic import, fix dialog crashes, selectable w… ([#73](https://github.com/MostroP2P/app/pull/73)) by @grunch
- **l10n:** add backupConfirmCheckbox key to all 5 locales ([#74](https://github.com/MostroP2P/app/pull/74)) by @grunch
- **final-phase:** polish & cross-cutting ([#69](https://github.com/MostroP2P/app/pull/69)) by @grunch
- **phase17:** account & identity management ([#68](https://github.com/MostroP2P/app/pull/68)) by @grunch
- **phase16:** settings & preferences — settings API, screens ... ([#67](https://github.com/MostroP2P/app/pull/67)) by @grunch
- **phase15:** notifications center — card widget, Sembast ... ([#66](https://github.com/MostroP2P/app/pull/66)) by @grunch
- **phase14:** NWC wallet integration — connect, settings, auto-pa ([#65](https://github.com/MostroP2P/app/pull/65)) by @grunch
- **us10:** phase 13 — post-trade rating system ([#64](https://github.com/MostroP2P/app/pull/64)) by @grunch
- **us9:** phase 12 — dispute system, admin chat, dispute list ([#63](https://github.com/MostroP2P/app/pull/63)) by @grunch
- **us12:** phase 11 — My Trades screen, list item, providers ([#61](https://github.com/MostroP2P/app/pull/61)) by @grunch
- **us8:** phase 10 — encrypted P2P chat, Blossom, nym avatar ([#60](https://github.com/MostroP2P/app/pull/60)) by @grunch
- **us6:** phase 8 — buyer trade flow, invoice screens, trade detail ([#57](https://github.com/MostroP2P/app/pull/57)) by @grunch
- **phase2b:** default configuration — relay seeds, Mostro node constants ([`01798da`](https://github.com/MostroP2P/app/commit/01798da))
- **us2:** phase 4 — secret words backup & notification bell ([#53](https://github.com/MostroP2P/app/pull/53)) by @grunch
- **us1:** phase 3 — first launch & identity setup ([#52](https://github.com/MostroP2P/app/pull/52)) by @grunch
- **foundation:** phase 2 — foundational infrastructure ([#51](https://github.com/MostroP2P/app/pull/51)) by @grunch
- **setup:** phase 1 — project initialization ([#50](https://github.com/MostroP2P/app/pull/50)) by @grunch
- implement Phase 1 & Phase 2 — Flutter+Rust scaffold and core in… ([#37](https://github.com/MostroP2P/app/pull/37)) by @grunch
- add Nostr-based exchange rates spec for v2 ([#36](https://github.com/MostroP2P/app/pull/36)) by @app/mostronatorcoder
- add settings, nym identity, and node selector contracts ([#17](https://github.com/MostroP2P/app/pull/17)) by @grunch
- add drawer menu, Account, Settings, About screen specs ([#10](https://github.com/MostroP2P/app/pull/10)) by @app/mostronatorcoder
- add anonymous chat identity (nym) system to spec ([#9](https://github.com/MostroP2P/app/pull/9)) by @app/mostronatorcoder

### 🐛 Bug Fixes

- **relay:** keep long-lived subscriptions alive across offline resumes ([#497](https://github.com/MostroP2P/app/pull/497)) by @grunch
- **settings:** lightning address save no longer crashes with a red screen ([#481](https://github.com/MostroP2P/app/pull/481)) by @grunch
- keep the automation contract whole through the bond flows ([#469](https://github.com/MostroP2P/app/pull/469)) by @grunch
- **#417:** a lost take returns to the ex-taker's book, one trade row per order ([#419](https://github.com/MostroP2P/app/pull/419)) by @Catrya
- classify the missing trade row instead of writing to nothing ([#412](https://github.com/MostroP2P/app/pull/412)) by @Forte11Cuba
- **#404:** cover every locale tag the sanitizer handles, and what it leaves behind ([#406](https://github.com/MostroP2P/app/pull/406)) by @Matobi98
- **home:** tint the selected Sell BTC tab coral ([#427](https://github.com/MostroP2P/app/pull/427)) by @grunch
- **orders:** publish the book on EOSE so an empty book leaves the skeleton ([#426](https://github.com/MostroP2P/app/pull/426)) by @grunch
- **orders:** re-target live subscriptions on node switch ([#423](https://github.com/MostroP2P/app/pull/423)) by @grunch
- **#335:** replace-not-discard the session on a confirmed retake ([#375](https://github.com/MostroP2P/app/pull/375)) by @Matobi98
- **ios:** apply Runner.entitlements to the Runner target ([#399](https://github.com/MostroP2P/app/pull/399)) by @Pivii
- **ios:** declare NSCameraUsageDescription ([#398](https://github.com/MostroP2P/app/pull/398)) by @Pivii
- **web:** sanitize unparseable browser locale before engine bootstrap ([#370](https://github.com/MostroP2P/app/pull/370)) by @Matobi98
- **relay:** close per-trade and per-order subscriptions on task exit ([#365](https://github.com/MostroP2P/app/pull/365)) by @grunch
- **orders:** refuse status writes from an out-of-order kind-14 replay ([#396](https://github.com/MostroP2P/app/pull/396)) by @Catrya
- **disputes:** persist the origin marker on a late-accepted open ([#388](https://github.com/MostroP2P/app/pull/388)) by @grunch
- persist counterparty pubkey so the maker's chat resolves the peer ([#347](https://github.com/MostroP2P/app/pull/347)) by @Forte11Cuba
- persist counterparty pubkey and create the maker's session at peer reveal ([#345](https://github.com/MostroP2P/app/pull/345)) by @Forte11Cuba
- **memory:** drop strangers' finished orders instead of keeping them ([#363](https://github.com/MostroP2P/app/pull/363)) by @grunch
- **ui:** let the order-book pipeline dispose with the home screen ([#356](https://github.com/MostroP2P/app/pull/356)) by @grunch
- **relay:** broadcast connection state only when it actually changes ([#364](https://github.com/MostroP2P/app/pull/364)) by @grunch
- **nostr:** scope the order-book query so relay replay caps cannot hide the book ([#379](https://github.com/MostroP2P/app/pull/379)) by @grunch
- **logging:** relay payloads leaked after the 0.45 bump, plus the SDK claims it left stale ([#386](https://github.com/MostroP2P/app/pull/386)) by @grunch
- **storage:** key notifications by id and commit bulk updates once ([#368](https://github.com/MostroP2P/app/pull/368)) by @grunch
- **observability:** log order-book stream lag ([#355](https://github.com/MostroP2P/app/pull/355)) by @grunch
- **perf:** publish the order book once per refetch, not once per event ([#360](https://github.com/MostroP2P/app/pull/360)) by @grunch
- **ui:** build each theme once and make push init idempotent ([#358](https://github.com/MostroP2P/app/pull/358)) by @grunch
- **perf:** stop cloning the whole trade-key map per daemon message ([#353](https://github.com/MostroP2P/app/pull/353)) by @grunch
- **perf:** make daemon-message dedup a hash lookup ([#352](https://github.com/MostroP2P/app/pull/352)) by @grunch
- **db:** apply SQLite pragmas per connection, not once per pool ([#351](https://github.com/MostroP2P/app/pull/351)) by @grunch
- **db:** index the trade lookups that run once per order event ([#350](https://github.com/MostroP2P/app/pull/350)) by @grunch
- **#202:** wait for the daemon reply before persisting a dispute ([#275](https://github.com/MostroP2P/app/pull/275)) by @AndreaDiazCorreia
- **perf:** stop logging at info level once per ingested order ([#349](https://github.com/MostroP2P/app/pull/349)) by @grunch
- persist rated_at marker so the rated state survives a restart ([#342](https://github.com/MostroP2P/app/pull/342)) by @Forte11Cuba
- **orders:** don't let fingerprint restore clobber the trade-key index ([#332](https://github.com/MostroP2P/app/pull/332)) by @Forte11Cuba
- **#259:** serialize daemon message dispatch and take persistence per order id ([#331](https://github.com/MostroP2P/app/pull/331)) by @AndreaDiazCorreia
- **#327:** make the rated trade state reachable ([#330](https://github.com/MostroP2P/app/pull/330)) by @AndreaDiazCorreia
- **tests:** implement update_trade_peer_reputation on the FailingStore stub ([#329](https://github.com/MostroP2P/app/pull/329)) by @Catrya
- **order:** prevent fixed price on range orders ([#323](https://github.com/MostroP2P/app/pull/323)) by @Forte11Cuba
- **order:** allow premium outside the default range when creating an order ([#317](https://github.com/MostroP2P/app/pull/317)) by @Forte11Cuba
- **#267:** add bottom SafeArea insets so the system bar doesn't overlap content ([#295](https://github.com/MostroP2P/app/pull/295)) by @codaMW
- **home:** own orders follow the tab split, with readable pills ([#293](https://github.com/MostroP2P/app/pull/293)) by @Catrya
- **orders:** rehydrate kind-14 decryption coverage at startup ([#292](https://github.com/MostroP2P/app/pull/292)) by @Catrya
- **orders:** handle inbound add-invoice in the kind-14 ingest ([#288](https://github.com/MostroP2P/app/pull/288)) by @Catrya
- **order:** back from invoice screens lands on trade detail ([#278](https://github.com/MostroP2P/app/pull/278)) by @Catrya
- **#203:** stop the public order status from driving trade actions ([#271](https://github.com/MostroP2P/app/pull/271)) by @AndreaDiazCorreia
- detect waiting-state timeouts and clean up local state ([#274](https://github.com/MostroP2P/app/pull/274)) by @Catrya
- **order-book:** parse every payment method from the multi-value pm tag ([#262](https://github.com/MostroP2P/app/pull/262)) by @Catrya
- **deps:** pin permission_handler_html to 0.1.3+5 ([#260](https://github.com/MostroP2P/app/pull/260)) by @Catrya
- **identity:** keep the trade-key counter durable outside mostro.db ([#250](https://github.com/MostroP2P/app/pull/250)) by @grunch
- **storage:** keep the Linux databases out of the user's Documents folder ([#248](https://github.com/MostroP2P/app/pull/248)) by @grunch
- **#223:** backup verify, redirect to 12 words after second wrong pick ([#224](https://github.com/MostroP2P/app/pull/224)) by @codaMW
- **web:** route wall-clock time through rt so wasm does not panic ([#211](https://github.com/MostroP2P/app/pull/211)) by @grunch
- **web:** convert PlatformInt64 fields before using them as int ([#209](https://github.com/MostroP2P/app/pull/209)) by @grunch
- **i18n:** complete UI localization and harden locale fallback ([#201](https://github.com/MostroP2P/app/pull/201)) by @AndreaDiazCorreia
- resolve flutter analyze lints ([#179](https://github.com/MostroP2P/app/pull/179)) by @AndreaDiazCorreia
- take_order and send_invoice wait for daemon confirmation ([#178](https://github.com/MostroP2P/app/pull/178)) by @Catrya
- correlate create_order replies by request_id and stop stale relay replay ([#172](https://github.com/MostroP2P/app/pull/172)) by @Catrya
- persist trade key index at derivation so the counter never regresses ([#171](https://github.com/MostroP2P/app/pull/171)) by @Catrya
- **orders:** parse multi-value fa tag so range orders show min–max ([#167](https://github.com/MostroP2P/app/pull/167)) by @Catrya
- Mostro node selection now takes effect, persists, and refreshes the order book ([#164](https://github.com/MostroP2P/app/pull/164)) by @Catrya
- phantom orders in order book and My Trades on daemon timeout ([#159](https://github.com/MostroP2P/app/pull/159)) by @Catrya
- **nip59:** authenticate daemon via seal identity, not rumor sender ([#104](https://github.com/MostroP2P/app/pull/104)) by @grunch
- **orders:** seller pay-invoice flow, NIP-13 PoW, order ID reconcilia… ([#99](https://github.com/MostroP2P/app/pull/99)) by @grunch
- **trades:** cancel order updates status, unify detail screens ([#97](https://github.com/MostroP2P/app/pull/97)) by @grunch
- **trades:** sync maker trade status and hold invoice from daemon ([#96](https://github.com/MostroP2P/app/pull/96)) by @grunch
- **db:** migrate trades table from v1 to v2 schema on open ([`83eab87`](https://github.com/MostroP2P/app/commit/83eab87))
- **trades:** remove spurious badge dot and pending status flash ([#86](https://github.com/MostroP2P/app/pull/86)) by @grunch
- **settings:** persist user preferences across app restarts ([#85](https://github.com/MostroP2P/app/pull/85)) by @grunch
- **web:** resolve dart2js compile errors for flutter build web ([#83](https://github.com/MostroP2P/app/pull/83)) by @grunch
- **order-book:** subscribe to all orders so status changes are receiv… ([#78](https://github.com/MostroP2P/app/pull/78)) by @grunch
- **order-book:** hide non-pending orders from the order book ([`95d411c`](https://github.com/MostroP2P/app/commit/95d411c))
- **router:** eliminate first-run race condition on startup ([#72](https://github.com/MostroP2P/app/pull/72)) by @grunch
- **review:** loading state for unresolved amountSats, guard overlapping order polls ([`71c3ab7`](https://github.com/MostroP2P/app/commit/71c3ab7))
- **android:** 16 KB page-size alignment for librust.so ([#62](https://github.com/MostroP2P/app/pull/62)) by @app/mostronatorcoder
- set bundle ID to foundation.mostro.app ([#58](https://github.com/MostroP2P/app/pull/58)) by @app/mostronatorcoder
- rewrite ORDER_BOOK.md Order List Item with correct card layout ([#43](https://github.com/MostroP2P/app/pull/43)) by @app/mostronatorcoder
- correct v1-reference docs (BIP-39 mnemonic and encrypted messaging) ([#25](https://github.com/MostroP2P/app/pull/25)) by @Catrya
- PaymentFailed is an Action, not a Status ([#15](https://github.com/MostroP2P/app/pull/15)) by @app/mostronatorcoder
- disputes only available in active/fiat-sent states ([#13](https://github.com/MostroP2P/app/pull/13)) by @app/mostronatorcoder
- ORDER_STATES.md post-merge corrections ([#12](https://github.com/MostroP2P/app/pull/12)) by @grunch

### ⚡ Performance

- **relay:** PR 3.6 + the 2.5 gap — batch key derivation, coalesced DM filter and Online sync ([#493](https://github.com/MostroP2P/app/pull/493)) by @grunch
- **trades:** finish PR 3.4 — trade screens follow a doorbell, not a poll ([#492](https://github.com/MostroP2P/app/pull/492)) by @grunch
- instant trade status — push-driven UI and first-OK publish ([#488](https://github.com/MostroP2P/app/pull/488)) by @grunch
- **ui:** repaint the countdown, not the screen, once a second ([#367](https://github.com/MostroP2P/app/pull/367)) by @grunch
- **ui:** build the order card's number formatters once per locale ([#357](https://github.com/MostroP2P/app/pull/357)) by @grunch
- **bridge:** coalesce relay-driven book updates into one emission ([#377](https://github.com/MostroP2P/app/pull/377)) by @Catrya
- **ui:** look orders up by id instead of scanning the whole book ([#366](https://github.com/MostroP2P/app/pull/366)) by @grunch
- **ingest:** cache trade-key misses so strangers' orders skip the DB ([#362](https://github.com/MostroP2P/app/pull/362)) by @grunch
- **chat:** O(1) dedupe, debounced mark-read, and no scroll hijack ([#369](https://github.com/MostroP2P/app/pull/369)) by @grunch

### ♻️ Refactoring

- **invoice:** one judge for payment destinations, in Rust ([#441](https://github.com/MostroP2P/app/pull/441)) by @grunch
- **keys:** let deriving be the mnemonic validation, and parse once ([#387](https://github.com/MostroP2P/app/pull/387)) by @grunch
- **orders:** move the request registry and status rules off the bridge ([#312](https://github.com/MostroP2P/app/pull/312)) by @grunch
- name the v2 transport for what it is ([#313](https://github.com/MostroP2P/app/pull/313)) by @grunch
- drop every protocol-v1 gift-wrap path ([#311](https://github.com/MostroP2P/app/pull/311)) by @grunch

### 📚 Documentation

- **perf:** status of the optimization plan; web persistence is no longer a stub ([#491](https://github.com/MostroP2P/app/pull/491)) by @grunch
- **push:** status after the push plan landed; v1 reference pointer ([#486](https://github.com/MostroP2P/app/pull/486)) by @grunch
- **push:** PR-6 — gotchas, spec final pass, dispute chat must wake ([#485](https://github.com/MostroP2P/app/pull/485)) by @grunch
- **push:** bring web push into scope ([#465](https://github.com/MostroP2P/app/pull/465)) by @grunch
- **push:** spec and phased plan for push notifications ([#462](https://github.com/MostroP2P/app/pull/462)) by @grunch
- **bond:** anti-abuse bond client spec and phased implementation plan ([#437](https://github.com/MostroP2P/app/pull/437)) by @grunch
- **specs:** drop the shared-key display from the user info panel scope ([#416](https://github.com/MostroP2P/app/pull/416)) by @grunch
- **plan:** record why infinite scroll does not apply to the order book ([#374](https://github.com/MostroP2P/app/pull/374)) by @grunch
- **specs:** sync and reorganize tasks.md for 004 and 005 ([#340](https://github.com/MostroP2P/app/pull/340)) by @Matobi98
- note that generated code goes stale on pull, not just on edit ([#359](https://github.com/MostroP2P/app/pull/359)) by @grunch
- phased performance and scalability optimization plan ([#348](https://github.com/MostroP2P/app/pull/348)) by @grunch
- **readme:** list supported NIPs and BUDs ([#336](https://github.com/MostroP2P/app/pull/336)) by @Matobi98
- **readme:** add Linux desktop toolchain to prerequisites ([#315](https://github.com/MostroP2P/app/pull/315)) by @Forte11Cuba
- specify an authenticated announcement channel + fix the app version it targets ([#318](https://github.com/MostroP2P/app/pull/318)) by @grunch
- add security policy ([#285](https://github.com/MostroP2P/app/pull/285)) by @AndreaDiazCorreia
- **cashu:** state the real goal — a user-selectable backend, not a test harness ([#232](https://github.com/MostroP2P/app/pull/232)) by @grunch
- **cashu:** client-side Cashu escrow spec ([#228](https://github.com/MostroP2P/app/pull/228)) by @grunch
- add design mocks for low-priority issues #126 #127 #128 #129 #131 #132 #139 #149 ([#185](https://github.com/MostroP2P/app/pull/185)) by @grunch
- add AGENTS.md and CONTRIBUTING.md ([#186](https://github.com/MostroP2P/app/pull/186)) by @grunch
- add design mocks for medium-priority issues #115 #124 #125 #130 #136 #140 ([#184](https://github.com/MostroP2P/app/pull/184)) by @grunch
- add design mocks for backlog issues #134 #135 #142 #143 #145 ([#183](https://github.com/MostroP2P/app/pull/183)) by @grunch
- **readme:** Add progress Overview and rename to "Mostro App" ([#165](https://github.com/MostroP2P/app/pull/165)) by @Catrya
- **claude:** rewrite CLAUDE.md as hand-maintained project guidelines ([#161](https://github.com/MostroP2P/app/pull/161)) by @Catrya
- sync specs to transport v2 and document order-creation timeout ([#160](https://github.com/MostroP2P/app/pull/160)) by @Catrya
- **tasks:** sync 004 status markers with implemented code ([#113](https://github.com/MostroP2P/app/pull/113)) by @Catrya
- **readme:** update for transport v2 and fix stale references ([#112](https://github.com/MostroP2P/app/pull/112)) by @Catrya
- **transport-v2:** add migration reference and implementation plan ([#109](https://github.com/MostroP2P/app/pull/109)) by @Catrya
- **v1-reference:** add anti-abuse bond reference ([#108](https://github.com/MostroP2P/app/pull/108)) by @Catrya
- **readme:** sync dependency versions and update setup instructions ([#105](https://github.com/MostroP2P/app/pull/105)) by @Catrya
- sync v1-reference (multi-mostro, disputes, relay sync) ([#107](https://github.com/MostroP2P/app/pull/107)) by @Catrya
- add comprehensive README and MIT license ([`2821ff3`](https://github.com/MostroP2P/app/commit/2821ff3))
- set app bundle ID to foundation.mostro.app ([#47](https://github.com/MostroP2P/app/pull/47)) by @app/mostronatorcoder
- **constitution:** V1 Flow Guide as Core Principle VII ([#46](https://github.com/MostroP2P/app/pull/46)) by @app/mostronatorcoder
- **constitution:** V1 Flow Guide as mandatory speckit ground truth ([#45](https://github.com/MostroP2P/app/pull/45)) by @app/mostronatorcoder
- add mandatory DESIGN_SYSTEM.md warning to V1 Flow Guide ([#44](https://github.com/MostroP2P/app/pull/44)) by @app/mostronatorcoder
- clarify dispute status taxonomy in DISPUTE_SYSTEM.md ([#41](https://github.com/MostroP2P/app/pull/41)) by @Catrya
- V1 Flow Guide for speckit reference ([#42](https://github.com/MostroP2P/app/pull/42)) by @app/mostronatorcoder
- update FCM implementation to reflect actual behavior ([#40](https://github.com/MostroP2P/app/pull/40)) by @AndreaDiazCorreia
- add branch protection rules documentation ([#38](https://github.com/MostroP2P/app/pull/38)) by @app/mostronatorcoder
- add Core Services specs (MostroService, ExchangeService, EncryptionService) ([#35](https://github.com/MostroP2P/app/pull/35)) by @app/mostronatorcoder
- comprehensive rewrite of Logging System spec ([#34](https://github.com/MostroP2P/app/pull/34)) by @app/mostronatorcoder
- add Notifications System comprehensive spec ([#33](https://github.com/MostroP2P/app/pull/33)) by @app/mostronatorcoder
- add Settings and Notification Settings specs ([#32](https://github.com/MostroP2P/app/pull/32)) by @app/mostronatorcoder
- add NWC cross-references across v1-reference specs ([#31](https://github.com/MostroP2P/app/pull/31)) by @app/mostronatorcoder
- translate Spanish text to English in v1-reference specs ([#30](https://github.com/MostroP2P/app/pull/30)) by @app/mostronatorcoder
- add rating system spec ([#28](https://github.com/MostroP2P/app/pull/28)) by @app/mostronatorcoder
- add dispute system spec ([#27](https://github.com/MostroP2P/app/pull/27)) by @grunch
- expand peer-to-peer chat spec ([#26](https://github.com/MostroP2P/app/pull/26)) by @app/mostronatorcoder
- add MY_TRADES.md spec ([#24](https://github.com/MostroP2P/app/pull/24)) by @app/mostronatorcoder
- add TRADE_EXECUTION.md spec ([#23](https://github.com/MostroP2P/app/pull/23)) by @app/mostronatorcoder
- add TAKE_ORDER.md spec ([#22](https://github.com/MostroP2P/app/pull/22)) by @app/mostronatorcoder
- HOME, NAVIGATION, ORDER_BOOK & ORDER_CREATION specs ([#21](https://github.com/MostroP2P/app/pull/21)) by @app/mostronatorcoder
- HOME & NAVIGATION specs ([#20](https://github.com/MostroP2P/app/pull/20)) by @app/mostronatorcoder
- add AUTHENTICATION.md - v1 reference spec ([#19](https://github.com/MostroP2P/app/pull/19)) by @app/mostronatorcoder
- fix order state transitions and improve documentation accuracy ([#18](https://github.com/MostroP2P/app/pull/18)) by @Catrya
- add comprehensive order states specification ([#11](https://github.com/MostroP2P/app/pull/11)) by @app/mostronatorcoder
- update DESIGN_SYSTEM.md with exact v1 visual specs ([#8](https://github.com/MostroP2P/app/pull/8)) by @app/mostronatorcoder
- add ARCHITECTURE.md - Rust/Dart boundary ADR ([#7](https://github.com/MostroP2P/app/pull/7)) by @app/mostronatorcoder
- add Mostro Protocol reference as critical foundation ([#3](https://github.com/MostroP2P/app/pull/3)) by @app/mostronatorcoder
- add v1 architecture reference for v2 development ([#2](https://github.com/MostroP2P/app/pull/2)) by @app/mostronatorcoder

### 🧪 Tests

- **escrow:** one lock for one global, not two racing ones ([#310](https://github.com/MostroP2P/app/pull/310)) by @grunch
- add golden tests and extract StatusChip design atom ([#187](https://github.com/MostroP2P/app/pull/187)) by @AndreaDiazCorreia
- Flutter test harness + critical notifier/filter unit tests ([#181](https://github.com/MostroP2P/app/pull/181)) by @AndreaDiazCorreia

### 👷 Build & CI

- **release:** publish a GitHub release with signed APKs when a tag is pushed ([#500](https://github.com/MostroP2P/app/pull/500)) by @grunch
- build the iOS app on every PR; raise the iOS minimum to 14.0 ([#487](https://github.com/MostroP2P/app/pull/487)) by @grunch
- bump Flutter to 3.41.9 and migrate containsSemantics to isSemantics ([#422](https://github.com/MostroP2P/app/pull/422)) by @grunch
- **#154:** run the web build on PRs and smoke-test the release bundle ([#226](https://github.com/MostroP2P/app/pull/226)) by @grunch
- add workflow to regenerate golden test images ([#189](https://github.com/MostroP2P/app/pull/189)) by @AndreaDiazCorreia
- add GitHub Actions workflow for Rust and Flutter checks ([#173](https://github.com/MostroP2P/app/pull/173)) by @AndreaDiazCorreia

### 🧹 Chores

- regenerate bindings and localizations after #475 ([#478](https://github.com/MostroP2P/app/pull/478)) by @grunch
- commit generated code and drop git hooks ([#476](https://github.com/MostroP2P/app/pull/476)) by @grunch
- install the git hooks automatically instead of by memory ([#432](https://github.com/MostroP2P/app/pull/432)) by @grunch
- relicense project under AGPLv3 or later ([#418](https://github.com/MostroP2P/app/pull/418)) by @grunch
- bump Android NDK to 28.2 and auto-regenerate bindings after pull ([#378](https://github.com/MostroP2P/app/pull/378)) by @grunch
- untrack the desktop generated plugin registrants ([#314](https://github.com/MostroP2P/app/pull/314)) by @grunch
- **l10n:** stop tracking generated localization bindings ([#276](https://github.com/MostroP2P/app/pull/276)) by @AndreaDiazCorreia
- guard flutter_rust_bridge codegen version mismatch ([#206](https://github.com/MostroP2P/app/pull/206)) by @grunch
- **clippy:** resolve warnings to enable -D warnings gate ([#166](https://github.com/MostroP2P/app/pull/166)) by @AndreaDiazCorreia
- **deps:** bump mostro-core 0.10 to 0.13.1 ([#110](https://github.com/MostroP2P/app/pull/110)) by @Catrya
- reset to clean state for 004-mostro-p2p-client ([#48](https://github.com/MostroP2P/app/pull/48)) by @grunch
- update Rust version requirement to latest stable (1.94+) ([#6](https://github.com/MostroP2P/app/pull/6)) by @app/mostronatorcoder

### 🔧 Other Changes

- Test-environment order expiry (MORTSOM_ORDER_EXPIRY_SECS) ([#413](https://github.com/MostroP2P/app/pull/413)) by @grunch
- Publish the remainder of a bought range order ([#411](https://github.com/MostroP2P/app/pull/411)) by @grunch
- Range remainders, republished maker orders and automation ids for ranges and ratings ([#410](https://github.com/MostroP2P/app/pull/410)) by @grunch
- Fix/381 session fallback ([#382](https://github.com/MostroP2P/app/pull/382)) by @Forte11Cuba
- Add opencode and qwen speckit related files ([`648adb7`](https://github.com/MostroP2P/app/commit/648adb7))
- Feat/pay with lightning wallet button ([#100](https://github.com/MostroP2P/app/pull/100)) by @grunch
- Fix/gift wrap status sync ([#98](https://github.com/MostroP2P/app/pull/98)) by @grunch
- Fix app id for linux ([`d395234`](https://github.com/MostroP2P/app/commit/d395234))
- Use default fiat from settings on create order ([`2f9f2d8`](https://github.com/MostroP2P/app/commit/2f9f2d8))
- Add locales for tradeWaitingForHoldInvoice ([`7cae35c`](https://github.com/MostroP2P/app/commit/7cae35c))
- Feat/maker order ux ([#81](https://github.com/MostroP2P/app/pull/81)) by @grunch
- Feat/create order ([#80](https://github.com/MostroP2P/app/pull/80)) by @grunch
- Feat/persistence db init ([#76](https://github.com/MostroP2P/app/pull/76)) by @grunch
- fix/add back button to order detail screen ([`6463851`](https://github.com/MostroP2P/app/commit/6463851))
- sort orders, recent first ([`14c9c59`](https://github.com/MostroP2P/app/commit/14c9c59))
- fix/shimmer skeleton ([`93caf47`](https://github.com/MostroP2P/app/commit/93caf47))
- fix/add missing import ([`9156fe7`](https://github.com/MostroP2P/app/commit/9156fe7))
- Update dependency ([#71](https://github.com/MostroP2P/app/pull/71)) by @grunch
- Fix readme ([`50a4134`](https://github.com/MostroP2P/app/commit/50a4134))
- Fix german text ([`a92299f`](https://github.com/MostroP2P/app/commit/a92299f))
- spec(phase18): add real order book bridge + shimmer loading phase ([#70](https://github.com/MostroP2P/app/pull/70)) by @grunch
- 004 mostro p2p client ([#59](https://github.com/MostroP2P/app/pull/59)) by @grunch
- Phase 7 ([#56](https://github.com/MostroP2P/app/pull/56)) by @grunch
- phase 6 ([#55](https://github.com/MostroP2P/app/pull/55)) by @grunch
- 004 mostro p2p client ([#54](https://github.com/MostroP2P/app/pull/54)) by @grunch
- Cleaning all implementation files ([#49](https://github.com/MostroP2P/app/pull/49)) by @grunch
- Phase 3: User Story 3 — Onboarding & Identity Setup ([#39](https://github.com/MostroP2P/app/pull/39)) by @grunch
- Finished speckit tasks ([`e721e44`](https://github.com/MostroP2P/app/commit/e721e44))
- Move CURRENT_FEATURES.md to v1-reference ([`d5522ed`](https://github.com/MostroP2P/app/commit/d5522ed))
- Fix constitution ([`77116ce`](https://github.com/MostroP2P/app/commit/77116ce))
- New features from v1-reference ([#16](https://github.com/MostroP2P/app/pull/16)) by @grunch
- Dispute is only available on fiatsent or active ([#14](https://github.com/MostroP2P/app/pull/14)) by @grunch
- added reference to ARCHITECTURE.md for boundary rules, ([`a5b2e1e`](https://github.com/MostroP2P/app/commit/a5b2e1e))
- plan: update artifacts for 15 states, range orders, and regenerate tasks ([#5](https://github.com/MostroP2P/app/pull/5)) by @grunch
- Add dark/light theme ([#4](https://github.com/MostroP2P/app/pull/4)) by @grunch
- Add specs ([#1](https://github.com/MostroP2P/app/pull/1)) by @grunch
- first commit ([`cbba9ce`](https://github.com/MostroP2P/app/commit/cbba9ce))
