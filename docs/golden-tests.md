# Golden Tests

Golden tests are visual regression tests: they render a widget and compare it,
pixel for pixel, against a committed reference image (the "golden" PNG). They
guard the DESIGN_SYSTEM atoms (status chips, role badges, order card,
notification card) against unintended visual changes, in both light and dark
themes.

- Golden test files: `test/features/**/**_golden_test.dart`
- Reference images: `test/features/**/goldens/*.png`
- Shared pump helper: `test/support/golden_harness.dart`

## Why images are generated in CI, not locally

Golden output depends on how the host rasterizes fonts, which varies across
operating systems and even across Linux distributions. A local machine and the
CI runner (`ubuntu-latest`) generally render fonts differently, so images
generated locally would not match what CI verifies, and the check would fail.

To avoid this, reference images are always generated in the CI environment via
the `Update goldens` workflow (`.github/workflows/update-goldens.yml`). Because
that workflow runs on the same `ubuntu-latest` image that later verifies them,
the committed PNGs match byte for byte.

Do not run `flutter test --update-goldens` locally and commit the result.

## Regenerating goldens

Run this whenever you intentionally change the appearance of a covered widget
(or add a new golden test):

1. Commit and push your code changes (widget + test) to the branch.
2. The normal CI run will fail on the golden tests if the reference images do
   not exist yet or no longer match. This is expected.
3. Trigger the workflow on your branch:

   ```bash
   gh workflow run update-goldens.yml --ref <your-branch>
   ```

   (Or use the Actions tab: "Update goldens" -> "Run workflow".)

4. The workflow regenerates the PNGs and commits them back to the branch.
5. That commit is pushed with the built-in `GITHUB_TOKEN`, so by GitHub's design
   it does not start a new CI run. Re-run the failed CI check (or push a
   follow-up commit) so `flutter test` verifies the fresh images and passes.

## Verification

No separate step is needed. The regular `flutter test` step in
`.github/workflows/ci.yml` runs the golden tests and compares against the
committed PNGs on every pull request and push.

## Determinism notes

- Widgets that render relative time (for example, "5m ago") read the clock
  through `package:clock` (`clock.now()`), not `DateTime.now()`. Golden tests
  freeze the clock with `withClock(Clock.fixed(...))` so the rendered label is
  stable over time.
- Golden widget tests run headless on the host renderer; they never run on an
  Android or iOS device. There is a single, host-rendered set of reference
  images, not one per platform.
