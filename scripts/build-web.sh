#!/usr/bin/env bash
# Compile the Rust core to WebAssembly with shared memory (threads) into web/pkg/.
#
# Do NOT use `flutter_rust_bridge_codegen build-web` directly: on current nightly,
# rustc no longer auto-adds the shared-memory linker flags when `+atomics` is set,
# so that build silently emits non-shared memory and FRB's worker pool dies at
# runtime with:
#   DataCloneError: Failed to execute 'postMessage' on 'Worker': #<Memory> could not be cloned.
# Full story in issue #212 (and #210 for the wasm bring-up it was found during).
#
# Usage:
#   ./scripts/build-web.sh              dev build (fast, unoptimized)
#   ./scripts/build-web.sh --release    release build
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

profile_flag="--dev"
if [[ "${1-}" == "--release" ]]; then
  profile_flag=""
elif [[ -n "${1-}" ]]; then
  echo "usage: $0 [--release]" >&2
  exit 2
fi

for tool in wasm-pack rustup python3; do
  command -v "$tool" >/dev/null || { echo "✗ $tool is not installed." >&2; exit 1; }
done

export RUSTUP_TOOLCHAIN=nightly
# +atomics/+bulk-memory/+mutable-globals enable wasm threads. The link-args are the
# shared-memory set rustc historically added by itself when it saw +atomics — minus
# __wasm_init_memory (no longer an exportable symbol in current lld) and plus
# __heap_base (required by wasm-bindgen's thread transform).
export RUSTFLAGS='-C target-feature=+atomics,+bulk-memory,+mutable-globals -C link-arg=--shared-memory -C link-arg=--max-memory=1073741824 -C link-arg=--import-memory -C link-arg=--export=__wasm_init_tls -C link-arg=--export=__tls_size -C link-arg=--export=__tls_align -C link-arg=--export=__tls_base -C link-arg=--export=__heap_base'

# shellcheck disable=SC2086  # $profile_flag must word-split (it is empty on release)
wasm-pack build -t no-modules -d "$repo_root/web/pkg" --no-typescript --out-name rust \
  $profile_flag rust -- -Z build-std=std,panic_abort

# Verify the emitted memory is actually shared. A toolchain regression here compiles
# fine and only fails at runtime (the DataCloneError above), so fail the build loudly
# instead of shipping a blank page.
python3 - "$repo_root/web/pkg/rust_bg.wasm" <<'EOF'
import sys

data = open(sys.argv[1], 'rb').read()

def leb(b, i):
    r = s = 0
    while True:
        x = b[i]; i += 1; r |= (x & 0x7f) << s
        if not x & 0x80:
            return r, i
        s += 7

i = 8  # skip magic + version
shared = None
while i < len(data) and shared is None:
    sid = data[i]; i += 1
    size, i = leb(data, i)
    if sid == 2:  # import section — threaded builds import their memory
        j = i
        n, j = leb(data, j)
        for _ in range(n):
            ml, j = leb(data, j); j += ml
            nl, j = leb(data, j); j += nl
            kind = data[j]; j += 1
            if kind == 0:      # function
                _, j = leb(data, j)
            elif kind == 1:    # table: elemtype + limits
                j += 1
                f = data[j]; j += 1
                _, j = leb(data, j)
                if f & 1:
                    _, j = leb(data, j)
            elif kind == 2:    # memory — what we are after
                shared = bool(data[j] & 0x2)
                break
            elif kind == 3:    # global: valtype + mutability
                j += 2
    elif sid == 5:  # local memory section — a non-threaded build defines its own
        j = i
        _, j = leb(data, j)
        shared = bool(data[j] & 0x2)
    i += size

if not shared:
    sys.exit(
        "✗ web/pkg/rust_bg.wasm was built WITHOUT shared memory — the app will crash "
        "at runtime spawning workers (DataCloneError). The RUSTFLAGS in this script "
        "did not take effect; see issue #212."
    )
print("✓ web/pkg/rust_bg.wasm has shared memory (threads enabled).")
EOF

echo "✓ WASM build complete: web/pkg/"
