# Cline Termux

[![Latest release](https://img.shields.io/github/v/release/IChouChiang/cline-termux?label=release)](https://github.com/IChouChiang/cline-termux/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Android%20aarch64%20(Termux)-3ddc84)](https://termux.dev)
[![License](https://img.shields.io/github/license/IChouChiang/cline-termux)](LICENSE)

Unofficial native Termux port of the Cline CLI TUI for Android `aarch64`.

This repository packages the upstream Cline CLI for Termux and adds the small
runtime/UX pieces needed for a phone-native terminal experience. It is not an
official Cline release.

![Cline TUI running natively in Termux on a Samsung S25 Ultra](docs/images/cline-termux-tui.png)

Current port:

```text
Cline CLI: 3.0.61
Termux release: v3.0.61-termux.2
Platform: Android aarch64
Command: cline
```

## Install

```sh
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash
```

Then run:

```sh
cline
```

or explicitly open the TUI:

```sh
cline --tui
```

## Requirements

- Termux on Android
- `aarch64` device
- Internet access for the first install
- An API key/provider supported by Cline

The installer installs required Termux packages if they are missing:

```text
curl
nodejs-lts
ripgrep
tar
coreutils
```

## Runtime Layout

The package follows Termux prefix layout and keeps user data in the official
Cline location:

```text
$PREFIX/bin/cline
$PREFIX/opt/cline-termux/current
$PREFIX/opt/bun-android-ffi/current
$PREFIX/bin/bun-ffi
~/.cline
```

The private `bun-ffi` runtime is used only by this Cline port. It does not
replace `$PREFIX/bin/bun`.

Each release installs into its own `$PREFIX/opt/cline-termux/<version>` tree
and `current` points at the active one. After a successful install the
installer keeps the previous version as an offline rollback path and removes
older trees. To keep more, or to keep everything:

```sh
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash -s -- --keep 3
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash -s -- --no-prune
```

The same settings are available as `CLINE_TERMUX_KEEP_VERSIONS` and
`CLINE_TERMUX_PRUNE=0`. Nothing outside `$PREFIX/opt/cline-termux` is removed.

## Why Bun FFI Is Included

Cline CLI v3 uses OpenTUI. OpenTUI loads its native renderer through
`bun:ffi dlopen()`.

Official Bun Android can run JavaScript, but currently cannot perform that
native `dlopen()` path because TinyCC is disabled. This port therefore depends
on a small experimental Bun Android FFI runtime:

```text
https://github.com/IChouChiang/bun-android-ffi
```

## Android Native OpenTUI Library

OpenTUI publishes native renderer packages for macOS, Linux, and Windows, but
not for Android. This port builds a genuine Android/Bionic
`@opentui/core-android-arm64` from pinned OpenTUI source with Zig and the
Android NDK, and ships it as a checksum-verified release asset. No Linux
prebuilt is aliased as Android and no ELF is rewritten.

The library also disables Android heap pointer tagging in a constructor:
Scudo's tagged pointers cannot survive Bun's number-based FFI pointers, which
otherwise corrupts every heap pointer that crosses the FFI boundary. Build
script and source patch live in `release/opentui-android/`; all pins are
recorded in `release/port-manifest.json`.

## Termux TUI Defaults

This port adjusts three mobile terminal behaviors by default:

```text
CLINE_TUI_TERMUX_DIALOG_SAFE_AREA_BOTTOM=15%
CLINE_TUI_TERMUX_MOUSE=off
CLINE_TUI_TERMUX_TOUCH_SCROLL=transcript
```

The first keeps dialogs such as `/settings`, `/model`, and `/history` higher
above the Android keyboard. The second lets Termux open the soft keyboard when
the screen is touched. The third maps Termux finger scrolling to the transcript;
use `Alt+Up` and `Alt+Down` to browse prompt history.

To restore OpenTUI mouse tracking:

```sh
CLINE_TUI_TERMUX_MOUSE=on cline --tui
```

To restore plain `Up`/`Down` prompt-history navigation:

```sh
CLINE_TUI_TERMUX_TOUCH_SCROLL=input cline --tui
```

## Verify

```sh
cline --version
cline --help
bun-ffi --version
```

The installer also runs a native OpenTUI `dlopen()` smoke test before reporting
success. Release acceptance goes further: every candidate must render real
frames through the packaged native library and draw the TUI input screen in a
pseudo-terminal on a physical device before it can be promoted.

## Maintainer Flow

Each stable upstream CLI tag is handled independently:

```sh
bash release/manage.sh inspect cli-v3.0.30
bash release/manage.sh candidate cli-v3.0.30
bash release/manage.sh promote v3.0.30-termux.1 --confirm-manual-test
```

`candidate` builds once, runs the upstream CLI unit and TUI suites, tests the
unpublished archive on Termux, publishes a prerelease, and installs that exact
tag on the S25 Ultra. Host-side test files are confined to a disposable staging
directory instead of accumulating in `/tmp`. `promote` only changes release
state after the manual touch/IME test; it does not rebuild or replace release
assets. Device acceptance checks use bounded retries. Promotion waits for
GitHub's Latest state, closes the matching update issue, audits active workflows,
and can safely resume after interruption. The manager has no range mode, so an
upstream CLI release cannot be skipped accidentally.

## Uninstall

```sh
rm -f "$PREFIX/bin/cline" "$PREFIX/bin/bun-ffi"
rm -rf "$PREFIX/opt/cline-termux" "$PREFIX/opt/bun-android-ffi"
```

This does not remove `~/.cline`, where Cline stores user settings, tasks, and
API keys.

## Status

Tested on:

```text
Samsung SM-S9380, Android 16, F-Droid Termux 0.118.3, aarch64
```

Known limitations:

- Android `aarch64` only
- experimental private Bun FFI runtime
- no guarantee as a general Bun replacement
- not yet an official Termux package

## Source And Attribution

Upstream Cline:

```text
https://github.com/cline/cline
```

Upstream OpenTUI (source of the Android native library build):

```text
https://github.com/sst/opentui
```

Downstream Bun FFI runtime:

```text
https://github.com/IChouChiang/bun-android-ffi
```

License:

```text
Apache-2.0 for Cline
MIT for OpenTUI; its LICENSE ships inside the Android native package
Bun and linked-library notices are included in the Bun FFI runtime artifact
```
