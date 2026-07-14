#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Sourcing exposes the download helpers without dispatching a manager command.
source "$SCRIPT_DIR/manage.sh"

CURL_RETRIES=0
CURL_MAX_TIME=5

fail_test() {
	echo "[fail] $*" >&2
	exit 1
}

ssh() {
	local host="$1"
	shift
	[ "$host" = test-host ] || fail_test "unexpected test host: $host"
	"$@"
}

export INSTALLER_ARGS_FILE="$WORK_DIR/installer-args"
installer="$WORK_DIR/installer.sh"
cat > "$installer" <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$INSTALLER_ARGS_FILE"
INSTALLER

install_release_on_host test-host "file://$installer" v3.0.31-termux.1
printf '%s\n' \
	--version \
	v3.0.31-termux.1 \
	--skip-pkg-update > "$WORK_DIR/expected-args"
cmp -s "$WORK_DIR/expected-args" "$INSTALLER_ARGS_FILE" \
	|| fail_test "remote installer arguments were not preserved"

rm -f "$INSTALLER_ARGS_FILE"
install_release_on_host test-host "file://$installer"
printf '%s\n' --skip-pkg-update > "$WORK_DIR/expected-args"
cmp -s "$WORK_DIR/expected-args" "$INSTALLER_ARGS_FILE" \
	|| fail_test "latest installer unexpectedly received a version"

rm -f "$INSTALLER_ARGS_FILE"
if install_release_on_host test-host "file://$WORK_DIR/missing-installer" \
	2> "$WORK_DIR/expected-download-error"; then
	fail_test "failed installer download returned success"
fi
[ ! -e "$INSTALLER_ARGS_FILE" ] \
	|| fail_test "installer ran after its download failed"

download_file "file://$installer" "$WORK_DIR/downloaded-installer"
cmp -s "$installer" "$WORK_DIR/downloaded-installer" \
	|| fail_test "downloaded file differs from its source"

echo "[ok] release manager download safeguards"
