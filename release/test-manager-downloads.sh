#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

export CLINE_TERMUX_MANAGER_TEMP_ROOT="$WORK_DIR/manager-temp"
export CLINE_TERMUX_MIN_TEMP_MIB=1
export CLINE_TERMUX_LATEST_WAIT_ATTEMPTS=3
export CLINE_TERMUX_LATEST_WAIT_SECONDS=0
export CLINE_TERMUX_LATEST_SMOKE_ATTEMPTS=3
export CLINE_TERMUX_LATEST_SMOKE_DELAY_SECONDS=0

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

require_temp_space
managed_temp="$(make_managed_temp_dir test-run)"
case "$managed_temp" in
	"$CLINE_TERMUX_MANAGER_TEMP_ROOT"/test-run.*) ;;
	*) fail_test "managed temporary directory escaped its configured root" ;;
esac
rm -rf "$managed_temp"

trap_temp="$(make_managed_temp_dir trap-scope)"
if (
	candidate_scope_failure() {
		local scoped_worktree="$WORK_DIR/missing-worktree"
		local scoped_branch="missing-branch"
		local scoped_temp="$trap_temp"
		local scoped_cleanup
		printf -v scoped_cleanup 'cleanup_candidate_run %q %q %q' \
			"$scoped_worktree" "$scoped_branch" "$scoped_temp"
		trap "$scoped_cleanup" EXIT
		return 1
	}
	candidate_scope_failure
); then
	fail_test "candidate cleanup scope test unexpectedly succeeded"
fi
[ ! -e "$trap_temp" ] \
	|| fail_test "candidate cleanup lost its paths after function scope unwound"

available_kib="$(df -Pk "$CLINE_TERMUX_MANAGER_TEMP_ROOT" | awk 'END { print $4 }')"
original_min_temp_mib="$MIN_TEMP_MIB"
MIN_TEMP_MIB="$((available_kib / 1024 + 1))"
if (require_temp_space) 2> "$WORK_DIR/capacity-error"; then
	fail_test "temporary storage preflight accepted an impossible capacity"
fi
grep -q 'release temporary storage needs' "$WORK_DIR/capacity-error" \
	|| fail_test "temporary storage failure did not explain the required capacity"
MIN_TEMP_MIB="$original_min_temp_mib"

latest_calls="$WORK_DIR/latest-calls"
printf '0\n' > "$latest_calls"
gh() {
	local count
	count="$(cat "$latest_calls")"
	count=$((count + 1))
	printf '%s\n' "$count" > "$latest_calls"
	if [ "$count" -lt 2 ]; then
		printf 'v3.0.32-termux.1\n'
	else
		printf 'v3.0.33-termux.1\n'
	fi
}
wait_for_latest_release v3.0.33-termux.1 \
	|| fail_test "Latest convergence did not tolerate propagation delay"
[ "$(cat "$latest_calls")" -eq 2 ] \
	|| fail_test "Latest convergence did not stop after the expected release appeared"
unset -f gh

acceptance_calls="$WORK_DIR/acceptance-calls"
printf '0\n' > "$acceptance_calls"
install_latest_with_acceptance() {
	local count
	count="$(cat "$acceptance_calls")"
	count=$((count + 1))
	printf '%s\n' "$count" > "$acceptance_calls"
	[ "$count" -ge 2 ]
}
retry_latest_acceptance test-host v3.0.33-termux.1 3.0.33 \
	|| fail_test "canonical acceptance did not recover from a transient failure"
[ "$(cat "$acceptance_calls")" -eq 2 ] \
	|| fail_test "canonical acceptance retry count was unexpected"

install_latest_with_acceptance() {
	return 1
}
if retry_latest_acceptance test-host v3.0.33-termux.1 3.0.33; then
	fail_test "canonical acceptance succeeded after every attempt failed"
fi

manager_repo_root="$REPO_ROOT"
promotion_repo="$WORK_DIR/promotion-repo"
promotion_origin="$WORK_DIR/promotion-origin.git"
git init -q --bare "$promotion_origin"
git init -q -b main "$promotion_repo"
git -C "$promotion_repo" config user.name test
git -C "$promotion_repo" config user.email test@example.com
printf 'base\n' > "$promotion_repo/state"
git -C "$promotion_repo" add state
git -C "$promotion_repo" commit -qm base
base_commit="$(git -C "$promotion_repo" rev-parse HEAD)"
printf 'candidate\n' > "$promotion_repo/state"
git -C "$promotion_repo" commit -qam candidate
candidate_commit="$(git -C "$promotion_repo" rev-parse HEAD)"
git -C "$promotion_repo" reset -q --hard "$base_commit"
git -C "$promotion_repo" remote add origin "$promotion_origin"
git -C "$promotion_repo" push -q origin "$base_commit:refs/heads/main"
git -C "$promotion_repo" fetch -q origin main

REPO_ROOT="$promotion_repo"
align_main_for_promotion "$candidate_commit"
[ "$(git -C "$promotion_repo" rev-parse HEAD)" = "$base_commit" ] \
	|| fail_test "normal promotion alignment advanced main too early"
git -C "$promotion_repo" push -q origin "$candidate_commit:refs/heads/main"
git -C "$promotion_repo" fetch -q origin main
align_main_for_promotion "$candidate_commit"
[ "$(git -C "$promotion_repo" rev-parse HEAD)" = "$candidate_commit" ] \
	|| fail_test "resumed promotion did not fast-forward local main"
REPO_ROOT="$manager_repo_root"

echo "[ok] release manager download safeguards"
