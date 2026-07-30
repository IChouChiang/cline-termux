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

# Fetches the genuine Android/Bionic @opentui/core-android-arm64 package
# (built from source by release/opentui-android/build-opentui-android.sh and
# published as a pinned GitHub release asset) and unpacks it into the staged
# node_modules. Every byte is checksum-verified against port-manifest.json.
install_opentui_android_package() {
	local manifest="$SCRIPT_DIR/port-manifest.json"
	local repository asset release_tag asset_sha256 lib_sha256
	repository="$(json_field "$manifest" openTuiAndroid.repository)"
	release_tag="$(json_field "$manifest" openTuiAndroid.releaseTag)"
	asset="$(json_field "$manifest" openTuiAndroid.asset)"
	asset_sha256="$(json_field "$manifest" openTuiAndroid.assetSha256)"
	lib_sha256="$(json_field "$manifest" openTuiAndroid.libSha256)"
	[ -n "$asset_sha256" ] || fail "openTuiAndroid.assetSha256 is not pinned"
	[ -n "$lib_sha256" ] || fail "openTuiAndroid.libSha256 is not pinned"

	local cache_dir="$SCRIPT_DIR/.tools/opentui-android"
	local tarball=""
	local candidate
	for candidate in "$SCRIPT_DIR/dist/$asset" "$cache_dir/$asset"; do
		if [ -f "$candidate" ] \
			&& [ "$(sha256sum "$candidate" | awk '{print $1}')" = "$asset_sha256" ]; then
			tarball="$candidate"
			break
		fi
	done
	if [ -z "$tarball" ]; then
		command -v curl >/dev/null 2>&1 || fail "curl is required to fetch $asset"
		mkdir -p "$cache_dir"
		info "Downloading $asset from $repository@$release_tag..."
		curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
			--connect-timeout 15 --max-time 300 \
			--output "$cache_dir/$asset" \
			"https://github.com/$repository/releases/download/$release_tag/$asset"
		tarball="$cache_dir/$asset"
	fi
	[ "$(sha256sum "$tarball" | awk '{print $1}')" = "$asset_sha256" ] \
		|| fail "checksum mismatch for $asset"

	local package_dir="$STAGE_DIR/node_modules/@opentui/core-android-arm64"
	rm -rf "$package_dir"
	mkdir -p "$package_dir"
	tar xzf "$tarball" -C "$package_dir" --strip-components=1 package
	[ "$(sha256sum "$package_dir/libopentui.so" | awk '{print $1}')" = "$lib_sha256" ] \
		|| fail "checksum mismatch for the packaged libopentui.so"
	[ -f "$package_dir/VERSION" ] \
		|| fail "the Android OpenTUI package is missing its VERSION provenance"
	info "Unpacked the checksum-verified Android OpenTUI package"
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

if [ -f "$CLI_DIR/bin/ca-certs.cjs" ]; then
	[ -f "$CLI_DIR/bin/cline" ] \
		|| fail "Cline certificate support is missing apps/cli/bin/cline"
	info "Packaging the upstream Node trust-store wrapper..."
	cp "$CLI_DIR/bin/cline" "$STAGE_DIR/cline-node-wrapper.cjs"
	cp "$CLI_DIR/bin/ca-certs.cjs" "$STAGE_DIR/ca-certs.cjs"
	cp "$SCRIPT_DIR/run-cline-termux.sh" "$STAGE_DIR/run-cline-termux.sh"
	chmod +x "$STAGE_DIR/run-cline-termux.sh"
	mkdir -p "$STAGE_DIR/empty-ca-dir"
fi

info "Resolving the locked Android/ARM64 runtime dependencies..."
mkdir -p "$STAGE_DIR/patches"
# Copy every port patch rather than naming versions, so an OpenTUI bump only
# requires renaming the patch files. runtime-package derives the matching
# patchedDependencies keys from the installed versions.
cp "$REPO_ROOT"/patches/*.patch "$STAGE_DIR/patches/"
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
install_opentui_android_package

[ -f "$STAGE_DIR/node_modules/@opentui/core-android-arm64/libopentui.so" ] \
	|| fail "missing OpenTUI Android native library"
[ -f "$STAGE_DIR/node_modules/@opentui-ui/dialog/package.json" ] \
	|| fail "missing patched @opentui-ui/dialog runtime package"
rg -q 'getDialogVerticalAlign' "$STAGE_DIR/node_modules/@opentui-ui/dialog/dist" \
	|| fail "the OpenTUI dialog safe-area patch was not applied"
rg -q 'this\.remove\(renderable\)' "$STAGE_DIR/node_modules/@opentui-ui/dialog/dist" \
	|| fail "the upstream OpenTUI dialog remove() fix was not applied"
rg -q --glob 'index-*.js' \
	'process\.platform === "linux" \|\| process\.platform === "android"' \
	"$STAGE_DIR/node_modules/@opentui/core" \
	|| fail "the OpenTUI Android renderer-thread patch was not applied"
# OpenTUI 0.4.x resolves its native package through a hardcoded
# darwin/linux/win32 chain that throws on Android. Without this hunk the build
# installs cleanly and only fails at launch on the device.
rg -q --glob 'index-*.js' \
	'@opentui/core-android-arm64' \
	"$STAGE_DIR/node_modules/@opentui/core" \
	|| fail "the OpenTUI Android native-package resolver patch was not applied"

# The genuine Bionic package replaces the Linux prebuilt entirely; nothing may
# alias or rewrite it. patchelf remains as a read-only verifier.
rm -rf "$STAGE_DIR/node_modules/@opentui/core-linux-arm64"
OPENTUI_LIB="$STAGE_DIR/node_modules/@opentui/core-android-arm64/libopentui.so"
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
