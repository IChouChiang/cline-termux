#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

# Real OpenTUI render smoke against an installed Cline Termux bundle. Creates
# a renderer through @opentui/core's test harness, renders a marker string,
# and asserts it appears in the captured native frame — both with the memory
# output backend and with the NativeSpanFeed (JS callback) backend.
#
# A dlopen probe alone is NOT a sufficient OpenTUI test on Android; this
# script exists to exercise the genuine render path.

INSTALL_BASE="${CLINE_TERMUX_INSTALL_BASE:-$PREFIX/opt/cline-termux}"
BUN_BASE="${CLINE_TERMUX_BUN_INSTALL_BASE:-$PREFIX/opt/bun-android-ffi}"
BUNDLE_DIR="${1:-$INSTALL_BASE/current}"
BUN_BIN="${BUN_BIN:-$BUN_BASE/current/bun}"

fail() {
	echo "[fail] $*" >&2
	exit 1
}

info() {
	echo "[info] $*"
}

ok() {
	echo "[ok] $*"
}

[ -x "$BUN_BIN" ] || fail "Bun FFI runtime not found at $BUN_BIN"
[ -d "$BUNDLE_DIR/node_modules/@opentui/core" ] \
	|| fail "no installed @opentui/core under $BUNDLE_DIR"
[ -f "$BUNDLE_DIR/node_modules/@opentui/core-android-arm64/libopentui.so" ] \
	|| fail "no Android OpenTUI native library under $BUNDLE_DIR"
[ -f "$BUNDLE_DIR/node_modules/@opentui/core-android-arm64/VERSION" ] \
	|| fail "the installed OpenTUI native package has no VERSION provenance; it is not the genuine Bionic build"

info "Using Bun $("$BUN_BIN" --version) against $BUNDLE_DIR"
# The script must live inside the bundle: Bun resolves imports from the
# script's directory and would otherwise auto-install an unpatched OpenTUI
# from the registry. --no-install makes any such fallback fail loudly.
SMOKE_SCRIPT="$(mktemp "$BUNDLE_DIR/.opentui-render-smoke.XXXXXX.mjs")"
trap 'rm -f "$SMOKE_SCRIPT"' EXIT

cat > "$SMOKE_SCRIPT" <<'EOF'
const { TextRenderable } = await import("@opentui/core")
const { createTestRenderer } = await import("@opentui/core/testing")

async function renderOnceWith(bufferedOutput, marker) {
  const { renderer, renderOnce, captureCharFrame, flush } = await createTestRenderer({
    width: 60,
    height: 8,
    bufferedOutput,
  })
  const text = new TextRenderable(renderer, { id: "smoke", content: marker })
  renderer.root.add(text)
  await renderOnce()
  for (let i = 0; i < 5; i++) {
    text.content = `${marker} frame ${i}`
    await renderOnce()
  }
  await flush()
  const frame = captureCharFrame()
  if (!frame.includes(`${marker} frame 4`)) {
    console.error(`render smoke failed for ${bufferedOutput} output; frame was:`)
    console.error(frame)
    process.exit(1)
  }
  console.log(`render-ok ${bufferedOutput}`)
}

await renderOnceWith("memory", "bionic-render-memory")
// A mock stdout that is not process.stdout routes through NativeSpanFeed,
// which exercises native-to-JS callbacks and streaming writes.
await renderOnceWith("stdout", "bionic-render-feed")
console.log("OPENTUI-RENDER-SMOKE-OK")
process.exit(0)
EOF

(
	cd "$BUNDLE_DIR"
	"$BUN_BIN" --no-install "$SMOKE_SCRIPT"
)
ok "OpenTUI rendered real frames on Termux through the genuine Bionic library"
