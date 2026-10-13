# Order links (`mostro:`)

A node writes a link to every pending order into the order's Kind 38383
`source` tag (mostro `src/nip33.rs`, `create_source_tag`):

```text
mostro:<order-id>?relays=<relay>,<relay>&mostro=<node pubkey>
```

Nostr clients that show NIP-69 orders render it as a link, and opening it
opens the order in Mostro. v1 handled the same links (`MostroP2P/mobile`,
`docs/DEEP_LINK_MOSTRO_SWITCH.md`, issue mobile#541); this is that feature on
v2's split — the link is read and the order looked up in Rust, the screens and
the OS hand-off are Dart.

## The link

- `mostro=` names the node that published the order: 64 hex characters, as the
  daemon writes it, or an `npub`. Daemons before mostro#678 leave it out, and
  the link is then the active node's, as in v1.
- `relays=` lists where the node publishes. It may be missing.

`OrderLink::parse` (`rust/src/nostr/order_link.rs`) is lenient about what a link
goes through on its way here — case, `mostro://` instead of `mostro:`, a
trailing slash, percent-encoding — and strict about what decides which order
is shown: the id must be a UUID, and a `mostro=` that is present must be a key.
A link whose node cannot be read is refused, never taken for the active node's.

A link's relays are asked before the user has said anything, and anyone can
write a link, so only public relays over TLS are kept: `wss://` to a host that
is not loopback, link-local, a private network or a `.local`-style name. That
keeps a link from making the app knock on the user's own machine or network. At
most eight are kept. A node on a private network (a test setup) is still found
through the pool's relays.

## Opening one

1. **The OS hands the link over.** `app_links` delivers it, including the link
   that launched the app. `DeepLinkListener` (`lib/features/deep_links/`, around
   the app root) sends `mostro:` links to `/order_link?link=…`. A link that
   arrives during the first run waits for it to end, and the same link twice
   within two seconds opens once. Flutter's own deep linking is off on Android
   and iOS, so go_router never receives the URI as a route.
2. **The order is looked up** (`resolve_order_link`, `rust/src/api/order_link.rs`):
   the newest revision of the Kind 38383 event the node signed for exactly that
   id, from the pool and the link's relays at once. Author, kind and `d` tag are
   checked again whatever the relay did with the filter. The link's relays are
   asked through a short-lived client of their own and **never join the pool**:
   a link adds no relay to the user's list, and the long-lived subscriptions
   (`nostr::live_subs`) are never issued on them. On the active node the event
   is also filed in the order book, through the live subscription's path
   (`ingest_order_event`), so Take Order shows it at once.
3. **An order on another node** changes nothing until the user agrees. The
   dialog names the node as the registry does, or by its key. A node outside
   the registry — neither trusted nor added — comes with a warning, since only
   the link vouches for it; a trade in progress is named as Settings names it.
   Agreeing takes the Settings path (`selectNode`), then the link is resolved
   again.
4. **Where it leads** (`orderLinkDestination`): a user who takes part in the
   order goes to the trade; a pending order opens the take screen of its side;
   anything else says the order is no longer available. The link screen
   replaces itself with its destination, so back returns to where the user was.

A link the core cannot read (`InvalidOrderLink`) and an order that left the
book are told with nothing to retry; an order no relay answered with
(`OrderLinkNotFound`) and a failed node change offer a retry.

What a link's relays return is signed by the node, so it is never forged, but
it can be old: a relay may hold back the revision that took the order. Taking
it is still the daemon's to accept, and the book keeps only the newest
revision, so the take screen shows the newer one as soon as the node's relays
deliver it.

## Platforms

| Platform | Registration | Notes |
|---|---|---|
| Android | `mostro` intent filter on the activity; `flutter_deeplinking_enabled` off | |
| iOS | `CFBundleURLTypes`; `FlutterDeepLinkingEnabled` off | |
| macOS | `CFBundleURLTypes` | |
| Linux | `MimeType=x-scheme-handler/mostro;` and `Exec=… %u` in the desktop entry `install.sh` adds, which also makes Mostro the scheme's default (`xdg-mime default`) | A release or profile build is single-instance: a link opened while it runs goes to the running window, and launching it again brings that window forward. |
| Windows | A release or profile build registers `HKCU\Software\Classes\mostro` at every start: the release is a zip with no installer | Single-instance too: `SendAppLink` hands the link to the running window. |
| Web | none | A page cannot handle `mostro:`: browsers let a page register `web+` schemes only. |

A **debug** build on Linux and Windows takes no part in that: it is never
single-instance, so `flutter run` keeps working next to an open release build,
and on Windows it does not claim the scheme, so the user's links keep opening
the release. It still reads a link it is started with (`./mostro '<link>'`).
Handing a link to a running window takes a release or profile build.

`test/ci/order_link_scheme_test.dart` holds these registrations.

## Trying it

Take a real link from the `source` tag of a pending order — any client that
shows Kind 38383 events has it — then:

- Android: `adb shell am start -a android.intent.action.VIEW -d '<link>'`
- iOS simulator: `xcrun simctl openurl booted '<link>'`
- macOS: `open '<link>'`
- Linux: run `install.sh` from a release bundle, then `xdg-open '<link>'`; or
  pass the link to the binary, `./mostro '<link>'`, with or without Mostro
  running.
- Windows: start a release build once, so it registers the scheme, then
  `start "" "<link>"` from `cmd`.

## The `app_links` version

Pinned to 6.x: 7.0 needs Dart 3.10, above the 3.7 this app still supports
(`pubspec.yaml`), and 7.1 and later need Flutter 3.44, above the one it builds
with. 6.4.1's Windows plugin reads a `WM_COPYDATA` message
without bounding it (fixed in 7.1.2), so another program of the same user could
crash Mostro by sending one. Move to 7.x with the Flutter upgrade; its Windows
setup then exports `SendAppLinkToInstance`, which replaces the runner's own.
