# Termux v3 Phone Test Plan

Status note, updated 2026-06-07: this is a historical canary test plan from
the first CLI `3.0.14` investigation. The current working package is CLI
`3.0.20` plus a private Bun Android FFI runtime and it has installed and
launched on the Samsung S7 Termux device. See
`docs/termux-v3-overnight-handover-2026-06-06.md` and
`release/TERMUX_V3_RELEASE.md` for the current package test path.

This branch starts from official upstream Cline `main` / CLI `3.0.14` and is a canary for the new v3 architecture. It must not replace `~/.cline-termux/current` until the gates below pass.

## Why This Is A Gate

Upstream CLI v3 no longer builds the old Node/Ink `dist/cli.mjs` runtime used by the current Termux port and Android bridge. The new CLI lives under `sdk/apps/cli` and runs through Bun/OpenTUI.

Current known phone state:

- `node` is available and is new enough.
- `cline` still points to the old working `2.13.1-local` runtime.
- the Android bridge still points at `~/.cline-termux/current/dist/lib.mjs` from the old runtime.
- `bun` is missing from standard Termux packages, but official Bun publishes `bun-linux-aarch64-android.zip` and that binary runs on this phone.

## Gate 1A: Bun/OpenTUI Runtime Smoke

Copy or clone this branch on the phone as a canary directory, for example:

```bash
~/workspace/cline-termux-v3-phone
```

Then run:

```bash
bash release/termux-v3-smoke.sh --runtime-only ~/workspace/cline-termux-v3-phone
```

If Bun is not already installed, install the official Android ARM64 Bun binary into a canary path and run the same runtime smoke gate:

```bash
bash release/termux-v3-smoke.sh --install-bun --runtime-only ~/workspace/cline-termux-v3-phone
```

The canary Bun path is:

```text
~/.local/opt/bun-android-canary/bun-linux-aarch64-android/bun
```

Do not switch `~/.cline-termux/current` until this script reaches:

```text
[ok] Termux Bun/OpenTUI runtime smoke passed
```

This runtime gate passed on the phone with official Bun Android ARM64 `1.3.14` plus the OpenTUI Android package alias workaround.

## Gate 1B: Cline v3 Source Smoke

After Gate 1A passes, run the full source gate:

```bash
bash release/termux-v3-smoke.sh ~/workspace/cline-termux-v3-phone
```

Do not switch `~/.cline-termux/current` until this script reaches:

```text
[ok] v3 CLI source can run on Termux
```

Current result: this full gate fails at upstream `bun install`, after the Bun/OpenTUI runtime smoke passes. The failure is broad Bun package-manager/linking behavior on Termux (`EACCES: Permission denied: failed to link package ...` across many packages, plus an observed tarball integrity failure for `@tailwindcss/oxide-android-arm64`). This is separate from OpenTUI runtime import, which now has a passing canary workaround.

The published CLI package path is being checked separately:

```bash
bash release/cline-v3-published-cli-smoke.sh
```

Registry note: the current public package is `cline@3.0.14`. `@cline/cli` exists but is currently published only as the older `0.0.x` package line, so do not use `@cline/cli@3.0.14` for the one-command Termux canary.

Current published-package result:

- `cline@3.0.14` installs on Termux with npm.
- `@cline/cli-android-arm64` is not published.
- Aliasing `@cline/cli-android-arm64` to `@cline/cli-linux-arm64@3.0.14` installs the Linux ARM64 compiled binary, but Android rejects it: `unexpected e_type: 2`.
- A tiny Bun source script runs on Android, but `bun build` and `bun build --compile` currently fail on Termux with `Cannot read directory "/data/": AccessDenied` and `Cannot read directory "/data/data/": AccessDenied`.

So the current upstream contribution path is not only package metadata. Cline needs an Android ARM64 compiled CLI package, and Bun likely needs Android-safe build/bundle behavior before that package can be built directly on a Termux device.

See `docs/termux-v3-upstream-gaps.md` for issue-ready repro notes.

## Gate 2: TUI Smoke

Only after Gate 1 passes, run the CLI in canary mode without changing the production launcher:

```bash
cd ~/workspace/cline-termux-v3-phone/sdk/apps/cli
bun --conditions=development ./src/index.ts --version
bun --conditions=development ./src/index.ts --help
bun --conditions=development ./src/index.ts --tui
```

Capture a screenshot or terminal log before changing any symlink.

## Current OpenTUI Status

Verified so far:

- Official Bun Android ARM64 binary runs on Termux: `bun 1.3.14`.
- `@opentui/core@0.1.102` publishes Linux ARM64 native packages, but not Android-specific OpenTUI native packages.
- `bun install @opentui/core@0.1.102` currently fails on this Termux device with repeated `EACCES: Permission denied while installing ...` package extraction errors.
- `npm install @opentui/core@0.1.102` succeeds, but Bun import fails because `@opentui/core` tries to load the unpublished package `@opentui/core-android-arm64/index.ts`.
- Installing `@opentui/core-android-arm64` as an npm alias to `@opentui/core-linux-arm64@0.1.102` with `npm install --force` lets `@opentui/core` and `@opentui/react` import successfully under Bun on Termux.

Next check: run the actual Cline v3 source/TUI smoke. The likely contribution path is an OpenTUI Android ARM64 package alias/native package plus a Bun package-manager Termux fix or documented npm-install workaround.

Focused command for the current OpenTUI import gate:

```bash
bash release/termux-v3-smoke.sh --runtime-only
```

This creates a temporary project, installs `@opentui/core-android-arm64` as an npm alias to `@opentui/core-linux-arm64`, and imports `@opentui/core`/`@opentui/react` with the official Android Bun binary. `release/opentui-termux-smoke.sh` remains as the smaller focused version of the same OpenTUI import check.

## Gate 3: Local Provider And Bridge Port

The old Termux fork features are not yet ported to v3. The important old features to preserve are:

- first-class local llama-server provider
- `/slots` context-window detection
- Gemma-local prompt variant and local auto-condense behavior
- `reasoning_content` support
- static local model catalog in TUI
- Android bridge session APIs: transcript snapshots, ask responses, injected browser session, and scoped `allow_always`

Those features should be mapped onto the new `sdk/packages/*` and `sdk/apps/cli` runtime only after the v3 CLI can run on Termux.

## Gate 4: Android Bridge

The current Android bridge imports `~/.cline-termux/current/dist/lib.mjs`. Upstream v3 does not provide that file. Do not point the Android app at a v3 canary until a new bridge-compatible library entrypoint exists and the bridge health/session smoke tests pass.
