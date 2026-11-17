#!/usr/bin/env bash
# Holds a pull request until each copy that it adds has a decision.
#   scripts/deslop-decisions.sh --report FILE [--decisions FILE]
# Reads the Deslop JSON report from scripts/deslop-pr.sh. A cluster needs a
# decision when the diff touches it, it is identical or nearly identical, and one
# of its new lines is outside test code (scripts/deslop-gate.jq). Fix it, and the
# next scan no longer finds it. Or keep it with one line in the decisions file
# (default .deslop-decisions):
#   <cluster id> keep <reason> <why, in words>
# where <reason> is one of:
#   shape       the copies share a shape and no logic: declarations, one table
#               row per line, one mapping call per column.
#   boundary    the copies sit on two sides of a boundary that must not share
#               code; the words name it.
#   issue:REF   sharing them is real work, tracked by the issue REF (#12,
#               group/project#12 or a URL).
# Blank lines and lines that start with # are skipped. A cluster that a later
# edit changes gets a new id, so it needs a new decision.
# Exit 0: every cluster has a decision. 3: a cluster has none (each is named).
# 1: no report, or a bad line in the decisions file. 2: wrong arguments.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'deslop-decisions: %s\n' "$*" >&2
  exit 1
}
usage() {
  printf 'usage: scripts/deslop-decisions.sh --report FILE [--decisions FILE]\n' >&2
  exit 2
}

report='' decisions=.deslop-decisions
while (($# > 0)); do
  case "$1" in
    --report | --decisions)
      (($# > 1)) || usage
      case "$1" in --report) report=$2 ;; *) decisions=$2 ;; esac
      shift
      ;;
    *) usage ;;
  esac
  shift
done
[[ -f "$report" ]] || die "no report at '$report'"

declare -A kept=()
if [[ -f "$decisions" ]]; then
  n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+keep[[:space:]]+(shape|boundary|issue:[^[:space:]]+)[[:space:]]+[^[:space:]] ]] \
      || die "$decisions line $n is not '<cluster id> keep <shape|boundary|issue:REF> <why>': $line"
    kept[${BASH_REMATCH[1]}]=1
  done <"$decisions"
fi

# One line for each cluster that needs a decision: id, kind, its new lines.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
clusters=$(jq -L "$here" -r 'include "deslop-gate"; .clusters[] | select(needs_decision)
  | [.id, (.kind | gsub("_"; " ")),
     ([.occurrences[] | select(.in_diff) | "\(.path):\(.start_line)-\(.end_line)"] | join(", "))]
  | @tsv' "$report") || die "cannot read the clusters in $report"

total=0 open=()
while IFS=$'\t' read -r id kind where; do
  [[ -n "$id" ]] || continue
  total=$((total + 1))
  [[ -n "${kept[$id]:-}" ]] || open+=("$id  $kind  $where")
done <<<"$clusters"

if ((${#open[@]} == 0)); then
  if ((total == 0)); then
    printf 'deslop-decisions: no copy this PR adds needs a decision\n'
  else
    printf 'deslop-decisions: each of the %d copies this PR adds has a decision\n' "$total"
  fi
  exit 0
fi
{
  printf 'deslop-decisions: %d of the %d copies this PR adds have no decision:\n' "${#open[@]}" "$total"
  printf '  %s\n' "${open[@]}"
  printf 'Fix each one, or keep it with a line "<cluster id> keep <shape|boundary|issue:REF> <why>" in %s, then push.\n' "$decisions"
  printf 'The reasons are listed at the top of scripts/deslop-decisions.sh.\n'
} >&2
exit 3
