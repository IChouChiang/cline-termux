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

exec "$CLINE_TERMUX_BUN" "$CLINE_TERMUX_HOME/index.js" "$@"
