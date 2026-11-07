#!/usr/bin/env bash
# Tests for the Assisted-by Standard reference implementation.
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
hook=$root/hooks/assisted-by-commit-msg
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo=$tmp/repo
mkdir -p "$repo"
git -C "$repo" init -q

pass=0
fail=0
status=0
out=

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
not_ok() {
	fail=$((fail + 1))
	printf 'FAIL %s\n' "$1"
	[[ -n ${2:-} ]] && printf '     %s\n' "$2"
}

eq() { # label actual expected
	if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1" "expected $(printf '%q' "$3"), got $(printf '%q' "$2")"; fi
}

msgfile() { # content -> path
	printf '%s' "$1" >"$tmp/msg"
	printf '%s' "$tmp/msg"
}

run_hook() { # [VAR=value ...] message-file
	local -a envs=()
	while [[ $# -gt 0 && $1 == *=* ]]; do
		envs+=("$1")
		shift
	done
	out=$(cd "$repo" && env -u AGENT_NAME -u AGENT_VERSION -u AGENT_MODEL_PROVIDER_SLUG \
		-u AGENT_MODEL_SLUG -u ASSISTED_BY "${envs[@]}" "$hook" "$1" 2>&1)
	status=$?
}

full_env=(AGENT_NAME=omp AGENT_VERSION=18.18.0 AGENT_MODEL_PROVIDER_SLUG=opencode-go AGENT_MODEL_SLUG=deepseek-v4.1-flash)
expected_trailer='Assisted-by: omp 18.18.0 (opencode-go/deepseek-v4.1-flash)'

# --- human commit ---------------------------------------------------------
m=$(msgfile $'feat: human\n')
run_hook "$m"
eq 'no environment leaves the message alone' "$(cat "$m")" 'feat: human'
eq 'no environment exits 0' "$status" 0

# --- full environment -----------------------------------------------------
m=$(msgfile $'feat: agent\n')
run_hook "${full_env[@]}" "$m"
eq 'full environment exits 0' "$status" 0
eq 'trailer is appended after a blank line' "$(cat "$m")" $'feat: agent\n\nAssisted-by: omp 18.18.0 (opencode-go/deepseek-v4.1-flash)'

# --- partial environment --------------------------------------------------
m=$(msgfile $'feat: partial\n')
run_hook AGENT_NAME=omp "$m"
eq 'partial environment fails' "$status" 1
eq 'partial environment leaves the message alone' "$(cat "$m")" 'feat: partial'
[[ $out == *'missing: AGENT_VERSION AGENT_MODEL_PROVIDER_SLUG AGENT_MODEL_SLUG'* ]] &&
	ok 'partial error names the missing variables' || not_ok 'partial error names the missing variables'

# --- invalid values -------------------------------------------------------
m=$(msgfile $'feat: invalid\n')
run_hook AGENT_NAME=OMP AGENT_VERSION=1.0.0 AGENT_MODEL_PROVIDER_SLUG=opencode-go AGENT_MODEL_SLUG=deepseek-v4.1-flash "$m"
eq 'uppercase agent name fails' "$status" 1
eq 'invalid agent name leaves the message alone' "$(cat "$m")" 'feat: invalid'

run_hook AGENT_NAME=omp AGENT_VERSION=1.0.0 AGENT_MODEL_PROVIDER_SLUG=opencode_go AGENT_MODEL_SLUG=deepseek-v4.1-flash "$m"
eq 'underscore provider fails' "$status" 1

run_hook AGENT_NAME=omp AGENT_VERSION=$'1.0\nInjected: yes' AGENT_MODEL_PROVIDER_SLUG=opencode-go AGENT_MODEL_SLUG=deepseek-v4.1-flash "$m"
eq 'newline in version fails' "$status" 1

# --- allowed grammar ------------------------------------------------------
m=$(msgfile $'feat: grammar\n')
run_hook AGENT_NAME=claude-code AGENT_VERSION=2.0.14-rc.1+build AGENT_MODEL_PROVIDER_SLUG=anthropic AGENT_MODEL_SLUG=claude-sonnet-4.6 "$m"
eq 'dash-case with dotted model and rich version is accepted' "$status" 0
eq 'grammar trailer is exact' "$(cat "$m")" $'feat: grammar\n\nAssisted-by: claude-code 2.0.14-rc.1+build (anthropic/claude-sonnet-4.6)'

# --- existing trailer -----------------------------------------------------
m=$(msgfile $'feat: existing\n\nAssisted-by: prior 1.0.0 (p/m)\n')
run_hook "${full_env[@]}" "$m"
eq 'existing trailer exits 0' "$status" 0
eq 'existing trailer is untouched' "$(cat "$m")" $'feat: existing\n\nAssisted-by: prior 1.0.0 (p/m)'
eq 'existing trailer is not duplicated' "$(grep -ci '^assisted-by:' "$m")" 1

# --- idempotency ----------------------------------------------------------
m=$(msgfile $'feat: twice\n')
run_hook "${full_env[@]}" "$m"
run_hook "${full_env[@]}" "$m"
eq 'two runs produce one trailer' "$(grep -ci '^assisted-by:' "$m")" 1

# --- excluded operations --------------------------------------------------
m=$(msgfile $'feat: merge\n')
touch "$repo/.git/MERGE_HEAD"
run_hook "${full_env[@]}" "$m"
rm -f "$repo/.git/MERGE_HEAD"
eq 'merge commit is skipped' "$(cat "$m")" 'feat: merge'

m=$(msgfile $'feat: opt-out\n')
run_hook ASSISTED_BY=0 "${full_env[@]}" "$m"
eq 'ASSISTED_BY=0 is skipped' "$(cat "$m")" 'feat: opt-out'

# --- hk integration -------------------------------------------------------
if command -v hk >/dev/null 2>&1; then
	hkrepo=$tmp/hk
	mkdir -p "$hkrepo"
	git -C "$hkrepo" init -q
	git -C "$hkrepo" config user.name tester
	git -C "$hkrepo" config user.email tester@example.com
	cp "$root/hk.pkl" "$hkrepo/"
	cp -R "$root/hooks" "$hkrepo/"
	if (cd "$hkrepo" && hk install >/dev/null 2>&1); then
		echo one >"$hkrepo/one.txt"
		git -C "$hkrepo" add one.txt
		(cd "$hkrepo" && env "${full_env[@]}" git commit -q -m 'feat: via hk' >/dev/null 2>&1)
		eq 'hk hook appends the trailer' "$(git -C "$hkrepo" log -1 --format=%B)" $'feat: via hk\n\nAssisted-by: omp 18.18.0 (opencode-go/deepseek-v4.1-flash)'

		before=$(git -C "$hkrepo" rev-parse HEAD)
		echo two >"$hkrepo/two.txt"
		git -C "$hkrepo" add two.txt
		(cd "$hkrepo" && env AGENT_NAME=omp git commit -q -m 'feat: blocked' >/dev/null 2>&1)
		eq 'hk hook blocks a partial environment' "$?" 1
		eq 'blocked commit did not land' "$(git -C "$hkrepo" rev-parse HEAD)" "$before"
	else
		not_ok 'hk install succeeded'
	fi
else
	printf 'skip hk integration: hk not installed\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
