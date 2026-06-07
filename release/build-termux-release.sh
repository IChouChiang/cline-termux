#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_DIR="$REPO_ROOT/apps/cli"
DIST_DIR="$SCRIPT_DIR/dist"
STAGING_DIR="$SCRIPT_DIR/staging"
TERMUX_HOST="${TERMUX_HOST:-termux_wifi}"
TERMUX_RUNTIME_DIR="${TERMUX_RUNTIME_DIR:-~/cline-v3}"
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

Builds a Cline Termux release tarball from the current repo bundle and a
tested Termux Android/ARM64 runtime dependency tree.

Options:
  --termux-host HOST     SSH host that can read the Termux runtime (default: $TERMUX_HOST)
  --runtime-dir DIR      Runtime dir on HOST containing node_modules (default: $TERMUX_RUNTIME_DIR)
  --release VERSION      Release version/tag, for example v3.0.20-termux.1
  --skip-build           Use existing apps/cli/dist instead of rebuilding
  --keep-staging         Keep release/staging after the tarball is produced
  -h, --help             Show this help
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--termux-host)
			[ -n "${2:-}" ] || fail "--termux-host requires a value"
			TERMUX_HOST="$2"
			shift 2
			;;
		--runtime-dir)
			[ -n "${2:-}" ] || fail "--runtime-dir requires a value"
			TERMUX_RUNTIME_DIR="$2"
			shift 2
			;;
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
	node -e "const fs=require('fs'); const data=JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); console.log(data[process.argv[2]])" "$1" "$2"
}

copy_dir() {
	local src="$1"
	local dst="$2"
	rm -rf "$dst"
	mkdir -p "$(dirname "$dst")"
	cp -R "$src" "$dst"
}

patch_android_alias_package_json() {
	local pkg_json="$1"
	node -e '
const fs = require("fs")
const file = process.argv[1]
const pkg = JSON.parse(fs.readFileSync(file, "utf8"))
pkg.name = "@opentui/core-android-arm64"
pkg.description = "Prebuilt android-arm64 binaries for @opentui/core"
pkg.os = ["android"]
pkg.cpu = ["arm64"]
fs.writeFileSync(file, `${JSON.stringify(pkg, null, 2)}\n`)
' "$pkg_json"
}

CLINE_VERSION="$(json_field "$CLI_DIR/package.json" version)"
if [ -z "$RELEASE_VERSION" ]; then
	RELEASE_VERSION="v$CLINE_VERSION-termux.1"
fi
RELEASE_VERSION="$(normalize_version "$RELEASE_VERSION")"
RELEASE_TAG="v$RELEASE_VERSION"
RELEASE_NAME="cline-termux-aarch64-v$RELEASE_VERSION"
STAGE_DIR="$STAGING_DIR/$RELEASE_NAME"
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
UPSTREAM_TAG="$(git -C "$REPO_ROOT" describe --tags --match 'cli-v*' --abbrev=0 2>/dev/null || echo unknown)"

case "$RELEASE_VERSION" in
	"$CLINE_VERSION"-termux.*)
		;;
	*)
		fail "release version '$RELEASE_VERSION' should begin with '$CLINE_VERSION-termux.'"
		;;
esac

command -v node >/dev/null 2>&1 || fail "node is required"
command -v rsync >/dev/null 2>&1 || fail "rsync is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

if [ "$SKIP_BUILD" = false ]; then
	info "Building @cline/cli..."
	(
		cd "$REPO_ROOT"
		PATH="$HOME/.bun/bin:$PATH" bun -F @cline/cli build
	)
fi

[ -f "$CLI_DIR/dist/index.js" ] || fail "missing $CLI_DIR/dist/index.js"
[ -d "$CLI_DIR/dist/extensions" ] || fail "missing $CLI_DIR/dist/extensions"
[ -d "$CLI_DIR/dist/cline-hub" ] || fail "missing $CLI_DIR/dist/cline-hub"

info "Checking Termux runtime on $TERMUX_HOST..."
ssh -o ConnectTimeout=8 "$TERMUX_HOST" "test \"\$(uname -m)\" = aarch64 && test -d $TERMUX_RUNTIME_DIR/node_modules && test -f $TERMUX_RUNTIME_DIR/node_modules/@opentui/core/package.json" \
	|| fail "Termux runtime is not usable. Expected node_modules under $TERMUX_RUNTIME_DIR on $TERMUX_HOST."

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"

info "Copying Cline bundle..."
cp "$CLI_DIR/dist/index.js" "$STAGE_DIR/index.js"
chmod +x "$STAGE_DIR/index.js"
copy_dir "$CLI_DIR/dist/extensions" "$STAGE_DIR/extensions"
copy_dir "$CLI_DIR/dist/cline-hub" "$STAGE_DIR/cline-hub"
cp "$SCRIPT_DIR/install-cline-termux.sh" "$STAGE_DIR/install.sh"
chmod +x "$STAGE_DIR/install.sh"

info "Syncing Android runtime dependencies from Termux..."
mkdir -p "$STAGE_DIR/node_modules"
rsync -a --delete \
	--exclude '.cache' \
	--exclude '.bin' \
	--exclude '@opentui/core-linux-x64' \
	--exclude '@cline/cli-linux-x64' \
	--exclude 'bun-webgpu-linux-x64' \
	"$TERMUX_HOST:$TERMUX_RUNTIME_DIR/node_modules/" \
	"$STAGE_DIR/node_modules/"

if [ ! -d "$STAGE_DIR/node_modules/@opentui/core-android-arm64" ]; then
	if [ -d "$STAGE_DIR/node_modules/@opentui/core-linux-arm64" ]; then
		info "Creating @opentui/core-android-arm64 alias from linux-arm64 native package..."
		copy_dir "$STAGE_DIR/node_modules/@opentui/core-linux-arm64" "$STAGE_DIR/node_modules/@opentui/core-android-arm64"
		patch_android_alias_package_json "$STAGE_DIR/node_modules/@opentui/core-android-arm64/package.json"
	else
		fail "missing @opentui/core-android-arm64 and no linux-arm64 native package was available to alias"
	fi
fi

[ -f "$STAGE_DIR/node_modules/@opentui/core-android-arm64/libopentui.so" ] \
	|| fail "missing OpenTUI Android native library"
[ -f "$STAGE_DIR/node_modules/@opentui-ui/dialog/package.json" ] \
	|| fail "missing patched @opentui-ui/dialog runtime package"

cat > "$STAGE_DIR/package.json" <<EOF
{
  "name": "cline-termux",
  "version": "$RELEASE_VERSION",
  "private": true,
  "type": "module",
  "description": "Cline CLI $CLINE_VERSION packaged for Termux Android aarch64",
  "bin": {
    "cline": "./index.js"
  },
  "os": [
    "android"
  ],
  "cpu": [
    "arm64"
  ]
}
EOF

cat > "$STAGE_DIR/VERSION" <<EOF
release=$RELEASE_VERSION
tag=$RELEASE_TAG
cline=$CLINE_VERSION
source=$SOURCE_COMMIT
upstream=$UPSTREAM_TAG
platform=termux-android
arch=aarch64
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

if ssh "$TERMUX_HOST" "test -f $TERMUX_RUNTIME_DIR/bun.lock"; then
	rsync -a "$TERMUX_HOST:$TERMUX_RUNTIME_DIR/bun.lock" "$STAGE_DIR/bun.lock"
fi

TARBALL="$DIST_DIR/$RELEASE_NAME.tar.gz"
CHECKSUM="$TARBALL.sha256"

info "Creating tarball..."
rm -f "$TARBALL" "$CHECKSUM"
(
	cd "$STAGING_DIR"
	tar czf "$TARBALL" "$RELEASE_NAME"
)

(
	cd "$DIST_DIR"
	sha256sum "$RELEASE_NAME.tar.gz" > "$RELEASE_NAME.tar.gz.sha256"
)

if [ "$KEEP_STAGING" = false ]; then
	rm -rf "$STAGE_DIR"
fi

ok "Release bundle ready."
echo "Tag:       $RELEASE_TAG"
echo "Tarball:   $TARBALL"
echo "Checksum:  $CHECKSUM"
echo
echo "Publish later with:"
echo "gh release create $RELEASE_TAG \\"
echo "  $TARBALL \\"
echo "  $CHECKSUM \\"
echo "  $SCRIPT_DIR/install-cline-termux.sh \\"
echo "  --repo IChouChiang/cline-termux \\"
echo "  --title \"Cline Termux $RELEASE_TAG\""
