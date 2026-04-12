# Cline Termux Edition v__VERSION__

Cline CLI running natively on Termux (Android `aarch64`).

## What's included

- Cline CLI v__VERSION__ bundled for Termux
- One-line installer for downloading or upgrading the latest bundle
- Prebuilt runtime payload so users do not need to compile on-device

## Source Baseline

- Upstream repo: `cline/cline`
- Downstream repo: `IChouChiang/cline-termux`
- Release source commit: `__SOURCE_COMMIT__`
- Upstream reference: `__UPSTREAM_COMMIT__`

## Downstream Changes

- `cli/package.json`: add Android platform support and `build:termux`
- `release/`: maintainer scripts for build, assembly, and installation
- `README.md`: Termux installation and maintenance notes

## Install

One-liner:

```bash
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/download/v__VERSION__-termux/install-cline-termux.sh | bash
```

From tarball:

```bash
tar xzf cline-termux-aarch64-v__VERSION__.tar.gz
cd cline-termux-aarch64-v__VERSION__
bash install.sh
```

## Requirements

- Termux on Android (`aarch64`)
- Node.js >= 20 (installed via `pkg` if needed)
- ripgrep (installed via `pkg` if needed)

## Verify

```bash
cline --version
cline --help
```

## Data Locations

| Path | Purpose |
|------|---------|
| `~/.cline-termux/v__VERSION__/` | Runtime payload for this release |
| `~/.cline-termux/current` | Symlink to active version |
| `~/.cline/` | User data, settings, API keys |
| `$PREFIX/bin/cline` | Global launcher |

## Checksum

```text
See cline-termux-aarch64-v__VERSION__.tar.gz.sha256
```
