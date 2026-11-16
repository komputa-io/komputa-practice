#!/usr/bin/env bash
# Queues a pull request to merge when its checks pass, then waits for them, so the agent runs it in the background and
# acts only when it ends. With --no-merge it queues nothing: on green it sends the parent the agent's code-ready message.
# A job that GitHub refused for billing (it fails in about a second with no steps run) is named as that, not as a failed
# test.
#   merge-on-green.sh <pr> <head sha>
#   merge-on-green.sh --no-merge <pr> <head sha> <message file>
# The merge is tied to the head commit, with a merge commit, and the branch goes on merge. The wait is bound by
# MERGE_ON_GREEN_TIMEOUT seconds (default 1800).
# Exit 0: every check passed, and the merge is queued (--no-merge: the message is sent). 1: a check failed; its name is
# printed. 2: wrong arguments. 3: a job was refused for billing. 4: the wait timed out. 5: the merge could not be queued
# (--no-merge: the message could not be sent).
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
command -v gh >/dev/null || {
  printf 'merge-on-green: gh is not on PATH\n' >&2
  exit 5
}
command -v jq >/dev/null || {
  printf 'merge-on-green: jq is not on PATH\n' >&2
  exit 5
}

if ((merge)); then
  gh pr merge "$pr" --auto --merge --match-head-commit "$sha" --delete-branch || {
    printf 'merge-on-green: could not queue the merge of #%s\n' "$pr" >&2
    exit 5
  }
fi

rc=0
timeout "${MERGE_ON_GREEN_TIMEOUT:-1800}" gh pr checks "$pr" --watch --fail-fast || rc=$?
case $rc in
  0)
    if ((merge)); then
      printf 'merge-on-green: #%s checks passed; the merge is queued\n' "$pr"
      exit 0
    fi
    parent=$(hc get "${HC_TERMINAL_ID-}" --json | jq -r '.parent // empty') || parent=
    if [[ -z $parent ]] || ! hc send "$parent" "$(cat "$msg")"; then
      printf 'merge-on-green: #%s checks passed, but the message to the parent was not sent\n' "$pr" >&2
      exit 5
    fi
    printf 'merge-on-green: #%s checks passed; the code-ready message is sent\n' "$pr"
    exit 0
    ;;
  124)
    printf 'merge-on-green: #%s checks did not finish in time\n' "$pr" >&2
    exit 4
    ;;
esac

# A check failed. A job with no steps that ended within 3 s never ran: GitHub refused it (billing or a quota).
billing=0
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
gh pr checks "$pr" --json name,bucket --jq '.[] | select(.bucket == "fail") | .name' | sed 's/^/merge-on-green: failed check: /' >&2 || true
printf 'merge-on-green: #%s has a failed check; read its log\n' "$pr" >&2
exit 1
