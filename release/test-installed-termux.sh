#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

EXPECTED_RELEASE="${1:-}"
EXPECTED_CLINE="${2:-}"
INSTALL_BASE="${CLINE_TERMUX_INSTALL_BASE:-$PREFIX/opt/cline-termux}"
BUN_BASE="${CLINE_TERMUX_BUN_INSTALL_BASE:-$PREFIX/opt/bun-android-ffi}"
LAUNCHER="${CLINE_TERMUX_LAUNCHER_PATH:-$PREFIX/bin/cline}"

fail() {
	echo "[fail] $*" >&2
	exit 1
}

ok() {
	echo "[ok] $*"
}

read_field() {
	sed -n "s/^$2=//p" "$1" | head -n 1
}

[ -n "$EXPECTED_RELEASE" ] || fail "usage: $0 RELEASE_TAG CLI_VERSION"
[ -n "$EXPECTED_CLINE" ] || fail "usage: $0 RELEASE_TAG CLI_VERSION"
[ -n "${PREFIX:-}" ] || fail "PREFIX is not set; run this inside Termux"
[ "$(uname -m)" = "aarch64" ] || fail "expected aarch64 Termux"
[ -x "$LAUNCHER" ] || fail "missing launcher: $LAUNCHER"
[ -f "$INSTALL_BASE/current/VERSION" ] || fail "missing installed VERSION"
[ -x "$BUN_BASE/current/bun" ] || fail "missing Bun FFI runtime"
command -v pkill >/dev/null 2>&1 || fail "pkill is required for the TUI PTY smoke"

VERSION_FILE="$INSTALL_BASE/current/VERSION"
ACTUAL_RELEASE="$(read_field "$VERSION_FILE" release)"
ACTUAL_CLINE="$(read_field "$VERSION_FILE" cline)"
[ "v$ACTUAL_RELEASE" = "$EXPECTED_RELEASE" ] \
	|| fail "expected release $EXPECTED_RELEASE, found v$ACTUAL_RELEASE"
[ "$ACTUAL_CLINE" = "$EXPECTED_CLINE" ] \
	|| fail "expected Cline $EXPECTED_CLINE, found $ACTUAL_CLINE"

if dpkg --compare-versions "$EXPECTED_CLINE" ge 3.0.43; then
	[ -f "$INSTALL_BASE/current/cline-node-wrapper.cjs" ] \
		|| fail "missing upstream Node launcher"
	[ -f "$INSTALL_BASE/current/ca-certs.cjs" ] \
		|| fail "missing upstream certificate helper"
	[ -x "$INSTALL_BASE/current/run-cline-termux.sh" ] \
		|| fail "missing Termux runtime adapter"
	mkdir -p "$HOME/tmp"
	CA_TEST_DIR="$(mktemp -d "$HOME/tmp/cline-termux-ca.XXXXXX")"
	ACTUAL_VERSION="$(CLINE_DIR="$CA_TEST_DIR" "$LAUNCHER" --version)"
	[ -s "$CA_TEST_DIR/cli-node-extra-ca-certs.pem" ] \
		|| fail "launcher did not create a managed OS trust bundle"
	rm -rf "$CA_TEST_DIR"
	CA_TEST_DIR=""
	[ "$ACTUAL_VERSION" = "$EXPECTED_CLINE" ] \
		|| fail "cline --version did not report $EXPECTED_CLINE"
	ok "Node launcher harvested the Termux OS trust store"
else
	[ "$($LAUNCHER --version)" = "$EXPECTED_CLINE" ] \
		|| fail "cline --version did not report $EXPECTED_CLINE"
fi
$LAUNCHER --help >/dev/null
ok "CLI metadata, version, and help"

[ -f "$INSTALL_BASE/current/node_modules/@opentui/core-android-arm64/VERSION" ] \
	|| fail "the packaged OpenTUI native library has no VERSION provenance; it is not the genuine Bionic build"
ok "Packaged OpenTUI native library carries build provenance"

(
	cd "$INSTALL_BASE/current"
	"$BUN_BASE/current/bun" -e '
import { dlopen } from "bun:ffi"
const lib = dlopen(
  "./node_modules/@opentui/core-android-arm64/libopentui.so",
  { createRenderer: { args: ["u32", "u32", "u8", "u8", "ptr"], returns: "ptr" } },
)
if (!lib.symbols.createRenderer) process.exit(1)
' >/dev/null
)
ok "Bun FFI loads the packaged OpenTUI renderer"

# A dlopen probe is not a render test. Drive the real render path through
# @opentui/core: memory output plus the NativeSpanFeed callback backend.
# The script must live inside the bundle: Bun resolves imports from the
# script's directory and would otherwise auto-install an unpatched OpenTUI
# from the registry. --no-install makes any such fallback fail loudly.
RENDER_SMOKE="$(mktemp "$INSTALL_BASE/current/.render-smoke.XXXXXX.mjs")"
cat > "$RENDER_SMOKE" <<'RENDER'
const { TextRenderable } = await import("@opentui/core")
const { createTestRenderer } = await import("@opentui/core/testing")
for (const bufferedOutput of ["memory", "stdout"]) {
  const marker = `render-${bufferedOutput}`
  const { renderer, renderOnce, captureCharFrame, flush } = await createTestRenderer({
    width: 60,
    height: 8,
    bufferedOutput,
  })
  const text = new TextRenderable(renderer, { id: "smoke", content: marker })
  renderer.root.add(text)
  await renderOnce()
  await flush()
  if (!captureCharFrame().includes(marker)) {
    console.error(`no rendered frame for ${bufferedOutput} output`)
    process.exit(1)
  }
}
process.exit(0)
RENDER
(
	cd "$INSTALL_BASE/current"
	"$BUN_BASE/current/bun" --no-install "$RENDER_SMOKE" >/dev/null
) || {
	rm -f "$RENDER_SMOKE"
	fail "OpenTUI did not render real frames through the packaged native library"
}
rm -f "$RENDER_SMOKE"
ok "OpenTUI rendered real frames through the packaged native library"

rg -q --glob 'index-*.js' \
	'process\.platform === "linux" \|\| process\.platform === "android"' \
	"$INSTALL_BASE/current/node_modules/@opentui/core" \
	|| fail "OpenTUI Android renderer-thread patch missing from install"
ok "OpenTUI disables renderer threading on Android"

command -v script >/dev/null 2>&1 || fail "script is required for the TUI PTY smoke"
command -v timeout >/dev/null 2>&1 || fail "timeout is required for the TUI PTY smoke"
mkdir -p "$HOME/tmp"
LOG_FILE="$(mktemp "$HOME/tmp/cline-termux-tui.XXXXXX")"
RUNTIME_DIR="$(realpath "$INSTALL_BASE/current")"
TUI_PROCESS_PATTERN="^$BUN_BASE/current/bun $RUNTIME_DIR/index.js --tui$"
stop_tui_smoke() {
	pkill -TERM -f "$TUI_PROCESS_PATTERN" 2>/dev/null || true
	sleep 1
	pkill -KILL -f "$TUI_PROCESS_PATTERN" 2>/dev/null || true
}
cleanup() {
	stop_tui_smoke
	rm -f "$LOG_FILE"
}
trap cleanup EXIT

set +e
(sleep 7) | timeout 7 script -q -c \
	"stty cols 80 rows 24; env TERM=xterm-256color COLORTERM=truecolor CLINE_NO_AUTO_UPDATE=1 CLINE_TERMUX_BUN=$BUN_BASE/current/bun CLINE_TERMUX_HOME=$RUNTIME_DIR $LAUNCHER --tui" \
	/dev/null >"$LOG_FILE" 2>&1
PTY_STATUS=$?
set -e
stop_tui_smoke
case "$PTY_STATUS" in
	0|124|137) ;;
	*) fail "packaged TUI exited unexpectedly with status $PTY_STATUS" ;;
esac
[ "$(wc -c < "$LOG_FILE")" -gt 1000 ] || fail "packaged TUI produced no rendered frame"
rg -a -q 'What can I do for you\?' "$LOG_FILE" \
	|| fail "packaged TUI did not render its input screen"
if rg -a -qi \
	'Cannot find package|dlopen failed|error while loading shared libraries|BindingError|Renderer not found' \
	"$LOG_FILE"; then
	fail "packaged TUI reported a module or native-library load failure"
fi
ok "packaged TUI rendered its input screen in a pseudo-terminal"

ok "Installed candidate acceptance passed for $EXPECTED_RELEASE"
