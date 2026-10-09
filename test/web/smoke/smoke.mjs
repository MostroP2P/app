#!/usr/bin/env node
// Headless-Chrome smoke test for the release web bundle (issue #154).
//
// The static guards around this bundle — the "Verify bundle" step in
// web-build.yml and test/web/pages_bundle_test.dart — only grep files. Every
// blank-page cause documented in CLAUDE.md under "Web (wasm) — non-obvious
// constraints" greps perfectly clean and fails at runtime, so this test loads
// the real artifact in a real browser and asserts it is alive:
//
//   1. the page is cross-origin isolated  (no SharedArrayBuffer → no wasm threads)
//   2. the Flutter engine mounted         (the view element exists)
//   3. startup finished                   (Rust bridge answered, nothing fatal after it)
//  3b. seeded bond rows read back         (opt-in: SMOKE_BOND_STORE=1)
//  3d. an attachment upload + read-back   (opt-in: SMOKE_ATTACHMENTS=1)
//  3e. Chrome would install it as an app (opt-in: SMOKE_INSTALLABLE=1)
//   4. nothing errored along the way      (console + uncaught page errors)
//   5. every asset the page asked for was served (catches --base-href breakage)
//
// (3) is what separates this from a "did the HTML load" test: a DataCloneError
// kills the worker pool while the DOM still looks perfectly healthy.
//
// The bundle is served with COOP/COEP set directly rather than through
// web/coi-serviceworker.min.js. The shim only registers when the headers are
// absent and takes effect one load late, which would make a first-load
// assertion flaky; serving the headers reaches the same isolated state
// deterministically. That is also why the shim is inert here — it is covered
// statically by pages_bundle_test.dart instead.
//
// Usage:
//   BUNDLE_DIR=../../../build/web BASE_PATH=/app/ node smoke.mjs

import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const here = dirname(fileURLToPath(import.meta.url));

/** The bundle under test. Must be the release build that actually ships. */
const BUNDLE_DIR = resolve(process.env.BUNDLE_DIR || join(here, '../../../build/web'));

/**
 * Sub-path the bundle is served from, matching production (`/app/`). Serving
 * from the root instead would let a broken `--base-href` pass here and fail
 * only once deployed to Pages.
 */
const BASE_PATH = process.env.BASE_PATH || '/app/';

/** Generous: a cold CI runner instantiates the wasm core before anything runs. */
const TIMEOUT_MS = Number(process.env.SMOKE_TIMEOUT_MS || 120_000);

const MIME = {
  '.bin': 'application/octet-stream',
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.otf': 'font/otf',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.symbols': 'text/plain; charset=utf-8',
  '.ttf': 'font/ttf',
  '.wasm': 'application/wasm',
  '.woff2': 'font/woff2',
};

/**
 * Console/page errors that say nothing about the bundle.
 *
 * The app dials real Nostr relays on startup; one being unreachable from a CI
 * runner is a fact about the internet, not about this build. Keep this list
 * narrow — anything broader hides the failures this test exists to catch.
 * Ignored entries are still printed.
 */
const IGNORABLE = [/WebSocket connection to 'wss:\/\//i, /favicon\.ico/i];

const isIgnorable = (text) => IGNORABLE.some((re) => re.test(text));

/** Frames printed per uncaught error; a wasm trap's culprit sits near the top. */
const MAX_STACK_FRAMES = 25;

/** The `at …` lines of an error's stack, without the message line it repeats. */
const stackFrames = (stack) =>
  (stack ?? '')
    .split('\n')
    .filter((line) => /^\s+at /.test(line))
    .slice(0, MAX_STACK_FRAMES)
    .map((line) => line.trim());

/**
 * Serves BUNDLE_DIR under BASE_PATH, cross-origin isolated.
 *
 * Every request it cannot satisfy is pushed to [misses]: a page whose
 * `--base-href` was not rewritten asks for `/main.dart.js` instead of
 * `/app/main.dart.js`, and that miss is the earliest unambiguous signal of it.
 */
function serveBundle(misses) {
  const server = createServer(async (req, res) => {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);

    const send = (status, body, type) => {
      res.writeHead(status, {
        'Content-Type': type || 'text/plain; charset=utf-8',
        // The whole point: SharedArrayBuffer, and therefore wasm threads.
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'require-corp',
        'Cross-Origin-Resource-Policy': 'same-origin',
        'Cache-Control': 'no-store',
      });
      res.end(body);
    };

    if (!pathname.startsWith(BASE_PATH)) {
      misses.push(pathname);
      return send(404, `outside ${BASE_PATH}`);
    }

    let rel = pathname.slice(BASE_PATH.length);
    if (rel === '' || rel.endsWith('/')) rel += 'index.html';

    // Containment check: normalize collapses any ../ before we touch the disk.
    const file = normalize(join(BUNDLE_DIR, rel));
    if (!file.startsWith(BUNDLE_DIR)) {
      misses.push(pathname);
      return send(403, 'forbidden');
    }

    try {
      const body = await readFile(file);
      send(200, body, MIME[extname(file).toLowerCase()]);
    } catch {
      misses.push(pathname);
      send(404, 'not found');
    }
  });

  return new Promise((ok, fail) => {
    server.on('error', fail);
    server.listen(0, '127.0.0.1', () => ok(server));
  });
}

/**
 * A Blossom endpoint on a second origin, for step 3d (#589 phase 4).
 *
 * Another port is another origin, so the page's upload is a real CORS request
 * from a cross-origin isolated page — the situation the production servers
 * put it in. It answers the way they do: `Access-Control-Allow-Origin: *`, a
 * preflight that allows `Authorization`, BUD-02's `PUT /upload` with a blob
 * descriptor, and the blob at `/<sha256>`. Nothing leaves the machine.
 */
/**
 * Why a BUD-02 upload authorization is unacceptable for `sha256`, or null when
 * it is fine: a base64 kind 24242 event, `t` = upload, `x` = the blob's hash,
 * an expiration still ahead. What a real server checks, short of the Schnorr
 * signature — Rust's blossom tests verify that one.
 */
function uploadAuthProblem(header, sha256) {
  if (!header?.startsWith('Nostr ')) return 'no "Nostr" authorization';
  let event;
  try {
    event = JSON.parse(Buffer.from(header.slice('Nostr '.length), 'base64').toString('utf8'));
  } catch {
    return 'the authorization is not a base64 JSON event';
  }
  const tag = (name) => event.tags?.find((t) => t[0] === name)?.[1];
  if (event.kind !== 24242) return `kind ${event.kind}, not 24242`;
  if (!/^[0-9a-f]{64}$/.test(event.pubkey ?? '') || !/^[0-9a-f]{128}$/.test(event.sig ?? '')) {
    return 'the event is not signed';
  }
  if (tag('t') !== 'upload') return `t tag "${tag('t')}", not "upload"`;
  if (tag('x') !== sha256) return `x tag "${tag('x')}" does not name the uploaded blob`;
  if (!(Number(tag('expiration')) > Date.now() / 1000)) return 'no future expiration';
  return null;
}

function serveBlossom(requests) {
  const blobs = new Map();
  const server = createServer((req, res) => {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const request = { method: req.method, path: pathname, authProblem: null };
    requests.push(request);
    const send = (status, body, type) => {
      res.writeHead(status, {
        'Content-Type': type || 'text/plain; charset=utf-8',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, HEAD, PUT, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type',
        'Cache-Control': 'no-store',
      });
      res.end(body);
    };

    if (req.method === 'OPTIONS') return send(204, '');
    if (req.method === 'PUT' && pathname === '/upload') {
      const chunks = [];
      req.on('data', (chunk) => chunks.push(chunk));
      req.on('end', () => {
        const blob = Buffer.concat(chunks);
        const sha256 = createHash('sha256').update(blob).digest('hex');
        // Refused like a real server would, so a bad authorization fails
        // the round trip rather than passing it.
        request.authProblem = uploadAuthProblem(req.headers.authorization, sha256);
        if (request.authProblem) return send(401, request.authProblem);
        blobs.set(sha256, blob);
        send(200, JSON.stringify({ sha256, size: blob.length }), 'application/json');
      });
      return;
    }
    const blob = req.method === 'GET' ? blobs.get(pathname.slice(1)) : undefined;
    if (blob) return send(200, blob, 'application/octet-stream');
    send(404, 'not found');
  });

  return new Promise((ok, fail) => {
    server.on('error', fail);
    server.listen(0, '127.0.0.1', () => ok(server));
  });
}

/**
 * Runs in the page: writes each seeded document into its store as a string,
 * which is how rust/src/db/indexeddb.rs stores them. Returns true, or why it
 * could not.
 *
 * Opens the database without a version, so it never triggers an upgrade of
 * its own: the stores must already exist, created by the app's first load.
 * A bundle that no longer creates them fails here, with the store it lacks.
 */
async function seedStores({ database, stores }) {
  const request = (req) =>
    new Promise((ok, fail) => {
      req.onsuccess = () => ok(req.result);
      req.onerror = () => fail(req.error);
    });
  const db = await request(indexedDB.open(database));
  try {
    const names = Object.keys(stores);
    const absent = names.filter((name) => !db.objectStoreNames.contains(name));
    if (absent.length) {
      return `database "${database}" (version ${db.version}) has no ${absent.join(', ')} store`;
    }
    const tx = db.transaction(names, 'readwrite');
    for (const [name, docs] of Object.entries(stores)) {
      for (const [key, doc] of Object.entries(docs)) {
        tx.objectStore(name).put(typeof doc === 'string' ? doc : JSON.stringify(doc), key);
      }
    }
    await new Promise((ok, fail) => {
      tx.oncomplete = ok;
      tx.onerror = () => fail(tx.error);
      tx.onabort = () => fail(tx.error);
    });
    return true;
  } finally {
    db.close();
  }
}

async function main() {
  // Fail with a useful message rather than 404-ing every asset.
  await readFile(join(BUNDLE_DIR, 'index.html')).catch(() => {
    throw new Error(
      `No bundle at ${BUNDLE_DIR}. Build it first:\n` +
        '  ./scripts/build-web.sh --release && flutter build web --release ' +
        `--base-href "${BASE_PATH}" --pwa-strategy=none`,
    );
  });

  const misses = [];
  const errors = [];
  const ignored = [];

  const server = await serveBundle(misses);
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}${BASE_PATH}`;
  console.log(`serving ${BUNDLE_DIR} at ${url}`);

  const blossomRequests = [];
  const blossom =
    process.env.SMOKE_ATTACHMENTS === '1' ? await serveBlossom(blossomRequests) : null;
  const blossomUrl = blossom && `http://127.0.0.1:${blossom.address().port}`;

  // Everything past this point runs under the finally that closes the server:
  // a listening socket keeps the event loop alive, so leaking one turns a
  // browser that failed to start into a job that hangs until its timeout
  // instead of a smoke test that fails in seconds.
  let browser;
  try {
    browser = await chromium.launch();
    // Pin the locale, overridable via SMOKE_LOCALE. A CI container usually has
    // none configured, so Chromium reports something Dart's intl rejects
    // outright — `RangeError: Incorrect locale information provided` thrown
    // before runApp, leaving the engine bootstrapped but no view mounted. Real
    // browsers always report a valid locale, so leaving it unset tests a
    // situation no user is ever in while hiding every failure that comes
    // after it — hence the 'en-US' default. web-build.yml also runs this
    // script once with SMOKE_LOCALE=C: a regression guard for issue #227,
    // fixed by the locale sanitizer in web/index.html. The pin stays for
    // determinism; it is no longer load-bearing for that bug. The other broken
    // tags cannot be delivered this way — see SMOKE_NAVIGATOR_LANGUAGES below.
    //
    // `??`, not `||`: the empty string is one of the broken tags this guards
    // against, and `||` would silently turn SMOKE_LOCALE='' into 'en-US' —
    // the one case the knob exists for, passing green without testing it.
    const page = await browser.newPage({ locale: process.env.SMOKE_LOCALE ?? 'en-US' });

    // The app reads its bond rows back only when asked (step 3b). An init
    // script, so the request is in place before the app starts, on the first
    // load and again on the reload.
    if (process.env.SMOKE_BOND_STORE === '1') {
      await page.addInitScript(() => {
        globalThis.mostroStoreProbeRequested = true;
      });
    }

    // Likewise for the attachment round trip (step 3d): the app runs it only
    // when this names the server to run it against.
    if (blossomUrl) {
      await page.addInitScript((server) => {
        globalThis.mostroAttachmentProbeServer = server;
      }, blossomUrl);
    }

    // SMOKE_LOCALE goes through Playwright, which normalizes the tag before the
    // page sees it: 'en_US' arrives as 'en-US' and '' falls back to the system
    // locale, so only 'C' survives the trip. That is a limit of that option,
    // not of the browser — an init script runs inside the page, before any of
    // its own scripts, so it can hand the engine a tag Playwright would never
    // deliver. Comma-separated, used verbatim; unset means "do not touch",
    // which is every run except the locale matrix in web-build.yml.
    //
    // `!== undefined`, not a truthiness check: SMOKE_NAVIGATOR_LANGUAGES=''
    // is the empty-tag case, one of the broken ones this exists to cover.
    //
    // `configurable: true` is load-bearing, but not as a false-green guard.
    // The sanitizer bails out when either property is already locked down
    // (#370 review), so a non-configurable shadow makes it skip the very path
    // under test — the engine then gets the raw tag and the positive run
    // *fails*, with the same `Incorrect locale information provided` a real
    // regression produces. Measured both ways on `C` and `C,es-AR` (#406
    // review). What this flag prevents is a red matrix that reads as a broken
    // sanitizer when it is really a broken harness.
    const forcedLanguages = process.env.SMOKE_NAVIGATOR_LANGUAGES;
    if (forcedLanguages !== undefined) {
      await page.addInitScript((langs) => {
        Object.defineProperty(navigator, 'languages', {
          get: () => langs,
          configurable: true,
        });
        Object.defineProperty(navigator, 'language', {
          get: () => langs[0] ?? '',
          configurable: true,
        });
      }, forcedLanguages.split(','));
    }

    // `frames` only adds context to the report: whether an error is ignorable
    // is still decided on its message alone.
    const record = (origin, text, frames = []) => {
      const entry = [`[${origin}] ${text}`, ...frames].join('\n    ');
      (isIgnorable(text) ? ignored : errors).push(entry);
    };
    page.on('console', (msg) => {
      if (msg.type() === 'error') record('console', msg.text());
    });
    // The stack is what names the culprit: "Atomics.wait cannot be called in
    // this context" alone does not say which Rust lock blocked (#294).
    page.on('pageerror', (err) =>
      record('pageerror', err.message, stackFrames(err.stack)),
    );

    // Collected but never fatal on its own: a cancelled preload is routine,
    // while a blocked CDN fetch is not, and only the surrounding failure says
    // which one this was. Printed whenever something else fails.
    const aborted = [];
    page.on('requestfailed', (req) => {
      const text = `${req.url()} — ${req.failure()?.errorText ?? 'unknown'}`;
      (isIgnorable(text) ? ignored : aborted).push(text);
    });

    const dump = (label, lines) => {
      if (!lines.length) return;
      console.error(`\n${label}:`);
      for (const line of lines) console.error(`  ${line}`);
    };

    // A CI log is the only evidence anyone will ever have about a failure here,
    // and none of what follows is reachable after the throw — so empty the
    // collectors first. Without this, a red run says nothing beyond "it did
    // not work", which is how the first one went.
    const fail = async (message) => {
      await page.screenshot({ path: 'smoke-failure.png' }).catch(() => {});
      dump('console and page errors', errors);
      dump("ignored (outside this bundle's control)", ignored);
      dump('requests this server could not serve', misses);
      dump('requests the browser gave up on', aborted);

      // What the engine actually got to. Flutter paints to canvas, so the body
      // is short — it is the <script> tags and whichever host elements the
      // bootstrap managed to create before it stopped.
      const snapshot = await page
        .evaluate(() => ({
          readyState: document.readyState,
          body: document.body ? document.body.outerHTML.slice(0, 1500) : '(no body)',
        }))
        .catch(() => null);
      if (snapshot) {
        console.error(`\ndocument.readyState: ${snapshot.readyState}`);
        console.error(`document.body:\n  ${snapshot.body}`);
      }

      throw new Error(message);
    };

    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: TIMEOUT_MS });

    // 1. Isolation. Cheap, unambiguous, and everything after it depends on it.
    const isolated = await page.evaluate(() => globalThis.crossOriginIsolated);
    if (isolated !== true) {
      await fail('page is not cross-origin isolated — SharedArrayBuffer is unavailable');
    }
    console.log('✓ cross-origin isolated');

    // 2. The engine mounted. Flutter paints to canvas, so there is no text to
    //    assert on — the view element is the observable signal.
    //
    //    state: 'attached', not Playwright's default of 'visible'. "Visible"
    //    means a non-empty bounding box, which is a fact about layout, not
    //    about whether the engine came up — a host element the engine has not
    //    sized yet is still proof it mounted. Waiting on 'visible' here timed
    //    out on a page that demonstrably had the element in its DOM.
    await page
      .waitForSelector('flutter-view, flt-glass-pane', {
        state: 'attached',
        timeout: TIMEOUT_MS,
      })
      .catch(() => fail('the Flutter view never mounted'));
    console.log('✓ Flutter view mounted');

    // 2b. The sanitizer left the locale it was supposed to leave.
    //
    //     Opt-in, and only meaningful alongside SMOKE_NAVIGATOR_LANGUAGES.
    //     "The view mounted" is enough for a tag with no valid part — the page
    //     could not have booted unless the sanitizer replaced it. It is not
    //     enough for a mixed list: with "C,es-AR" a sanitizer that dropped the
    //     whole list for the fallback boots exactly as happily as one that
    //     kept "es-AR", and the user silently loses their language. Only
    //     reading the result back tells those two apart.
    if (process.env.SMOKE_EXPECT_LANGUAGES !== undefined) {
      const expected = process.env.SMOKE_EXPECT_LANGUAGES;
      const actual = (
        await page.evaluate(() => Array.from(navigator.languages ?? []))
      ).join(',');
      if (actual !== expected) {
        await fail(
          `navigator.languages is "${actual}", expected "${expected}"`,
        );
      }
      console.log(`✓ locale sanitized to [${actual}]`);
    }

    // 3. Startup finished, which takes the Rust bridge answering. The app sets
    //    the ready flag only at the very end, so a failure anywhere in startup
    //    shows up here. Poll for either outcome so a failure stops the
    //    run immediately with its reason instead of timing out silently.
    await page
      .waitForFunction(
        () =>
          globalThis.mostroBridgeReady === true ||
          typeof globalThis.mostroBridgeError === 'string',
        undefined,
        { timeout: TIMEOUT_MS },
      )
      .catch(() =>
        fail(
          'startup never finished — most often the FRB worker pool is dead ' +
            '(DataCloneError); check that web/pkg was built by scripts/build-web.sh',
        ),
      );
    const bridgeError = await page.evaluate(() => globalThis.mostroBridgeError);
    if (bridgeError) await fail(`startup failed: ${bridgeError}`);
    console.log('✓ startup finished (Rust bridge answered)');

    // 3b. Bond rows survive the persistent store (docs/ANTI_ABUSE_BOND.md T5.1).
    //
    //     Opt-in: only the release bundle has a store to read. A bridge that
    //     answers says nothing about IndexedDB, and the bond rows in it — a
    //     payout claim, trades parked at WaitingTakerBond / WaitingMakerBond —
    //     reach the UI only through a serde decode in the wasm core and an FRB
    //     decode in Dart. A build that breaks either one shows an empty My
    //     Trades and logs nothing this script would catch.
    //
    //     So seed the rows into the database the first load created, reload so
    //     the app reads them at startup, and compare what it publishes
    //     (lib/core/web/store_probe.dart) with what was seeded. The seed file is
    //     decoded by a Rust unit test too, so it cannot drift from the types.
    if (process.env.SMOKE_BOND_STORE === '1') {
      const seed = JSON.parse(await readFile(join(here, 'seed', 'bond_store.json'), 'utf8'));
      const seeded = await page
        .evaluate(seedStores, { database: seed.database, stores: seed.stores })
        .catch((err) => `seeding threw: ${err.message}`);
      if (seeded !== true) await fail(`could not seed the bond rows: ${seeded}`);

      await page.reload({ waitUntil: 'domcontentloaded', timeout: TIMEOUT_MS });
      await page
        .waitForFunction(
          // The bridge error too: the reloaded page publishes no probe when
          // its bridge call fails, and that should fail now, with its reason,
          // rather than as a probe timeout after the whole budget.
          () =>
            typeof globalThis.mostroStoreProbe === 'string' ||
            typeof globalThis.mostroStoreProbeError === 'string' ||
            typeof globalThis.mostroBridgeError === 'string',
          undefined,
          { timeout: TIMEOUT_MS },
        )
        .catch(() => fail('the app never published what it read from the store (mostroStoreProbe)'));
      const reloadBridgeError = await page.evaluate(() => globalThis.mostroBridgeError);
      if (reloadBridgeError) {
        await fail(`startup failed after the reload: ${reloadBridgeError}`);
      }
      const probeError = await page.evaluate(() => globalThis.mostroStoreProbeError);
      if (probeError) await fail(`reading the bond rows back failed: ${probeError}`);

      const probe = JSON.parse(await page.evaluate(() => globalThis.mostroStoreProbe));
      const same = (want, got) => Object.entries(want).every(([k, v]) => got[k] === v);
      const missing = [
        ...seed.expect.claims.filter((want) => !probe.claims.some((got) => same(want, got))),
        ...seed.expect.trades.filter((want) => !probe.trades.some((got) => same(want, got))),
      ];
      if (missing.length) {
        await fail(
          `seeded bond rows were not read back: ${JSON.stringify(missing)}\n` +
            `  the app read: ${JSON.stringify(probe)}`,
        );
      }
      console.log(
        `✓ bond rows read back (${seed.expect.claims.length} claim, ` +
          `${seed.expect.trades.length} trades)`,
      );
    }

    // 3c. The messaging worker is active on the isolated page
    //     (docs/PUSH_NOTIFICATIONS.md T4.5). Opt-in: SMOKE_PUSH_WORKER=1.
    //
    //     A second service worker beside the isolation shim, registered
    //     relative to the base path, loading the Firebase SDK from gstatic
    //     under COEP. Each of those can fail on a page that is otherwise
    //     healthy, and CI never asks for a token (no permission, no key), so
    //     only the registration says the worker would work.
    if (process.env.SMOKE_PUSH_WORKER === '1') {
      const scope = new URL(`${BASE_PATH}firebase-cloud-messaging-push-scope`, url).href;
      const state = await page
        .evaluate(
          async ({ scope, timeout }) => {
            const deadline = Date.now() + timeout;
            while (Date.now() < deadline) {
              const registration = await navigator.serviceWorker.getRegistration(scope);
              if (registration?.scope === scope && registration.active) return 'active';
              await new Promise((ok) => setTimeout(ok, 250));
            }
            return 'never active';
          },
          { scope, timeout: TIMEOUT_MS },
        )
        .catch((err) => `unreadable (${err.message})`);
      if (state !== 'active') await fail(`the messaging worker under ${scope} is ${state}`);
      const stillIsolated = await page.evaluate(() => globalThis.crossOriginIsolated);
      if (stillIsolated !== true) {
        await fail('the page lost cross-origin isolation beside the messaging worker');
      }
      console.log('✓ messaging worker active, page still isolated');
    }

    // 3d. An attachment makes the round trip on the web (#589 phase 4).
    //
    //     Opt-in: SMOKE_ATTACHMENTS=1. The bridge answering says nothing about
    //     the browser's fetch from an isolated page to another origin, nor the
    //     IndexedDB blob cache, and either can break while the page looks
    //     healthy. The app encrypts random bytes, uploads them to the endpoint
    //     above, downloads them back against their hash, caches and decrypts
    //     them (lib/core/web/attachment_probe.dart), then reports.
    if (blossomUrl) {
      await page
        .waitForFunction(
          () =>
            globalThis.mostroAttachmentProbe === true ||
            typeof globalThis.mostroAttachmentProbeError === 'string' ||
            typeof globalThis.mostroBridgeError === 'string',
          undefined,
          { timeout: TIMEOUT_MS },
        )
        .catch(() => fail('the attachment round trip never reported (mostroAttachmentProbe)'));
      // The endpoint refuses an upload whose kind 24242 authorization is
      // wrong (uploadAuthProblem), so a success here means it was right.
      const authProblem = blossomRequests.find((r) => r.authProblem)?.authProblem;
      if (authProblem) await fail(`the upload authorization was refused: ${authProblem}`);
      const probeError = await page.evaluate(() => globalThis.mostroAttachmentProbeError);
      if (probeError) await fail(`the attachment round trip failed: ${probeError}`);
      console.log('✓ attachment uploaded, downloaded, cached and decrypted');
    }

    // 3e. Chrome would install the page as an app (#658). Opt-in:
    //     SMOKE_INSTALLABLE=1. A broken manifest link, a missing icon or a
    //     scope that excludes the start URL all leave the page working and
    //     only take away the install prompt, and with it web push on iOS,
    //     which Safari only allows for a home-screen app.
    if (process.env.SMOKE_INSTALLABLE === '1') {
      const reasons = await installabilityErrors(url);
      if (reasons.length) await fail(`Chrome would not install the page: ${reasons.join(', ')}`);
      console.log('✓ installable as an app');
    }

    // 4/5. Anything the page complained about, and anything it asked for that
    //      this server could not serve.
    if (ignored.length) {
      console.log("\nignored (outside this bundle's control):");
      for (const e of ignored) console.log(`  ${e}`);
    }
    // fail() prints the contents; these only have to name the failure.
    if (misses.length) await fail('some requests were not served (check --base-href)');
    if (errors.length) await fail('the page reported errors');
    console.log('✓ no console or page errors\n\nweb bundle smoke test passed.');
  } finally {
    // browser is undefined when chromium.launch() itself threw.
    await browser?.close().catch(() => {});
    // close() only stops new connections; a keep-alive socket the browser left
    // behind would hold the process open just as a listening one would.
    server.closeAllConnections();
    server.close();
    blossom?.closeAllConnections();
    blossom?.close();
  }
}

/**
 * Chrome's own reasons not to install the page at [url], as error ids; empty
 * when it would. Asks Chrome (`Page.getInstallabilityErrors`) instead of
 * re-implementing its criteria. Two things make the answer mean something:
 * the full Chromium build, because the default headless shell reports every
 * page installable, and a persistent profile, because an incognito one never
 * is. Polled briefly, since the manifest and its icons load after the page.
 */
async function installabilityErrors(url) {
  const profile = await mkdtemp(join(tmpdir(), 'smoke-install-'));
  const context = await chromium.launchPersistentContext(profile, { channel: 'chromium' });
  try {
    const page = await context.newPage();
    await page.goto(url, { waitUntil: 'load' });
    const cdp = await context.newCDPSession(page);
    const deadline = Date.now() + Math.min(TIMEOUT_MS, 15_000);
    let reasons;
    do {
      const { installabilityErrors } = await cdp.send('Page.getInstallabilityErrors');
      reasons = installabilityErrors.map((e) => e.errorId);
      if (!reasons.length) return reasons;
      await new Promise((ok) => setTimeout(ok, 500));
    } while (Date.now() < deadline);
    return reasons;
  } finally {
    await context.close().catch(() => {});
    await rm(profile, { recursive: true, force: true }).catch(() => {});
  }
}

main().catch((err) => {
  console.error(`\n✗ web bundle smoke test failed: ${err.message}`);
  process.exitCode = 1;
});
