#!/usr/bin/env bash
# Files a few issues from the nightly Deslop scan, and keeps one standing issue.
#   scripts/deslop-issues.sh --report FILE --state FILE [--forge github|onedev --sha SHA --post]
# Dry run by default: prints the plan and changes nothing. With --post it:
#   - compares the report with the last run's clusters (--state, a small JSON file
#     this script rewrites; keep it between runs). With no state it is the first
#     run: it records the baseline and files no cluster issue;
#   - files at most 3 issues a night, for the largest new clusters. A cluster
#     whose marker is on any issue, open or closed, is never filed again;
#   - comments "Gone in SHA" on the issue of a cluster that has gone, and closes it;
#   - edits the standing "Deslop nightly" issue (creates it once, labelled `tracking`, so
#     Sitrep Live keeps it off its Work board). The `tracking` label must exist: on GitHub
#     create it in the repo; on OneDev the issue gets Type: tracking and Triage: needs-triage,
#     so add that value to the Type field (without it the issue is filed with Triage only,
#     with a WARNING).
# A cluster over the night's cap is baselined and never filed later; so is every
# cluster of a first run, and of the first run after embeddings are turned on.
# Reports only identical and nearly identical clusters, and same_behavior ones of
# at least FLOOR lines of mass (Deslop's embedding layer matches a lot of tests).
# github: gh, with GH_TOKEN and GITHUB_REPOSITORY in the environment.
# onedev: curl and jq, with ODEV_HOST, ODEV_PROJECT and ODEV_TOKEN in the environment.
# The token stays in the environment: it is never an argument and never printed.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'deslop-issues: %s\n' "$*" >&2
  exit 1
}
usage() {
  printf 'usage: scripts/deslop-issues.sh --report FILE --state FILE [--forge github|onedev --sha SHA --post]\n' >&2
  exit 2
}

readonly CAP=3 FLOOR=300 LABEL=needs-triage TRACKING=tracking
report='' state='' forge='' sha='' post=0
while (($# > 0)); do
  case "$1" in
    --post) post=1 ;;
    --report | --state | --forge | --sha)
      (($# > 1)) || usage
      case "$1" in --report) report=$2 ;; --state) state=$2 ;; --forge) forge=$2 ;; *) sha=$2 ;; esac
      shift
      ;;
    *) usage ;;
  esac
  shift
done
[[ -f "$report" && -n "$state" ]] || usage
if ((post)); then
  [[ "$forge" =~ ^(github|onedev)$ && -n "$sha" ]] || usage
fi

# The plan: what is new, still open and gone, and the state to keep.
prev='{"runs":[],"clusters":{}}'
first=1
[[ ! -f "$state" ]] || { prev=$(<"$state") && first=0; }
plan=$(jq -n --slurpfile r "$report" --argjson prev "$prev" --argjson first "$first" --argjson cap "$CAP" \
  --argjson floor "$FLOOR" --arg sha "$sha" --arg date "$(date -u +%F)" '
  $r[0] as $r
  | ($r.embedding_provenance != null) as $emb
  | [$r.clusters[] | select(.kind == "identical" or .kind == "nearly_identical" or (.kind == "same_behavior" and .mass >= $floor))] as $cur
  | (["identical", "nearly_identical"] + (if $emb then ["same_behavior"] else [] end)) as $kinds
  | ($cur | map({key: .id, value: .kind}) | from_entries) as $now
  | ($prev.clusters | to_entries | map(select(.key | in($now) | not))) as $absent
  # A kind this run did not look for (embeddings off tonight) is not gone, only unseen.
  | ($absent | map(select(.value as $k | $kinds | index($k)))) as $gone
  | ($absent - $gone | from_entries) as $unseen
  | [$cur[] | select(.id | in($prev.clusters) | not)] as $new
  | {first: ($first == 1),
     new: ($new | sort_by(-.mass)), gone: ($gone | map(.key)),
     open: (if $first == 1 then $cur | length else ($cur | length) - ($new | length) end),
     percent: ($r.metrics.duplication_percent * 10 | round / 10),
     lines: "\($r.metrics.duplicated_loc) of \($r.metrics.analysed_loc)",
     state: {clusters: ($now + $unseen),
             runs: (($prev.runs + [{date: $date, sha: $sha[:7], percent: ($r.metrics.duplication_percent * 10 | round / 10),
                new: (if $first == 1 then 0 else ($new | length) end), open: (if $first == 1 then $cur | length else ($cur | length) - ($new | length) end), gone: ($gone | length)}]) | .[-7:])}}')

suggest() {
  case "$1" in
    identical) echo 'These copies are identical: keep one, in the module that fits best, and call it from the others.' ;;
    nearly_identical) echo 'These copies differ in small details: extract one function that takes the differing parts as parameters, and call it from each place.' ;;
    *) echo 'These do the same job in different code: keep the clearest version and replace the others with calls to it.' ;;
  esac
}
cluster_body() { # one cluster as JSON on stdin
  local c
  c=$(cat)
  printf '<!-- deslop-cluster: %s -->\n**Deslop found duplicate code** (%s, mass %s, %s copies).\n\nLocations:\n' \
    "$(jq -r .id <<<"$c")" "$(jq -r '.kind | gsub("_"; " ")' <<<"$c")" "$(jq .mass <<<"$c")" "$(jq '.occurrences | length' <<<"$c")"
  jq -r '.occurrences[:10][] | "- `\(.path):\(.start_line)-\(.end_line)`"' <<<"$c"
  local path from to
  read -r path from to < <(jq -r '.occurrences[0] | "\(.path) \(.start_line) \(.end_line)"' <<<"$c")
  printf '\nThe duplicated lines, from the first location:\n\n~~~~\n%s\n~~~~\n\n**Suggested merge.** %s\n' \
    "$(sed -n "${from},$((to < from + 14 ? to : from + 14))p" "$path" 2>/dev/null)" "$(suggest "$(jq -r .kind <<<"$c")")"
}
standing_body() { # the number of issues filed tonight
  jq -r --arg sha "$sha" --argjson filed "$1" '
    "<!-- deslop-nightly -->\n**Deslop nightly**, " + (.state.runs[-1].date) + ", " + $sha[:7] + "\n\n"
    + "Duplication: \(.percent)% (\(.lines) lines).\n\n"
    + (if .first then "Baseline recorded: \(.open) clusters tracked, none filed.\n"
       else "New \(.state.runs[-1].new) (filed \($filed)), still open \(.open), gone \(.gone | length).\n" end)
    + "\n| Run | Commit | Duplication | New | Open | Gone |\n|---|---|---|---|---|---|\n"
    + (.state.runs | reverse | map("| \(.date) | \(.sha) | \(.percent)% | \(.new) | \(.open) | \(.gone) |") | join("\n"))' <<<"$plan"
}

if ((! post)); then
  jq -r '"first run: \(.first)\nnew: \(.new | length), would file: \(if .first then "none, this is the baseline" else [.new[:3][] | "\(.id) (mass \(.mass))"] | join(", ") end)\nstill open: \(.open)\ngone: \(.gone | join(", "))\nduplication: \(.percent)%"' <<<"$plan"
  printf '\n(dry run: add --post to file issues)\n'
  exit 0
fi

# Each forge: list_marked prints "KEY<TAB>NUMBER<TAB>STATE" for every issue with a
# marker, closed ones too; then create (a third argument "plain" swaps the
# needs-triage label for tracking, for the standing issue), edit, close (with a comment) by number.
if [[ "$forge" == github ]]; then
  repo=${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY}
  list_marked() {
    gh api --paginate "repos/$repo/issues?state=all&per_page=100" | jq -r '.[] | select(.pull_request == null)
      | (.body // "" | capture("<!-- deslop-(?<k>cluster: [0-9a-f]+|nightly) -->")? // empty) as $m | "\($m.k)\t\(.number)\t\(.state)"'
  }
  create_issue() {
    local label=(-f "labels[]=$LABEL")
    # The standing issue is tracking, not work: Sitrep Live keeps it off its Work board. The label must exist in the repo.
    [[ "${3:-}" != plain ]] || label=(-f "labels[]=$TRACKING")
    printf '%s' "$2" | gh api -X POST "repos/$repo/issues" -f "title=$1" -F body=@- "${label[@]}" >/dev/null
  }
  edit_issue() { printf '%s' "$2" | gh api -X PATCH "repos/$repo/issues/$1" -F body=@- >/dev/null; }
  close_issue() {
    printf '%s' "$2" | gh api -X POST "repos/$repo/issues/$1/comments" -F body=@- >/dev/null
    gh api -X PATCH "repos/$repo/issues/$1" -f state=closed >/dev/null
  }
else
  : "${ODEV_HOST:?set ODEV_HOST}" "${ODEV_PROJECT:?set ODEV_PROJECT}" "${ODEV_TOKEN:?set ODEV_TOKEN}"
  # The token goes in a header read from a file descriptor, so it is on no command line.
  api() {
    local path=$1
    shift
    curl -fsS --max-time 30 -H @<(printf 'Authorization: Bearer %s\n' "$ODEV_TOKEN") "$@" "${ODEV_HOST%/}/~api/$path"
  }
  list_marked() {
    local off=0 page n
    # An unknown project lists as empty, so look it up first: it fails loudly.
    # shellcheck disable=SC2310 # the failure is handled here, on purpose
    api "projects/ids/$ODEV_PROJECT" >/dev/null || die "OneDev has no project '$ODEV_PROJECT' for this token"
    while :; do
      page=$(api issues -G --data-urlencode "query=\"Project\" is \"$ODEV_PROJECT\"" --data-urlencode "offset=$off" --data-urlencode count=100)
      jq -r '.[] | (.description // "" | capture("<!-- deslop-(?<k>cluster: [0-9a-f]+|nightly) -->")? // empty) as $m
        | "\($m.k)\t\(.id)\t\(.state | ascii_downcase | if . == "closed" then "closed" else "open" end)"' <<<"$page"
      n=$(jq length <<<"$page")
      ((n == 100)) || break
      off=$((off + 100))
    done
  }
  post_issue() { # title, description, fields as JSON, project id
    jq -n --argjson p "$4" --arg t "$1" --arg d "$2" --argjson f "$3" '{title: $t, projectId: $p, description: $d, fields: $f}' \
      | api issues -X POST -H 'Content-Type: application/json' --data-binary @- >/dev/null
  }
  create_issue() {
    local pid fields
    pid=$(api "projects/ids/$ODEV_PROJECT")
    fields=$(jq -nc --arg l "$LABEL" '{Triage: $l}')
    # The standing issue also gets Type: tracking; the board's tracking rule wins over Triage.
    # A project whose Type field has no such value refuses it: file with Triage only and say so.
    if [[ "${3:-}" == plain ]]; then
      # shellcheck disable=SC2310 # the failure is handled here, on purpose
      post_issue "$1" "$2" "$(jq -nc --arg l "$LABEL" --arg t "$TRACKING" '{Triage: $l, Type: $t}')" "$pid" 2>/dev/null && return 0
      printf 'deslop-issues: WARNING the project has no Type value %s (or refused it); filing with Triage only\n' "$TRACKING" >&2
    fi
    # A project without the Triage field (or value) refuses it: file without it and say so.
    # shellcheck disable=SC2310 # the failure is handled here, on purpose
    post_issue "$1" "$2" "$fields" "$pid" 2>/dev/null || {
      printf 'deslop-issues: WARNING the project has no Triage field, or no such value (or refused it); filing without it\n' >&2
      post_issue "$1" "$2" '{}' "$pid"
    }
  }
  # The description takes the bare text as its body, not JSON.
  edit_issue() { printf '%s' "$2" | api "issues/$1/description" -X POST -H 'Content-Type: application/json' --data-binary @- >/dev/null; }
  close_issue() {
    jq -n --arg c "$2" '{state: "Closed", comment: $c}' \
      | api "issues/$1/state-transitions" -X POST -H 'Content-Type: application/json' --data-binary @- >/dev/null
  }
fi

# The state is written before any issue call, so a refused issue never loses the baseline.
mkdir -p "$(dirname "$state")"
jq .state <<<"$plan" >"$state"

filed=0 closed=0
marked=$(list_marked)
find_marked() { awk -F'\t' -v k="$1" '$1 == k { print $2 "\t" $3; exit }' <<<"$marked"; }

if jq -e '.first | not' <<<"$plan" >/dev/null; then
  while IFS= read -r c; do
    id=$(jq -r .id <<<"$c")
    hit=$(find_marked "cluster: $id")
    [[ -z "$hit" ]] || continue
    paths=$(jq -r '.occurrences[0] | "\(.path):\(.start_line)"' <<<"$c")
    create_issue "Duplicate code at $paths (cluster ${id:0:8})" "$(cluster_body <<<"$c")"
    filed=$((filed + 1))
    ((filed < CAP)) || break
  done < <(jq -c '.new[]' <<<"$plan")
  while IFS= read -r id; do
    hit=$(find_marked "cluster: $id")
    if [[ "${hit#*$'\t'}" == open ]]; then
      close_issue "${hit%%$'\t'*}" "Gone in ${sha:0:7}."
      closed=$((closed + 1))
    fi
  done < <(jq -r '.gone[]' <<<"$plan")
fi

body=$(standing_body "$filed")
hit=$(find_marked nightly)
if [[ -n "$hit" ]]; then edit_issue "${hit%%$'\t'*}" "$body"; else create_issue "Deslop nightly" "$body" plain; fi
printf 'deslop-issues: filed %s, closed %s, standing issue %s\n' "$filed" "$closed" "$([[ -n "$hit" ]] && echo edited || echo created)"
