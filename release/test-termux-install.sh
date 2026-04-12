#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

GITHUB_REPO="IChouChiang/cline-termux"
MODE="release-latest"
TARBALL_PATH=""
WORK_DIR=""

if [ -t 1 ]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	NC='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	NC=''
fi

usage() {
	cat <<EOF
Usage:
  bash release/test-termux-install.sh [--from-release-latest]
  bash release/test-termux-install.sh --from-tarball /absolute/path/to/cline-termux-aarch64-vX.Y.Z.tar.gz

Options:
  --from-release-latest   Install from the latest GitHub release (default).
  --from-tarball PATH     Install from a local bundle tarball. Use this to test an unreleased build on a second Termux device.
  --repo OWNER/REPO       Override the GitHub repo for release-latest mode.
  --help                  Show this help text.
EOF
}

cleanup() {
	if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
		rm -rf "$WORK_DIR"
	fi
}

trap cleanup EXIT

info() {
	echo -e "${BLUE}[info]${NC} $*"
}

ok() {
	echo -e "${GREEN}[ok]${NC} $*"
}

warn() {
	echo -e "${YELLOW}[warn]${NC} $*"
}

die() {
	echo -e "${RED}[error]${NC} $*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--from-release-latest)
			MODE="release-latest"
			shift
			;;
		--from-tarball)
			MODE="tarball"
			TARBALL_PATH="$2"
			shift 2
			;;
		--repo)
			GITHUB_REPO="$2"
			shift 2
			;;
		--help)
			usage
			exit 0
			;;
		*)
			die "Unknown argument: $1"
			;;
	esac
done

[ -n "${PREFIX:-}" ] || die "This script must run inside Termux."
[ -d "$PREFIX" ] || die "PREFIX directory not found: $PREFIX"
[ "$(uname -m)" = "aarch64" ] || die "This test expects aarch64 Termux."
command -v bash >/dev/null 2>&1 || die "bash is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

WORK_DIR=$(mktemp -d)
INSTALL_SCRIPT="$WORK_DIR/install-cline-termux.sh"

if [ "$MODE" = "release-latest" ]; then
	info "Downloading latest installer from GitHub Releases for $GITHUB_REPO ..."
	curl -fsSL "https://github.com/$GITHUB_REPO/releases/latest/download/install-cline-termux.sh" -o "$INSTALL_SCRIPT" \
		|| die "Failed to download the latest installer script."
	bash "$INSTALL_SCRIPT"
else
	[ -n "$TARBALL_PATH" ] || die "--from-tarball requires a tarball path"
	[ -f "$TARBALL_PATH" ] || die "Tarball not found: $TARBALL_PATH"
	info "Testing local bundle tarball: $TARBALL_PATH"
	tar xzf "$TARBALL_PATH" -C "$WORK_DIR"
	BUNDLE_DIR=$(find "$WORK_DIR" -maxdepth 1 -type d -name 'cline-termux-*' | head -n 1)
	[ -d "$BUNDLE_DIR" ] || die "Could not find extracted bundle directory"
	bash "$BUNDLE_DIR/install.sh"
fi

info "Running post-install checks..."
command -v cline >/dev/null 2>&1 || die "cline launcher not found on PATH"
[ -x "$PREFIX/bin/cline" ] || die "Launcher missing or not executable: $PREFIX/bin/cline"
[ -L "$HOME/.cline-termux/current" ] || warn "~/.cline-termux/current is not a symlink"
[ -f "$HOME/.cline-termux/current/dist/cli.mjs" ] || die "Installed cli.mjs not found"
[ -f "$HOME/.cline-termux/current/package.json" ] || die "Installed package.json not found"

VERSION=$(cline --version 2>/dev/null || true)
[ -n "$VERSION" ] || die "cline --version returned nothing"
ok "cline --version -> $VERSION"

cline --help >/dev/null 2>&1 || die "cline --help failed"
ok "cline --help works"

if [ -L "$HOME/.cline-termux/current/node_modules/@vscode/ripgrep/bin/rg" ]; then
	ok "@vscode/ripgrep binary link is present"
else
	warn "@vscode/ripgrep bin link is missing; the installer may have changed"
fi

info "Smoke test completed successfully."
echo
echo "Installed version: $VERSION"
echo "Launcher:          $PREFIX/bin/cline"
echo "Install root:      $HOME/.cline-termux/current"