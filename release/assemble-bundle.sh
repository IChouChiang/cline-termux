#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

test -f "cli/dist/cli.mjs" || {
	echo "ERROR: cli/dist/cli.mjs not found. Build first with: cd cli && npm run build:termux" >&2
	exit 1
}

test -d "node_modules" || {
	echo "ERROR: node_modules not found at repo root. Run npm install first." >&2
	exit 1
}

VERSION=$(node -e "console.log(JSON.parse(require('fs').readFileSync('cli/package.json', 'utf8')).version)")
SOURCE_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
RELEASE_NAME="cline-termux-aarch64-v${VERSION}"
STAGE_DIR="$SCRIPT_DIR/staging/${RELEASE_NAME}"
DIST_DIR="$SCRIPT_DIR/dist"

echo "=== Assembling Cline Termux Edition v${VERSION} ==="

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/dist/agent" "$STAGE_DIR/man" "$STAGE_DIR/node_modules" "$DIST_DIR"

cp "cli/dist/cli.mjs" "$STAGE_DIR/dist/"
find "cli/dist" -maxdepth 1 -name '*.wasm' -exec cp {} "$STAGE_DIR/dist/" \;
if [ -d "cli/dist/agent" ]; then
	cp -R "cli/dist/agent"/. "$STAGE_DIR/dist/agent/"
fi
if [ -f "cli/man/cline.1" ]; then
	cp "cli/man/cline.1" "$STAGE_DIR/man/"
fi

cat > "$STAGE_DIR/package.json" <<EOF
{
  "name": "cline-termux-edition",
  "version": "$VERSION",
  "type": "module",
  "bin": { "cline": "./dist/cli.mjs" },
  "os": ["android"],
  "cpu": ["arm64"],
  "engines": { "node": ">=20.0.0" }
}
EOF

cat > "$STAGE_DIR/VERSION" <<EOF
$VERSION
source-commit: $SOURCE_COMMIT
platform: termux-android
arch: aarch64
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Resolving external runtime dependencies..."
EXTERNALS=$(node -e '
		const fs = require("fs")
		const source = fs.readFileSync("cli/esbuild.mts", "utf8")
		const match = source.match(/external:\s*\[(.*?)\]/s)
		if (!match) {
			throw new Error("Could not locate the esbuild external list")
		}
		const packages = [...match[1].matchAll(/"([^"]+)"/g)].map((entry) => entry[1])
		console.log([...new Set(packages)].sort().join("\n"))
	')

DEP_LIST=$(printf '%s\n' "$EXTERNALS" | node -e '
		const fs = require("fs")
		const path = require("path")
		const root = path.join(process.cwd(), "node_modules")
		const seeds = fs.readFileSync(0, "utf8").split(/\r?\n/).filter(Boolean)
		const needed = new Set()
		function add(name) {
			if (needed.has(name)) {
				return
			}
			const pkgPath = path.join(root, name, "package.json")
			if (!fs.existsSync(pkgPath)) {
				throw new Error(`Missing runtime package: ${name}`)
			}
			needed.add(name)
			const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"))
			for (const dep of Object.keys(pkg.dependencies || {})) {
				add(dep)
			}
		}
		for (const seed of seeds) {
			add(seed)
		}
		console.log([...needed].sort().join("\n"))
	')

echo "$DEP_LIST" | while IFS= read -r dep; do
	SRC="node_modules/$dep"
	DST="$STAGE_DIR/node_modules/$dep"
	mkdir -p "$(dirname "$DST")"
	cp -R "$SRC" "$DST"
done

mkdir -p "$STAGE_DIR/node_modules/@vscode/ripgrep/bin"
cp "$SCRIPT_DIR/install-cline-termux.sh" "$STAGE_DIR/install.sh"
chmod +x "$STAGE_DIR/install.sh" "$STAGE_DIR/dist/cli.mjs"

TARBALL="$DIST_DIR/${RELEASE_NAME}.tar.gz"

(
	cd "$SCRIPT_DIR/staging"
	tar czf "$TARBALL" "$RELEASE_NAME"
)

(
	cd "$DIST_DIR"
	sha256sum "${RELEASE_NAME}.tar.gz" > "${RELEASE_NAME}.tar.gz.sha256"
)

echo "Tarball:  $TARBALL"
echo "Checksum: $DIST_DIR/${RELEASE_NAME}.tar.gz.sha256"