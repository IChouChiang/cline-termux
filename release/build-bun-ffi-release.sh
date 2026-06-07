#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
BUN_BIN="${BUN_FFI_BIN:-/home/ichou/workspace/bun-android-ffi-fork/build/release/bun}"
BUN_SOURCE_DIR="${BUN_FFI_SOURCE_DIR:-/home/ichou/workspace/bun-android-ffi-fork}"
BUN_VERSION="${BUN_FFI_VERSION:-1.4.0-canary.1-55f6c899f}"
RELEASE_NAME="bun-android-ffi-aarch64-v$BUN_VERSION"
STAGE_DIR="$SCRIPT_DIR/staging/$RELEASE_NAME"

fail() {
	echo "[fail] $*" >&2
	exit 1
}

command -v file >/dev/null 2>&1 || fail "file is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
[ -x "$BUN_BIN" ] || fail "Bun FFI binary not found or not executable: $BUN_BIN"
[ -f "$BUN_SOURCE_DIR/LICENSE.md" ] || fail "Bun LICENSE.md not found: $BUN_SOURCE_DIR/LICENSE.md"

if ! file "$BUN_BIN" | grep -qi 'Android'; then
	fail "$BUN_BIN is not an Android binary"
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"

cp "$BUN_BIN" "$STAGE_DIR/bun"
chmod 755 "$STAGE_DIR/bun"
cp "$BUN_SOURCE_DIR/LICENSE.md" "$STAGE_DIR/LICENSE.md"

cat > "$STAGE_DIR/VERSION" <<EOF
release=$BUN_VERSION
runtime=bun-android-ffi
platform=termux-android
arch=aarch64
source_repo=https://github.com/IChouChiang/bun-android-ffi
upstream_repo=https://github.com/oven-sh/bun
upstream_base=55f6c899f5
source_patch=patches/bun-android-ffi.patch
binary_sha256=$(sha256sum "$BUN_BIN" | awk '{print $1}')
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

cat > "$STAGE_DIR/README.md" <<'EOF'
# Bun Android FFI

Unofficial experimental Bun Android ARM64 build for Termux.

This binary is built from a Bun canary source tree with TinyCC enabled so
`bun:ffi dlopen()` works for native TUI runtimes such as OpenTUI.

Tested for this release:

- `bun --version`
- `bun:ffi dlopen()`
- OpenTUI `libopentui.so` loading
- Cline Termux TUI runtime

Not guaranteed:

- security hardening
- general replacement for official Bun
- `bun:ffi cc()`
- `bun install` / `bun build` behavior on every Termux setup

License and attribution are included in LICENSE.md and NOTICE.md.
EOF

cat > "$STAGE_DIR/NOTICE.md" <<EOF
# Notice

This is an unofficial downstream runtime artifact built from Bun source.

Upstream Bun:

https://github.com/oven-sh/bun

Downstream artifact/source patch repo:

https://github.com/IChouChiang/bun-android-ffi

Base upstream commit:

55f6c899f5

Downstream source patch:

patches/bun-android-ffi.patch in the artifact repo

This binary is experimental and intended for the Cline Termux native TUI
runtime. It is not an official Bun release and is not a general replacement for
official Bun.
EOF

TARBALL="$DIST_DIR/$RELEASE_NAME.tar.gz"
CHECKSUM="$TARBALL.sha256"
rm -f "$TARBALL" "$CHECKSUM"

(
	cd "$SCRIPT_DIR/staging"
	tar czf "$TARBALL" "$RELEASE_NAME"
)

(
	cd "$DIST_DIR"
	sha256sum "$RELEASE_NAME.tar.gz" > "$RELEASE_NAME.tar.gz.sha256"
)

rm -rf "$STAGE_DIR"

echo "Bun FFI bundle: $TARBALL"
echo "Checksum:       $CHECKSUM"
