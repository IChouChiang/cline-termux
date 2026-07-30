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
- the committed OpenTUI Android renderer-thread and native-resolver patches
- the committed OpenTUI dialog patch
- the checksum-pinned genuine Android/Bionic `@opentui/core-android-arm64`
  package (built from OpenTUI source by
  `release/opentui-android/build-opentui-android.sh` and published as the
  `openTuiAndroid` GitHub release asset)
- the published Bun Android FFI artifact

A phone is a test target, not a build input. Runtime dependencies are resolved
for Linux ARM64 on the workstation; the OpenTUI native library alone is the
Bionic build above. No Linux OpenTUI prebuilt is aliased as Android and no ELF
is rewritten — `patchelf` remains in the pipeline only as a read-only verifier.

The Bionic library additionally disables Android heap pointer tagging in a
constructor: Scudo's TBI-tagged pointers cannot be represented by Bun's
f64-based FFI pointers, which corrupts every malloc-backed pointer that
crosses the FFI boundary (Yoga nodes, NativeSpanFeed streams). The device
gates verify real rendered frames, not just a `dlopen()`.

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

1. verifies that the manager staging filesystem has at least 4 GiB free
2. creates an isolated Git worktree and disposable temporary directory
3. merges one upstream CLI tag
4. resolves only allowlisted metadata conflicts
5. installs with upstream's exact Bun version
6. tests the release-manager download safeguards
7. runs SDK build, CLI unit tests, typecheck, CLI build, and official TUI tests
8. creates a deterministic Android ARM64 archive
9. tests the unpublished archive in a Termux sandbox on the S25 Ultra
10. pushes the final tag and creates a public GitHub prerelease
11. installs that exact release URL on the S25 Ultra
12. runs version, help, FFI `dlopen`, and a bounded-retry visible-frame TUI check

The official TUI suite creates many isolated Cline homes without removing them.
The manager points `TMPDIR` at a disposable run directory under
`${XDG_CACHE_HOME:-$HOME/.cache}/cline-termux/release-manager/`, outside the
source repository. This matters for tests that verify behavior outside a Git
repository or Node package boundary. The manager removes the entire directory
on success, failure, or interruption. Override the location with
`CLINE_TERMUX_MANAGER_TEMP_ROOT` or the required reserve with
`CLINE_TERMUX_MIN_TEMP_MIB` when necessary.

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
and marks the unchanged prerelease stable/latest. It waits until GitHub's Latest
API resolves to the new tag, then retries the complete canonical
`releases/latest` install and device acceptance sequence. A partially completed
promotion can be rerun with the same command; it validates and converges local
`main`, `origin/main`, and GitHub release state without rebuilding or replacing
assets. After acceptance, it closes the exact matching upstream-update issue and
warns if active GitHub workflows fall outside the downstream allowlist in
`release/port-manifest.json`. The final release check is an install/update from
that stable URL on the S7+.

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
- If every post-promotion latest-URL attempt fails, the manager restores the
  previous GitHub Latest release and restores the candidate's prerelease state.
  `main` remains fast-forwarded to the immutable candidate so the same promotion
  command can resume safely after the transport or device problem is fixed.
- Do not advance to the next upstream CLI tag until the current stable release
  passes on both physical devices.
