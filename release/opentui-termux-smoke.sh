#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

BUN_CANARY_DIR="${BUN_CANARY_DIR:-$HOME/.local/opt/bun-android-canary}"
BUN_BIN="${BUN_BIN:-$BUN_CANARY_DIR/bun-linux-aarch64-android/bun}"
SMOKE_DIR="${SMOKE_DIR:-$HOME/tmp/opentui-termux-alias-force}"
OPENTUI_VERSION="${OPENTUI_VERSION:-0.4.3}"

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

[ -x "$BUN_BIN" ] || fail "Bun not found at $BUN_BIN. Run release/termux-v3-smoke.sh --install-bun first."
command -v npm >/dev/null 2>&1 || fail "npm is required for the OpenTUI Termux alias smoke"

info "Using Bun $($BUN_BIN --version) at $BUN_BIN"
info "Preparing OpenTUI smoke project at $SMOKE_DIR"
rm -rf "$SMOKE_DIR"
mkdir -p "$SMOKE_DIR/project"
cd "$SMOKE_DIR/project"

cat > package.json <<EOF
{
  "type": "module",
  "dependencies": {
    "@opentui/core": "$OPENTUI_VERSION",
    "@opentui/core-android-arm64": "npm:@opentui/core-linux-arm64@$OPENTUI_VERSION",
    "@opentui/react": "$OPENTUI_VERSION",
    "react": "19.2.4",
    "react-reconciler": "0.32.0"
  }
}
EOF

info "Installing OpenTUI with Android alias workaround"
npm install --force --omit=dev > npm-install.log 2>&1 || {
	cat npm-install.log >&2
	fail "npm install failed"
}

info "Importing @opentui/core and @opentui/react with Bun"
"$BUN_BIN" -e '
const core = await import("@opentui/core")
const react = await import("@opentui/react")
console.log("core-ok " + Object.keys(core).slice(0, 8).join(","))
console.log("react-ok " + Object.keys(react).slice(0, 8).join(","))
' > import.log 2>&1 || {
	cat import.log >&2
	fail "OpenTUI import failed"
}
cat import.log
ok "OpenTUI imports under Bun on Termux with the Android alias workaround"
