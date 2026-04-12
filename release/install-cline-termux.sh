#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

GITHUB_REPO="IChouChiang/cline-termux"
INSTALL_BASE="$HOME/.cline-termux"
LAUNCHER_PATH="$PREFIX/bin/cline"
DOWNLOAD_DIR=""

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

cleanup() {
	if [ -n "$DOWNLOAD_DIR" ] && [ -d "$DOWNLOAD_DIR" ]; then
		rm -rf "$DOWNLOAD_DIR"
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

error() {
	echo -e "${RED}[error]${NC} $*" >&2
}

die() {
	error "$@"
	exit 1
}

info "Checking environment..."

[ -n "${PREFIX:-}" ] || die "This installer requires Termux (PREFIX not set)."
[ -d "$PREFIX" ] || die "PREFIX directory not found: $PREFIX"
[ "$(uname -m)" = "aarch64" ] || die "This release is built for aarch64 only."
command -v pkg >/dev/null 2>&1 || die "pkg not found. Is this Termux?"

ok "Termux aarch64 detected."

info "Updating package index..."
pkg update -y >/dev/null
pkg upgrade -y >/dev/null

NEEDED_PKGS=()
if ! command -v node >/dev/null 2>&1; then
	NEEDED_PKGS+=(nodejs-lts)
elif [ "$(node -e 'console.log(process.versions.node.split(".")[0])')" -lt 20 ]; then
	NEEDED_PKGS+=(nodejs-lts)
fi

if ! command -v rg >/dev/null 2>&1; then
	NEEDED_PKGS+=(ripgrep)
fi

if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
	info "Installing required packages: ${NEEDED_PKGS[*]}"
	pkg install -y "${NEEDED_PKGS[@]}"
fi

ok "Required packages are available."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/dist/cli.mjs" ] && [ -f "$SCRIPT_DIR/package.json" ]; then
	info "Installing from extracted bundle: $SCRIPT_DIR"
	SOURCE_DIR="$SCRIPT_DIR"
	VERSION=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$SOURCE_DIR/package.json', 'utf8')).version)")
else
	info "Fetching latest release metadata from GitHub..."
	RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest") \
		|| die "Failed to fetch release info from GitHub."

	RELEASE_INFO=$(echo "$RELEASE_JSON" | node -e '
		const data = JSON.parse(require("fs").readFileSync(0, "utf8"))
		const asset = (data.assets || []).find((entry) => /^cline-termux-aarch64-.*\.tar\.gz$/.test(entry.name))
		if (!asset) {
			process.exit(1)
		}
		console.log([data.tag_name || "", asset.name, asset.browser_download_url || ""].join("\n"))
	') || die "Could not find a Termux bundle asset in the latest release."

	TAG_NAME=$(echo "$RELEASE_INFO" | sed -n '1p')
	ASSET_NAME=$(echo "$RELEASE_INFO" | sed -n '2p')
	DOWNLOAD_URL=$(echo "$RELEASE_INFO" | sed -n '3p')

	[ -n "$TAG_NAME" ] || die "Could not determine the latest release tag."
	[ -n "$DOWNLOAD_URL" ] || die "Could not determine the bundle download URL."

	DOWNLOAD_DIR=$(mktemp -d)
	info "Downloading $ASSET_NAME ..."
	curl -fSL -o "$DOWNLOAD_DIR/$ASSET_NAME" "$DOWNLOAD_URL" || die "Failed to download release bundle."

	CHECKSUM_URL="${DOWNLOAD_URL}.sha256"
	if curl -fsSL -o "$DOWNLOAD_DIR/$ASSET_NAME.sha256" "$CHECKSUM_URL" 2>/dev/null; then
		info "Verifying checksum..."
		pushd "$DOWNLOAD_DIR" >/dev/null
		sha256sum -c "$ASSET_NAME.sha256" >/dev/null 2>&1 || die "Checksum verification failed."
		popd >/dev/null
		ok "Checksum verified."
	else
		warn "No checksum file found; skipping verification."
	fi

	info "Extracting bundle..."
	tar xzf "$DOWNLOAD_DIR/$ASSET_NAME" -C "$DOWNLOAD_DIR"
	SOURCE_DIR=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type d -name 'cline-termux-*' | head -n 1)
	[ -d "$SOURCE_DIR" ] || die "Could not find the extracted bundle directory."
	VERSION=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$SOURCE_DIR/package.json', 'utf8')).version)")
fi

TARGET_DIR="$INSTALL_BASE/v$VERSION"

if [ -d "$TARGET_DIR" ]; then
	warn "Replacing existing installation at $TARGET_DIR"
	rm -rf "$TARGET_DIR"
fi

mkdir -p "$TARGET_DIR"
cp -R "$SOURCE_DIR"/. "$TARGET_DIR"/
ln -sfn "$TARGET_DIR" "$INSTALL_BASE/current"

ok "Installed to $TARGET_DIR"

info "Linking ripgrep binary..."
mkdir -p "$TARGET_DIR/node_modules/@vscode/ripgrep/bin"
ln -sf "$(command -v rg)" "$TARGET_DIR/node_modules/@vscode/ripgrep/bin/rg"

info "Creating launcher at $LAUNCHER_PATH ..."
cat > "$LAUNCHER_PATH" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash

CLINE_HOME="$HOME/.cline-termux/current"

if [ ! -d "$CLINE_HOME" ]; then
	echo "Error: Cline Termux Edition not found at $CLINE_HOME" >&2
	exit 1
fi

exec node "$CLINE_HOME/dist/cli.mjs" "$@"
LAUNCHER
chmod +x "$LAUNCHER_PATH"

info "Running smoke tests..."
INSTALLED_VERSION=$("$LAUNCHER_PATH" --version 2>/dev/null || true)
if [ "$INSTALLED_VERSION" = "$VERSION" ]; then
	ok "cline --version -> $INSTALLED_VERSION"
else
	warn "Expected version $VERSION but got '$INSTALLED_VERSION'"
fi

if "$LAUNCHER_PATH" --help >/dev/null 2>&1; then
	ok "cline --help works"
else
	warn "cline --help returned non-zero"
fi

echo
ok "Cline Termux Edition v$VERSION installed. Run: cline"