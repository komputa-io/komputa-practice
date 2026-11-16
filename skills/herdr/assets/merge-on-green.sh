#!/usr/bin/env bash
# Waits for a pull request's checks, then merges it (or, with --no-merge, sends the parent the agent's code-ready message).
# It runs on GitHub (gh) and on OneDev (odev); `odev project which --json` picks the forge. Run it in the background and act
# only when it ends. A GitHub job that was refused for billing (it fails in about a second with no steps run) is named as
# that, not as a failed test.
#   merge-on-green.sh <pr> <head sha>
#   merge-on-green.sh --no-merge <pr> <head sha> <message file>
# First it checks that <sha> is the local HEAD, that the tree is clean, and (GitHub) that <sha> is the pull request's head on
# the forge. On OneDev, `odev pr checks --head` makes the last check and fails on a head that moved.
# GitHub: `gh pr merge --auto --merge --match-head-commit`, then the wait on the checks. OneDev: `odev pr checks --head
# --wait`, then `odev pr merge --head --delete-branch`. The wait is bound by MERGE_ON_GREEN_TIMEOUT seconds (default 1800).
# After a merge it waits (same bound) until the pull request is merged, then sends the parent a merge-ready message. With
# --no-merge the message it sends is the file plus a line with the head SHA and the check totals that the helper read.
# Exit 0: done (the merge-ready or the code-ready message is sent). 1: a check failed; its name is printed. 2: wrong
# arguments. 3: a job was refused for billing (GitHub only). 4: a wait timed out. 5: the merge could not be queued or
# made, or a message could not be sent. 6: refused before any merge: <sha> is not the pull request's head, or not the
# local HEAD, or the tree is dirty.
set -Eeuo pipefail
shopt -s inherit_errexit

merge=1 msg=
if [[ ${1-} == --no-merge ]]; then
  merge=0
  shift
  msg=${3-}
  [[ -n $msg && -f $msg ]] || {
    printf 'usage: merge-on-green.sh --no-merge <pr number> <full head sha> <message file>\n' >&2
    exit 2
  }
  set -- "${@:1:2}"
fi
(($# == 2)) && [[ $1 =~ ^[0-9]+$ && $2 =~ ^[0-9a-f]{40}$ ]] || {
  printf 'usage: merge-on-green.sh [--no-merge ... <message file>] <pr number> <full head sha>\n' >&2
  exit 2
}
pr=$1 sha=$2
command -v jq >/dev/null || {
  printf 'merge-on-green: jq is not on PATH\n' >&2
  exit 5
}
forge=github cli=gh
if command -v odev >/dev/null && [[ $(odev project which --json 2>/dev/null | jq -r '.kind // empty') == onedev ]]; then
  forge=onedev cli=odev
fi
command -v "$cli" >/dev/null || {
  printf 'merge-on-green: %s is not on PATH\n' "$cli" >&2
  exit 5
}
bound=${MERGE_ON_GREEN_TIMEOUT:-1800}
poll=${MERGE_ON_GREEN_POLL:-5}

refuse() {
  printf 'merge-on-green: refused: %s\n' "$1" >&2
  exit 6
}
[[ $(git rev-parse HEAD 2>/dev/null) == "$sha" ]] || refuse "$sha is not the local HEAD"
[[ -z $(git status --porcelain 2>/dev/null) ]] || refuse 'the working tree is not clean'
if [[ $forge == github ]]; then
  [[ $(gh pr view "$pr" --json headRefOid --jq .headRefOid) == "$sha" ]] || refuse "$sha is not the head of #$pr on the forge"
fi

# send_parent <text>: sends the text to the address report-to prints (the parent, or the fresh lead after a handover).
send_parent() {
  local to rt
  rt=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/report-to
  [[ -x $rt ]] || rt=$rt.sh
  to=$("$rt") || to=
  [[ -n $to ]] && hc send "$to" "$1"
}

# gh_failed: a GitHub check failed. A job with no steps that ended within 3 s never ran: GitHub refused it.
gh_failed() {
  local billing=0 name link job steps secs names
  while IFS=$'\t' read -r name link; do
    [[ $link =~ ^https://github\.com/([^/]+/[^/]+)/actions/runs/[0-9]+/job/([0-9]+) ]] || continue
    job=$(gh api "repos/${BASH_REMATCH[1]}/actions/jobs/${BASH_REMATCH[2]}" --jq '[(.steps | length), ((.completed_at | fromdate) - (.started_at | fromdate))] | @tsv') || continue
    read -r steps secs <<<"$job"
    if ((steps == 0 && secs <= 3)); then
      printf 'merge-on-green: #%s job "%s" failed in %ss with no steps run: GitHub refused it, probably for billing. Check the Actions minutes; it is not a test failure.\n' "$pr" "$name" "$secs" >&2
      billing=1
    fi
  done < <(gh pr checks "$pr" --json name,bucket,link --jq '.[] | select(.bucket == "fail") | [.name, .link] | @tsv')
  ((billing == 0)) || exit 3
  names=$(gh pr checks "$pr" --json name,bucket --jq '.[] | select(.bucket == "fail") | .name') || names=
  if [[ -n $names ]]; then
    while IFS= read -r name; do printf 'merge-on-green: failed check: %s\n' "$name" >&2; done <<<"$names"
    printf 'merge-on-green: #%s has a failed check; read its log\n' "$pr" >&2
  else
    printf 'merge-on-green: #%s: no check has reported a failure\n' "$pr" >&2
  fi
  exit 1
}

rc=0 totals=
if [[ $forge == onedev ]]; then
  errf=$(mktemp)
  totals=$(odev pr checks "$pr" --head "$sha" --wait --timeout "${bound}s" 2>"$errf") || rc=$?
  err=$(<"$errf")
  rm -f -- "$errf"
  case $rc in
    0) ;;
    1)
      [[ -n $totals ]] || refuse "odev: ${err:-no answer}"
      printf 'merge-on-green: #%s has a failed check: %s\n' "$pr" "$totals" >&2
      exit 1
      ;;
    *)
      printf 'merge-on-green: #%s checks did not finish in time: %s\n' "$pr" "$totals" >&2
      exit 4
      ;;
  esac
else
  if ((merge)); then
    gh pr merge "$pr" --auto --merge --match-head-commit "$sha" --delete-branch || {
      printf 'merge-on-green: could not queue the merge of #%s\n' "$pr" >&2
      exit 5
    }
  fi
  timeout "$bound" gh pr checks "$pr" --watch --fail-fast || rc=$?
  case $rc in
    0)
      [[ $(gh pr view "$pr" --json headRefOid --jq .headRefOid) == "$sha" ]] || refuse "the head of #$pr moved during the wait"
      totals=$(gh pr checks "$pr" --json bucket --jq '[.[].bucket] | group_by(.) | map("\(length) \(.[0])") | join(", ")') || totals=unknown
      ;;
    124)
      printf 'merge-on-green: #%s checks did not finish in time\n' "$pr" >&2
      exit 4
      ;;
    *) gh_failed ;;
  esac
fi

if ((merge == 0)); then
  # shellcheck disable=SC2310 # the || branch reports the failure
  send_parent "$(<"$msg")
Checked by merge-on-green at head $sha: checks $totals." || {
    printf 'merge-on-green: #%s checks passed, but the message to the parent was not sent\n' "$pr" >&2
    exit 5
  }
  printf 'merge-on-green: #%s checks passed; the code-ready message is sent\n' "$pr"
  exit 0
fi

if [[ $forge == onedev ]]; then
  odev pr merge "$pr" --head "$sha" --delete-branch || {
    printf 'merge-on-green: could not merge #%s\n' "$pr" >&2
    exit 5
  }
else
  state='' waited=0
  while :; do
    state=$(gh pr view "$pr" --json state --jq .state) || state=
    [[ $state == MERGED ]] && break
    ((waited < bound)) || {
      printf 'merge-on-green: #%s checks passed but it is not merged after %ss\n' "$pr" "$bound" >&2
      exit 4
    }
    sleep "$poll"
    waited=$((waited + poll))
  done
fi
# shellcheck disable=SC2310 # the || branch reports the failure
send_parent "PASS merge-ready: #$pr merged at head $sha (checks $totals). The worktree and local branch are yours to remove." || {
  printf 'merge-on-green: #%s is merged, but the message to the parent was not sent\n' "$pr" >&2
  exit 5
}
printf 'merge-on-green: #%s is merged; the merge-ready message is sent\n' "$pr"
