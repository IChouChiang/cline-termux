#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TERMUX_HOST="${TERMUX_HOST:-termux}"
TERMUX_REPO="${TERMUX_REPO:-~/workspace/cline-termux}"
SKIP_PROTO=false
SKIP_BUILD=false
PROTO_SOURCE=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--termux-host)
			TERMUX_HOST="$2"
			shift 2
			;;
		--termux-repo)
			TERMUX_REPO="$2"
			shift 2
			;;
		--skip-proto)
			SKIP_PROTO=true
			shift
			;;
		--skip-build)
			SKIP_BUILD=true
			shift
			;;
		--proto-source)
			PROTO_SOURCE="$2"
			shift 2
			;;
		*)
			echo "Unknown option: $1" >&2
			exit 1
			;;
	esac
done

echo "Checking SSH connectivity to $TERMUX_HOST..."
ssh -o ConnectTimeout=5 "$TERMUX_HOST" "echo ok" >/dev/null

if [ -n "$PROTO_SOURCE" ]; then
	LOCAL_BUILD_DIR="$PROTO_SOURCE"
else
	LOCAL_BUILD_DIR="$REPO_ROOT"
fi

if [ "$SKIP_PROTO" = false ]; then
	echo "Running proto generation on host..."
	if [ "$LOCAL_BUILD_DIR" = "$REPO_ROOT" ]; then
		(
			cd "$REPO_ROOT"
			npm run protos
		)
	fi

	for file in "src/shared/proto" "src/generated" "webview-ui/src/services/grpc-client.ts"; do
		if [ ! -e "$LOCAL_BUILD_DIR/$file" ]; then
			echo "ERROR: missing generated artifact: $LOCAL_BUILD_DIR/$file" >&2
			exit 1
		fi
	done

	echo "Syncing generated artifacts to Termux..."
	rsync -az --delete "$LOCAL_BUILD_DIR/src/shared/proto/" "$TERMUX_HOST:$TERMUX_REPO/src/shared/proto/"
	rsync -az --delete "$LOCAL_BUILD_DIR/src/generated/" "$TERMUX_HOST:$TERMUX_REPO/src/generated/"
	rsync -az "$LOCAL_BUILD_DIR/webview-ui/src/services/grpc-client.ts" "$TERMUX_HOST:$TERMUX_REPO/webview-ui/src/services/grpc-client.ts"
else
	echo "Skipping host proto generation. Verifying remote artifacts..."
	ssh "$TERMUX_HOST" "test -d $TERMUX_REPO/src/shared/proto && test -d $TERMUX_REPO/src/generated && test -f $TERMUX_REPO/webview-ui/src/services/grpc-client.ts"
fi

if [ "$SKIP_BUILD" = false ]; then
	echo "Building CLI on Termux..."
	ssh "$TERMUX_HOST" "cd $TERMUX_REPO/cli && npm run build:termux"
else
	echo "Skipping Termux CLI build. Verifying existing dist..."
	ssh "$TERMUX_HOST" "test -f $TERMUX_REPO/cli/dist/cli.mjs"
fi

echo "Assembling Termux bundle on device..."
ssh "$TERMUX_HOST" "cd $TERMUX_REPO && bash release/assemble-bundle.sh"

VERSION=$(ssh "$TERMUX_HOST" "node -e \"console.log(JSON.parse(require('fs').readFileSync('$TERMUX_REPO/cli/package.json', 'utf8')).version)\"")
RELEASE_NAME="cline-termux-aarch64-v${VERSION}"
LOCAL_DIST_DIR="$SCRIPT_DIR/dist"

mkdir -p "$LOCAL_DIST_DIR"

echo "Pulling release artifacts back to host..."
	rsync -az "$TERMUX_HOST:$TERMUX_REPO/release/dist/${RELEASE_NAME}.tar.gz" "$LOCAL_DIST_DIR/"
	rsync -az "$TERMUX_HOST:$TERMUX_REPO/release/dist/${RELEASE_NAME}.tar.gz.sha256" "$LOCAL_DIST_DIR/"

SOURCE_COMMIT=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
UPSTREAM_COMMIT=$(git -C "$REPO_ROOT" rev-parse --short upstream/main 2>/dev/null || echo unknown)
NOTES_OUTPUT="$LOCAL_DIST_DIR/RELEASE_NOTES-v${VERSION}.md"

node -e '
		const fs = require("fs")
		const [templatePath, outputPath, version, sourceCommit, upstreamCommit] = process.argv.slice(1)
		let text = fs.readFileSync(templatePath, "utf8")
		text = text.replaceAll("__VERSION__", version)
		text = text.replaceAll("__SOURCE_COMMIT__", sourceCommit)
		text = text.replaceAll("__UPSTREAM_COMMIT__", upstreamCommit)
		fs.writeFileSync(outputPath, text)
	' "$SCRIPT_DIR/RELEASE_NOTES.md" "$NOTES_OUTPUT" "$VERSION" "$SOURCE_COMMIT" "$UPSTREAM_COMMIT"

echo
echo "Release bundle ready: $LOCAL_DIST_DIR/${RELEASE_NAME}.tar.gz"
echo "Checksum:             $LOCAL_DIST_DIR/${RELEASE_NAME}.tar.gz.sha256"
echo "Release notes:        $NOTES_OUTPUT"
echo
echo "Publish with:"
cat <<EOF
gh release create v${VERSION}-termux \
	$LOCAL_DIST_DIR/${RELEASE_NAME}.tar.gz \
	$LOCAL_DIST_DIR/${RELEASE_NAME}.tar.gz.sha256 \
	$SCRIPT_DIR/install-cline-termux.sh \
	--title "Cline Termux Edition v${VERSION}" \
	--notes-file $NOTES_OUTPUT
EOF