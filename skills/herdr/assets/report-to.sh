#!/usr/bin/env bash
# Prints the address a worker sends its reports to: its parent, or the fresh lead after a handover.
#   report-to.sh            (in a worker: hc send "$(~/.config/herdr-core/report-to)" "<message>")
# The target is the worker's `lead.to` label (practice-watch handover sets it on the old lead's live children), else
# its hc parent. While the target is an old lead (watch.old=1) or no longer live, it moves on to the live session that
# the handover labelled lead.from=<target>, else to the one live lead (lead=1) in the target's folder; at most 5 steps.
# When neither exists, the target stays as it is: the old lead can still forward.
# Exit 0: the address is printed. 1: no target (no parent and no label). 2: no hc terminal, or hc or jq is missing.
# Any other code: hc failed on this terminal; use the address in the `reach` line of the first message.
set -Eeuo pipefail
shopt -s inherit_errexit

if [[ -z ${HC_TERMINAL_ID-} ]] || ! command -v hc >/dev/null || ! command -v jq >/dev/null; then
  printf 'report-to: needs an hc terminal (HC_TERMINAL_ID), hc and jq\n' >&2
  exit 2
fi
# one_live [FILTER...]: the address of the one live terminal that hc ls lists with FILTER whose folder is $cwd (any
# folder when $cwd is empty), or nothing. It never fails: an hc that does not answer lists nobody.
one_live() {
  hc ls --json "$@" | jq -r --arg cwd "$cwd" '[.terminals[] | select(.state == "live" and ($cwd == "" or .cwd == $cwd))
    | .address] | if length == 1 then .[0] else empty end' || true
}
to=$(hc get "$HC_TERMINAL_ID" --json | jq -r '.labels["lead.to"] // .parent // empty')
[[ -n $to ]] || exit 1
for _ in 1 2 3 4 5; do
  info=$(hc get "$to" --json) || info='{}'
  jq -e '.state == "live" and .labels["watch.old"] != "1"' <<<"$info" >/dev/null && break
  cwd='' next=$(one_live --label "lead.from=$to")
  if [[ -z $next ]]; then
    cwd=$(jq -r '.foreground.cwd // .cwd // ""' <<<"$info")
    if [[ -n $cwd ]]; then next=$(one_live --label lead=1); fi
  fi
  [[ -n $next && $next != "$to" ]] || break
  to=$next
done
printf '%s\n' "$to"
