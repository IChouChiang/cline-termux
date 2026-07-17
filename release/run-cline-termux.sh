#!/data/data/com.termux/files/usr/bin/bash

set -e

: "${CLINE_TERMUX_HOME:?CLINE_TERMUX_HOME is required}"
: "${CLINE_TERMUX_BUN:?CLINE_TERMUX_BUN is required}"

exec "$CLINE_TERMUX_BUN" "$CLINE_TERMUX_HOME/index.js" "$@"
