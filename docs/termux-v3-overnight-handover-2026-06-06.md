# Termux Cline v3 Handover - Updated 2026-06-07

This is the current state of the native Cline v3 Termux port after the Bun FFI
work, OpenTUI runtime work, Cline `3.0.20` forward-port, release packaging, and
Samsung S7 tablet install test.

It replaces the earlier overnight notes that still described the official-Bun
failure as the current state.

## Executive Summary

We now have a working two-artifact local package for Cline CLI v3 on Termux
Android aarch64.

The shape is:

```text
Termux user
  -> $PREFIX/bin/cline
  -> $PREFIX/opt/bun-android-ffi/current/bun
  -> $PREFIX/opt/cline-termux/current/index.js
  -> @opentui/core-android-arm64/libopentui.so
```

The package installed and launched successfully on the Samsung S7 tablet. The
Bun FFI repo and release asset are now public. The next work is to commit/push
the Cline Termux release scripts, publish the Cline release asset, and test the
public one-command installer.

Current local version alignment:

```text
Cline upstream CLI tag: cli-v3.0.20
Cline Termux tag plan:  v3.0.20-termux.1
Cline command:          cline
Bun FFI runtime:        1.4.0-canary.1-55f6c899f
```

## Current Repositories

### Cline Termux V3

Path:

```text
/home/ichou/workspace/cline-termux-v3-phone
```

Branch:

```text
termux/cli-v3.0.20-phone
```

Current commit:

```text
8953f8f7e fix: forward-port termux tui patches to cli 3.0.20
```

Relationship to upstream CLI tag:

```text
git rev-list --left-right --count HEAD...cli-v3.0.20
# 1 0

git describe --tags --match 'cli-v*' --always HEAD
# cli-v3.0.20-1-g8953f8f7e
```

Meaning: the branch is exactly one downstream Termux commit ahead of official
Cline CLI `cli-v3.0.20`.

### Bun Android FFI Fork

Path:

```text
/home/ichou/workspace/bun-android-ffi-fork
```

Public repo:

```text
https://github.com/IChouChiang/bun-android-ffi
```

Branch:

```text
main
```

Current public HEAD:

```text
4d60455f2d Initial artifact release metadata
```

The public repo is intentionally a tiny artifact/patch repo, not a full Bun
source mirror. It includes `LICENSE.md`, `NOTICE.md`, and
`patches/bun-android-ffi.patch`.

Local Android FFI source commit:

```text
ecc71fc8f1 feat(android): enable bun:ffi/TinyCC for Android + native Cline TUI handover
```

Relationship before the README cleanup was one FFI code commit ahead of the
upstream Bun canary base:

```text
ecc71fc8f1 -> 55f6c899f5
```

Built binary:

```text
/home/ichou/workspace/bun-android-ffi-fork/build/release/bun
```

Properties:

```text
ELF 64-bit LSB pie executable, ARM aarch64, Android 28
Bun 1.4.0-canary.1+55f6c899f
binary sha256 bd7ad66134dce00d5d238d2c56aa8adf22feddd2c57a239df7d761a428e4e6d9
```

## What Changed In Bun

The hard runtime gate was not Cline first. It was Bun FFI.

Official Bun Android can run JavaScript and import `bun:ffi`, but actual native
loading fails:

```text
bun:ffi dlopen() is not available in this build (TinyCC is disabled)
```

OpenTUI needs a real `bun:ffi dlopen()` call to load `libopentui.so`, so the
official Android Bun package cannot run the native TUI today.

The Bun fork does only the Cline-needed Android FFI enablement:

```text
scripts/build/buildOptionsRs.ts
scripts/build/config.ts
scripts/build/deps/tinycc.ts
scripts/build/rust.ts
src/tcc_sys/tcc.rs
patches/tinycc/bionic-compat.c
scripts/android-build-env.sh
scripts/android-ffi-spike.sh
ANDROID_CLINE_TUI_HANDOVER.md
```

Important behavior:

- `--tinycc=on` enables the TinyCC build path.
- Rust receives `--cfg=bun_tinycc` when TinyCC is enabled.
- Android bionic gets a small `ldexpl` compatibility shim.
- Android strip handling uses the Android/LLVM strip path.
- The resulting binary can `dlopen()` OpenTUI's Android native library.

Release packaging now treats this as a private runtime for Cline, not a general
replacement for Termux or official Bun.

## What Changed In OpenTUI

OpenTUI resolves native packages from:

```text
@opentui/core-${process.platform}-${process.arch}
```

On Termux Android aarch64 this becomes:

```text
@opentui/core-android-arm64
```

That package is not currently published upstream. Our packaged runtime includes
an Android package directory with:

```text
node_modules/@opentui/core-android-arm64/libopentui.so
```

For the Cline UX itself, we patched `@opentui-ui/dialog@0.1.2` through Bun
patched dependencies:

```text
patches/@opentui-ui%2Fdialog@0.1.2.patch
```

The patch adds these dialog layout options:

```text
verticalAlign
safeAreaTop
safeAreaBottom
```

Cline's Termux helper uses that to move centered dialogs above the soft
keyboard:

```text
apps/cli/src/tui/utils/termux-dialog-safe-area.ts
```

Default behavior:

```text
CLINE_TUI_TERMUX_DIALOG_SAFE_AREA_BOTTOM=15%
```

That value is the built-in Termux default; the environment variable can still
override it with rows or a percent.

## What Changed In Cline

The current downstream Cline commit is:

```text
8953f8f7e fix: forward-port termux tui patches to cli 3.0.20
```

It combines the three earlier Termux UX/runtime fixes onto official
`cli-v3.0.20`.

### Android Bun Glyph Fix

File:

```text
apps/cli/bun.mts
```

The generated bundle had a `// @bun` directive. On Android Bun this caused
non-ASCII TUI strings to render as mojibake, such as the `a-hat` characters in
settings and status labels.

The fix strips the generated marker after build. This is intentionally scoped
to the generated bundle and keeps real Unicode UI text intact.

### Dialog Safe Area

Files:

```text
apps/cli/src/tui/root.tsx
apps/cli/src/tui/utils/termux-dialog-safe-area.ts
apps/cli/src/tui/utils/termux-dialog-safe-area.test.ts
patches/@opentui-ui%2Fdialog@0.1.2.patch
```

This moves `/settings`, `/model`, `/history`, and similar dialog windows higher
on Termux when the IME is present or likely to cover centered windows.

### Tap To Keyboard

Files:

```text
apps/cli/src/tui/index.tsx
apps/cli/src/tui/history-standalone.tsx
apps/cli/src/commands/auth.ts
apps/cli/src/tui/utils/termux-renderer-options.ts
apps/cli/src/tui/utils/termux-renderer-options.test.ts
apps/cli/src/tui/utils/termux-runtime.ts
```

Termux opens the soft keyboard on screen touch only when the terminal is not in
mouse tracking mode. OpenTUI enables mouse tracking by default, which makes
Termux send taps as mouse events instead.

Default behavior now:

```text
CLINE_TUI_TERMUX_MOUSE=off
```

The env var can restore pointer tracking:

```sh
CLINE_TUI_TERMUX_MOUSE=on cline --tui
```

## Verification Done Before Packaging

On the Cline branch:

```sh
cd /home/ichou/workspace/cline-termux-v3-phone/apps/cli
../../node_modules/.bin/vitest run \
  src/tui/utils/termux-dialog-safe-area.test.ts \
  src/tui/utils/termux-renderer-options.test.ts \
  --config vitest.config.ts

../../node_modules/.bin/tsc --noEmit -p tsconfig.json

cd /home/ichou/workspace/cline-termux-v3-phone
PATH="$HOME/.bun/bin:$PATH" bun -F @cline/cli build
```

Results:

```text
focused tests passed
typecheck passed
CLI build passed
```

## Release Scripts

The local release work lives under:

```text
release/
```

Important scripts:

```text
release/build-bun-ffi-release.sh
release/build-termux-release.sh
release/install-cline-termux.sh
release/test-termux-install.sh
release/TERMUX_V3_RELEASE.md
```

Other smoke scripts remain for historical or focused testing:

```text
release/cline-v3-published-cli-smoke.sh
release/opentui-termux-smoke.sh
release/termux-v3-smoke.sh
```

The current installer can:

- install Cline under `$PREFIX/opt/cline-termux/<release>`;
- install the private Bun runtime under `$PREFIX/opt/bun-android-ffi/<version>`;
- create `$PREFIX/bin/bun-ffi` as a convenience symlink;
- create `$PREFIX/bin/cline` as the official command;
- use a local Bun tarball placed beside the Cline bundle;
- download the Bun tarball from a GitHub release when published;
- run a real OpenTUI `dlopen()` smoke test before declaring success.

It does not replace `$PREFIX/bin/bun`.

## Local Artifacts

Current generated artifacts:

```text
release/dist/bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz
release/dist/bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz.sha256
release/dist/cline-termux-aarch64-v3.0.20-termux.1.tar.gz
release/dist/cline-termux-aarch64-v3.0.20-termux.1.tar.gz.sha256
```

Checksums:

```text
4faca366cb4e5404f3c08f1a1764e39eeb005f0ae5724c02f8090b8a93554a13  release/dist/bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz
30b021b3497b0c41d2bf4d78a1ca9fd43e0f3658da667b3c38d8608d06beed79  release/dist/cline-termux-aarch64-v3.0.20-termux.1.tar.gz
```

`release/dist/` is ignored by git, so these are local build outputs, not source
files to commit.

The Bun tarball contains only:

```text
bun
VERSION
README.md
LICENSE.md
NOTICE.md
```

It intentionally does not contain machine-specific scripts, private notes, or
the full Bun source tree.

The Bun artifact is now published at:

```text
https://github.com/IChouChiang/bun-android-ffi/releases/tag/v1.4.0-canary.1-55f6c899f
```

## S7 Tablet Test

SSH alias:

```text
termux_wifi_s7
HostName 192.168.2.208
User u0_a427
Port 8022
IdentityFile ~/.ssh/id_ed25519
```

The S7 initially proved the exact concern we had: the first package that used
official Bun failed at TUI launch with:

```text
bun:ffi dlopen() is not available in this build (TinyCC is disabled)
```

After the two-artifact installer was updated, both tests passed.

Sandbox test command:

```sh
cd ~/tmp/cline-termux-v3-ffi-install
bash test-termux-install.sh \
  --from-tarball cline-termux-aarch64-v3.0.20-termux.1.tar.gz \
  --bun-tarball bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz \
  --keep-work
```

Real install command:

```sh
cd ~/tmp/cline-termux-v3-ffi-install
tar xzf cline-termux-aarch64-v3.0.20-termux.1.tar.gz
cd cline-termux-aarch64-v3.0.20-termux.1
bash install.sh --force --skip-pkg-update
```

Observed post-install checks:

```text
cline --version -> 3.0.20
bun-ffi --version -> 1.4.0
cline --help works
OpenTUI native dlopen works
$PREFIX/bin/bun-ffi -> $PREFIX/opt/bun-android-ffi/current/bun
$PREFIX/opt/bun-android-ffi/current -> .../1.4.0-canary.1-55f6c899f
$PREFIX/opt/cline-termux/current -> .../3.0.20-termux.1
```

The user then launched Cline TUI manually on S7 and confirmed it opened
successfully.

## Device Notes

### Main Phone

SSH alias:

```text
termux_wifi
HostName 192.168.2.95
User u0_a496
Port 8022
IdentityFile ~/.ssh/id_ed25519
```

The main phone canary still has:

```text
~/cline-v3
~/bun-ffi
$PREFIX/bin/cline-tui
```

That was a development launcher. The public package direction is now:

```text
$PREFIX/bin/cline
$PREFIX/bin/bun-ffi
$PREFIX/opt/cline-termux/current
$PREFIX/opt/bun-android-ffi/current
```

### S7 Tablet

The S7 is the first successful clean second-device install of the new package.
It previously had V2 `cline 2.14.0`; the installer backed up the old launcher
before writing the new one.

## Worktree State

Committed Cline branch change:

```text
8953f8f7e fix: forward-port termux tui patches to cli 3.0.20
```

Public Bun fork state:

```text
4d60455f2d Initial artifact release metadata
```

Untracked source work in the Cline checkout is expected:

```text
docs/termux-v3-chatbot-brief.md
docs/termux-v3-overnight-handover-2026-06-06.md
docs/termux-v3-phone-test.md
docs/termux-v3-port-map.md
docs/termux-v3-upstream-gaps.md
release/
```

Temporary staging directories were removed. `release/dist/` is generated and
ignored.

## Next Release Plan

1. Commit the Cline Termux release scripts and docs.
2. Publish:

```text
cline-termux-aarch64-v3.0.20-termux.1.tar.gz
install-cline-termux.sh
```

3. Test the public installer from GitHub on S7 or another clean Termux:

```sh
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash
cline --version
cline --help
cline --tui
```

## Upstream Candidates Later

Bun:

- Android `bun:ffi dlopen()` support through a TinyCC-enabled build or official
  alternative.
- Termux-safe `bun install` and `bun build` behavior.

OpenTUI:

- Publish `@opentui/core-android-arm64`, or document/support the correct
  Android ARM64 native package path.
- Consider dialog safe-area support as a general terminal mobile UX feature.

Cline:

- Consider Termux/mobile TUI defaults for keyboard-friendly mouse mode.
- Consider mobile terminal dialog safe-area knobs.
- Longer term: official Android ARM64 CLI package or source-runner path.

## Current Recommendation

The port has moved from "experimental canary" to "locally packageable and
second-device verified." The Bun runtime is now public. The next best step is
to finish the Cline Termux release packaging:

```text
publish Cline Termux package -> test public installer
```
