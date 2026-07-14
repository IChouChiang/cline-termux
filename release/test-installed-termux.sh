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

VERSION_FILE="$INSTALL_BASE/current/VERSION"
ACTUAL_RELEASE="$(read_field "$VERSION_FILE" release)"
ACTUAL_CLINE="$(read_field "$VERSION_FILE" cline)"
[ "v$ACTUAL_RELEASE" = "$EXPECTED_RELEASE" ] \
	|| fail "expected release $EXPECTED_RELEASE, found v$ACTUAL_RELEASE"
[ "$ACTUAL_CLINE" = "$EXPECTED_CLINE" ] \
	|| fail "expected Cline $EXPECTED_CLINE, found $ACTUAL_CLINE"
[ "$($LAUNCHER --version)" = "$EXPECTED_CLINE" ] \
	|| fail "cline --version did not report $EXPECTED_CLINE"
$LAUNCHER --help >/dev/null
ok "CLI metadata, version, and help"

(
	cd "$INSTALL_BASE/current"
	"$BUN_BASE/current/bun" -e '
import { dlopen } from "bun:ffi"
const lib = dlopen(
  "./node_modules/@opentui/core-android-arm64/libopentui.so",
  { createRenderer: { args: ["u32", "u32", "bool", "bool"], returns: "ptr" } },
)
if (!lib.symbols.createRenderer) process.exit(1)
' >/dev/null
)
ok "Bun FFI loads the packaged OpenTUI renderer"

command -v script >/dev/null 2>&1 || fail "script is required for the TUI PTY smoke"
command -v timeout >/dev/null 2>&1 || fail "timeout is required for the TUI PTY smoke"
mkdir -p "$HOME/tmp"
LOG_FILE="$(mktemp "$HOME/tmp/cline-termux-tui.XXXXXX")"
cleanup() {
	rm -f "$LOG_FILE"
}
trap cleanup EXIT

set +e
(sleep 7) | timeout 7 script -q -c \
	"env CLINE_NO_AUTO_UPDATE=1 $LAUNCHER --tui" "$LOG_FILE" >/dev/null 2>&1
PTY_STATUS=$?
set -e
case "$PTY_STATUS" in
	0|124|137) ;;
	*) fail "packaged TUI exited unexpectedly with status $PTY_STATUS" ;;
esac
[ "$(wc -c < "$LOG_FILE")" -gt 100 ] || fail "packaged TUI produced no screen output"
if rg -qi 'Cannot find package|dlopen failed|error while loading shared libraries' "$LOG_FILE"; then
	fail "packaged TUI reported a module or native-library load failure"
fi
ok "packaged TUI stayed alive in a pseudo-terminal"

ok "Installed candidate acceptance passed for $EXPECTED_RELEASE"
