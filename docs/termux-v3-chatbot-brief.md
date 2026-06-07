# Cline v3 On Termux: Chatbot Brief

Status note, updated 2026-06-07: this file is a historical brief from the
early CLI `3.0.14` investigation. The current port has moved to Cline CLI
`3.0.20` and the S7 tablet successfully installed and launched the two-artifact
package using a private Bun Android FFI runtime. See
`docs/termux-v3-overnight-handover-2026-06-06.md` and
`release/TERMUX_V3_RELEASE.md` for the current release path.

Use this as a paste-ready brief for another chatbot, upstream maintainer, or package author.

## Short Answer

We still cannot use the new official Cline v3 CLI on Termux as a working replacement yet.

The Bun/OpenTUI runtime layer now works on Termux with a workaround, but the actual official Cline v3 CLI cannot run because Cline does not publish an Android ARM64 native CLI binary and the Linux ARM64 binary is not compatible with Android/Termux.

The old working Termux runtime must remain in place:

```text
~/.cline-termux/current -> ~/.cline-termux/v3.77.0-local
cline --version -> 2.13.1-local
```

Do not switch the production symlink to v3 yet.

## Goal

Make official Cline v3/CLI `3.0.14` run on Android Termux ARM64 while preserving the downstream Termux/Android bridge features.

Target environment:

```text
Device: Samsung Android phone
Shell: Termux
Arch: aarch64 / arm64
Node: v24.14.1
Bun: official bun-linux-aarch64-android, verified v1.3.14
Repo canary path: ~/workspace/cline-termux-v3-phone
Stable runtime: ~/.cline-termux/current, must not be changed
```

## What Works

Official Bun Android ARM64 works:

```bash
~/.local/opt/bun-android-canary/bun-linux-aarch64-android/bun --version
```

Verified output:

```text
1.3.14
```

OpenTUI import works if the missing Android native package name is aliased to the Linux ARM64 package:

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

Passing runtime smoke:

```bash
bash ~/workspace/cline-termux-v3-phone/release/termux-v3-smoke.sh --runtime-only ~/workspace/cline-termux-v3-phone
```

Passing result:

```text
[ok] Node v24.14.1
[ok] Bun 1.3.14 at ~/.local/opt/bun-android-canary/bun-linux-aarch64-android/bun
[ok] OpenTUI imports under Bun on Termux with the Android alias workaround
[ok] Termux Bun/OpenTUI runtime smoke passed
```

## What Fails

### 1. OpenTUI Missing Android Package

`@opentui/core@0.1.102` tries to load:

```text
@opentui/core-android-arm64/index.ts
```

But that package is not published. The Linux ARM64 package can be aliased and import successfully, so this may be a packaging/metadata gap rather than an ABI gap.

Question for OpenTUI:

```text
Can OpenTUI publish @opentui/core-android-arm64, or officially map Android ARM64 to @opentui/core-linux-arm64 if that native package is supported on Android/Termux?
```

### 2. Official Cline CLI Has No Android ARM64 Native Package

The current public package is:

```text
cline@3.0.14
```

Important package-name note:

```text
@cline/cli@3.0.14 is not published.
@cline/cli exists only on an older 0.0.x package line.
```

`cline@3.0.14` publishes optional native packages like:

```text
@cline/cli-linux-arm64@3.0.14
```

But it does not publish:

```text
@cline/cli-android-arm64@3.0.14
```

Aliasing Android to Linux installs the binary:

```json
{
	"dependencies": {
		"cline": "3.0.14",
		"@cline/cli-android-arm64": "npm:@cline/cli-linux-arm64@3.0.14"
	}
}
```

But the Linux binary does not run on Android:

```text
error: ".../node_modules/@cline/cli-android-arm64/bin/cline" has unexpected e_type: 2
```

Question for Cline:

```text
Can Cline add and publish @cline/cli-android-arm64 for the official CLI package, and update the cline launcher/postinstall optional dependency list to include Android ARM64?
```

### 3. Bun Package Manager And Build Fail On Termux

Running `bun install` in the upstream SDK checkout fails with many package-link errors:

```text
EACCES: Permission denied: failed to link package: ...
```

A tiny Bun source script runs on Android, but building does not:

```bash
bun hello.ts
bun build hello.ts --target=bun --outfile hello.js
bun build --compile hello.ts --outfile hello
```

Observed:

```text
hello.ts runs successfully
bun build fails: Cannot read directory "/data/": AccessDenied
bun build --compile fails: Cannot read directory "/data/": AccessDenied
also: Cannot read directory "/data/data/": AccessDenied
```

Question for Bun:

```text
Is Bun build/compile supported on Android Termux? If yes, what flags or working directory setup prevent Bun from scanning inaccessible Android ancestor directories like /data and /data/data?
```

## Current Repro Scripts

These scripts exist in the canary checkout:

```text
release/termux-v3-smoke.sh
release/opentui-termux-smoke.sh
release/cline-v3-published-cli-smoke.sh
docs/termux-v3-upstream-gaps.md
```

Useful commands:

```bash
# Positive runtime gate: Bun + OpenTUI import works.
bash release/termux-v3-smoke.sh --runtime-only ~/workspace/cline-termux-v3-phone

# Focused OpenTUI import check.
bash release/opentui-termux-smoke.sh

# Published Cline package check: installs, then proves native binary gap.
bash release/cline-v3-published-cli-smoke.sh

# Full source smoke: currently fails at bun install.
bash release/termux-v3-smoke.sh ~/workspace/cline-termux-v3-phone
```

## Questions To Ask Another Chatbot

1. Given the facts above, is there any way to run official `cline@3.0.14` on Termux today without an Android ARM64 native Cline binary?
2. Can Bun's `--compile-executable-path` or any cross-compile flow produce a real Android ARM64 executable from Linux/macOS for Cline's CLI?
3. How should Cline's `sdk/apps/cli/script/build.ts` be extended to build and publish `@cline/cli-android-arm64`?
4. Is OpenTUI's Linux ARM64 native package actually safe to use on Android, or should OpenTUI build a distinct Android native package?
5. Can the Cline CLI source be run on Termux without `bun install`, perhaps using npm plus prebuilt package bundles, or is the native compiled package the correct path?
6. What is the smallest upstream PR sequence: OpenTUI Android package, Bun Termux build fix, then Cline Android CLI package?

## Current Conclusion

The new version is not usable as the Termux production Cline yet.

We have proven the lower runtime layer is close: official Bun Android runs, and OpenTUI imports with a package alias. The blocker moved upward to official Cline packaging and Bun build/install support on Android. The next real milestone is an Android ARM64 Cline CLI binary or a source-install path that avoids Bun's current Termux package/build failures.
