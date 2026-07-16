#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/port-manifest.json"
GITHUB_REPO="${CLINE_TERMUX_GITHUB_REPO:-IChouChiang/cline-termux}"
DEFAULT_HOST="$(node -e 'const p=require(process.argv[1]); console.log(p.termux.candidateHost)' "$MANIFEST")"
WORK_ROOT="$SCRIPT_DIR/.work"
TOOLS_ROOT="$SCRIPT_DIR/.tools"
CANDIDATE_ROOT="$SCRIPT_DIR/candidates"
MANAGER_TEMP_ROOT="${CLINE_TERMUX_MANAGER_TEMP_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/cline-termux/release-manager}"
MIN_TEMP_MIB="${CLINE_TERMUX_MIN_TEMP_MIB:-4096}"
CURL_RETRIES="${CLINE_TERMUX_CURL_RETRIES:-5}"
CURL_MAX_TIME="${CLINE_TERMUX_CURL_MAX_TIME:-600}"
LATEST_WAIT_ATTEMPTS="${CLINE_TERMUX_LATEST_WAIT_ATTEMPTS:-20}"
LATEST_WAIT_SECONDS="${CLINE_TERMUX_LATEST_WAIT_SECONDS:-3}"
LATEST_SMOKE_ATTEMPTS="${CLINE_TERMUX_LATEST_SMOKE_ATTEMPTS:-3}"
LATEST_SMOKE_DELAY_SECONDS="${CLINE_TERMUX_LATEST_SMOKE_DELAY_SECONDS:-5}"
CANDIDATE_SMOKE_ATTEMPTS="${CLINE_TERMUX_CANDIDATE_SMOKE_ATTEMPTS:-3}"
CANDIDATE_SMOKE_DELAY_SECONDS="${CLINE_TERMUX_CANDIDATE_SMOKE_DELAY_SECONDS:-5}"

fail() {
	echo "[fail] $*" >&2
	exit 1
}

info() {
	echo "[info] $*"
}

ok() {
	echo "[ok] $*"
}

warn() {
	echo "[warn] $*" >&2
}

usage() {
	cat <<EOF
Usage: bash release/manage.sh COMMAND [options]

Commands:
  inspect CLI_TAG
      Read-only review of one next upstream CLI release.

  candidate CLI_TAG [--revision N] [--host SSH_HOST]
      Merge exactly one release in an isolated worktree, run source and package
      gates, publish a prerelease, and install that exact tag on the test phone.

  promote RELEASE_TAG --confirm-manual-test [--host SSH_HOST]
      Fast-forward main to the tested candidate and promote the unchanged
      prerelease to the stable/latest release.

  status
      Show the maintained version and GitHub release state.

There is intentionally no range mode. Every upstream CLI tag is reviewed,
tested on a physical device, and promoted independently.
EOF
}

json_get() {
	local file="$1"
	local path="$2"
	node -e '
const fs = require("fs")
const value = process.argv[2].split(".").reduce(
  (current, key) => current[key],
  JSON.parse(fs.readFileSync(process.argv[1], "utf8")),
)
if (typeof value === "object") console.log(JSON.stringify(value))
else console.log(value)
' "$file" "$path"
}

git_json_get() {
	local ref="$1"
	local path="$2"
	local field="$3"
	git -C "$REPO_ROOT" show "$ref:$path" | node -e '
const fs = require("fs")
const value = process.argv[1].split(".").reduce(
  (current, key) => current[key],
  JSON.parse(fs.readFileSync(0, "utf8")),
)
if (typeof value === "object") console.log(JSON.stringify(value))
else console.log(value)
' "$field"
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

require_positive_integer() {
	local name="$1"
	local value="$2"
	[[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "$name must be a positive integer"
}

require_nonnegative_integer() {
	local name="$1"
	local value="$2"
	[[ "$value" =~ ^[0-9]+$ ]] || fail "$name must be a non-negative integer"
}

make_managed_temp_dir() {
	local name="$1"
	mkdir -p "$MANAGER_TEMP_ROOT"
	mktemp -d "$MANAGER_TEMP_ROOT/$name.XXXXXX"
}

require_temp_space() {
	require_positive_integer CLINE_TERMUX_MIN_TEMP_MIB "$MIN_TEMP_MIB"
	mkdir -p "$MANAGER_TEMP_ROOT"
	local available_kib required_kib
	available_kib="$(df -Pk "$MANAGER_TEMP_ROOT" | awk 'END { print $4 }')"
	[[ "$available_kib" =~ ^[0-9]+$ ]] \
		|| fail "could not determine free space for $MANAGER_TEMP_ROOT"
	required_kib=$((MIN_TEMP_MIB * 1024))
	[ "$available_kib" -ge "$required_kib" ] || fail \
		"release temporary storage needs ${MIN_TEMP_MIB} MiB free at $MANAGER_TEMP_ROOT; only $((available_kib / 1024)) MiB is available"
}

download_file() {
	local url="$1"
	local output="$2"
	curl --fail --location --silent --show-error \
		--retry "$CURL_RETRIES" --retry-all-errors \
		--connect-timeout 15 --max-time "$CURL_MAX_TIME" \
		--output "$output" "$url"
}

install_release_on_host() {
	local host="$1"
	local installer_url="$2"
	local release_tag="${3:--}"

	ssh "$host" bash -s -- \
		"$installer_url" "$release_tag" "$CURL_RETRIES" "$CURL_MAX_TIME" <<'REMOTE'
set -euo pipefail

installer_url="$1"
release_tag="$2"
curl_retries="$3"
curl_max_time="$4"
installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT

curl --fail --location --silent --show-error \
	--retry "$curl_retries" --retry-all-errors \
	--connect-timeout 15 --max-time "$curl_max_time" \
	--output "$installer" "$installer_url"

install_args=(--skip-pkg-update)
if [ "$release_tag" != - ]; then
	install_args=(--version "$release_tag" "${install_args[@]}")
fi
bash "$installer" "${install_args[@]}"
REMOTE
}

latest_release_tag() {
	gh api "repos/$GITHUB_REPO/releases/latest" --jq .tag_name
}

wait_for_latest_release() {
	local expected_tag="$1"
	local attempt actual_tag
	require_positive_integer CLINE_TERMUX_LATEST_WAIT_ATTEMPTS "$LATEST_WAIT_ATTEMPTS"
	require_nonnegative_integer CLINE_TERMUX_LATEST_WAIT_SECONDS "$LATEST_WAIT_SECONDS"
	for ((attempt = 1; attempt <= LATEST_WAIT_ATTEMPTS; attempt++)); do
		actual_tag="$(latest_release_tag 2>/dev/null || true)"
		if [ "$actual_tag" = "$expected_tag" ]; then
			ok "GitHub Latest resolves to $expected_tag"
			return 0
		fi
		warn "GitHub Latest is ${actual_tag:-unavailable}; waiting for $expected_tag ($attempt/$LATEST_WAIT_ATTEMPTS)"
		[ "$attempt" -eq "$LATEST_WAIT_ATTEMPTS" ] || sleep "$LATEST_WAIT_SECONDS"
	done
	return 1
}

install_latest_with_acceptance() {
	local host="$1"
	local release_tag="$2"
	local cli_version="$3"
	local latest_url="https://github.com/$GITHUB_REPO/releases/latest/download/install-cline-termux.sh"
	local remote_test="~/tmp/test-installed-latest.sh"

	install_release_on_host "$host" "$latest_url"
	scp -q "$SCRIPT_DIR/test-installed-termux.sh" "$host:$remote_test"
	ssh "$host" "bash $remote_test '$release_tag' '$cli_version'"
}

retry_latest_acceptance() {
	local host="$1"
	local release_tag="$2"
	local cli_version="$3"
	local attempt
	require_positive_integer CLINE_TERMUX_LATEST_SMOKE_ATTEMPTS "$LATEST_SMOKE_ATTEMPTS"
	require_nonnegative_integer CLINE_TERMUX_LATEST_SMOKE_DELAY_SECONDS "$LATEST_SMOKE_DELAY_SECONDS"
	for ((attempt = 1; attempt <= LATEST_SMOKE_ATTEMPTS; attempt++)); do
		info "Canonical latest install and acceptance ($attempt/$LATEST_SMOKE_ATTEMPTS)..."
		if install_latest_with_acceptance "$host" "$release_tag" "$cli_version"; then
			return 0
		fi
		warn "canonical latest acceptance attempt $attempt failed"
		[ "$attempt" -eq "$LATEST_SMOKE_ATTEMPTS" ] \
			|| sleep "$((LATEST_SMOKE_DELAY_SECONDS * attempt))"
	done
	return 1
}

run_candidate_acceptance() {
	local host="$1"
	local release_tag="$2"
	local cli_version="$3"
	local remote_test="~/tmp/test-installed-$release_tag.sh"

	scp -q "$SCRIPT_DIR/test-installed-termux.sh" "$host:$remote_test"
	ssh "$host" "bash $remote_test '$release_tag' '$cli_version'"
}

retry_candidate_acceptance() {
	local host="$1"
	local release_tag="$2"
	local cli_version="$3"
	local attempt
	require_positive_integer CLINE_TERMUX_CANDIDATE_SMOKE_ATTEMPTS "$CANDIDATE_SMOKE_ATTEMPTS"
	require_nonnegative_integer CLINE_TERMUX_CANDIDATE_SMOKE_DELAY_SECONDS "$CANDIDATE_SMOKE_DELAY_SECONDS"
	for ((attempt = 1; attempt <= CANDIDATE_SMOKE_ATTEMPTS; attempt++)); do
		info "Published candidate acceptance ($attempt/$CANDIDATE_SMOKE_ATTEMPTS)..."
		if run_candidate_acceptance "$host" "$release_tag" "$cli_version"; then
			return 0
		fi
		warn "published candidate acceptance attempt $attempt failed"
		[ "$attempt" -eq "$CANDIDATE_SMOKE_ATTEMPTS" ] \
			|| sleep "$((CANDIDATE_SMOKE_DELAY_SECONDS * attempt))"
	done
	return 1
}

warn_unexpected_active_workflows() {
	if ! command -v gh >/dev/null 2>&1; then
		warn "cannot audit active GitHub workflows because gh is unavailable"
		return 0
	fi

	local workflows unexpected
	if ! workflows="$(gh workflow list --repo "$GITHUB_REPO" --all --limit 100 --json path,state 2>/dev/null)"; then
		warn "could not audit active GitHub workflows"
		return 0
	fi
	unexpected="$(printf '%s' "$workflows" | node -e '
const fs = require("fs")
const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
const workflows = JSON.parse(fs.readFileSync(0, "utf8"))
const allowed = new Set(manifest.github.allowedActiveWorkflows)
for (const workflow of workflows) {
  if (workflow.state === "active" && !allowed.has(workflow.path)) {
    console.log(workflow.path)
  }
}
' "$MANIFEST")"

	if [ -z "$unexpected" ]; then
		ok "Active GitHub workflows match the downstream allowlist"
		return 0
	fi
	warn "unexpected active GitHub workflows detected:"
	while IFS= read -r workflow; do
		[ -n "$workflow" ] && echo "  $workflow" >&2
	done <<< "$unexpected"
	warn "review and disable unrelated inherited workflows before the next release"
}

close_matching_upstream_issues() {
	local cli_version="$1"
	local release_tag="$2"
	local issues issue_number failed=0

	if ! issues="$(gh issue list \
		--repo "$GITHUB_REPO" \
		--state open \
		--label upstream-update \
		--label cline-sync \
		--limit 100 \
		--json number,title)"; then
		return 1
	fi
	while IFS= read -r issue_number; do
		[ -n "$issue_number" ] || continue
		gh issue close "$issue_number" \
			--repo "$GITHUB_REPO" \
			--comment "Released and validated as [$release_tag](https://github.com/$GITHUB_REPO/releases/tag/$release_tag)." \
			|| failed=1
	done < <(printf '%s' "$issues" | node -e '
const fs = require("fs")
const version = process.argv[1]
const legacySuffix = `, CLI ${version}`
const cliOnlyTitle = `Upstream Cline CLI release available: cli-v${version}`
for (const issue of JSON.parse(fs.readFileSync(0, "utf8"))) {
  if (issue.title === cliOnlyTitle || issue.title.endsWith(legacySuffix)) {
    console.log(issue.number)
  }
}
' "$cli_version")
	return "$failed"
}

require_clean_main() {
	[ "$(git -C "$REPO_ROOT" branch --show-current)" = "main" ] \
		|| fail "check out main before running the release manager"
	[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] \
		|| fail "the main worktree must be clean"
}

validate_cli_tag() {
	[[ "$1" =~ ^cli-v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
		|| fail "expected a stable CLI tag such as cli-v3.0.30"
}

validate_release_tag() {
	[[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-termux\.[0-9]+$ ]] \
		|| fail "expected a Termux release tag such as v3.0.30-termux.1"
}

fetch_upstream_tag() {
	local tag="$1"
	info "Fetching upstream $tag..."
	git -C "$REPO_ROOT" fetch --quiet upstream "refs/tags/$tag:refs/tags/$tag"
}

next_stable_cli_tag() {
	local current="$1"
	git -C "$REPO_ROOT" ls-remote --refs --tags upstream 'refs/tags/cli-v*' \
		| sed -n 's#.*refs/tags/\(cli-v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$#\1#p' \
		| sort -V \
		| awk -v current="$current" '$0 == current { getline; print; exit }'
}

manifest_from_ref() {
	local ref="$1"
	local output="$2"
	git -C "$REPO_ROOT" show "$ref:release/port-manifest.json" > "$output"
}

inspect_release() {
	local target_tag="$1"
	local current_tag current_commit target_commit target_version next_tag
	local current_bun target_bun current_node target_node blocked=0

	validate_cli_tag "$target_tag"
	current_tag="$(json_get "$MANIFEST" upstream.tag)"
	current_commit="$(json_get "$MANIFEST" upstream.commit)"
	fetch_upstream_tag "$target_tag"
	target_commit="$(git -C "$REPO_ROOT" rev-parse "$target_tag^{}")"
	target_version="$(git_json_get "$target_tag" apps/cli/package.json version)"
	next_tag="$(next_stable_cli_tag "$current_tag")"

	echo
	echo "Current upstream: $current_tag ($current_commit)"
	echo "Requested target: $target_tag ($target_commit)"
	echo "CLI version:      $target_version"
	echo "Expected next:    ${next_tag:-none}"
	echo

	[ "$target_tag" = "cli-v$target_version" ] || {
		warn "tag and apps/cli package version disagree"
		blocked=1
	}
	[ "$target_tag" = "$next_tag" ] || {
		warn "$target_tag is not the next stable CLI release after $current_tag"
		blocked=1
	}
	git -C "$REPO_ROOT" merge-base --is-ancestor "$current_commit" "$target_commit" || {
		warn "$target_tag is not descended from the recorded upstream commit"
		blocked=1
	}

	current_bun="$(json_get "$MANIFEST" toolchain.bun)"
	target_bun="$(git_json_get "$target_tag" package.json engines.bun)"
	current_node="$(json_get "$MANIFEST" toolchain.node)"
	target_node="$(git_json_get "$target_tag" package.json engines.node)"
	printf '%-25s %-16s %-16s\n' "Pinned input" "Current" "Target"
	printf '%-25s %-16s %-16s\n' "Bun" "$current_bun" "$target_bun"
	printf '%-25s %-16s %-16s\n' "Node" "$current_node" "$target_node"

	local dependency manifest_key current_value target_value
	for dependency in \
		'@opentui/core:openTui.core' \
		'@opentui/react:openTui.react' \
		'@opentui-ui/dialog:openTui.dialog'; do
		manifest_key="${dependency#*:}"
		dependency="${dependency%%:*}"
		current_value="$(json_get "$MANIFEST" "$manifest_key")"
		target_value="$(git_json_get "$target_tag" apps/cli/package.json "dependencies.$dependency")"
		target_value="${target_value#^}"
		printf '%-25s %-16s %-16s\n' "$dependency" "$current_value" "$target_value"
		if [ "$current_value" != "$target_value" ]; then
			warn "$dependency changed and requires an explicit port review"
			blocked=1
		fi
	done
	if [ "$current_bun" != "$target_bun" ]; then
		warn "the upstream Bun pin changed; review and rebuild bun-android-ffi first"
		blocked=1
	fi
	if [ "$current_node" != "$target_node" ]; then
		warn "the upstream Node requirement changed"
		blocked=1
	fi

	local downstream_paths upstream_paths overlap_paths merge_output merge_status
	downstream_paths="$(mktemp)"
	upstream_paths="$(mktemp)"
	overlap_paths="$(mktemp)"
	merge_output="$(mktemp)"
	trap 'rm -f "$downstream_paths" "$upstream_paths" "$overlap_paths" "$merge_output"' RETURN
	git -C "$REPO_ROOT" diff --name-only "$current_commit..HEAD" | sort -u > "$downstream_paths"
	git -C "$REPO_ROOT" diff --name-only "$current_commit..$target_commit" | sort -u > "$upstream_paths"
	comm -12 "$downstream_paths" "$upstream_paths" > "$overlap_paths"

	echo
	echo "Upstream CLI diff:"
	git -C "$REPO_ROOT" diff --stat "$current_commit..$target_commit" -- apps/cli
	echo
	echo "Paths changed both downstream and upstream:"
	if [ -s "$overlap_paths" ]; then
		sed 's/^/  /' "$overlap_paths"
	else
		echo "  none"
	fi

	set +e
	git -C "$REPO_ROOT" merge-tree --write-tree HEAD "$target_commit" > "$merge_output" 2>&1
	merge_status=$?
	set -e
	local conflict_paths allowed_path conflict unexpected=0
	conflict_paths="$(awk 'NF == 4 && $3 ~ /^[123]$/ { print $4 }' "$merge_output" | sort -u)"
	echo
	echo "Simulated merge conflicts:"
	if [ -n "$conflict_paths" ]; then
		while IFS= read -r conflict; do
			[ -n "$conflict" ] || continue
			echo "  $conflict"
			local allowed=false
			while IFS= read -r allowed_path; do
				[ "$conflict" = "$allowed_path" ] && allowed=true
			done < <(node -e 'const p=require(process.argv[1]); console.log(p.merge.allowedConflictPaths.join("\n"))' "$MANIFEST")
			[ "$allowed" = true ] || unexpected=1
		done <<< "$conflict_paths"
	else
		echo "  none"
		[ "$merge_status" -eq 0 ] || unexpected=1
	fi
	if [ "$unexpected" -ne 0 ]; then
		warn "the simulated merge has an unexpected conflict"
		blocked=1
	fi

	trap - RETURN
	rm -f "$downstream_paths" "$upstream_paths" "$overlap_paths" "$merge_output"
	if [ "$blocked" -ne 0 ]; then
		fail "inspection blocked automated candidate preparation"
	fi
	ok "$target_tag is ready for one-version candidate preparation"
	warn_unexpected_active_workflows
}

ensure_pinned_bun() {
	local version="$1"
	local machine archive_name extracted_name url tool_dir bun_path zip_path
	local sums_path expected_checksum actual_checksum
	machine="$(uname -m)"
	case "$machine" in
		x86_64)
			archive_name="bun-linux-x64.zip"
			extracted_name="bun-linux-x64"
			;;
		aarch64|arm64)
			archive_name="bun-linux-aarch64.zip"
			extracted_name="bun-linux-aarch64"
			;;
		*) fail "unsupported build host architecture: $machine" ;;
	esac
	tool_dir="$TOOLS_ROOT/bun-$version"
	bun_path="$tool_dir/$extracted_name/bun"
	if [ ! -x "$bun_path" ] || [ "$($bun_path --version 2>/dev/null || true)" != "$version" ]; then
		require_command curl
		require_command unzip
		mkdir -p "$tool_dir"
		zip_path="$tool_dir/$archive_name"
		url="https://github.com/oven-sh/bun/releases/download/bun-v$version/$archive_name"
		info "Downloading pinned Bun $version..." >&2
		curl -fL --retry 3 -o "$zip_path" "$url"
		sums_path="$tool_dir/SHASUMS256.txt"
		curl -fL --retry 3 -o "$sums_path" \
			"https://github.com/oven-sh/bun/releases/download/bun-v$version/SHASUMS256.txt"
		expected_checksum="$(awk -v name="$archive_name" '$2 == name { print $1 }' "$sums_path")"
		[ -n "$expected_checksum" ] || fail "Bun checksum list does not contain $archive_name"
		actual_checksum="$(sha256sum "$zip_path" | awk '{ print $1 }')"
		[ "$actual_checksum" = "$expected_checksum" ] || fail "Bun archive checksum mismatch"
		unzip -oq "$zip_path" -d "$tool_dir"
		chmod +x "$bun_path"
		rm -f "$zip_path"
	fi
	[ "$($bun_path --version)" = "$version" ] || fail "could not provision Bun $version"
	printf '%s\n' "$bun_path"
}

ensure_gitleaks() {
	local version="$1"
	local machine archive_name tool_dir tool_path checksum_file expected actual
	machine="$(uname -m)"
	case "$machine" in
		x86_64) archive_name="gitleaks_${version}_linux_x64.tar.gz" ;;
		aarch64|arm64) archive_name="gitleaks_${version}_linux_arm64.tar.gz" ;;
		*) fail "unsupported gitleaks host architecture: $machine" ;;
	esac
	tool_dir="$TOOLS_ROOT/gitleaks-$version"
	tool_path="$tool_dir/gitleaks"
	if [ ! -x "$tool_path" ] || [ "$($tool_path version 2>/dev/null || true)" != "$version" ]; then
		mkdir -p "$tool_dir"
		info "Downloading gitleaks $version for the repository commit hook..." >&2
		gh release download "v$version" \
			--repo gitleaks/gitleaks \
			--pattern "$archive_name" \
			--pattern "gitleaks_${version}_checksums.txt" \
			--dir "$tool_dir" \
			--clobber
		checksum_file="$tool_dir/gitleaks_${version}_checksums.txt"
		expected="$(awk -v name="$archive_name" '$2 == name { print $1 }' "$checksum_file")"
		[ -n "$expected" ] || fail "gitleaks checksum list does not contain $archive_name"
		actual="$(sha256sum "$tool_dir/$archive_name" | awk '{ print $1 }')"
		[ "$actual" = "$expected" ] || fail "gitleaks archive checksum mismatch"
		tar xzf "$tool_dir/$archive_name" -C "$tool_dir" gitleaks
		chmod +x "$tool_path"
	fi
	[ "$($tool_path version)" = "$version" ] || fail "could not provision gitleaks $version"
	printf '%s\n' "$tool_path"
}

ensure_patchelf() {
	local version="$1"
	local machine archive_name expected_checksum tool_dir tool_path actual_checksum
	machine="$(uname -m)"
	case "$machine" in
		x86_64)
			archive_name="patchelf-$version-x86_64.tar.gz"
			expected_checksum="$(json_get "$MANIFEST" toolchain.patchelf.linuxX64Sha256)"
			;;
		aarch64|arm64)
			archive_name="patchelf-$version-aarch64.tar.gz"
			expected_checksum="$(json_get "$MANIFEST" toolchain.patchelf.linuxArm64Sha256)"
			;;
		*) fail "unsupported patchelf host architecture: $machine" ;;
	esac
	tool_dir="$TOOLS_ROOT/patchelf-$version"
	tool_path="$tool_dir/extracted/bin/patchelf"
	if [ ! -x "$tool_path" ] \
		|| [ "$($tool_path --version 2>/dev/null | awk '{ print $2 }')" != "$version" ]; then
		mkdir -p "$tool_dir/extracted"
		info "Downloading patchelf $version for OpenTUI Android compatibility..." >&2
		gh release download "$version" \
			--repo NixOS/patchelf \
			--pattern "$archive_name" \
			--dir "$tool_dir" \
			--clobber
		actual_checksum="$(sha256sum "$tool_dir/$archive_name" | awk '{ print $1 }')"
		[ "$actual_checksum" = "$expected_checksum" ] || fail "patchelf archive checksum mismatch"
		rm -rf "$tool_dir/extracted"
		mkdir -p "$tool_dir/extracted"
		tar xzf "$tool_dir/$archive_name" -C "$tool_dir/extracted"
		chmod +x "$tool_path"
	fi
	[ "$($tool_path --version | awk '{ print $2 }')" = "$version" ] \
		|| fail "could not provision patchelf $version"
	printf '%s\n' "$tool_path"
}

run_gate() {
	local log_dir="$1"
	local name="$2"
	shift 2
	info "Gate: $name"
	"$@" 2>&1 | tee "$log_dir/$name.log"
}

cleanup_managed_temp() {
	rm -rf -- "$1"
}

cleanup_candidate_run() {
	local worktree="$1"
	local branch="$2"
	local candidate_temp="$3"
	git -C "$REPO_ROOT" worktree remove --force "$worktree" >/dev/null 2>&1 || true
	git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
	cleanup_managed_temp "$candidate_temp"
	git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
}

install_worktree_dependencies() {
	local worktree="$1"
	local bun_bin="$2"
	local log_file="$3"
	local attempt
	for attempt in 1 2 3; do
		info "Installing locked dependencies (attempt $attempt/3)..."
		if (
			cd "$worktree"
			timeout --foreground 300 "$bun_bin" install \
				--ignore-scripts \
				--network-concurrency 8
		) 2>&1 | tee -a "$log_file"; then
			(
				cd "$worktree"
				"$bun_bin" install --frozen-lockfile --ignore-scripts
			)
			return 0
		fi
		warn "dependency install attempt $attempt failed; retrying partial downloads"
		sleep "$((attempt * 2))"
	done
	fail "dependency installation failed after three bounded attempts"
}

resolve_expected_conflicts() {
	local worktree="$1"
	local target_commit="$2"
	local conflicts path allowed
	conflicts="$(git -C "$worktree" diff --name-only --diff-filter=U)"
	for path in $conflicts; do
		allowed=false
		while IFS= read -r allowed_path; do
			[ "$path" = "$allowed_path" ] && allowed=true
		done < <(node -e 'const p=require(process.argv[1]); console.log(p.merge.allowedConflictPaths.join("\n"))' "$MANIFEST")
		[ "$allowed" = true ] || fail "unexpected merge conflict: $path"
		case "$path" in
			README.md)
				git -C "$worktree" restore --source=HEAD --staged --worktree "$path"
				;;
			bun.lock|package.json)
				git -C "$worktree" restore --source="$target_commit" --staged --worktree "$path"
				;;
			*) fail "no resolver is defined for allowed conflict: $path" ;;
		esac
	done
}

phone_local_bundle_test() {
	local host="$1"
	local candidate_dir="$2"
	local release_tag="$3"
	local release_name="cline-termux-aarch64-$release_tag"
	local remote_dir="~/tmp/cline-termux-candidate-$release_tag"
	local bun_asset bun_checksum
	bun_asset="$SCRIPT_DIR/dist/$(json_get "$MANIFEST" bunFfi.asset)"
	bun_checksum="$bun_asset.sha256"

	info "Testing the unpublished package in an isolated sandbox on $host..."
	ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" "rm -rf $remote_dir && mkdir -p $remote_dir"
	scp -q \
		"$candidate_dir/$release_name.tar.gz" \
		"$candidate_dir/$release_name.tar.gz.sha256" \
		"$SCRIPT_DIR/test-termux-install.sh" \
		"$host:$remote_dir/"
	local remote_bun_option=""
	if [ -f "$bun_asset" ]; then
		scp -q "$bun_asset" "$host:$remote_dir/"
		remote_bun_option="--bun-tarball $remote_dir/$(basename "$bun_asset")"
		if [ -f "$bun_checksum" ]; then
			scp -q "$bun_checksum" "$host:$remote_dir/"
		fi
	fi
	ssh "$host" "bash $remote_dir/test-termux-install.sh --from-tarball $remote_dir/$release_name.tar.gz $remote_bun_option"
	ok "Unpublished package passed the isolated Termux install test"
}

install_published_candidate() {
	local host="$1"
	local release_tag="$2"
	local cli_version="$3"
	local installer_url="https://github.com/$GITHUB_REPO/releases/download/$release_tag/install-cline-termux.sh"

	info "Installing the exact published prerelease on $host..."
	install_release_on_host "$host" "$installer_url" "$release_tag"
	retry_candidate_acceptance "$host" "$release_tag" "$cli_version"
	ok "Published candidate passed automated S25 Ultra acceptance"
}

candidate_release() {
	local target_tag="$1"
	shift
	local revision=1 host="$DEFAULT_HOST"
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--revision)
				[ -n "${2:-}" ] || fail "--revision requires a value"
				revision="${2:-}"
				shift 2
				;;
			--host)
				[ -n "${2:-}" ] || fail "--host requires a value"
				host="${2:-}"
				shift 2
				;;
			*) fail "unknown candidate option: $1" ;;
		esac
	done
	case "$revision" in
		''|*[!0-9]*) fail "--revision must be a positive integer" ;;
	esac
	[ "$revision" -gt 0 ] || fail "--revision must be a positive integer"
	for required in cmp curl df gh scp sha256sum ssh timeout unzip; do
		require_command "$required"
	done
	require_temp_space

	require_clean_main
	git -C "$REPO_ROOT" fetch --quiet origin main
	[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$(git -C "$REPO_ROOT" rev-parse origin/main)" ] \
		|| fail "local main must exactly match origin/main before candidate preparation"
	inspect_release "$target_tag"

	local target_commit cli_version release_tag release_name branch worktree candidate_dir
	local bun_version bun_bin gitleaks_version gitleaks_bin patchelf_version patchelf_bin
	local log_dir merge_status candidate_commit notes_file candidate_temp cleanup_trap
	target_commit="$(git -C "$REPO_ROOT" rev-parse "$target_tag^{}")"
	cli_version="$(git_json_get "$target_tag" apps/cli/package.json version)"
	release_tag="v$cli_version-termux.$revision"
	release_name="cline-termux-aarch64-$release_tag"
	validate_release_tag "$release_tag"
	git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$release_tag" >/dev/null \
		&& fail "tag already exists: $release_tag; use the next downstream revision"
	gh release view "$release_tag" --repo "$GITHUB_REPO" >/dev/null 2>&1 \
		&& fail "GitHub release already exists: $release_tag"

	bun_version="$(json_get "$MANIFEST" toolchain.bun)"
	bun_bin="$(ensure_pinned_bun "$bun_version")"
	gitleaks_version="$(json_get "$MANIFEST" toolchain.gitleaks)"
	gitleaks_bin="$(ensure_gitleaks "$gitleaks_version")"
	patchelf_version="$(json_get "$MANIFEST" toolchain.patchelf.version)"
	patchelf_bin="$(ensure_patchelf "$patchelf_version")"
	branch="termux-candidate-${release_tag#v}"
	worktree="$WORK_ROOT/$release_tag"
	candidate_dir="$CANDIDATE_ROOT/$release_tag"
	log_dir="$candidate_dir/logs"
	mkdir -p "$WORK_ROOT" "$log_dir"
	candidate_temp="$(make_managed_temp_dir "candidate-${release_tag#v}")"
	printf -v cleanup_trap 'cleanup_candidate_run %q %q %q' \
		"$worktree" "$branch" "$candidate_temp"
	trap "$cleanup_trap" EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM

	if git -C "$REPO_ROOT" worktree list --porcelain \
		| grep -Fxq "worktree $worktree"; then
		git -C "$REPO_ROOT" worktree remove --force "$worktree"
	fi
	git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
	rm -rf "$worktree"
	git -C "$REPO_ROOT" worktree prune
	git -C "$REPO_ROOT" worktree add -q -b "$branch" "$worktree" main

	info "Merging $target_tag in isolated worktree..."
	set +e
	git -C "$worktree" merge --no-ff --no-commit "$target_commit"
	merge_status=$?
	set -e
	if [ "$merge_status" -ne 0 ]; then
		resolve_expected_conflicts "$worktree" "$target_commit"
	fi
	[ -f "$worktree/.git/MERGE_HEAD" ] || [ -f "$(git -C "$worktree" rev-parse --git-path MERGE_HEAD)" ] \
		|| fail "the upstream merge did not leave a merge candidate"

	node "$worktree/release/port-metadata.mjs" update \
		"$target_tag" "$target_commit" "$release_tag"
	TMPDIR="$candidate_temp" install_worktree_dependencies \
		"$worktree" "$bun_bin" "$log_dir/dependency-install.log"
	git -C "$worktree" add -A
	[ -z "$(git -C "$worktree" diff --name-only --diff-filter=U)" ] \
		|| fail "unresolved merge conflicts remain"

	run_gate "$log_dir" release-manager \
		env TMPDIR="$candidate_temp" bash "$worktree/release/test-manager-downloads.sh"
	run_gate "$log_dir" build-sdk \
		env TMPDIR="$candidate_temp" bash -lc "cd '$worktree' && '$bun_bin' run build:sdk"
	run_gate "$log_dir" cli-unit \
		env TMPDIR="$candidate_temp" bash -lc "cd '$worktree' && '$bun_bin' -F @cline/cli test:unit"
	run_gate "$log_dir" cli-typecheck \
		env TMPDIR="$candidate_temp" bash -lc "cd '$worktree' && '$bun_bin' -F @cline/cli typecheck"
	run_gate "$log_dir" cli-build \
		env TMPDIR="$candidate_temp" bash -lc "cd '$worktree' && '$bun_bin' -F @cline/cli build"
	run_gate "$log_dir" cli-tui \
		env TMPDIR="$candidate_temp" bash -lc "cd '$worktree' && '$bun_bin' -F @cline/cli test:e2e:cli:tui"

	PATH="$(dirname "$gitleaks_bin"):$PATH" \
		git -C "$worktree" commit -m "chore(termux): update to cli v$cli_version"
	candidate_commit="$(git -C "$worktree" rev-parse HEAD)"
	CLINE_TERMUX_DIST_DIR="$candidate_dir" \
		BUN_BIN="$bun_bin" \
		PATCHELF_BIN="$patchelf_bin" \
		TMPDIR="$candidate_temp" \
		bash "$worktree/release/build-termux-release.sh" \
			--release "$release_tag" --skip-build
	cp "$worktree/release/install-cline-termux.sh" "$candidate_dir/install-cline-termux.sh"
	cp "$worktree/release/test-installed-termux.sh" "$candidate_dir/test-installed-termux.sh"
	phone_local_bundle_test "$host" "$candidate_dir" "$release_tag"

	info "Publishing $release_tag as a prerelease..."
	git -C "$worktree" tag -a "$release_tag" -m "Cline Termux $release_tag" "$candidate_commit"
	git -C "$worktree" push origin "refs/tags/$release_tag"
	notes_file="$candidate_dir/release-notes.md"
	printf '%s\n' \
		"Native Termux port of upstream Cline CLI $cli_version for Android aarch64." \
		"" \
		"This is a release candidate pending physical touch, IME, dialog, and real-conversation testing on the S25 Ultra." \
		"" \
		"Upstream: https://github.com/cline/cline/releases/tag/$target_tag" \
		"Source commit: $candidate_commit" \
		> "$notes_file"
	gh release create "$release_tag" \
		"$candidate_dir/$release_name.tar.gz" \
		"$candidate_dir/$release_name.tar.gz.sha256" \
		"$candidate_dir/install-cline-termux.sh" \
		--repo "$GITHUB_REPO" \
		--verify-tag \
		--prerelease \
		--latest=false \
		--title "Cline Termux $release_tag" \
		--notes-file "$notes_file"
	install_published_candidate "$host" "$release_tag" "$cli_version"

	cleanup_candidate_run "$worktree" "$branch" "$candidate_temp"
	trap - EXIT INT TERM
	echo
	ok "$release_tag is installed on $host and ready for manual testing"
	echo "Please test on the S25 Ultra:"
	echo "  1. Tap the input box and confirm the IME opens."
	echo "  2. Finger-scroll the transcript."
	echo "  3. Open /settings, /model, and /history with the IME visible."
	echo "  4. Send one real prompt and complete a short conversation."
	echo
	echo "After that passes:"
	echo "  bash release/manage.sh promote $release_tag --confirm-manual-test"
}

align_main_for_promotion() {
	local tag_commit="$1"
	local head_commit origin_commit
	head_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
	origin_commit="$(git -C "$REPO_ROOT" rev-parse origin/main)"

	if [ "$head_commit" != "$origin_commit" ] \
		&& [ "$head_commit" != "$tag_commit" ] \
		&& [ "$origin_commit" != "$tag_commit" ]; then
		fail "local main and origin/main diverged outside the promotion candidate"
	fi
	git -C "$REPO_ROOT" merge-base --is-ancestor "$head_commit" "$tag_commit" \
		|| fail "local main is not an ancestor of the promotion candidate"
	git -C "$REPO_ROOT" merge-base --is-ancestor "$origin_commit" "$tag_commit" \
		|| fail "origin/main is not an ancestor of the promotion candidate"

	if [ "$origin_commit" = "$tag_commit" ] && [ "$head_commit" != "$tag_commit" ]; then
		info "Resuming promotion by fast-forwarding local main to origin/main..."
		git -C "$REPO_ROOT" merge --ff-only origin/main
	fi
}

previous_candidate_release() {
	local tag_commit="$1"
	local parent_commit
	parent_commit="$(git -C "$REPO_ROOT" rev-parse "$tag_commit^1" 2>/dev/null)" \
		|| return 1
	git -C "$REPO_ROOT" show "$parent_commit:release/port-manifest.json" 2>/dev/null \
		| node -e '
const fs = require("fs")
const manifest = JSON.parse(fs.readFileSync(0, "utf8"))
if (!manifest.termux?.releaseTag) process.exit(1)
console.log(manifest.termux.releaseTag)
'
}

restore_failed_promotion() {
	local release_tag="$1"
	local rollback_release="$2"
	local restore_prerelease="$3"

	if [ -n "$rollback_release" ] && [ "$rollback_release" != "$release_tag" ]; then
		warn "restoring $rollback_release as GitHub Latest"
		gh release edit "$rollback_release" --repo "$GITHUB_REPO" --latest \
			|| warn "could not restore $rollback_release as Latest"
	fi
	if [ "$restore_prerelease" = true ]; then
		warn "restoring $release_tag to prerelease status"
		gh release edit "$release_tag" --repo "$GITHUB_REPO" --prerelease \
			|| warn "could not restore $release_tag to prerelease status"
	fi
}

promote_release() {
	local release_tag="$1"
	shift
	local host="$DEFAULT_HOST" confirmed=false
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--host)
				[ -n "${2:-}" ] || fail "--host requires a value"
				host="${2:-}"
				shift 2
				;;
			--confirm-manual-test)
				confirmed=true
				shift
				;;
			*) fail "unknown promote option: $1" ;;
		esac
	done
	validate_release_tag "$release_tag"
	[ "$confirmed" = true ] || fail "promotion requires --confirm-manual-test"
	for required in cmp curl df gh scp sha256sum ssh; do
		require_command "$required"
	done
	require_clean_main
	require_temp_space
	git -C "$REPO_ROOT" fetch --quiet origin main "refs/tags/$release_tag:refs/tags/$release_tag"

	local release_json prerelease draft tag_commit temp_manifest cli_version
	local promotion_temp asset_dir asset_base archive_name cleanup_trap
	local previous_latest fallback_release rollback_release changed_release_state=false
	release_json="$(gh release view "$release_tag" --repo "$GITHUB_REPO" --json isDraft,isPrerelease)"
	prerelease="$(printf '%s' "$release_json" | node -e 'const fs=require("fs"); console.log(JSON.parse(fs.readFileSync(0,"utf8")).isPrerelease)')"
	draft="$(printf '%s' "$release_json" | node -e 'const fs=require("fs"); console.log(JSON.parse(fs.readFileSync(0,"utf8")).isDraft)')"
	[ "$draft" = false ] || fail "$release_tag is still a draft"
	case "$prerelease" in
		true|false) ;;
		*) fail "could not determine release state for $release_tag" ;;
	esac
	tag_commit="$(git -C "$REPO_ROOT" rev-parse "$release_tag^{}")"
	align_main_for_promotion "$tag_commit"

	promotion_temp="$(make_managed_temp_dir "promote-${release_tag#v}")"
	printf -v cleanup_trap 'cleanup_managed_temp %q' "$promotion_temp"
	trap "$cleanup_trap" EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	local TMPDIR="$promotion_temp"
	export TMPDIR
	temp_manifest="$(mktemp)"
	manifest_from_ref "$release_tag" "$temp_manifest"
	cli_version="$(json_get "$temp_manifest" upstream.cliVersion)"
	[ "$(json_get "$temp_manifest" termux.releaseTag)" = "$release_tag" ] \
		|| fail "candidate manifest does not match $release_tag"
	rm -f "$temp_manifest"

	asset_dir="$(mktemp -d)"
	(
		asset_base="https://github.com/$GITHUB_REPO/releases/download/$release_tag"
		archive_name="cline-termux-aarch64-$release_tag.tar.gz"
		info "Downloading published candidate assets for verification..."
		download_file "$asset_base/$archive_name" "$asset_dir/$archive_name"
		download_file "$asset_base/$archive_name.sha256" "$asset_dir/$archive_name.sha256"
		download_file "$asset_base/install-cline-termux.sh" "$asset_dir/install-cline-termux.sh"
		git -C "$REPO_ROOT" show "$release_tag:release/install-cline-termux.sh" \
			> "$asset_dir/tagged-install-cline-termux.sh"
		cmp -s \
			"$asset_dir/install-cline-termux.sh" \
			"$asset_dir/tagged-install-cline-termux.sh" \
			|| fail "published installer does not match the tagged source"
		cd "$asset_dir"
		sha256sum -c "$archive_name.sha256"
	)
	ok "Published candidate assets are intact"

	previous_latest="$(latest_release_tag)" \
		|| fail "could not determine the current GitHub Latest release"
	fallback_release="$(previous_candidate_release "$tag_commit" || true)"
	rollback_release="$previous_latest"
	if [ "$rollback_release" = "$release_tag" ]; then
		rollback_release="$fallback_release"
	fi

	if [ "$(git -C "$REPO_ROOT" rev-parse HEAD)" != "$tag_commit" ]; then
		git -C "$REPO_ROOT" merge --ff-only "$tag_commit"
	fi
	if [ "$(git -C "$REPO_ROOT" rev-parse origin/main)" != "$tag_commit" ]; then
		git -C "$REPO_ROOT" push origin main
	fi

	if [ "$prerelease" = true ] || [ "$previous_latest" != "$release_tag" ]; then
		changed_release_state=true
		if ! gh release edit "$release_tag" --repo "$GITHUB_REPO" --prerelease=false --latest; then
			restore_failed_promotion "$release_tag" "$rollback_release" "$prerelease"
			fail "could not publish $release_tag as stable/latest; main remains resumable at the candidate"
		fi
	else
		info "$release_tag is already stable and GitHub Latest; verifying it again"
	fi

	if ! wait_for_latest_release "$release_tag" \
		|| ! retry_latest_acceptance "$host" "$release_tag" "$cli_version"; then
		if [ "$changed_release_state" = true ]; then
			restore_failed_promotion "$release_tag" "$rollback_release" "$prerelease"
		else
			warn "$release_tag was already stable/latest, so its public state was left unchanged"
		fi
		fail "promotion acceptance failed; main remains at the candidate and this command can be rerun safely"
	fi

	cleanup_managed_temp "$promotion_temp"
	trap - EXIT INT TERM
	if ! close_matching_upstream_issues "$cli_version" "$release_tag"; then
		warn "release succeeded, but its upstream-update issue could not be closed"
	fi
	warn_unexpected_active_workflows
	ok "$release_tag is stable, latest, and installed from the canonical latest URL"
	echo "The final release check is now the clean install/update on termux_wifi_s7."
}

show_status() {
	require_command gh
	echo "Main commit:       $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
	echo "Upstream CLI:      $(json_get "$MANIFEST" upstream.tag)"
	echo "Termux release:    $(json_get "$MANIFEST" termux.releaseTag)"
	echo "Pinned build Bun:  $(json_get "$MANIFEST" toolchain.bun)"
	echo "Bun FFI runtime:   $(json_get "$MANIFEST" bunFfi.version)"
	echo
	gh release list --repo "$GITHUB_REPO" --limit 8
	echo
	warn_unexpected_active_workflows
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
	return 0
fi

require_command git
require_command node

case "${1:-}" in
	inspect)
		[ "$#" -eq 2 ] || fail "inspect requires exactly one CLI tag"
		require_clean_main
		inspect_release "$2"
		;;
	candidate)
		[ "$#" -ge 2 ] || fail "candidate requires a CLI tag"
		target="$2"
		shift 2
		candidate_release "$target" "$@"
		;;
	promote)
		[ "$#" -ge 2 ] || fail "promote requires a Termux release tag"
		release="$2"
		shift 2
		promote_release "$release" "$@"
		;;
	status)
		[ "$#" -eq 1 ] || fail "status takes no arguments"
		show_status
		;;
	-h|--help|help|'')
		usage
		;;
	*)
		usage >&2
		fail "unknown command: $1"
		;;
esac
