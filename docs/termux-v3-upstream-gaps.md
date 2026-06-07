# Termux v3 Upstream Gaps

Status note, updated 2026-06-07: this file is still useful as an upstream-gap
scratchpad, but it was written before the custom Bun Android FFI runtime and
the CLI `3.0.20` package succeeded on the S7 tablet. Current release packaging
details live in `docs/termux-v3-overnight-handover-2026-06-06.md` and
`release/TERMUX_V3_RELEASE.md`.

These are the upstream-facing gaps found while testing official Cline `3.86.0` / CLI `3.0.14` on Samsung Termux aarch64. The old `~/.cline-termux/current` runtime remains untouched.

## Confirmed Working

- Official Bun publishes an Android ARM64 binary: `bun-linux-aarch64-android.zip`.
- That Bun binary runs on Termux: `bun 1.3.14`.
- `@opentui/core` and `@opentui/react` import under Bun on Termux when the missing Android native package name is aliased to the Linux ARM64 native package.
- Repro command:

```bash
bash release/termux-v3-smoke.sh --install-bun --runtime-only ~/workspace/cline-termux-v3-phone
```

## 1. OpenTUI Android Native Package Metadata

Observed:

- `@opentui/core@0.1.102` tries to load `@opentui/core-android-arm64/index.ts` when run by Bun on Android ARM64.
- `@opentui/core-android-arm64` is not published.
- `@opentui/core-linux-arm64@0.1.102` appears compatible enough for the import smoke if installed under the missing Android package name.

Minimal workaround:

```json
{
  "dependencies": {
    "@opentui/core": "0.1.102",
    "@opentui/core-android-arm64": "npm:@opentui/core-linux-arm64@0.1.102",
    "@opentui/react": "0.1.102",
    "react": "19.2.4",
    "react-reconciler": "0.32.0"
  }
}
```

Expected upstream fix:

- Publish `@opentui/core-android-arm64`, or officially map Android ARM64 to the Linux ARM64 native package if that ABI support is intentional.

## 2. Cline Android CLI Binary Package

Observed:

- The current public CLI package is `cline@3.0.14`.
- `@cline/cli@3.0.14` is not published; `@cline/cli` is currently an older `0.0.x` package line.
- `cline@3.0.14` publishes native optional packages such as `@cline/cli-linux-arm64`, but no `@cline/cli-android-arm64`.
- Aliasing `@cline/cli-android-arm64` to `@cline/cli-linux-arm64@3.0.14` installs, but the binary does not run on Android:

```text
error: ".../node_modules/@cline/cli-android-arm64/bin/cline" has unexpected e_type: 2
```

Expected upstream/downstream fix:

- Add an Android ARM64 compile target and publish `@cline/cli-android-arm64`.
- Update the `cline` launcher/postinstall optional dependency list to include the Android package.

## 3. Bun Package Manager And Build On Termux

Observed:

- `bun install` in the upstream SDK checkout fails on Termux with many package-link errors:

```text
EACCES: Permission denied: failed to link package: ...
```

- A tiny Bun source script runs on Android, but `bun build` and `bun build --compile` fail before building:

```text
error: Cannot read directory "/data/": AccessDenied
error: Cannot read directory "/data/data/": AccessDenied
```

Expected upstream fix:

- Bun package manager should not fail package linking on Termux's app-private filesystem.
- Bun build/compile should avoid scanning inaccessible Android ancestor directories.
- Ideally Bun should expose/document an Android ARM64 compile target usable by Cline's release script.

## Downstream Order

1. Keep `release/termux-v3-smoke.sh --runtime-only` passing.
2. Upstream or locally patch OpenTUI Android native package metadata.
3. Add/prove a Cline Android ARM64 binary package.
4. Only after CLI `--version`, `--help`, and `--tui` pass, port local provider and Android bridge features.
