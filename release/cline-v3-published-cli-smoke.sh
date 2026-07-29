#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

CLINE_CLI_PACKAGE="${CLINE_CLI_PACKAGE:-cline}"
CLINE_CLI_VERSION="${CLINE_CLI_VERSION:-3.0.14}"
OPENTUI_VERSION="${OPENTUI_VERSION:-0.4.3}"
BUN_CANARY_DIR="${BUN_CANARY_DIR:-$HOME/.local/opt/bun-android-canary}"
BUN_BIN="${BUN_BIN:-$BUN_CANARY_DIR/bun-linux-aarch64-android/bun}"
SMOKE_DIR="${SMOKE_DIR:-}"

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
command -v npm >/dev/null 2>&1 || fail "npm is required"

info "Testing published $CLINE_CLI_PACKAGE@$CLINE_CLI_VERSION with Bun $($BUN_BIN --version)"
mkdir -p "$HOME/tmp"
if [ -z "$SMOKE_DIR" ]; then
	SMOKE_DIR=$(mktemp -d "$HOME/tmp/cline-v3-published-cli.XXXXXX")
else
	rm -rf "$SMOKE_DIR"
	mkdir -p "$SMOKE_DIR"
fi
info "Using smoke directory $SMOKE_DIR"
cd "$SMOKE_DIR"

cat > package.json <<EOF
{
  "type": "module",
  "dependencies": {
		"$CLINE_CLI_PACKAGE": "$CLINE_CLI_VERSION",
		"@cline/cli-android-arm64": "npm:@cline/cli-linux-arm64@$CLINE_CLI_VERSION",
    "@opentui/core-android-arm64": "npm:@opentui/core-linux-arm64@$OPENTUI_VERSION"
  }
}
EOF

info "Installing published CLI package with OpenTUI Android alias"
npm install --force --omit=dev --ignore-scripts --no-audit --no-fund > install.log 2>&1 || {
	cat install.log >&2
	fail "published CLI install failed"
}
ok "published CLI package installed"

info "Running aliased native CLI binary --version"
node_modules/@cline/cli-android-arm64/bin/cline --version > native-version.log 2>&1 || {
	cat native-version.log >&2
	fail "aliased Linux ARM64 Cline binary is not Android-compatible"
}
cat native-version.log

info "Running published CLI wrapper --version"
node node_modules/cline/bin/cline --version > version.log 2>&1 || {
	cat version.log >&2
	fail "published CLI --version failed"
}
cat version.log

info "Running published CLI --help"
node node_modules/cline/bin/cline --help > help.log 2>&1 || {
	cat help.log >&2
	fail "published CLI --help failed"
}
head -40 help.log
ok "published Cline CLI runs on Termux through Bun"
