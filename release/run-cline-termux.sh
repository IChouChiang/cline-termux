#!/data/data/com.termux/files/usr/bin/bash

set -e

: "${CLINE_TERMUX_HOME:?CLINE_TERMUX_HOME is required}"
: "${CLINE_TERMUX_BUN:?CLINE_TERMUX_BUN is required}"

# Bun caches the transpiled form of every source file over 50 KB. Its default
# location is ~/.bun/install/cache/@t@, keyed by content hash, so each release
# of this port added another ~40 MB there that nothing ever removed (16
# releases had piled up ~680 MB on a device that never ran Bun for anything
# else). Keeping the cache inside the release tree preserves the startup-time
# benefit and lets the installer's old-version prune reclaim it with the tree.
if [ -z "${BUN_RUNTIME_TRANSPILER_CACHE_PATH:-}" ]; then
	export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$CLINE_TERMUX_HOME/.transpiler-cache"
	mkdir -p "$BUN_RUNTIME_TRANSPILER_CACHE_PATH" 2>/dev/null || true
fi

# A plain Bun reads bunfig.toml, and on most builds .env, from the folder it
# starts in, and a `preload` entry there would run inside Cline before any
# Cline code. Upstream switched that off for its compiled binaries
# (cline/cline#15781); this port runs the JS bundle, so it gets the same
# protection from two flags: its own, empty config file in place of the
# folder's bunfig.toml, and no .env loading. The config path is the real path
# of this release tree, not the path through `current`, so that the copies of
# the runtime that Cline starts with these flags (the Hub daemon, the plugin
# sandbox, connectors; apps/cli/src/utils/termux-runtime-flags.ts) keep a
# valid path for as long as their own tree exists. A missing file stops Bun
# with an error instead of running unprotected.
runtime_home="$(cd -P -- "$CLINE_TERMUX_HOME" >/dev/null && pwd -P)"

exec "$CLINE_TERMUX_BUN" \
	--config="$runtime_home/cline-termux-runtime.toml" \
	--no-env-file \
	"$CLINE_TERMUX_HOME/index.js" "$@"
