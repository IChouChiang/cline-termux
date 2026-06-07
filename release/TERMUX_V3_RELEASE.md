# Cline Termux V3 Release

This release path packages Cline CLI `3.0.20` for native Termux Android
aarch64. It deliberately separates the Cline app payload from the experimental
Bun Android FFI runtime, so the public `cline` command can work without
replacing the user's normal `$PREFIX/bin/bun`.

Current status: the local two-artifact package installed and launched
successfully on the Samsung S7 Termux test device. The Bun runtime repo and
release asset are public; the Cline Termux release asset is still local.

## Artifacts

Two tarballs are required:

| Artifact | Purpose |
| --- | --- |
| `bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz` | Private Bun runtime with `bun:ffi dlopen()` enabled for Android |
| `cline-termux-aarch64-v3.0.20-termux.1.tar.gz` | Cline CLI bundle plus Android OpenTUI runtime dependencies |

Current local checksums:

```text
4faca366cb4e5404f3c08f1a1764e39eeb005f0ae5724c02f8090b8a93554a13  release/dist/bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz
30b021b3497b0c41d2bf4d78a1ca9fd43e0f3658da667b3c38d8608d06beed79  release/dist/cline-termux-aarch64-v3.0.20-termux.1.tar.gz
```

The `release/dist/` directory is generated output and is ignored by git.

## Install Layout

The installer follows Termux prefix conventions while keeping this port
self-contained:

| Path | Purpose |
| --- | --- |
| `$PREFIX/opt/bun-android-ffi/<version>/` | Versioned private Bun FFI runtime |
| `$PREFIX/opt/bun-android-ffi/current` | Symlink to the active Bun FFI runtime |
| `$PREFIX/bin/bun-ffi` | Convenience symlink to the private Bun runtime |
| `$PREFIX/opt/cline-termux/<release>/` | Versioned Cline Termux runtime payload |
| `$PREFIX/opt/cline-termux/current` | Symlink to the active Cline release |
| `$PREFIX/bin/cline` | User-facing Cline launcher |
| `~/.cline/` | Official Cline user data, settings, tasks, and API keys |

There is intentionally no public `cline-tui` launcher. Users keep the official
command habit:

```sh
cline
cline --tui
```

The generated `$PREFIX/bin/cline` launcher runs:

```text
$PREFIX/opt/bun-android-ffi/current/bun
$PREFIX/opt/cline-termux/current/index.js
```

It never falls back to official Bun, because official Bun Android currently
starts JavaScript but fails the real OpenTUI `bun:ffi dlopen()` path.

## Build Locally

Build the private Bun FFI runtime tarball from the local Bun fork:

```sh
bash release/build-bun-ffi-release.sh
```

Expected output:

```text
release/dist/bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz
release/dist/bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz.sha256
```

Build the Cline Termux tarball from the current repo bundle and a known-good
Android runtime dependency tree:

```sh
bash release/build-termux-release.sh \
  --termux-host termux_wifi \
  --runtime-dir '~/cline-v3' \
  --release v3.0.20-termux.1
```

If `apps/cli/dist` is already current:

```sh
bash release/build-termux-release.sh \
  --skip-build \
  --termux-host termux_wifi \
  --runtime-dir '~/cline-v3' \
  --release v3.0.20-termux.1
```

Expected output:

```text
release/dist/cline-termux-aarch64-v3.0.20-termux.1.tar.gz
release/dist/cline-termux-aarch64-v3.0.20-termux.1.tar.gz.sha256
```

## Test On Termux

Sandbox test from local tarballs:

```sh
bash release/test-termux-install.sh \
  --from-tarball cline-termux-aarch64-v3.0.20-termux.1.tar.gz \
  --bun-tarball bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz
```

Real install from extracted tarball:

```sh
tar xzf cline-termux-aarch64-v3.0.20-termux.1.tar.gz
cd cline-termux-aarch64-v3.0.20-termux.1
bash install.sh --force
```

The installer smoke test checks:

```text
bun-ffi --version
cline --version
cline --help
OpenTUI native dlopen with createRenderer
```

The important smoke is the `dlopen()` check. Importing `bun:ffi` alone is not
enough, because official Bun Android can import the module while still failing
with TinyCC disabled when `dlopen()` is called.

## Published Install Command

After both GitHub releases exist, the intended one-command install is:

```sh
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash
```

Useful environment overrides:

```sh
CLINE_TERMUX_VERSION=v3.0.20-termux.1
CLINE_TERMUX_GITHUB_REPO=IChouChiang/cline-termux
CLINE_TERMUX_BUN_FFI_REPO=IChouChiang/bun-android-ffi
CLINE_TERMUX_BUN_FFI_VERSION=1.4.0-canary.1-55f6c899f
CLINE_TUI_TERMUX_DIALOG_SAFE_AREA_BOTTOM=15%
CLINE_TUI_TERMUX_MOUSE=off
```

## Publish Order

The Bun runtime has already been published:

```text
https://github.com/IChouChiang/bun-android-ffi
https://github.com/IChouChiang/bun-android-ffi/releases/tag/v1.4.0-canary.1-55f6c899f
```

That repo is intentionally a tiny artifact/patch repo, not a full Bun source
mirror. It includes the Bun license notice and `patches/bun-android-ffi.patch`
for the downstream Android FFI source changes.

Original publish command:

```sh
gh release create v1.4.0-canary.1-55f6c899f \
  release/dist/bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz \
  release/dist/bun-android-ffi-aarch64-v1.4.0-canary.1-55f6c899f.tar.gz.sha256 \
  --repo IChouChiang/bun-android-ffi \
  --title "Bun Android FFI v1.4.0-canary.1-55f6c899f"
```

Next, publish Cline:

```sh
gh release create v3.0.20-termux.1 \
  release/dist/cline-termux-aarch64-v3.0.20-termux.1.tar.gz \
  release/dist/cline-termux-aarch64-v3.0.20-termux.1.tar.gz.sha256 \
  release/install-cline-termux.sh \
  --repo IChouChiang/cline-termux \
  --title "Cline Termux v3.0.20-termux.1"
```

After publishing, test the public path on a clean Termux install:

```sh
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash
cline --version
cline --help
cline --tui
```

## S7 Verification

The Samsung S7 Termux device passed both:

```text
release/test-termux-install.sh with both local tarballs
real install.sh from the extracted Cline tarball
```

Post-install layout on S7:

```text
$PREFIX/bin/cline
$PREFIX/bin/bun-ffi -> $PREFIX/opt/bun-android-ffi/current/bun
$PREFIX/opt/bun-android-ffi/current -> .../1.4.0-canary.1-55f6c899f
$PREFIX/opt/cline-termux/current -> .../3.0.20-termux.1
```

The user also launched the TUI manually on S7 and confirmed it opened
successfully.
