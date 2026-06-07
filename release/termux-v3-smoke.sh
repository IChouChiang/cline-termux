#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

REPO_DIR="$HOME/workspace/cline-termux-v3-phone"
BUN_CANARY_DIR="${BUN_CANARY_DIR:-$HOME/.local/opt/bun-android-canary}"
BUN_ANDROID_URL="${BUN_ANDROID_URL:-https://github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64-android.zip}"
OPENTUI_VERSION="${OPENTUI_VERSION:-0.1.102}"
OPENTUI_SMOKE_DIR="${OPENTUI_SMOKE_DIR:-$HOME/tmp/opentui-termux-runtime-smoke}"
INSTALL_BUN=false
RUNTIME_ONLY=false
SKIP_OPENTUI_SMOKE=false
PACKAGE_MANAGER="${TERMUX_V3_PACKAGE_MANAGER:-bun}"

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
Usage: bash release/termux-v3-smoke.sh [options] [repo-dir]

Options:
  --install-bun          Install official Bun Android ARM64 into $BUN_CANARY_DIR if missing
	--package-manager pm   Install SDK dependencies with npm or bun (default: $PACKAGE_MANAGER)
  --runtime-only         Stop after Node, Bun, and OpenTUI import checks
  --skip-opentui-smoke   Skip the temporary OpenTUI Android alias import check
  -h, --help             Show this help
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--install-bun)
			INSTALL_BUN=true
			shift
			;;
		--package-manager)
			[ -n "${2:-}" ] || fail "--package-manager requires npm or bun"
			PACKAGE_MANAGER="$2"
			shift 2
			;;
		--runtime-only)
			RUNTIME_ONLY=true
			shift
			;;
		--skip-opentui-smoke)
			SKIP_OPENTUI_SMOKE=true
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		--*)
			fail "unknown option: $1"
			;;
		*)
			REPO_DIR="$1"
			shift
			;;
	esac
done

CLI_DIR="$REPO_DIR/sdk/apps/cli"
SDK_DIR="$REPO_DIR/sdk"

case "$PACKAGE_MANAGER" in
	npm|bun)
		;;
	*)
		fail "unsupported package manager: $PACKAGE_MANAGER"
		;;
esac

install_bun_canary() {
	command -v curl >/dev/null 2>&1 || fail "curl is required to install Bun canary"
	command -v unzip >/dev/null 2>&1 || fail "unzip is required to install Bun canary"
	mkdir -p "$BUN_CANARY_DIR"
	(
		cd "$BUN_CANARY_DIR"
		rm -rf bun-linux-aarch64-android bun.zip
		info "Downloading official Bun Android aarch64 build"
		curl -fL --retry 3 -o bun.zip "$BUN_ANDROID_URL"
		unzip -oq bun.zip
		chmod +x "$BUN_CANARY_DIR/bun-linux-aarch64-android/bun"
	)
}

find_bun() {
	if command -v bun >/dev/null 2>&1; then
		command -v bun
		return
	fi
	local canary_bun="$BUN_CANARY_DIR/bun-linux-aarch64-android/bun"
	if [ -x "$canary_bun" ]; then
		echo "$canary_bun"
		return
	fi
	return 1
}

smoke_opentui_import() {
	command -v npm >/dev/null 2>&1 || fail "npm is required for the OpenTUI Termux alias smoke"

	info "Checking OpenTUI import with Android ARM64 alias workaround"
	rm -rf "$OPENTUI_SMOKE_DIR"
	mkdir -p "$OPENTUI_SMOKE_DIR/project"
	(
		cd "$OPENTUI_SMOKE_DIR/project"
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
		npm install --force --omit=dev > npm-install.log 2>&1 || {
			cat npm-install.log >&2
			fail "OpenTUI npm alias install failed"
		}
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
	)
	ok "OpenTUI imports under Bun on Termux with the Android alias workaround"
}

install_opentui_android_alias() {
	command -v npm >/dev/null 2>&1 || fail "npm is required to install the OpenTUI Android alias workaround"
	[ -d "$SDK_DIR/node_modules" ] || fail "SDK node_modules is missing after dependency install"

	info "Installing OpenTUI Linux ARM64 native package as Android alias"
	(
		cd "$SDK_DIR"
		npm install --force --ignore-scripts --no-audit --no-fund --no-save "@opentui/core-linux-arm64@$OPENTUI_VERSION" >/tmp/cline-v3-opentui-native.log 2>&1 || {
			cat /tmp/cline-v3-opentui-native.log >&2
			fail "OpenTUI Linux ARM64 native package install failed"
		}
		rm -rf node_modules/@opentui/core-android-arm64
		cp -R node_modules/@opentui/core-linux-arm64 node_modules/@opentui/core-android-arm64
	)
	ok "OpenTUI Android native alias installed"
}

install_sdk_dependencies() {
	case "$PACKAGE_MANAGER" in
		npm)
			command -v npm >/dev/null 2>&1 || fail "npm is required for the Termux SDK install fallback"
			info "npm source install is experimental and can be slow; prefer --runtime-only or the published CLI smoke until the Android binary target exists"
			info "Installing SDK dependencies with npm"
			(
				cd "$SDK_DIR"
				npm install --force --ignore-scripts --no-audit --no-fund >/tmp/cline-v3-npm-install.log 2>&1 || {
					cat /tmp/cline-v3-npm-install.log >&2
					fail "npm SDK dependency install failed"
				}
			)
			install_opentui_android_alias
			;;
		bun)
			info "Installing SDK dependencies with bun"
			(
				cd "$SDK_DIR"
				"$BUN_BIN" install
			)
			;;
	esac
}

info "Checking Termux v3 Cline canary prerequisites"
[ -n "${PREFIX:-}" ] || fail "PREFIX is not set; this must run inside Termux"
[ "$(uname -m)" = "aarch64" ] || fail "expected aarch64 device, got $(uname -m)"
command -v node >/dev/null 2>&1 || fail "node is missing"
NODE_MAJOR=$(node -e 'console.log(process.versions.node.split(".")[0])')
[ "$NODE_MAJOR" -ge 22 ] || fail "Node >=22 required, got $(node --version)"
ok "Node $(node --version)"

if ! BUN_BIN=$(find_bun); then
	if [ "$INSTALL_BUN" = true ]; then
		install_bun_canary
		BUN_BIN=$(find_bun) || fail "Bun canary install did not produce a runnable bun binary"
	else
		fail "bun is missing. Upstream CLI v3 requires Bun/OpenTUI. Official Bun publishes bun-linux-aarch64-android; rerun with --install-bun to install it into $BUN_CANARY_DIR."
	fi
fi
ok "Bun $($BUN_BIN --version) at $BUN_BIN"

if [ "$SKIP_OPENTUI_SMOKE" != true ]; then
	smoke_opentui_import
fi

if [ "$RUNTIME_ONLY" = true ]; then
	ok "Termux Bun/OpenTUI runtime smoke passed"
	exit 0
fi

[ -d "$CLI_DIR" ] || fail "missing CLI directory: $CLI_DIR"
[ -f "$CLI_DIR/src/index.ts" ] || fail "missing CLI entrypoint: $CLI_DIR/src/index.ts"
[ -f "$SDK_DIR/package.json" ] || fail "missing SDK package.json: $SDK_DIR/package.json"

install_sdk_dependencies

info "Running CLI source smoke checks"
(
	cd "$CLI_DIR"
	"$BUN_BIN" --conditions=development ./src/index.ts --version
	"$BUN_BIN" --conditions=development ./src/index.ts --help >/tmp/cline-v3-help.txt
)

ok "v3 CLI source can run on Termux"
echo "Help output captured at /tmp/cline-v3-help.txt"
