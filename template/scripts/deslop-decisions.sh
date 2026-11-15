#!/usr/bin/env bash
# Holds a pull request until each duplicate that it adds has a decision.
#   scripts/deslop-decisions.sh --report FILE [--decisions FILE]
# Reads the Deslop JSON report from scripts/deslop-pr.sh. Each cluster that the
# diff touches needs a decision. Fix it, and the next scan no longer finds it.
# Or keep it with one line in the decisions file (default .deslop-decisions):
#   <cluster id> keep <reason>
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
    [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+keep[[:space:]]+[^[:space:]] ]] \
      || die "$decisions line $n is not '<cluster id> keep <reason>': $line"
    kept[${BASH_REMATCH[1]}]=1
  done <"$decisions"
fi

# One line for each cluster that the diff touches: id, kind, its new lines.
clusters=$(jq -r '.clusters[] | select(.intersects_diff)
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
  printf 'deslop-decisions: each of the %d duplicates this PR adds has a decision\n' "$total"
  exit 0
fi
{
  printf 'deslop-decisions: %d of the %d duplicates this PR adds have no decision:\n' "${#open[@]}" "$total"
  printf '  %s\n' "${open[@]}"
  printf 'Fix each one, or keep it with a line "<cluster id> keep <reason>" in %s, then push.\n' "$decisions"
} >&2
exit 3
