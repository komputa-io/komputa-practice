#!/usr/bin/env bash
# Tests for skills/herdr/assets/merge-on-green.sh with a stub gh on PATH: nothing reaches GitHub.
#   scripts/tests/merge-on-green.test.sh
set -Eeuo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script=$(cd -- "$here/../.." && pwd)/skills/herdr/assets/merge-on-green.sh
root=$(mktemp -d "${TMPDIR:-/tmp}/merge-on-green-test.XXXXXX")
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin"
sha=0123456789abcdef0123456789abcdef01234567

# The stub logs each call. WATCH_RC is the exit code of `pr checks --watch`; JOB is the job JSON that `api` returns.
cat >"$root/bin/gh" <<'STUB'
#!/bin/sh
echo "$*" >>"$STUB_LOG"
case "$1 $2" in
  "pr merge") exit "${MERGE_RC:-0}" ;;
  "pr checks")
    case "$*" in
      *--watch*) exit "${WATCH_RC:-0}" ;;
      *) echo '[{"name":"check","bucket":"fail","link":"https://github.com/o/r/actions/runs/9/job/77"}]' | jq -r '.[] | [.name, .link] | @tsv' ;;
    esac
    ;;
  "api repos/o/r/actions/jobs/77") echo "$JOB_TSV" ;;
esac
STUB
chmod +x "$root/bin/gh"
# The stub hc answers `get` with a parent and logs `send`.
cat >"$root/bin/hc" <<'STUB'
#!/bin/sh
case "$1" in
  get) echo '{"parent":"t1"}' ;;
  send) echo "hc $*" >>"$STUB_LOG" ;;
esac
STUB
chmod +x "$root/bin/hc"
echo "code-ready PASS" >"$root/msg"

fail=0
# run <name> <want rc> <want text> [env...]: runs the script on the stub.
run() {
  local name=$1 want=$2 text=$3 rc=0
  shift 3
  : >"$root/log"
  env PATH="$root/bin:$PATH" STUB_LOG="$root/log" "$@" "$script" 7 "$sha" >"$root/out" 2>&1 || rc=$?
  if [[ $rc != "$want" ]] || ! grep -q -F -e "$text" "$root/out"; then
    printf 'FAIL  %s (exit %s, want %s; text: %s)\n' "$name" "$rc" "$want" "$text"
    sed 's/^/      | /' "$root/out"
    fail=1
  else printf 'ok    %s\n' "$name"; fi
}

run "green: queues the merge on the head commit, then reports it" 0 "checks passed" WATCH_RC=0
grep -q -F -e "pr merge 7 --auto --merge --match-head-commit $sha --delete-branch" "$root/log" || {
  echo "FAIL  merge call"
  fail=1
}
run "a failed test is named as a failed check" 1 "has a failed check" WATCH_RC=1 JOB_TSV="$(printf '12\t40')"
run "a job that failed in 1 s with no steps is named a billing refusal" 3 "probably for billing" WATCH_RC=1 JOB_TSV="$(printf '0\t1')"
run "a wait that times out says so" 4 "did not finish in time" WATCH_RC=124
run "a merge that cannot be queued stops before the wait" 5 "could not queue" MERGE_RC=1
if grep -q -F -e "--watch" "$root/log"; then
  echo "FAIL  no wait after a refused merge"
  fail=1
fi
run_nm() { # run_nm <name> <want rc> <want text> [env...]: the --no-merge mode
  local name=$1 want=$2 text=$3 rc=0
  shift 3
  : >"$root/log"
  env PATH="$root/bin:$PATH" STUB_LOG="$root/log" HC_TERMINAL_ID=t9 "$@" "$script" --no-merge 7 "$sha" "$root/msg" >"$root/out" 2>&1 || rc=$?
  if [[ $rc != "$want" ]] || ! grep -q -F -e "$text" "$root/out"; then
    printf 'FAIL  %s (exit %s, want %s; text: %s)\n' "$name" "$rc" "$want" "$text"
    fail=1
  else printf 'ok    %s\n' "$name"; fi
}
run_nm "--no-merge green: sends the message to the parent, queues no merge" 0 "message is sent" WATCH_RC=0
if ! grep -q -F -e "hc send t1 code-ready PASS" "$root/log" || grep -q -F -e "pr merge" "$root/log"; then
  echo "FAIL  --no-merge send or merge call"
  fail=1
fi
run_nm "--no-merge red: names the failed check, sends nothing" 1 "failed check: check" WATCH_RC=1 JOB_TSV="$(printf '12\t40')"
if grep -q -F -e "hc send" "$root/log"; then
  echo "FAIL  no message on red"
  fail=1
fi
((fail == 0))
