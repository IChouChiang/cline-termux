#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_DIR="$REPO_ROOT/apps/cli"
DIST_DIR="${CLINE_TERMUX_DIST_DIR:-$SCRIPT_DIR/dist}"
STAGING_DIR="${CLINE_TERMUX_STAGING_DIR:-$SCRIPT_DIR/staging}"
BUN_BIN="${BUN_BIN:-bun}"
PATCHELF_BIN="${PATCHELF_BIN:-patchelf}"
RELEASE_VERSION="${CLINE_TERMUX_RELEASE_VERSION:-}"
SKIP_BUILD=false
KEEP_STAGING=false

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
Usage: bash release/build-termux-release.sh [options]

Builds a deterministic Cline Termux Android/ARM64 release tarball. Runtime
dependencies are resolved locally from the repository lockfile; a phone is not
used as a build input.

Options:
  --release VERSION  Release version/tag, for example v3.0.30-termux.1
  --skip-build       Use existing apps/cli/dist instead of rebuilding
  --keep-staging     Keep release/staging after the tarball is produced
  -h, --help         Show this help
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--release)
			[ -n "${2:-}" ] || fail "--release requires a value"
			RELEASE_VERSION="$2"
			shift 2
			;;
		--skip-build)
			SKIP_BUILD=true
			shift
			;;
		--keep-staging)
			KEEP_STAGING=true
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

normalize_version() {
	case "$1" in
		v*) printf '%s\n' "${1#v}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}

json_field() {
	node -e 'const fs=require("fs"); const data=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); console.log(process.argv[2].split(".").reduce((value, key) => value[key], data))' "$1" "$2"
}

patch_android_alias_package_json() {
	local package_json="$1"
	node -e '
const fs = require("fs")
const file = process.argv[1]
const pkg = JSON.parse(fs.readFileSync(file, "utf8"))
pkg.name = "@opentui/core-android-arm64"
pkg.description = "Prebuilt android-arm64 binaries for @opentui/core"
pkg.os = ["android"]
pkg.cpu = ["arm64"]
fs.writeFileSync(file, `${JSON.stringify(pkg, null, 2)}\n`)
' "$package_json"
}

CLINE_VERSION="$(json_field "$CLI_DIR/package.json" version)"
if [ -z "$RELEASE_VERSION" ]; then
	RELEASE_VERSION="v$CLINE_VERSION-termux.1"
fi
RELEASE_VERSION="$(normalize_version "$RELEASE_VERSION")"
RELEASE_TAG="v$RELEASE_VERSION"
RELEASE_NAME="cline-termux-aarch64-v$RELEASE_VERSION"
STAGE_DIR="$STAGING_DIR/$RELEASE_NAME"
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
UPSTREAM_TAG="$(json_field "$SCRIPT_DIR/port-manifest.json" upstream.tag)"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$REPO_ROOT" show -s --format=%ct HEAD)}"
BUILT_AT="$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"

case "$RELEASE_VERSION" in
	"$CLINE_VERSION"-termux.*) ;;
	*) fail "release version '$RELEASE_VERSION' should begin with '$CLINE_VERSION-termux.'" ;;
esac

command -v node >/dev/null 2>&1 || fail "node is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"
command -v gzip >/dev/null 2>&1 || fail "gzip is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
command -v rg >/dev/null 2>&1 || fail "ripgrep is required"
[ -x "$BUN_BIN" ] || command -v "$BUN_BIN" >/dev/null 2>&1 || fail "Bun is required: $BUN_BIN"
[ -x "$PATCHELF_BIN" ] || command -v "$PATCHELF_BIN" >/dev/null 2>&1 \
	|| fail "patchelf is required: $PATCHELF_BIN"

if [ "$SKIP_BUILD" = false ]; then
	info "Building @cline/cli with $BUN_BIN..."
	(
		cd "$REPO_ROOT"
		"$BUN_BIN" -F @cline/cli build
	)
fi

[ -f "$CLI_DIR/dist/index.js" ] || fail "missing $CLI_DIR/dist/index.js"
[ -d "$CLI_DIR/dist/extensions" ] || fail "missing $CLI_DIR/dist/extensions"
[ -d "$CLI_DIR/dist/cline-hub" ] || fail "missing $CLI_DIR/dist/cline-hub"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"

info "Copying the Cline bundle..."
cp "$CLI_DIR/dist/index.js" "$STAGE_DIR/index.js"
chmod +x "$STAGE_DIR/index.js"
cp -R "$CLI_DIR/dist/extensions" "$STAGE_DIR/extensions"
cp -R "$CLI_DIR/dist/cline-hub" "$STAGE_DIR/cline-hub"
cp "$SCRIPT_DIR/install-cline-termux.sh" "$STAGE_DIR/install.sh"
chmod +x "$STAGE_DIR/install.sh"

info "Resolving the locked Android/ARM64 runtime dependencies..."
mkdir -p "$STAGE_DIR/patches"
cp "$REPO_ROOT/patches/@opentui%2Fcore@0.1.102.patch" "$STAGE_DIR/patches/"
cp "$REPO_ROOT/patches/@opentui-ui%2Fdialog@0.1.2.patch" "$STAGE_DIR/patches/"
node "$SCRIPT_DIR/port-metadata.mjs" runtime-package \
	"$STAGE_DIR/package.json" "$RELEASE_VERSION"
(
	cd "$STAGE_DIR"
	"$BUN_BIN" install \
		--production \
		--ignore-scripts \
		--cpu arm64 \
		--os linux \
		--backend copyfile
)

[ -f "$STAGE_DIR/node_modules/@opentui/core-android-arm64/libopentui.so" ] \
	|| fail "missing OpenTUI Android native library"
[ -f "$STAGE_DIR/node_modules/@opentui-ui/dialog/package.json" ] \
	|| fail "missing patched @opentui-ui/dialog runtime package"
rg -q 'getDialogVerticalAlign' "$STAGE_DIR/node_modules/@opentui-ui/dialog/dist" \
	|| fail "the OpenTUI dialog safe-area patch was not applied"
rg -q --glob 'index-*.js' \
	'process\.platform === "linux" \|\| process\.platform === "android"' \
	"$STAGE_DIR/node_modules/@opentui/core" \
	|| fail "the OpenTUI Android renderer-thread patch was not applied"

patch_android_alias_package_json \
	"$STAGE_DIR/node_modules/@opentui/core-android-arm64/package.json"
rm -rf "$STAGE_DIR/node_modules/@opentui/core-linux-arm64"
OPENTUI_LIB="$STAGE_DIR/node_modules/@opentui/core-android-arm64/libopentui.so"
if ! "$PATCHELF_BIN" --print-needed "$OPENTUI_LIB" | grep -Fxq libc.so; then
	info "Adding the Android libc dependency to libopentui.so..."
	"$PATCHELF_BIN" --add-needed libc.so "$OPENTUI_LIB"
fi
"$PATCHELF_BIN" --print-needed "$OPENTUI_LIB" | grep -Fxq libc.so \
	|| fail "libopentui.so is missing its Android libc dependency"

printf '%s\n' \
	"release=$RELEASE_VERSION" \
	"tag=$RELEASE_TAG" \
	"cline=$CLINE_VERSION" \
	"source=$SOURCE_COMMIT" \
	"upstream=$UPSTREAM_TAG" \
	"platform=termux-android" \
	"arch=aarch64" \
	"built=$BUILT_AT" \
	> "$STAGE_DIR/VERSION"

TARBALL="$DIST_DIR/$RELEASE_NAME.tar.gz"
CHECKSUM="$TARBALL.sha256"

info "Creating deterministic release archive..."
rm -f "$TARBALL" "$CHECKSUM"
(
	cd "$STAGING_DIR"
	tar \
		--sort=name \
		--mtime="@$SOURCE_DATE_EPOCH" \
		--owner=0 \
		--group=0 \
		--numeric-owner \
		-cf - "$RELEASE_NAME" | gzip -n > "$TARBALL"
)
(
	cd "$DIST_DIR"
	sha256sum "$RELEASE_NAME.tar.gz" > "$RELEASE_NAME.tar.gz.sha256"
)

if [ "$KEEP_STAGING" = false ]; then
	rm -rf "$STAGE_DIR"
fi

ok "Release bundle ready."
echo "Tag:      $RELEASE_TAG"
echo "Tarball:  $TARBALL"
echo "Checksum: $CHECKSUM"
