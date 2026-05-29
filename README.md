# Cline Termux

Unofficial downstream fork of [Cline](https://github.com/cline/cline) for running the Cline CLI/TUI on Android through Termux, with additional bridge work used by the companion Android GUI experiment.

For the full product description, VS Code extension docs, provider setup, and upstream feature details, read the official Cline repository and docs:

- Official repository: https://github.com/cline/cline
- Official docs: https://docs.cline.bot

## What This Fork Is

- A Termux-oriented Cline runtime for Android/aarch64.
- A downstream fork carrying local patches for the Termux CLI/TUI path.
- A shared runtime for two entrypoints:
  - `dist/cli.mjs` for direct Termux CLI/TUI use.
  - `dist/lib.mjs` for the Android app bridge backend.
- A working area for Android GUI and bridge validation used by the mobile coding-agent project.

This repository is not yet a clean Termux-only distribution repo. It currently includes some Android GUI test and bridge integration work because the mobile app and Termux runtime are being developed together. A future cleanup may split or package the pure Termux release path more cleanly.

## Install

```bash
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash
```

Then launch from Termux:

```bash
cline
```

The installer preserves `~/.cline` across upgrades.

## Current Notes

- This is not an official Cline release.
- The Termux edition is distributed as a prebuilt bundle prepared with generated artifacts from a compatible host. Fresh source rebuilds entirely on-device in Termux are not currently a supported goal.
- Browser interaction support differs from desktop Cline and may depend on the Android bridge path.
- Upstream Cline moves quickly. This fork tracks upstream releases manually, with GitHub Actions used only to open update reminder issues.

## Maintaining The Fork

The intended maintenance flow is:

1. A scheduled workflow watches official Cline versions.
2. When upstream moves ahead, it opens an `upstream-update` issue.
3. Updates are reviewed and ported manually on a short-lived sync branch.
4. Termux CLI/TUI and Android bridge smoke tests are run before publishing a new local release.

## License

This fork is derived from Cline and remains under the [Apache License 2.0](./LICENSE). Original Cline copyright and license terms apply.

Third-party dependencies, models, Android components, and external services used with this fork are governed by their own licenses and terms. Review the relevant upstream projects before redistributing bundled artifacts.