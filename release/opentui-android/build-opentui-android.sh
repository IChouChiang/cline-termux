#!/usr/bin/env bash

set -euo pipefail

# Builds the genuine Android/Bionic @opentui/core-android-arm64 package from
# OpenTUI source with Zig and the Android NDK. No prebuilt Linux artifact is
# aliased and no ELF is rewritten; the library links against Bionic stubs and
# carries an Android ELF note.
#
# The result is an npm-layout tarball published as a GitHub release asset
# (see openTuiAndroid in release/port-manifest.json), which
# build-termux-release.sh verifies by checksum and unpacks into the runtime
# bundle.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$RELEASE_DIR/.." && pwd)"
MANIFEST="$RELEASE_DIR/port-manifest.json"
TOOLS_ROOT="$RELEASE_DIR/.tools"
WORK_ROOT="$RELEASE_DIR/.work"
DIST_DIR="$RELEASE_DIR/dist"

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

json_get() {
	node -e '
const value = process.argv[2].split(".").reduce(
  (current, key) => current[key],
  JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")),
)
if (value === undefined || value === null) process.exit(1)
console.log(value)
' "$1" "$2"
}

for required in curl git node readelf sha256sum tar unzip; do
	command -v "$required" >/dev/null 2>&1 || fail "$required is required"
done
[ "$(uname -m)" = "x86_64" ] || fail "the pinned toolchain assumes an x86_64 build host"

OPENTUI_REPO="$(json_get "$MANIFEST" openTuiAndroid.opentuiRepository)"
OPENTUI_TAG="$(json_get "$MANIFEST" openTuiAndroid.opentuiTag)"
OPENTUI_COMMIT="$(json_get "$MANIFEST" openTuiAndroid.opentuiCommit)"
OPENTUI_VERSION="$(json_get "$MANIFEST" openTuiAndroid.version)"
REVISION="$(json_get "$MANIFEST" openTuiAndroid.revision)"
ASSET_NAME="$(json_get "$MANIFEST" openTuiAndroid.asset)"
ZIG_VERSION="$(json_get "$MANIFEST" openTuiAndroid.zig)"
ZIG_SHA256="$(json_get "$MANIFEST" openTuiAndroid.zigSha256)"
NDK_RELEASE="$(json_get "$MANIFEST" openTuiAndroid.ndk)"
NDK_SHA256="$(json_get "$MANIFEST" openTuiAndroid.ndkSha256)"
API_LEVEL="$(json_get "$MANIFEST" openTuiAndroid.androidApiLevel)"
SOURCE_PATCH="$SCRIPT_DIR/opentui-v$OPENTUI_VERSION-android.patch"
[ -f "$SOURCE_PATCH" ] || fail "missing source patch: $SOURCE_PATCH"

RELEASE_NAME="opentui-core-android-arm64-v$OPENTUI_VERSION.$REVISION"
[ "$ASSET_NAME" = "$RELEASE_NAME.tgz" ] \
	|| fail "manifest asset name '$ASSET_NAME' does not match '$RELEASE_NAME.tgz'"

ensure_zig() {
	local tool_dir="$TOOLS_ROOT/zig-$ZIG_VERSION"
	local zig_bin="$tool_dir/zig-x86_64-linux-$ZIG_VERSION/zig"
	if [ ! -x "$zig_bin" ]; then
		info "Downloading Zig $ZIG_VERSION..." >&2
		mkdir -p "$tool_dir"
		curl -fLsS --retry 3 -o "$tool_dir/zig.tar.xz" \
			"https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz"
		echo "$ZIG_SHA256  $tool_dir/zig.tar.xz" | sha256sum -c - >&2 \
			|| fail "Zig archive checksum mismatch"
		tar xJf "$tool_dir/zig.tar.xz" -C "$tool_dir"
	fi
	[ "$("$zig_bin" version)" = "$ZIG_VERSION" ] || fail "could not provision Zig $ZIG_VERSION"
	printf '%s\n' "$zig_bin"
}

ensure_ndk_sysroot() {
	local tool_dir="$TOOLS_ROOT/android-ndk-$NDK_RELEASE"
	local sysroot="$tool_dir/android-ndk-$NDK_RELEASE/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
	if [ ! -d "$sysroot/usr/lib/aarch64-linux-android/$API_LEVEL" ]; then
		info "Downloading Android NDK $NDK_RELEASE (sysroot only is kept)..." >&2
		mkdir -p "$tool_dir"
		curl -fLsS --retry 3 -o "$tool_dir/ndk.zip" \
			"https://dl.google.com/android/repository/android-ndk-$NDK_RELEASE-linux.zip"
		echo "$NDK_SHA256  $tool_dir/ndk.zip" | sha256sum -c - >&2 \
			|| fail "NDK archive checksum mismatch"
		unzip -q "$tool_dir/ndk.zip" \
			"android-ndk-$NDK_RELEASE/toolchains/llvm/prebuilt/linux-x86_64/sysroot/*" \
			-d "$tool_dir"
		rm -f "$tool_dir/ndk.zip"
	fi
	[ -d "$sysroot/usr/lib/aarch64-linux-android/$API_LEVEL" ] \
		|| fail "NDK sysroot is missing API level $API_LEVEL"
	printf '%s\n' "$sysroot"
}

ZIG_BIN="$(ensure_zig)"
SYSROOT="$(ensure_ndk_sysroot)"
CRT_DIR="$SYSROOT/usr/lib/aarch64-linux-android/$API_LEVEL"

SRC_DIR="$WORK_ROOT/opentui-build-v$OPENTUI_VERSION"
if [ ! -d "$SRC_DIR/.git" ]; then
	info "Cloning OpenTUI $OPENTUI_TAG..."
	mkdir -p "$WORK_ROOT"
	git clone --quiet --depth 1 --branch "$OPENTUI_TAG" "$OPENTUI_REPO" "$SRC_DIR"
fi
ACTUAL_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
[ "$ACTUAL_COMMIT" = "$OPENTUI_COMMIT" ] \
	|| fail "OpenTUI checkout is $ACTUAL_COMMIT, expected $OPENTUI_COMMIT"
git -C "$SRC_DIR" checkout --quiet -- .
git -C "$SRC_DIR" clean --quiet -fd
git -C "$SRC_DIR" apply "$SOURCE_PATCH"
info "Applied $(basename "$SOURCE_PATCH")"

ZIG_SRC="$SRC_DIR/packages/core/src/zig"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$SRC_DIR" show -s --format=%ct HEAD)}"

LIBC_FILE="$WORK_ROOT/android-libc-$API_LEVEL.txt"
cat > "$LIBC_FILE" <<EOF
include_dir=$SYSROOT/usr/include
sys_include_dir=$SYSROOT/usr/include/aarch64-linux-android
crt_dir=$CRT_DIR
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
EOF

# Zig's own HTTP client cannot always reach GitHub; pre-seed the package cache
# with curl. build.zig.zon's content hashes still verify both archives.
prefetch_zig_deps() {
	local dep_dir="$WORK_ROOT/opentui-zig-deps"
	mkdir -p "$dep_dir"
	if [ ! -f "$dep_dir/uucode.tar.gz" ]; then
		curl -fLsS --retry 3 -o "$dep_dir/uucode.tar.gz" \
			"https://github.com/jacobsandlund/uucode/archive/84ceda8561a17ba4a9b96ac5c583f779660bbd4e.tar.gz"
	fi
	if [ ! -f "$dep_dir/yoga.tar.gz" ]; then
		curl -fLsS --retry 3 -o "$dep_dir/yoga.tar.gz" \
			"https://github.com/facebook/yoga/archive/refs/tags/v3.2.1.tar.gz"
	fi
	(cd "$ZIG_SRC" && "$ZIG_BIN" fetch "$dep_dir/uucode.tar.gz" >/dev/null)
	(cd "$ZIG_SRC" && "$ZIG_BIN" fetch "$dep_dir/yoga.tar.gz" >/dev/null)
}
prefetch_zig_deps

info "Building libopentui.so for aarch64-linux-android.$API_LEVEL..."
(
	cd "$ZIG_SRC"
	"$ZIG_BIN" build \
		"-Dtarget=aarch64-linux-android.$API_LEVEL" \
		-Doptimize=ReleaseFast \
		"-Dandroid-lib-dir=$CRT_DIR" \
		--libc "$LIBC_FILE"
)
LIB="$ZIG_SRC/lib/aarch64-linux-android.$API_LEVEL/libopentui.so"
[ -f "$LIB" ] || fail "build produced no library at $LIB"

info "Verifying the library is a genuine Bionic build..."
ELF_HEADER="$(readelf -h "$LIB")"
grep -q 'AArch64' <<< "$ELF_HEADER" || fail "not an AArch64 ELF"
readelf --notes "$LIB" > "$WORK_ROOT/libopentui-notes.txt"
grep -q 'Android' "$WORK_ROOT/libopentui-notes.txt" || fail "missing the Android ELF note"
NEEDED="$(readelf -d "$LIB" | sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p' | sort)"
[ "$NEEDED" = "$(printf 'libc.so\nlibdl.so\nlibm.so\n')" ] \
	|| fail "unexpected DT_NEEDED set: $(echo "$NEEDED" | tr '\n' ' ')"
DYN_SYMS="$WORK_ROOT/libopentui-dyn-syms.txt"
readelf --dyn-syms -W "$LIB" > "$DYN_SYMS"
grep -q '__errno_location' "$DYN_SYMS" \
	&& fail "library references glibc/musl __errno_location" || true
grep -q ' __errno' "$DYN_SYMS" \
	|| fail "library does not reference Bionic __errno"
grep -q 'WEAK.*UND mallopt' "$DYN_SYMS" \
	|| fail "missing the weak mallopt heap-tagging constructor binding"
EXPORTS="$(awk '$7!="UND" && ($5=="GLOBAL" || $5=="WEAK") && $8!="" {count++} END {print count}' "$DYN_SYMS")"
[ "$EXPORTS" -ge 1800 ] || fail "suspiciously few dynamic exports: $EXPORTS"
for symbol in createRenderer yogaNodeCreateForOpenTUI bufferDrawText; do
	grep -q " $symbol\$" "$DYN_SYMS" \
		|| fail "missing expected export: $symbol"
done
rm -f "$DYN_SYMS" "$WORK_ROOT/libopentui-notes.txt"
ok "libopentui.so is Bionic: Android ELF note, DT_NEEDED [$(echo "$NEEDED" | tr '\n' ' ' | sed 's/ $//')], __errno, $EXPORTS exports"

STAGE_DIR="$WORK_ROOT/$RELEASE_NAME/package"
rm -rf "$WORK_ROOT/${RELEASE_NAME:?}"
mkdir -p "$STAGE_DIR"
cp "$LIB" "$STAGE_DIR/libopentui.so"
cp "$SRC_DIR/LICENSE" "$STAGE_DIR/LICENSE"
PATCH_SHA256="$(sha256sum "$SOURCE_PATCH" | awk '{print $1}')"
LIB_SHA256="$(sha256sum "$LIB" | awk '{print $1}')"

node - "$STAGE_DIR/package.json" "$OPENTUI_VERSION" <<'EOF'
const fs = require("fs")
const [output, version] = process.argv.slice(2)
fs.writeFileSync(output, `${JSON.stringify({
	name: "@opentui/core-android-arm64",
	version,
	description: "Prebuilt android-arm64 (Bionic) binaries for @opentui/core, built from source for the Cline Termux port",
	type: "module",
	main: "index.js",
	module: "index.js",
	license: "MIT",
	repository: {
		type: "git",
		url: "https://github.com/IChouChiang/cline-termux",
		directory: "release/opentui-android",
	},
	exports: {
		".": {
			bun: "./index.bun.js",
			import: "./index.js",
		},
	},
	os: ["android"],
	cpu: ["arm64"],
}, null, 2)}\n`)
EOF

cat > "$STAGE_DIR/index.js" <<'EOF'
import { fileURLToPath } from "node:url"

export default fileURLToPath(new URL("./libopentui.so", import.meta.url))
EOF

cat > "$STAGE_DIR/index.bun.js" <<'EOF'
const module = await import("./libopentui.so", { with: { type: "file" } })

export default module.default
EOF

cat > "$STAGE_DIR/VERSION" <<EOF
package=@opentui/core-android-arm64
version=$OPENTUI_VERSION
revision=$REVISION
platform=android
arch=aarch64
api_level=$API_LEVEL
opentui_repo=$OPENTUI_REPO
opentui_tag=$OPENTUI_TAG
opentui_commit=$OPENTUI_COMMIT
source_patch=release/opentui-android/$(basename "$SOURCE_PATCH")
source_patch_sha256=$PATCH_SHA256
zig=$ZIG_VERSION
ndk=$NDK_RELEASE
lib_sha256=$LIB_SHA256
built=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
EOF

cat > "$STAGE_DIR/README.md" <<'EOF'
# @opentui/core-android-arm64 (Cline Termux port)

Genuine Android/Bionic build of the OpenTUI native renderer, compiled from
OpenTUI source with Zig and the Android NDK for the Cline Termux port. Not an
official OpenTUI artifact.

The only source changes are an Android target branch in build.zig and a
constructor that disables Bionic heap pointer tagging (Scudo TBI tags do not
survive Bun's f64 FFI pointer representation). See VERSION for full
provenance and the pinned toolchain.
EOF

mkdir -p "$DIST_DIR"
TARBALL="$DIST_DIR/$RELEASE_NAME.tgz"
rm -f "$TARBALL" "$TARBALL.sha256"
(
	cd "$WORK_ROOT/$RELEASE_NAME"
	tar \
		--sort=name \
		--mtime="@$SOURCE_DATE_EPOCH" \
		--owner=0 \
		--group=0 \
		--numeric-owner \
		-cf - package | gzip -n > "$TARBALL"
)
(
	cd "$DIST_DIR"
	sha256sum "$RELEASE_NAME.tgz" > "$RELEASE_NAME.tgz.sha256"
)
ASSET_SHA256="$(awk '{print $1}' "$TARBALL.sha256")"

ok "Android OpenTUI package ready."
echo "Tarball:      $TARBALL"
echo "assetSha256:  $ASSET_SHA256"
echo "libSha256:    $LIB_SHA256"
echo
echo "Record both hashes in release/port-manifest.json (openTuiAndroid) and publish with:"
echo "  gh release create opentui-android-v$OPENTUI_VERSION.$REVISION \\"
echo "    '$TARBALL' '$TARBALL.sha256' \\"
echo "    --repo IChouChiang/cline-termux --latest=false \\"
echo "    --title 'OpenTUI Android arm64 v$OPENTUI_VERSION.$REVISION' \\"
echo "    --notes 'Genuine Android/Bionic build of the OpenTUI 0.4.3 native renderer for the Cline Termux port. See the VERSION file inside the tarball for provenance.'"
