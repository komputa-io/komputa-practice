#!/usr/bin/env bash
# The lead runs this as one background command. It polls the lead's children once a minute and exits with one line
# that names a stalled worker, which re-invokes the lead. The lead looks at the worker and runs the watch again.
#   stall-watch.sh
# A child is stalled when it has shown the same status for more than STALL_AFTER seconds (default 300) and is either
# working on one tool call, or idle without having reported. STALL_POLL is the poll gap in seconds (default 60).
# Exit 0: a worker is stalled (the line says which). 2: no hc terminal, or hc or jq is missing.
set -Eeuo pipefail
shopt -s inherit_errexit

if [[ -z ${HC_TERMINAL_ID-} ]] || ! command -v hc >/dev/null || ! command -v jq >/dev/null; then
  printf 'stall-watch: needs an hc terminal (HC_TERMINAL_ID), hc and jq\n' >&2
  exit 2
fi
me=$HC_TERMINAL_ID after=${STALL_AFTER:-300} poll=${STALL_POLL:-60}

while :; do
  now=$(date +%s)
  while read -r child; do
    line=$(hc get "$child" --json | jq -r --argjson now "$now" --argjson after "$after" '
      ((.status_ms // empty) / 1000) as $since
      | select(($now - $since) > $after)
      | if .status.state == "working" then "has run one step for \(($now - $since) / 60 | floor) min: \(.status.msg)"
        elif (.status.state == "done" or .status.state == "idle") and (.reported | not) then "has been idle for \(($now - $since) / 60 | floor) min without a report"
        else empty end') || continue
    if [[ -n $line ]]; then
      printf 'stall-watch: %s %s\n' "$child" "$line"
      exit 0
    fi
  done < <(hc ls --json | jq -r --arg me "$me" '.terminals[] | select(.parent == $me and .state == "live") | .address')
  sleep "$poll"
done
