#!/usr/bin/env bash
# Tests for skills/herdr/assets/merge-on-green.sh with a stub gh on PATH: nothing reaches GitHub.
#   scripts/tests/merge-on-green.test.sh
set -Eeuo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script=$(cd -- "$here/../.." && pwd)/skills/herdr/assets/merge-on-green.sh
root=$(mktemp -d "${TMPDIR:-/tmp}/merge-on-green-test.XXXXXX")
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin"
git init -q "$root/repo"
git -C "$root/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
sha=$(git -C "$root/repo" rev-parse HEAD)
other=0123456789abcdef0123456789abcdef01234567

# The stub logs each call. WATCH_RC is the exit code of `pr checks --watch`; JOB is the job JSON that `api` returns.
cat >"$root/bin/gh" <<'STUB'
#!/bin/sh
echo "$*" >>"$STUB_LOG"
case "$1 $2" in
  "pr merge") exit "${MERGE_RC:-0}" ;;
  "pr view")
    case "$*" in
      *headRefOid*) if [ -n "$GH_HEAD_AFTER" ] && grep -q -e --watch "$STUB_LOG"; then echo "$GH_HEAD_AFTER"; else echo "${GH_HEAD:-$SHA}"; fi ;;
      *) echo "${GH_STATE:-MERGED}" ;;
    esac
    ;;
  "pr checks")
    case "$*" in
      *"--json bucket "*) echo "3 pass" ;;
      *--watch*) exit "${WATCH_RC:-0}" ;;
      *) [ -n "$NO_FAIL" ] || echo '[{"name":"check","bucket":"fail","link":"https://github.com/o/r/actions/runs/9/job/77"}]' | jq -r '.[] | [.name, .link] | @tsv' ;;
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
# The stub odev: FORGE=onedev says the clone is OneDev; ODEV_RC and ODEV_OUT answer `pr checks --head`.
cat >"$root/bin/odev" <<'STUB'
#!/bin/sh
echo "odev $*" >>"$STUB_LOG"
case "$1 $2" in
  "project which") [ "$FORGE" = onedev ] && echo '{"kind":"onedev"}' || echo '{"kind":"not-onedev"}' ;;
  "pr checks") echo "$ODEV_OUT"; exit "${ODEV_RC:-0}" ;;
  "pr merge") exit 0 ;;
esac
STUB
chmod +x "$root/bin/odev"
echo "code-ready PASS" >"$root/msg"

fail=0
# run <name> <want rc> <want text> [env...]: runs the script on the stub.
run() {
  local name=$1 want=$2 text=$3 rc=0 sa=$sha a
  shift 3
  for a in "$@"; do [[ $a == SHA_ARG=* ]] && sa=${a#SHA_ARG=}; done
  : >"$root/log"
  (cd "$root/repo" && env PATH="$root/bin:$PATH" STUB_LOG="$root/log" SHA="$sha" HC_TERMINAL_ID=t9 MERGE_ON_GREEN_POLL=0 "$@" "$script" 7 "$sa") >"$root/out" 2>&1 || rc=$?
  if [[ $rc != "$want" ]] || ! grep -q -F -e "$text" "$root/out"; then
    printf 'FAIL  %s (exit %s, want %s; text: %s)\n' "$name" "$rc" "$want" "$text"
    sed 's/^/      | /' "$root/out"
    fail=1
  else printf 'ok    %s\n' "$name"; fi
}

run "green: queues the merge on the head commit, then reports it" 0 "merge-ready message is sent" WATCH_RC=0
grep -q -F -e "pr merge 7 --auto --merge --match-head-commit $sha --delete-branch" "$root/log" || {
  echo "FAIL  merge call"
  fail=1
}
if ! grep -q -F -e "hc send t1 PASS merge-ready: #7 merged at head $sha" "$root/log"; then
  echo "FAIL  merge-ready message"
  fail=1
fi
run "a failed test is named as a failed check" 1 "has a failed check; read its log" WATCH_RC=1 JOB_TSV="$(printf '12\t40')"
run "a job that failed in 1 s with no steps is named a billing refusal" 3 "probably for billing" WATCH_RC=1 JOB_TSV="$(printf '0\t1')"
run "a wait that times out says so" 4 "did not finish in time" WATCH_RC=124
run "a merge that cannot be queued stops before the wait" 5 "could not queue" MERGE_RC=1
if grep -q -F -e "--watch" "$root/log"; then
  echo "FAIL  no wait after a refused merge"
  fail=1
fi
run_nm() { # run_nm <name> <want rc> <want text> [env...]: the --no-merge mode
  local name=$1 want=$2 text=$3 rc=0 sa=$sha a
  shift 3
  for a in "$@"; do [[ $a == SHA_ARG=* ]] && sa=${a#SHA_ARG=}; done
  : >"$root/log"
  (cd "$root/repo" && env PATH="$root/bin:$PATH" STUB_LOG="$root/log" SHA="$sha" HC_TERMINAL_ID=t9 "$@" "$script" --no-merge 7 "$sa" "$root/msg") >"$root/out" 2>&1 || rc=$?
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
run "a merge that never lands times out, no merge-ready sent" 4 "not merged after" GH_STATE=OPEN MERGE_ON_GREEN_TIMEOUT=0
run "a sha that is not the forge head is refused before any merge" 6 "not the head of #7" GH_HEAD=$other
run "a sha that is not the local HEAD is refused before any merge" 6 "not the local HEAD" SHA_ARG=$other
if grep -q -F -e "pr merge" "$root/log"; then
  echo "FAIL  a merge call after a refusal"
  fail=1
fi
echo dirty >"$root/repo/f"
run "a dirty tree is refused" 6 "not clean"
rm "$root/repo/f"
run_nm "--no-merge message carries the head and the totals the helper read" 0 "code-ready message is sent" WATCH_RC=0
grep -q -F -e "Checked by merge-on-green at head $sha: checks 3 pass" "$root/log" || {
  echo "FAIL  no-merge message facts"
  fail=1
}
run_nm "a red wait with no failed check does not send the owner to a log" 1 "no check has reported" WATCH_RC=1 JOB_TSV="$(printf '12\t40')" NO_FAIL=1
run_nm "--no-merge: a head that moves during the wait is refused, nothing sent" 6 "moved during the wait" GH_HEAD_AFTER=$other
if grep -q -F -e "hc send" "$root/log"; then
  echo "FAIL  message sent after the head moved"
  fail=1
fi
run "OneDev green: waits with --head, merges with --head, sends merge-ready" 0 "merge-ready message is sent" FORGE=onedev ODEV_OUT="all passed"
if ! grep -q -F -e "odev pr checks 7 --head $sha --wait --timeout" "$root/log" \
  || ! grep -q -F -e "odev pr merge 7 --head $sha --delete-branch" "$root/log" || grep -q "^gh " "$root/log"; then
  echo "FAIL  OneDev calls"
  fail=1
fi
run "OneDev red: exit 1, no merge" 1 "failed check: job failed" FORGE=onedev ODEV_RC=1 ODEV_OUT="job failed"
run "OneDev head moved: odev error is a refusal" 6 "refused: odev:" FORGE=onedev ODEV_RC=1 ODEV_OUT=
grep -q -F -e "odev pr merge" "$root/log" && {
  echo "FAIL  OneDev merge after refusal"
  fail=1
}
((fail == 0))
