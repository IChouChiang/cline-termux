#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

GITHUB_REPO="${CLINE_TERMUX_GITHUB_REPO:-IChouChiang/cline-termux}"
TERMUX_PREFIX="${PREFIX:-}"
INSTALL_BASE="${CLINE_TERMUX_INSTALL_BASE:-$TERMUX_PREFIX/opt/cline-termux}"
LAUNCHER_PATH="${CLINE_TERMUX_LAUNCHER_PATH:-$TERMUX_PREFIX/bin/cline}"
BUN_FFI_REPO="${CLINE_TERMUX_BUN_FFI_REPO:-IChouChiang/bun-android-ffi}"
BUN_FFI_VERSION="${CLINE_TERMUX_BUN_FFI_VERSION:-1.4.0-canary.1-55f6c899f}"
BUN_FFI_ASSET="${CLINE_TERMUX_BUN_FFI_ASSET:-bun-android-ffi-aarch64-v$BUN_FFI_VERSION.tar.gz}"
BUN_FFI_INSTALL_BASE="${CLINE_TERMUX_BUN_INSTALL_BASE:-$TERMUX_PREFIX/opt/bun-android-ffi}"
BUN_FFI_LINK_PATH="${CLINE_TERMUX_BUN_LINK_PATH:-$TERMUX_PREFIX/bin/bun-ffi}"
REQUESTED_VERSION="${CLINE_TERMUX_VERSION:-}"
FORCE="${CLINE_TERMUX_FORCE:-0}"
SKIP_PKG_UPDATE="${CLINE_TERMUX_SKIP_PKG_UPDATE:-0}"
SKIP_BUN_INSTALL="${CLINE_TERMUX_SKIP_BUN_INSTALL:-0}"
DOWNLOAD_DIR=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURL_RETRIES="${CLINE_TERMUX_CURL_RETRIES:-5}"
CURL_MAX_TIME="${CLINE_TERMUX_CURL_MAX_TIME:-600}"

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
	printf '%b[info]%b %s\n' "$BLUE" "$NC" "$*"
}

ok() {
	printf '%b[ok]%b %s\n' "$GREEN" "$NC" "$*"
}

warn() {
	printf '%b[warn]%b %s\n' "$YELLOW" "$NC" "$*"
}

die() {
	printf '%b[error]%b %s\n' "$RED" "$NC" "$*" >&2
	exit 1
}

curl_request() {
	curl --fail --location --silent --show-error \
		--retry "$CURL_RETRIES" --retry-all-errors \
		--connect-timeout 15 --max-time "$CURL_MAX_TIME" \
		"$@"
}

usage() {
	cat <<EOF
Usage: bash install-cline-termux.sh [options]

Options:
  --version VERSION   Install a specific release tag, for example v3.0.29-termux.1
  --repo OWNER/REPO   Download from a different GitHub repository
  --install-base DIR  Install under DIR instead of $INSTALL_BASE
  --launcher PATH     Write the cline launcher to PATH instead of $LAUNCHER_PATH
  --force             Back up and replace an existing non-Cline-Termux launcher
  --skip-pkg-update   Do not run pkg update before installing prerequisites
  --skip-bun-install  Require an existing Bun FFI runtime instead of installing it
  -h, --help          Show this help

Environment overrides use the CLINE_TERMUX_* names shown in the script.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--version)
			[ -n "${2:-}" ] || die "--version requires a value"
			REQUESTED_VERSION="$2"
			shift 2
			;;
		--repo)
			[ -n "${2:-}" ] || die "--repo requires OWNER/REPO"
			GITHUB_REPO="$2"
			shift 2
			;;
		--install-base)
			[ -n "${2:-}" ] || die "--install-base requires a directory"
			INSTALL_BASE="$2"
			shift 2
			;;
		--launcher)
			[ -n "${2:-}" ] || die "--launcher requires a path"
			LAUNCHER_PATH="$2"
			shift 2
			;;
		--force)
			FORCE=1
			shift
			;;
		--skip-pkg-update)
			SKIP_PKG_UPDATE=1
			shift
			;;
		--skip-bun-install)
			SKIP_BUN_INSTALL=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "Unknown option: $1"
			;;
	esac
done

normalize_tag() {
	case "$1" in
		v*) printf '%s\n' "$1" ;;
		*) printf 'v%s\n' "$1" ;;
	esac
}

read_release_field() {
	local file="$1"
	local key="$2"
	sed -n "s/^$key=//p" "$file" | head -n 1
}

find_bun() {
	if [ -n "${CLINE_TERMUX_BUN:-}" ] && [ -x "$CLINE_TERMUX_BUN" ]; then
		printf '%s\n' "$CLINE_TERMUX_BUN"
		return 0
	fi
	if [ -x "$BUN_FFI_INSTALL_BASE/current/bun" ]; then
		printf '%s\n' "$BUN_FFI_INSTALL_BASE/current/bun"
		return 0
	fi
	return 1
}

install_prerequisites() {
	if [ "$SKIP_PKG_UPDATE" != 1 ]; then
		info "Updating Termux package index..."
		pkg update -y >/dev/null
	fi

	local needed=()
	command -v curl >/dev/null 2>&1 || needed+=(curl)
	command -v node >/dev/null 2>&1 || needed+=(nodejs-lts)
	command -v rg >/dev/null 2>&1 || needed+=(ripgrep)
	command -v tar >/dev/null 2>&1 || needed+=(tar)
	command -v sha256sum >/dev/null 2>&1 || needed+=(coreutils)

	if [ "${#needed[@]}" -gt 0 ]; then
		info "Installing required Termux packages: ${needed[*]}"
		pkg install -y "${needed[@]}"
	fi
}

verify_checksum_if_present() {
	local asset="$1"
	local checksum="$asset.sha256"
	if [ -f "$checksum" ]; then
		info "Verifying $(basename "$asset")..."
		(
			cd "$(dirname "$asset")"
			sha256sum -c "$(basename "$checksum")" >/dev/null
		) || die "Checksum verification failed for $asset."
		ok "Checksum verified."
	fi
}

find_local_bun_asset() {
	local parent_dir
	parent_dir="$(dirname "$SCRIPT_DIR")"
	for candidate in \
		"$SCRIPT_DIR/deps/$BUN_FFI_ASSET" \
		"$SCRIPT_DIR/$BUN_FFI_ASSET" \
		"$parent_dir/$BUN_FFI_ASSET" \
		"$PWD/$BUN_FFI_ASSET"; do
		if [ -f "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

download_bun_ffi() {
	local tag="v$BUN_FFI_VERSION"
	local api_url="https://api.github.com/repos/$BUN_FFI_REPO/releases/tags/$tag"

	info "Fetching Bun FFI release metadata from GitHub..."
	local release_json
	release_json=$(curl_request "$api_url") \
		|| die "Failed to fetch Bun FFI release metadata for $tag."

	local download_url
	download_url=$(printf '%s' "$release_json" | BUN_FFI_ASSET="$BUN_FFI_ASSET" node -e '
const fs = require("fs")
const data = JSON.parse(fs.readFileSync(0, "utf8"))
const asset = (data.assets || []).find((entry) => entry.name === process.env.BUN_FFI_ASSET)
if (!asset) process.exit(1)
console.log(asset.browser_download_url || "")
') || die "Could not find Bun FFI asset $BUN_FFI_ASSET in $BUN_FFI_REPO@$tag."
	[ -n "$download_url" ] || die "Bun FFI asset download URL was missing."

	mkdir -p "$DOWNLOAD_DIR"
	info "Downloading $BUN_FFI_ASSET ..."
	curl_request -o "$DOWNLOAD_DIR/$BUN_FFI_ASSET" "$download_url" \
		|| die "Failed to download Bun FFI runtime."

	if curl_request -o "$DOWNLOAD_DIR/$BUN_FFI_ASSET.sha256" "$download_url.sha256" 2>/dev/null; then
		verify_checksum_if_present "$DOWNLOAD_DIR/$BUN_FFI_ASSET"
	else
		warn "No Bun FFI checksum asset found; continuing without checksum verification."
	fi
}

install_bun_ffi() {
	if [ "$SKIP_BUN_INSTALL" = 1 ]; then
		die "Bun FFI runtime is missing. Install it or rerun without --skip-bun-install."
	fi

	local asset
	if asset=$(find_local_bun_asset); then
		info "Installing Bun FFI from local asset: $asset"
		verify_checksum_if_present "$asset"
	else
		[ -n "$DOWNLOAD_DIR" ] || DOWNLOAD_DIR=$(mktemp -d)
		download_bun_ffi
		asset="$DOWNLOAD_DIR/$BUN_FFI_ASSET"
	fi

	local extract_dir source_dir version_file bun_version target_dir tmp_dir
	extract_dir=$(mktemp -d)
	tar xzf "$asset" -C "$extract_dir"
	source_dir=$(find "$extract_dir" -maxdepth 1 -type d -name 'bun-android-ffi-aarch64-v*' | head -n 1)
	[ -d "$source_dir" ] || die "Could not find extracted Bun FFI directory."
	[ -x "$source_dir/bun" ] || die "Bun FFI asset is missing executable bun."
	version_file="$source_dir/VERSION"
	[ -f "$version_file" ] || die "Bun FFI asset is missing VERSION."
	bun_version=$(read_release_field "$version_file" "release")
	[ -n "$bun_version" ] || die "Bun FFI VERSION is missing release=..."

	target_dir="$BUN_FFI_INSTALL_BASE/$bun_version"
	tmp_dir="$BUN_FFI_INSTALL_BASE/.install-$bun_version.$$"

	rm -rf "$tmp_dir"
	mkdir -p "$tmp_dir"
	cp -R "$source_dir"/. "$tmp_dir"/
	chmod +x "$tmp_dir/bun"
	if [ -d "$target_dir" ]; then
		warn "Replacing existing Bun FFI runtime at $target_dir"
		rm -rf "$target_dir"
	fi
	mv "$tmp_dir" "$target_dir"

	if [ -e "$BUN_FFI_INSTALL_BASE/current" ] && [ ! -L "$BUN_FFI_INSTALL_BASE/current" ]; then
		die "$BUN_FFI_INSTALL_BASE/current exists but is not a symlink. Move it aside before installing."
	fi
	ln -sfn "$target_dir" "$BUN_FFI_INSTALL_BASE/current"

	mkdir -p "$(dirname "$BUN_FFI_LINK_PATH")"
	ln -sfn "$BUN_FFI_INSTALL_BASE/current/bun" "$BUN_FFI_LINK_PATH"
	rm -rf "$extract_dir"
	ok "Installed Bun FFI $bun_version to $target_dir"
}

download_release() {
	local api_url

	if [ -n "$REQUESTED_VERSION" ]; then
		REQUESTED_VERSION="$(normalize_tag "$REQUESTED_VERSION")"
		api_url="https://api.github.com/repos/$GITHUB_REPO/releases/tags/$REQUESTED_VERSION"
	else
		api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
	fi

	info "Fetching release metadata from GitHub..."
	local release_json
	release_json=$(curl_request "$api_url") || die "Failed to fetch release metadata."

	local release_info
	release_info=$(printf '%s' "$release_json" | node -e '
const fs = require("fs")
const data = JSON.parse(fs.readFileSync(0, "utf8"))
const asset = (data.assets || []).find((entry) => /^cline-termux-aarch64-v.+\.tar\.gz$/.test(entry.name))
if (!asset) process.exit(1)
console.log([data.tag_name || "", asset.name, asset.browser_download_url || ""].join("\n"))
') || die "Could not find a cline-termux aarch64 tarball in the release."

	local tag_name asset_name download_url
	tag_name=$(printf '%s\n' "$release_info" | sed -n '1p')
	asset_name=$(printf '%s\n' "$release_info" | sed -n '2p')
	download_url=$(printf '%s\n' "$release_info" | sed -n '3p')

	[ -n "$tag_name" ] || die "Release tag was missing from GitHub metadata."
	[ -n "$download_url" ] || die "Release asset download URL was missing."

	DOWNLOAD_DIR=$(mktemp -d)
	info "Downloading $asset_name ..."
	curl_request -o "$DOWNLOAD_DIR/$asset_name" "$download_url" \
		|| die "Failed to download release tarball."

	local checksum_url="$download_url.sha256"
	if curl_request -o "$DOWNLOAD_DIR/$asset_name.sha256" "$checksum_url" 2>/dev/null; then
		info "Verifying checksum..."
		(
			cd "$DOWNLOAD_DIR"
			sha256sum -c "$asset_name.sha256" >/dev/null
		) || die "Checksum verification failed."
		ok "Checksum verified."
	else
		warn "No checksum asset found; continuing without checksum verification."
	fi

	info "Extracting bundle..."
	tar xzf "$DOWNLOAD_DIR/$asset_name" -C "$DOWNLOAD_DIR"
	SOURCE_DIR=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type d -name 'cline-termux-aarch64-v*' | head -n 1)
	[ -d "$SOURCE_DIR" ] || die "Could not find extracted bundle directory."
}

install_bundle() {
	local source_dir="$1"
	local version_file="$source_dir/VERSION"

	[ -f "$source_dir/index.js" ] || die "Bundle is missing index.js"
	[ -d "$source_dir/node_modules" ] || die "Bundle is missing node_modules"
	[ -f "$version_file" ] || die "Bundle is missing VERSION"

	local release_version cline_version
	release_version=$(read_release_field "$version_file" "release")
	cline_version=$(read_release_field "$version_file" "cline")
	[ -n "$release_version" ] || die "VERSION is missing release=..."
	[ -n "$cline_version" ] || die "VERSION is missing cline=..."

	local target_dir="$INSTALL_BASE/$release_version"
	local tmp_dir="$INSTALL_BASE/.install-$release_version.$$"

	if [ -d "$target_dir" ]; then
		warn "Replacing existing installation at $target_dir"
		rm -rf "$target_dir"
	fi

	rm -rf "$tmp_dir"
	mkdir -p "$tmp_dir"
	cp -R "$source_dir"/. "$tmp_dir"/
	chmod +x "$tmp_dir/index.js"
	mv "$tmp_dir" "$target_dir"

	if [ -e "$INSTALL_BASE/current" ] && [ ! -L "$INSTALL_BASE/current" ]; then
		die "$INSTALL_BASE/current exists but is not a symlink. Move it aside before installing."
	fi
	ln -sfn "$target_dir" "$INSTALL_BASE/current"

	ok "Installed Cline Termux $release_version to $target_dir"
}

write_launcher() {
	local launcher_dir
	launcher_dir=$(dirname "$LAUNCHER_PATH")
	mkdir -p "$launcher_dir"

	if [ -e "$LAUNCHER_PATH" ] && ! grep -q "CLINE_TERMUX_LAUNCHER=1" "$LAUNCHER_PATH" 2>/dev/null; then
		if [ "$FORCE" = 1 ]; then
			local backup="$LAUNCHER_PATH.backup.$(date +%Y%m%d-%H%M%S)"
			warn "Backing up existing launcher to $backup"
			mv "$LAUNCHER_PATH" "$backup"
		else
			die "$LAUNCHER_PATH already exists and was not created by this installer. Rerun with --force to back it up and replace it."
		fi
	fi

	info "Creating launcher at $LAUNCHER_PATH ..."
	cat > "$LAUNCHER_PATH" <<LAUNCHER
#!/data/data/com.termux/files/usr/bin/bash
# CLINE_TERMUX_LAUNCHER=1

set -e

CLINE_TERMUX_HOME="\${CLINE_TERMUX_HOME:-$INSTALL_BASE/current}"
DEFAULT_TERMUX_BUN="$BUN_FFI_INSTALL_BASE/current/bun"

if [ ! -f "\$CLINE_TERMUX_HOME/index.js" ]; then
	echo "Error: Cline Termux runtime not found at \$CLINE_TERMUX_HOME" >&2
	exit 1
fi

if [ -n "\${CLINE_TERMUX_BUN:-}" ] && [ -x "\$CLINE_TERMUX_BUN" ]; then
	BUN_BIN="\$CLINE_TERMUX_BUN"
elif [ -x "\$DEFAULT_TERMUX_BUN" ]; then
	BUN_BIN="\$DEFAULT_TERMUX_BUN"
else
	echo "Error: Bun FFI runtime not found. Re-run the Cline Termux installer." >&2
	exit 1
fi

export CLINE_NO_AUTO_UPDATE="\${CLINE_NO_AUTO_UPDATE:-1}"

if [ -f "\$CLINE_TERMUX_HOME/cline-node-wrapper.cjs" ] \
	&& [ -f "\$CLINE_TERMUX_HOME/ca-certs.cjs" ] \
	&& [ -x "\$CLINE_TERMUX_HOME/run-cline-termux.sh" ]; then
	export CLINE_TERMUX_HOME
	export CLINE_TERMUX_BUN="\$BUN_BIN"
	export CLINE_BIN_PATH="\${CLINE_BIN_PATH:-\$CLINE_TERMUX_HOME/run-cline-termux.sh}"
	if [ -z "\${SSL_CERT_FILE:-}" ] && [ -r "$TERMUX_PREFIX/etc/tls/cert.pem" ]; then
		export SSL_CERT_FILE="$TERMUX_PREFIX/etc/tls/cert.pem"
	fi
	if [ -z "\${SSL_CERT_DIR:-}" ] && [ -d "\$CLINE_TERMUX_HOME/empty-ca-dir" ]; then
		export SSL_CERT_DIR="\$CLINE_TERMUX_HOME/empty-ca-dir"
	fi
	exec node "\$CLINE_TERMUX_HOME/cline-node-wrapper.cjs" "\$@"
fi

exec "\$BUN_BIN" "\$CLINE_TERMUX_HOME/index.js" "\$@"
LAUNCHER
	chmod +x "$LAUNCHER_PATH"
}

smoke_test() {
	local version_file="$INSTALL_BASE/current/VERSION"
	local cline_version bun_bin
	cline_version=$(read_release_field "$version_file" "cline")
	bun_bin=$(find_bun) || die "Bun FFI runtime disappeared after installation."

	info "Running smoke tests..."
	if "$bun_bin" --version >/dev/null 2>&1; then
		ok "bun-ffi --version -> $("$bun_bin" --version)"
	else
		die "Bun FFI runtime does not start."
	fi

	local installed_version
	installed_version=$("$LAUNCHER_PATH" --version 2>/dev/null || true)
	if [ "$installed_version" = "$cline_version" ]; then
		ok "cline --version -> $installed_version"
	else
		warn "Expected cline --version to print $cline_version, got '$installed_version'"
	fi

	if "$LAUNCHER_PATH" --help >/dev/null 2>&1; then
		ok "cline --help works"
	else
		warn "cline --help returned non-zero"
	fi

	if (
		cd "$INSTALL_BASE/current"
		"$bun_bin" -e 'import { dlopen } from "bun:ffi"; const lib = dlopen("./node_modules/@opentui/core-android-arm64/libopentui.so", { createRenderer: { args: ["u32", "u32", "bool", "bool"], returns: "ptr" } }); if (!lib.symbols.createRenderer) process.exit(1); console.log("opentui-dlopen-ok")' >/dev/null
	); then
		ok "OpenTUI native dlopen works"
	else
		die "OpenTUI native dlopen failed."
	fi
}

info "Checking environment..."
[ -n "${PREFIX:-}" ] || die "This installer requires Termux (PREFIX not set)."
[ -d "$PREFIX" ] || die "PREFIX directory not found: $PREFIX"
[ "$(uname -m)" = "aarch64" ] || die "This release is built for Termux aarch64 only."
command -v pkg >/dev/null 2>&1 || die "pkg was not found. Is this Termux?"
ok "Termux aarch64 detected."

install_prerequisites

if ! BUN_BIN=$(find_bun); then
	install_bun_ffi
	BUN_BIN=$(find_bun) || die "Bun FFI installation did not produce a runnable runtime."
fi
ok "Bun FFI $("$BUN_BIN" --version) at $BUN_BIN"

SOURCE_DIR=""
if [ -f "$SCRIPT_DIR/index.js" ] && [ -f "$SCRIPT_DIR/VERSION" ] && [ -d "$SCRIPT_DIR/node_modules" ]; then
	info "Installing from extracted bundle: $SCRIPT_DIR"
	SOURCE_DIR="$SCRIPT_DIR"
else
	download_release
fi

install_bundle "$SOURCE_DIR"
write_launcher
smoke_test

echo
ok "Cline Termux installed. Run: cline"
