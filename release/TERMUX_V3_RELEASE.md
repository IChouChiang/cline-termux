# Cline Termux V3 Release

The release system packages one upstream Cline CLI tag at a time for native
Termux on Android `aarch64`. Cline, its private Bun FFI runtime, and user data
remain separate:

```text
$PREFIX/bin/cline
$PREFIX/opt/cline-termux/<release>
$PREFIX/opt/bun-android-ffi/<version>
~/.cline
```

The launcher sets `CLINE_NO_AUTO_UPDATE=1` by default. Updates are owned by this
release process because an official CLI update would not include the Termux
runtime and UX patches.

## Release Inputs

`release/port-manifest.json` records the maintained upstream tag and commit,
the Termux release, pinned build toolchain, Bun FFI artifact, OpenTUI versions,
dependency patches, and the small allowlist of expected merge conflicts.

The Cline archive is built from:

- the committed Cline/OpenTUI source tree
- the repository `bun.lock`
- the Bun version pinned by upstream Cline
- the committed OpenTUI Android renderer-thread patch
- the committed OpenTUI dialog patch
- a pinned `patchelf` step that adds `DT_NEEDED libc.so` to `libopentui.so`
- the published Bun Android FFI artifact

A phone is a test target, not a build input. Runtime dependencies are resolved
for Linux ARM64 on the workstation, and `@opentui/core-linux-arm64` is installed
under the Android package alias expected by OpenTUI.

The upstream Linux ARM64 OpenTUI ELF does not declare `libc.so` as a needed
library. Android's linker consequently cannot resolve `getauxval` when Bun
loads it directly. The builder adds that dependency deterministically and the
phone gate verifies a real `dlopen()` before publication.

OpenTUI disables its native renderer thread on Linux. The Android patch extends
that existing platform rule to Android, where enabling the thread prevents the
renderer and Bun event loop from making progress. The package and phone gates
verify that this pinned patch is present before accepting a candidate.

## Managed Flow

Inspect exactly the next stable CLI release:

```sh
bash release/manage.sh inspect cli-v3.0.30
```

The inspection verifies sequential versioning, ancestry, Bun/Node/OpenTUI pins,
downstream/upstream path overlap, and simulated merge conflicts. Toolchain or
OpenTUI changes stop automation for manual review.

Prepare and publish a candidate:

```sh
bash release/manage.sh candidate cli-v3.0.30
```

The candidate command:

1. creates an isolated Git worktree from `main`
2. merges one upstream CLI tag
3. resolves only allowlisted metadata conflicts
4. installs with upstream's exact Bun version
5. tests the release-manager download safeguards
6. runs SDK build, CLI unit tests, typecheck, CLI build, and official TUI tests
7. creates a deterministic Android ARM64 archive
8. tests the unpublished archive in a Termux sandbox on the S25 Ultra
9. pushes the final tag and creates a public GitHub prerelease
10. installs that exact release URL on the S25 Ultra
11. runs version, help, FFI `dlopen`, and a visible-frame TUI check

Nothing is pushed before the source and unpublished-package gates pass. The
candidate tag uses the final release name, such as `v3.0.30-termux.1`, so the
same immutable assets can later be promoted without rebuilding.

## Manual Candidate Test

On the S25 Ultra:

1. launch `cline --tui`
2. tap the input box and confirm the IME opens
3. finger-scroll the transcript
4. open `/settings`, `/model`, and `/history` with the IME visible
5. send one real prompt and complete a short conversation

Promote only after those checks pass:

```sh
bash release/manage.sh promote \
  v3.0.30-termux.1 \
  --confirm-manual-test
```

Promotion downloads the published assets with bounded retries, verifies the
archive checksum and installer against the tagged source, fast-forwards `main`,
and marks the unchanged prerelease stable/latest. It then downloads and runs the
canonical `releases/latest` installer as separate steps so a transport failure
cannot be masked by a shell pipeline. The final release check is an
install/update from that stable URL on the S7+.

There is deliberately no range mode. If several upstream tags are pending, the
entire candidate/manual/promote/device cycle is completed for each tag before
the next inspection.

## Manual Builder

The manager normally owns packaging. For diagnostics, build directly with:

```sh
bash release/build-termux-release.sh \
  --release v3.0.30-termux.1
```

Use `--skip-build` only when `apps/cli/dist` was built from the current commit.
The archive and checksum are written to `release/dist/`, which is ignored by
Git.

## Public Install

Stable users install or update with:

```sh
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash
```

The installer checks the Cline archive checksum, keeps versioned directories,
updates the `current` symlink atomically, and runs a native OpenTUI `dlopen()`
smoke before reporting success.

## Recovery Rules

- Never replace assets attached to a published tag.
- A failed candidate receives the next downstream revision, such as
  `v3.0.30-termux.2`.
- If the post-promotion latest-URL check fails, restore the previous release as
  GitHub's Latest release and investigate before continuing.
- Do not advance to the next upstream CLI tag until the current stable release
  passes on both physical devices.
