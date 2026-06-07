# Termux v3 Port Map

Status note, updated 2026-06-07: this file maps the first Cline v3 exploration
around CLI `3.0.14`. The current working port is based on CLI `3.0.20`, uses a
private Bun Android FFI runtime, and has passed an S7 Termux install and launch
test. See `docs/termux-v3-overnight-handover-2026-06-06.md` and
`release/TERMUX_V3_RELEASE.md` before using this as current guidance.

Upstream Cline `3.86.0` / CLI `3.0.14` is not a direct upgrade of the current Termux runtime. The old fork is Node/Ink-based and exposes `dist/cli.mjs` plus `dist/lib.mjs`; upstream v3 is Bun/OpenTUI-based under `sdk/apps/cli` and does not expose those files.

## Current Hard Gate

The Samsung Termux environment has:

- `node v24.14.1`
- old working `cline 2.13.1-local`
- old working bridge process using `~/bridge/dist/server.mjs`
- no `bun` from Termux packages
- official Bun Android ARM64 canary works from `bun-linux-aarch64-android.zip` (`bun 1.3.14` verified)

Standard `pkg search bun` did not find a Bun package. The first solved piece is Bun itself: official Bun publishes Android artifacts and the Android ARM64 binary starts on the Samsung device. The second solved piece is OpenTUI import with an Android package alias workaround:

- `bun install @opentui/core@0.1.102` fails on Termux with package extraction `EACCES` errors.
- `npm install @opentui/core@0.1.102` succeeds.
- OpenTUI then tries to load `@opentui/core-android-arm64/index.ts`, but that package is not published.
- Installing `@opentui/core-android-arm64` as an npm alias to `@opentui/core-linux-arm64@0.1.102` with `npm install --force` allows `@opentui/core` and `@opentui/react` to import under Bun on Termux.

The remaining hard gate is the full Cline v3 source/TUI smoke. The first run failed at upstream `bun install` with widespread Termux `EACCES` package-link errors and one `@tailwindcss/oxide-android-arm64` integrity failure, after the Bun/OpenTUI runtime gate had already passed. Until the source/TUI gate passes, do not port or deploy over the working runtime.

The current public npm package for the CLI release is `cline@3.0.14`; `@cline/cli` is still on an older `0.0.x` package line. The published-package canary is tracked by `release/cline-v3-published-cli-smoke.sh`. That canary currently proves another upstream gap: `cline@3.0.14` installs, but no `@cline/cli-android-arm64` package is published. Aliasing it to `@cline/cli-linux-arm64@3.0.14` installs the Linux ARM64 binary, but Android rejects that binary with `unexpected e_type: 2`, so Cline needs a true Android ARM64 binary target.

Issue-ready repro notes are in `docs/termux-v3-upstream-gaps.md`.

## Local Features To Preserve

These local-only commits from the old fork contain the phone-facing behavior:

| Old Commit | Feature | v3 Port Area |
| --- | --- | --- |
| `656ba0e2` | Android/Termux CLI build support | `sdk/apps/cli/script/build.ts`, package metadata |
| `8a2aaa0a` | Configurable build heap | v3 build/release scripts if still needed |
| `239bf733` | First-class `local` provider for llama-server | `sdk/packages/core` LLM/provider registry plus `sdk/apps/cli` auth/config UI |
| `70e09b68` | `/slots` context-window detection | local-provider handler in v3 core |
| `c3962de2` | `gemma-local` prompt variant/bootstrap | v3 prompt/runtime package location |
| `60e67265` | Lightweight local auto-condense | v3 context management/runtime |
| `f6dcfe1b` | Post-condense XML-format boost | v3 local prompt/context logic |
| `72895541` | `reasoning_content` support/provider label | v3 local provider stream parser |
| `a2b53435` | `task_progress` focus-chain support | v3 agent event/session update path |
| `2246cbe2` | Detected context in TUI status | `sdk/apps/cli/src/tui/*` |
| `3fe6f9ed` | Static local model catalog in TUI | `sdk/apps/cli` provider/model picker |
| `c22cbc52` | Session transcript snapshots | `sdk/packages/core` session/message artifact APIs |
| `e61de557` | Ask response session API | `sdk/apps/cli/src/acp/*` and core session APIs |
| `96ee0cfb` | Injected browser sessions | v3 runtime capabilities and browser tool host surface |
| `42dee361` | Scoped `allow_always` approvals | `sdk/apps/cli/src/acp/permissions.ts` and approval cache |

## Recommended Order

1. Keep `release/termux-v3-smoke.sh --runtime-only` passing, then make `release/termux-v3-smoke.sh` pass without `--runtime-only`.
2. Prepare a small upstream issue/PR for OpenTUI Android ARM64 packaging. The first proposal should be either publishing `@opentui/core-android-arm64` or formally aliasing/reusing the Linux ARM64 native package on Android if upstream accepts that compatibility.
3. Prepare a Cline CLI packaging issue/PR for `@cline/cli-android-arm64`; Linux ARM64 binaries are not Android-compatible.
4. Prepare a separate Bun issue for Termux package-manager/build support. The observed package-manager `EACCES` errors are in `bun install`, and `bun build`/`bun build --compile` also fail on Android by trying to read inaccessible `/data` ancestors.
5. Run v3 CLI `--version`, `--help`, and `--tui` from either a real Android binary package or source in a canary checkout.
6. Add a local provider with the smallest possible model catalog and `/v1/chat/completions` streaming support.
7. Add `/slots` context detection and `reasoning_content` parsing.
8. Reintroduce the `gemma-local` prompt variant and local auto-condense behavior.
9. Build a new bridge-compatible library entrypoint; the old Android bridge cannot import v3 until this exists.
10. Only then run Android bridge/session instrumentation and manual phone UI tests.

## Do Not Do Yet

- Do not change `~/.cline-termux/current`.
- Do not overwrite `~/.cline` state.
- Do not deploy the Android app against v3.
- Do not claim the upstream sync is phone-ready until the Bun/OpenTUI gate and bridge library entrypoint both pass.
