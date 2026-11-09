# Mortsom on Pull Requests — Automated E2E Gate

**Status:** Phases 1–3 (selection, map, pull request run, verdict, `main` baseline). Shadow mode.
**Harness:** [MostroP2P/mortsom](https://github.com/MostroP2P/mortsom) (public)
**Reserved by:** `docs/CONTRIBUTION_QUALITY_SPEC.md` §9.1 (layer 6) and its `mortsom:*` labels.
**Modelled on:** the daemon's Ortsom gate (`docs/ORTSOM_PR_E2E_SPEC.md` in MostroP2P/mostro).
**Initial mode:** label-only. Pull requests are never closed or blocked by this gate.

## 1. Goal

Every pull request that changes app behaviour is run through the Mortsom
end-to-end suite automatically: two real copies of the app built from the
pull request trade against each other on a regtest stack (bitcoind, LND
nodes, relay and a mostrod) that the job builds itself. The scenarios run
are chosen from what the pull request touches. The result is compared with
a baseline of `main`, and the pull request is labelled with a verdict that
says whether it — and not `main`, the harness or the runner — broke
scenarios.

### Non-goals

- Replacing `ci.yml`. A pull request that does not build is `inconclusive`
  here; whether it builds is CI's question.
- Covering what Mortsom has no scenario for. Changed paths without a
  scenario are reported as **not covered** (§4.4), never as tested.
- Running on mainnet or with real sats. Only the regtest stack is used,
  and the job holds no secret.
- Web and mobile platforms. This phase runs the Linux desktop build only
  (§12).

## 2. What already exists in Mortsom

| Capability | How |
|---|---|
| Build the app from a branch or pull request | `mortsom run --ref <branch\|PR URL>`: Mortsom fetches the PR head itself, forks included |
| Self-contained regtest stack, no secrets | `mortsom stack up` (plain) and `mortsom stack up --bond` (anti-abuse bonds) |
| Scenario catalog for selection | `mortsom list --json` (schema 1, `docs/gate-contract.md` in Mortsom) |
| Machine-readable results | `artifacts/<run-id>/summary.json`, one run per scenario, with typed failure categories |
| A job that does all of the above | the reusable workflow `MostroP2P/mortsom/.github/workflows/app-e2e.yml` (`workflow_call`) |

A scenario written for the other kind of daemon is **skipped**, never
failed: the `bond` family runs only on a bonded stack and every other
family only on a plain one. Scenarios that need an interruption Linux
cannot cause (`needs` in the catalog) and the one that drives the app's
own wallet (`needs_app_wallet`) are skipped on Linux.

## 3. Architecture

```text
push to main ─┐
cron (daily) ─┴─► mortsom-baseline.yml ─► artifacts mortsom-baseline-{plain,bond} + meta
                                                              │
pull_request ──► mortsom-pr.yml          no secrets, read-only token
                   job select   PR's map → plain / bond scenario lists
                   job plain ┐  calls mortsom app-e2e.yml (pinned) with --ref <PR URL>
                   job bond  ┘  artifacts mortsom-pr-{plain,bond}
                   job meta     artifact mortsom-pr-meta
                        │
workflow_run ──► mortsom-verdict.yml     definition and scripts from main
                   - trusted selection from main's map and the API file list
                   - reference baseline for the merge-base
                   - verdict, sticky comment, labels; never runs PR code

pull_request, push ──► mortsom-map.yml   unit tests, map coverage, pin check
```

Everything that decides lives in version-controlled scripts under
`.github/mortsom/`, with unit tests; the workflows stay thin.

```text
.github/mortsom/
├── map.toml              # settings and path → scenario rules
├── scenarios.json        # `mortsom list --json` of the pinned Mortsom, committed
├── select_scenarios.py   # changed files → selection.json (+ plain/bond lists)
├── verdict.py            # PR results + baselines → verdict.json + comment.md
├── run_verdict.py        # API calls, artifact download, labels and comment
└── tests/                # unittest suites (stdlib only)
```

Python 3.12 from the runner image, standard library only (`tomllib`).

## 4. Scenario selection

### 4.1 The map

`.github/mortsom/map.toml` holds the settings and a list of rules. A rule
maps path globs to tags and/or scenario names, or marks them `ignore`,
`full` or `uncovered` (with a reason).

```toml
[settings]
mortsom_ref = "<commit of MostroP2P/mortsom>"  # also the `uses:` ref in the workflows
always_tags = ["smoke"]        # every non-ignored selection runs these
min_scenarios = 4              # eligible scenarios needed for `would-close`
close_ratio = 0.5              # regressions / eligible that make `would-close`
baseline_max_distance = 10     # first-parent commits back from the merge-base
stability_window = 3           # baselines a scenario must have passed to be stable
max_scenarios = 16             # per stack; above it the selection is capped (§4.3)

[[rule]]
name = "trade flow"
paths = ["lib/features/order/**", "lib/features/trades/**", "rust/src/api/orders/**"]
tags = ["happy-path", "cancellation", "expiration"]

[[rule]]
name = "chat"
paths = ["lib/features/chat/**", "rust/src/attachments/**"]
uncovered = "Mortsom has no chat scenario"
```

The current map is the file itself; §4.5 lists what it does not cover.

### 4.2 Glob semantics

Repository-relative, `/`-separated paths. `**/` matches zero or more
directories, `**` anything, `*` and `?` stay within one path segment. No
braces, no negation. All matching rules contribute; order does not matter.
The same matcher as the size check (`.github/quality/size_check.py`).

### 4.3 Algorithm

Input: the files the pull request changes (both names for a rename).

1. Drop files matched by an `ignore` rule. Nothing left: mode `none`, no
   run, verdict `not-applicable`.
2. Any remaining file matched by a `full` rule: mode `full`, every
   scenario.
3. Otherwise mode `subset`: the union of `always_tags` and the tags and
   scenarios of every rule a remaining file matches. A file matched only
   by `uncovered` rules is recorded as **uncovered** with the reason; a
   file matched by no rule as **unmapped**.
4. Resolve tags to names with `scenarios.json`. An unknown tag or name is
   a hard error of the selection (the map is stale): verdict
   `inconclusive`.
5. Drop what Linux cannot run (`needs` non-empty, `needs_app_wallet`),
   recorded as `not-runnable`.
6. Split by `needs_bonded_daemon` into the **plain** and the **bond**
   lists; each runs on its own stack, and a list that is empty is not run.
7. **Cap.** If a list has more than `max_scenarios`, keep the
   `always_tags` scenarios and then names in catalog order up to the cap;
   the rest are recorded as `capped` and named in the comment. A `full`
   run on `main` (the baseline) is never capped.

`select_scenarios.py` writes `selection.json`:

```json
{
  "mode": "subset",
  "plain": ["cancel_before_taken", "happy_buy", "happy_sell"],
  "bond": [],
  "matched_rules": ["trade flow"],
  "uncovered_files": {"lib/features/chat/chat_screen.dart": "Mortsom has no chat scenario"},
  "unmapped_files": [],
  "not_runnable": ["background_at_taken"],
  "capped": [],
  "ignored_files": ["docs/RELAYS.md"]
}
```

### 4.4 Keeping the map complete

`mortsom-map.yml` runs on every pull request and every push to `main`:

- the unit tests of `.github/mortsom/`;
- a **coverage test**: every tracked `lib/**/*.dart` (outside generated
  code), every `rust/src/**/*.rs`, `pubspec.yaml` and `rust/Cargo.toml`
  matches at least one rule (`ignore`, `uncovered`, `full` or a selecting
  rule). A new module nobody mapped fails here, in the pull request that
  adds it;
- every tag and scenario name in the map exists in `scenarios.json`;
- a **pin check**: the `uses: MostroP2P/mortsom/...@<ref>` lines of the
  workflows equal `settings.mortsom_ref`.

Bumping Mortsom is one pull request that changes `mortsom_ref`, both
`uses:` lines and `scenarios.json` (regenerated with `mortsom list --json`
at that commit).

### 4.5 What the map does not cover

Paths marked `uncovered` (no scenario exercises them on Linux today):
chat and attachments, Cashu, push and local notifications,
announcements, deep links, the walkthrough, the install screen and
platform code (`android/`, `ios/`, `macos/`, `windows/`, `web/`). A pull
request that only touches these runs `smoke` and its comment says, in
words, that its change was not exercised.

## 5. Baseline of `main` — `mortsom-baseline.yml`

- **Triggers:** push to `main` (ignoring Markdown-only pushes), daily
  schedule, `workflow_dispatch`.
- **What runs:** the full Linux-runnable catalog, plain and bond lists on
  their own stacks, never capped, with the pinned Mortsom and `--ref main`.
- **Concurrency:** group `mortsom-baseline`, no cancellation.
- **Output:** artifacts `mortsom-baseline-plain` and
  `mortsom-baseline-bond` (the summaries) and `mortsom-baseline-meta`
  (`sha` = the workflow's commit, the app commit Mortsom recorded in the
  summaries' provenance, `mortsom_ref`, status per stack), retained
  90 days.
- A failing scenario on `main` is information, not an error: the run's
  conclusion is informational and the job summary lists failures.

## 6. Pull request run — `mortsom-pr.yml`

- **Trigger:** `pull_request` (`opened`, `synchronize`, `reopened`,
  `ready_for_review`, and `labeled`/`unlabeled` for `mortsom:*` labels).
  Drafts, Dependabot and `mortsom:skip` do not run; `mortsom-map.yml`
  still does.
- **Permissions:** `contents: read`. No secrets. Fork pull requests run
  the same way (after a maintainer approves a first-time contributor's
  workflows, as GitHub requires).
- **select:** checks out the pull request and runs `select_scenarios.py`
  on `git diff --name-only <base>...<head>` with the pull request's own
  map, so a pull request that adds a rule is run with it. The verdict
  does not trust this selection (§9).
- **plain / bond:** each calls
  `MostroP2P/mortsom/.github/workflows/app-e2e.yml@<mortsom_ref>` with
  `app_ref` = the pull request URL, `scenarios` = its list and `bond`.
- **meta:** uploads `meta.json` (number, head SHA, base SHA, selection).
- **Concurrency:** group per pull request, `cancel-in-progress: true`.

## 7. Verdict — `mortsom-verdict.yml`

Runs on `workflow_run` of "Mortsom PR" (completed), from `main`, with
`pull-requests: write`, `issues: write`, `actions: read`. It treats every
artifact as untrusted data and never checks out or runs pull request code.

### 7.1 Finding the baseline

The merge-base comes from the API
(`compare/main...<head_sha>` → `merge_base_commit.sha`). Candidates are
recent `mortsom-baseline.yml` runs on `main` whose `mortsom_ref` equals
`main`'s pin, keyed by the app commit Mortsom recorded as built
(`app_build.remote_selection.revision` in the summaries; a baseline builds
`main` by name, which may have moved since the run was queued, and a run
whose two stacks built different commits is discarded), within
`baseline_max_distance` first-parent commits of the merge-base. The most recent is the
**reference**; the `stability_window` most recent are the **history**.
None: `inconclusive`, reason `no-baseline`.

### 7.2 Classifying each scenario

For each scenario of the **trusted selection** (recomputed with `main`'s
map and the API's file list), with pull request outcome `P`:

| Condition | Class | Eligible |
|---|---|---|
| `P` is `skipped` | `skipped` | no |
| absent from the reference baseline | `no-baseline` | no |
| not `passed` in the reference, or not `passed` (or retried) in any run of the history | `unstable-on-main` | no |
| `P` failed with category `test-infrastructure`, `relay`, `wallet` or `environment-misconfiguration` | `harness` | no |
| `P` is `passed` | `pass` (noted `retried` if `attempts` > 1) | yes |
| `P` failed with category `product` or `automation-contract` | `regression` | yes |
| missing from the pull request summaries of a completed run | `missing`, counted as `regression` | yes |

`eligible = pass + regression`, `ratio = regression / eligible`. A run
whose suite job did not complete (timeout, cancellation) is
`inconclusive`, reason `incomplete-run`, and nothing is classified.

### 7.3 Verdicts

First match wins.

| Verdict | When | Label |
|---|---|---|
| `not-applicable` | mode `none` | none; previous `mortsom:*` verdict labels removed |
| `inconclusive` | selection error, gate files modified by the pull request (§9), app build failed, incomplete run, no baseline, or every failure is `harness` | `mortsom:inconclusive` |
| `would-close` | `eligible ≥ min_scenarios` and `ratio ≥ close_ratio`, and no cap applies | `mortsom:would-close` |
| `regression` | a `would-close` condition held but `mortsom:expected-break` caps it, or at least one `regression` | `mortsom:regression` |
| `pass` | otherwise | `mortsom:pass` |

Verdict labels are mutually exclusive and re-evaluated on every run.

### 7.4 The comment

One comment, found by the marker `<!-- mortsom-verdict -->` on a comment
by `github-actions[bot]`, edited in place:

- the verdict with its numbers, e.g. *2 of 6 eligible scenarios regressed*;
- the app commit tested, the Mortsom revision, the baseline commit and its
  distance from the merge-base;
- a table of regressions (scenario, category, detail). The detail comes
  from a run of untrusted code: cut to 200 characters, one line, inside a
  code span with backticks removed;
- collapsed lists of passes, skipped, harness, `unstable-on-main`,
  `no-baseline`, `not-runnable` and `capped` scenarios;
- **not covered**: uncovered files with the reason, and unmapped files;
- links to the pull request run, its artifacts and the baseline run;
- in shadow mode: *Shadow mode: nothing is blocked or closed.*

## 8. Labels

| Label | Applied by | Effect |
|---|---|---|
| `mortsom:pass` / `mortsom:regression` / `mortsom:inconclusive` / `mortsom:would-close` | verdict | The verdict (§7.3) |
| `mortsom:skip` | maintainer | No suite run; the verdict removes verdict labels |
| `mortsom:run` | maintainer | Re-runs; removed once the run reports |
| `mortsom:expected-break` | maintainer | Caps the verdict at `regression`, for intended behaviour changes Mortsom has not caught up with |
| `mortsom:false-positive` | maintainer | Disagrees with a verdict; data for the shadow review (§11) |

## 9. Security

- **The run job holds nothing worth stealing.** `mortsom-pr.yml` has a
  read-only token and no secrets, so building and running the pull
  request's code (and a pull request that edits the workflow itself) can
  only affect its own run.
- **The verdict never trusts the run.** It recomputes the selection from
  `main`'s map and the API's file list; a scenario the run was asked to
  run and did not is `missing` and counts as a regression. A pull request
  that changes `.github/mortsom/**` or the gate workflows gets
  `inconclusive`, reason `gate-modified`, because its run used its own
  gate.
- **Results are only as trustworthy as the job that wrote them.** The
  app code runs in the same job that writes `summary.json`, so a pull
  request can forge its own results. In shadow mode that only affects a
  label; before Phase 4 (enforcement) the summaries must come from a step
  the app process cannot write to.
- **Artifacts are data.** The verdict parses JSON with size limits and
  never executes anything from them; text that reaches the comment is
  escaped (§7.4).
- **Caches.** The reusable workflow never saves the Flutter cache, and
  Mortsom's own Rust cache is saved only by Mortsom's `main`.

## 10. Changes in Mortsom

Done in MostroP2P/mortsom#123: `mortsom list --json`, `docs/gate-contract.md`
(catalog and `summary.json` fields) and the reusable `app-e2e.yml`.

## 11. Rollout

| Phase | Content |
|---|---|
| 1 | This spec, `map.toml`, `scenarios.json`, `select_scenarios.py` with tests, `mortsom-map.yml` |
| 2 | `mortsom-pr.yml` and `mortsom-baseline.yml` |
| 3 | `verdict.py`, `run_verdict.py`, `mortsom-verdict.yml`. **Shadow**: labels and comment only |
| 4 | A separate decision: after at least 4 weeks of shadow verdicts, with every `mortsom:would-close` reviewed by a maintainer, decide whether `would-close` blocks a merge |

Phases 1–3 land together; the gate starts in shadow mode.

## 12. Cost and known gaps

- **Cost.** Each pull request builds the app on a GitHub-hosted runner
  (no cache, by design) and runs its selection; the bond stack doubles
  the setup when bond scenarios are selected. First measurement
  (MostroP2P/mortsom#123, smoke against `main`): 21 minutes end to end,
  of which 3.6 build Mortsom, 6.6 start the regtest stack and 8.6 build
  the app and run three scenarios (17–50 s each). A trade-flow change
  (MostroP2P/app#925) selected 15 scenarios: 51 minutes end to end, 24 of
  them in scenarios (19 s to 6.4 min each; `pending_order_expires` is the
  longest), all passed on the first attempt. `max_scenarios = 16` keeps a
  stack's run under an hour.
- **Linux only.** Web, Android and iOS code is not exercised, and the
  interruption scenarios (background, network loss, rotation, relay
  faults) are skipped on Linux.
- **Configuration.** Mortsom starts mostrod from its own settings, so app
  behaviour that depends on other daemon configurations is not covered.
- **Not covered paths** are listed in every comment (§4.5); a pass says
  nothing about them.
- **Escaped bugs only.** Like any test, the gate finds what its scenarios
  assert.
