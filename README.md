# Cline Termux

Unofficial native Termux port of the Cline CLI TUI for Android `aarch64`.

This repository packages the upstream Cline CLI for Termux and adds the small
runtime/UX pieces needed for a phone-native terminal experience. It is not an
official Cline release.

Current port:

```text
Cline CLI: 3.0.29
Termux release: v3.0.29-termux.1
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

## Why Bun FFI Is Included

Cline CLI v3 uses OpenTUI. OpenTUI loads its native renderer through
`bun:ffi dlopen()`.

Official Bun Android can run JavaScript, but currently cannot perform that
native `dlopen()` path because TinyCC is disabled. This port therefore depends
on a small experimental Bun Android FFI runtime:

```text
https://github.com/IChouChiang/bun-android-ffi
```

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
success.

## Maintainer Flow

Each stable upstream CLI tag is handled independently:

```sh
bash release/manage.sh inspect cli-v3.0.30
bash release/manage.sh candidate cli-v3.0.30
bash release/manage.sh promote v3.0.30-termux.1 --confirm-manual-test
```

`candidate` builds once, runs the upstream CLI unit and TUI suites, tests the
unpublished archive on Termux, publishes a prerelease, and installs that exact
tag on the S25 Ultra. `promote` only changes release state after the manual
touch/IME test; it does not rebuild or replace release assets. The manager has
no range mode, so an upstream CLI release cannot be skipped accidentally.

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

Downstream Bun FFI runtime:

```text
https://github.com/IChouChiang/bun-android-ffi
```

License:

```text
Apache-2.0 for Cline
Bun and linked-library notices are included in the Bun FFI runtime artifact
```
