#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

TARBALL=""
BUN_TARBALL=""
WORK_DIR="${CLINE_TERMUX_TEST_DIR:-}"
KEEP_WORK=false
INSTALL_SCRIPT=""

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

usage() {
	cat <<EOF
Usage: bash release/test-termux-install.sh --from-tarball FILE [options]

Options:
  --from-tarball FILE  Test install from a local cline-termux tarball
  --bun-tarball FILE   Provide a local bun-android-ffi tarball to the installer
  --keep-work          Keep the temporary install sandbox
  -h, --help           Show this help
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--from-tarball)
			[ -n "${2:-}" ] || fail "--from-tarball requires a file"
			TARBALL="$2"
			shift 2
			;;
		--bun-tarball)
			[ -n "${2:-}" ] || fail "--bun-tarball requires a file"
			BUN_TARBALL="$2"
			shift 2
			;;
		--keep-work)
			KEEP_WORK=true
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			fail "unknown option: $1"
			;;
	esac
done

[ -n "${PREFIX:-}" ] || fail "PREFIX is not set; this must run inside Termux"
[ "$(uname -m)" = "aarch64" ] || fail "expected aarch64 Termux"
[ -n "$TARBALL" ] || fail "--from-tarball is required"
[ -f "$TARBALL" ] || fail "tarball not found: $TARBALL"
if [ -n "$BUN_TARBALL" ]; then
	[ -f "$BUN_TARBALL" ] || fail "Bun tarball not found: $BUN_TARBALL"
fi

if [ -z "$WORK_DIR" ]; then
	WORK_DIR=$(mktemp -d "$HOME/tmp/cline-termux-install-test.XXXXXX")
else
	rm -rf "$WORK_DIR"
	mkdir -p "$WORK_DIR"
fi

cleanup() {
	if [ "$KEEP_WORK" = false ] && [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
		rm -rf "$WORK_DIR"
	fi
}
trap cleanup EXIT

info "Using test sandbox $WORK_DIR"
mkdir -p "$WORK_DIR/bin" "$WORK_DIR/extract"
tar xzf "$TARBALL" -C "$WORK_DIR/extract"
if [ -n "$BUN_TARBALL" ]; then
	cp "$BUN_TARBALL" "$WORK_DIR/extract/"
	if [ -f "$BUN_TARBALL.sha256" ]; then
		cp "$BUN_TARBALL.sha256" "$WORK_DIR/extract/"
	fi
fi
BUNDLE_DIR=$(find "$WORK_DIR/extract" -maxdepth 1 -type d -name 'cline-termux-aarch64-v*' | head -n 1)
[ -d "$BUNDLE_DIR" ] || fail "bundle directory not found after extraction"

INSTALL_SCRIPT="$BUNDLE_DIR/install.sh"
[ -f "$INSTALL_SCRIPT" ] || fail "bundle is missing install.sh"

CLINE_TERMUX_INSTALL_BASE="$WORK_DIR/opt/cline-termux" \
CLINE_TERMUX_BUN_INSTALL_BASE="$WORK_DIR/opt/bun-android-ffi" \
CLINE_TERMUX_BUN_LINK_PATH="$WORK_DIR/bin/bun-ffi" \
CLINE_TERMUX_LAUNCHER_PATH="$WORK_DIR/bin/cline" \
CLINE_TERMUX_SKIP_PKG_UPDATE=1 \
CLINE_TERMUX_FORCE=1 \
	bash "$INSTALL_SCRIPT" --skip-pkg-update --force

[ -x "$WORK_DIR/bin/cline" ] || fail "test launcher was not created"
[ -L "$WORK_DIR/opt/cline-termux/current" ] || fail "current symlink was not created"
[ -f "$WORK_DIR/opt/cline-termux/current/index.js" ] || fail "index.js missing from install"
[ -x "$WORK_DIR/opt/bun-android-ffi/current/bun" ] || fail "Bun FFI runtime missing from install"
[ -L "$WORK_DIR/bin/bun-ffi" ] || fail "bun-ffi symlink was not created"
[ -f "$WORK_DIR/opt/cline-termux/current/node_modules/@opentui/core-android-arm64/libopentui.so" ] \
	|| fail "OpenTUI Android native library missing from install"
rg -q --glob 'index-*.js' \
	'process\.platform === "linux" \|\| process\.platform === "android"' \
	"$WORK_DIR/opt/cline-termux/current/node_modules/@opentui/core" \
	|| fail "OpenTUI Android renderer-thread patch missing from install"

VERSION_FILE="$WORK_DIR/opt/cline-termux/current/VERSION"
CLINE_VERSION=$(sed -n 's/^cline=//p' "$VERSION_FILE" | head -n 1)
if dpkg --compare-versions "$CLINE_VERSION" ge 3.0.43; then
	[ -f "$WORK_DIR/opt/cline-termux/current/cline-node-wrapper.cjs" ] \
		|| fail "upstream Node launcher missing from install"
	[ -f "$WORK_DIR/opt/cline-termux/current/ca-certs.cjs" ] \
		|| fail "upstream certificate helper missing from install"
	[ -x "$WORK_DIR/opt/cline-termux/current/run-cline-termux.sh" ] \
		|| fail "Termux runtime adapter missing from install"
	CA_TEST_DIR="$WORK_DIR/ca-test"
	mkdir -p "$CA_TEST_DIR"
	INSTALLED_VERSION=$(CLINE_DIR="$CA_TEST_DIR" "$WORK_DIR/bin/cline" --version)
	[ -s "$CA_TEST_DIR/cli-node-extra-ca-certs.pem" ] \
		|| fail "Cline launcher did not create a managed OS trust bundle"
else
	INSTALLED_VERSION=$("$WORK_DIR/bin/cline" --version)
fi
[ "$INSTALLED_VERSION" = "$CLINE_VERSION" ] \
	|| fail "expected cline --version to print $CLINE_VERSION, got $INSTALLED_VERSION"

"$WORK_DIR/bin/cline" --help >/dev/null
ok "Install smoke passed: cline --version -> $INSTALLED_VERSION"

if [ "$KEEP_WORK" = true ]; then
	echo "Sandbox: $WORK_DIR"
fi
