# Cline Termux Edition - Release Procedure

## Scope

Keep this repository narrow: upstream Cline plus the Termux packaging layer only. Do not land local-model experiments or unrelated downstream features here.

The expected downstream delta is small and should stay close to:

- `cli/package.json`
- `.gitignore`
- `README.md`
- `release/`

## Prerequisites

- PC or WSL host with Node.js >= 20, npm, git, rsync, and SSH access to Termux
- Termux device with `nodejs-lts`, `ripgrep`, `rsync`, and this repo cloned at `~/workspace/cline-termux`
- GitHub CLI if you want to publish directly from the host

## Upstream Sync

```bash
cd /path/to/cline-termux
git fetch upstream origin --tags
git checkout main
git rebase upstream/main
git diff --name-only upstream/main...main
```

That file list should stay small. If it starts drifting into product behavior, back it out and keep the repo packaging-only.

## Build and Assemble a Release

From the host machine:

```bash
cd /path/to/cline-termux
bash release/build-release.sh --termux-host termux --termux-repo ~/workspace/cline-termux
```

This script:

1. Runs `npm run protos` on the host, or uses `--proto-source` if supplied.
2. Syncs generated proto artifacts to Termux.
3. Builds the CLI on Termux with `npm run build:termux`.
4. Assembles the release tarball on Termux so native dependencies come from the Android environment.
5. Pulls the tarball and checksum back into `release/dist/`.
6. Renders release notes into `release/dist/RELEASE_NOTES-v<VERSION>.md`.

## Manual Test

```bash
scp release/dist/cline-termux-aarch64-v<VERSION>.tar.gz termux:~/
ssh termux 'cd ~ && tar xzf cline-termux-aarch64-v<VERSION>.tar.gz && cd cline-termux-aarch64-v<VERSION> && bash install.sh'
ssh termux 'cline --version && cline --help >/dev/null'
```

## Publish

```bash
gh release create v<VERSION>-termux \
  release/dist/cline-termux-aarch64-v<VERSION>.tar.gz \
  release/dist/cline-termux-aarch64-v<VERSION>.tar.gz.sha256 \
  release/install-cline-termux.sh \
  --title "Cline Termux Edition v<VERSION>" \
  --notes-file release/dist/RELEASE_NOTES-v<VERSION>.md
```

## End-User Install

```bash
curl -fsSL https://github.com/IChouChiang/cline-termux/releases/latest/download/install-cline-termux.sh | bash
```

## Install Layout

| Path | Purpose |
|------|---------|
| `~/.cline-termux/v<VERSION>/` | Versioned runtime payload |
| `~/.cline-termux/current` | Symlink to active version |
| `$PREFIX/bin/cline` | Global launcher |
| `~/.cline/` | User data preserved across upgrades |