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
# The acceptance Hub gets its own data directory and port, so it neither meets
# nor stops a Hub the user already runs.
ACCEPTANCE_HUB_PORT=25496
HUB_HOME=""
HUB_STARTED=0
acceptance_hub() {
	timeout 60 env CLINE_DIR="$HUB_HOME" CLINE_HUB_PORT="$ACCEPTANCE_HUB_PORT" \
		CLINE_NO_AUTO_UPDATE=1 "$LAUNCHER" hub "$@"
}
cleanup() {
	stop_tui_smoke
	if [ "$HUB_STARTED" = 1 ]; then
		acceptance_hub stop >/dev/null 2>&1 || true
	fi
	[ -z "$HUB_HOME" ] || rm -rf "$HUB_HOME"
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

# The Hub daemon is spawned as `<runtime> <release>/entry.js`. Releases before
# 3.0.68-termux.2 shipped no entry.js, so every start failed and the CLI
# quietly ran in-process. From then on a Hub must start from this exact
# release and stop again. That check is isolated; the TUI smoke above, like
# any TUI session, may still leave the user's own auto-started Hub running.
if dpkg --compare-versions "${EXPECTED_RELEASE#v}" ge 3.0.68-termux.2; then
	[ -f "$RUNTIME_DIR/entry.js" ] || fail "missing Hub daemon entry: $RUNTIME_DIR/entry.js"
	HUB_HOME="$(mktemp -d "$HOME/tmp/cline-termux-hub.XXXXXX")"
	HUB_STARTED=1
	HUB_URL="$(acceptance_hub start | tail -n 1)" || {
		tail -n 20 "$HUB_HOME/data/logs/hub-daemon.log" >&2 || true
		fail "cline hub start did not bring up a Hub"
	}
	[ "$HUB_URL" = "ws://127.0.0.1:$ACCEPTANCE_HUB_PORT/hub" ] \
		|| fail "cline hub start reported an unexpected URL: ${HUB_URL:-<empty>}"
	HUB_STATUS="$(acceptance_hub status)"
	HUB_PID="$(printf '%s\n' "$HUB_STATUS" | sed -n 's/.*"running":true.*"pid":\([0-9][0-9]*\).*/\1/p')"
	[ -n "$HUB_PID" ] && [ -r "/proc/$HUB_PID/cmdline" ] \
		|| fail "cline hub status reported no live Hub process: $HUB_STATUS"
	HUB_ENTRY="$(tr '\0' '\n' < "/proc/$HUB_PID/cmdline" | sed -n 2p)"
	[ "$(realpath "$HUB_ENTRY" 2>/dev/null)" = "$RUNTIME_DIR/entry.js" ] \
		|| fail "the running Hub (pid $HUB_PID, entry ${HUB_ENTRY:-?}) is not this release's daemon"
	HUB_STOP="$(acceptance_hub stop)"
	printf '%s\n' "$HUB_STOP" | rg -q '"stopped":true' \
		|| fail "cline hub stop did not stop the Hub: $HUB_STOP"
	HUB_STARTED=0
	ok "Hub daemon starts from this release and stops cleanly"
fi

ok "Installed candidate acceptance passed for $EXPECTED_RELEASE"
