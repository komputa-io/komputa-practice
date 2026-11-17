#!/usr/bin/env bash
# Runs, on each canary project, every job the template defines that runs on a schedule or by hand,
# and records a pass for the candidate commit when all of them pass.
#   scripts/canary.sh [--apply] <candidate sha>
# Run it in a clone of the template. The canaries are in scripts/canary.list. OneDev needs ODEV_HOST.
# First it checks that each canary's default branch records the candidate in .copier-answers.yml
# (`_commit`): it refuses to test an older template. A dry run (the default) lists the jobs and starts none.
# Jobs in scripts/canary.skip (they cost money per run) are shown as skipped and never started.
# --apply starts each job, waits for it (CANARY_TIMEOUT seconds, default 1800), prints a table and, when
# every job passed, writes .canary/<sha>.pass, which scripts/release.sh needs.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'canary: %s\n' "$*" >&2
  exit 1
}

apply=0 sha=
for a in "$@"; do
  case "$a" in
    --apply) apply=1 ;;
    -*) die "unknown option $a" ;;
    *) sha=$a ;;
  esac
done
[[ -n $sha ]] || die "usage: scripts/canary.sh [--apply] <candidate sha>"
full=$(git rev-parse --verify -q "$sha^{commit}") || die "'$sha' is not a commit here"
list=${CANARY_LIST:-$(dirname "$0")/canary.list}
skiplist=${CANARY_SKIP:-$(dirname "$0")/canary.skip}
out=${CANARY_DIR:-$(git rev-parse --show-toplevel)/.canary}
timeout=${CANARY_TIMEOUT:-1800}
poll=${CANARY_POLL:-15}

# Prints yes when the recorded `_commit` (a tag, a describe string or a sha) names the candidate, else no.
names_candidate() {
  local c=$1 tip=''
  if [[ $c =~ -g([0-9a-f]{7,})$ ]]; then c=${BASH_REMATCH[1]}; fi
  if [[ $c =~ ^[0-9a-f]{7,40}$ ]]; then
    [[ $full == "$c"* ]] && echo yes || echo no
  else
    tip=$(git rev-parse --verify -q "$c^{commit}" || true)
    [[ $tip == "$full" ]] && echo yes || echo no
  fi
}

# OneDev reads through odev, GitHub through gh. Each prints the file, or nothing when it is absent.
onedev_id() { odev project list --host "$ODEV_HOST" --limit 1000 --json | jq -r --arg p "$1" '.[] | select(.path == $p) | .id'; }
onedev_read() { # id branch file
  odev api --host "$ODEV_HOST" "repositories/$1/files" -q "revision=$2" -q "file=$3" 2>/dev/null | jq -r '.base64Content' | base64 -d || true
}
github_read() { gh api "repos/$1/contents/$2" --jq .content 2>/dev/null | base64 -d || true; }

# Jobs of an OneDev build spec on stdin: those with a ScheduleTrigger, and Merge dependency update.
onedev_jobs() {
  awk '
    function flush() { if (name != "" && (sched || name == "Merge dependency update")) print name }
    !lead && match($0, /^ *- name: /) { lead = substr($0, 1, RLENGTH) }
    lead && index($0, lead) == 1 {
      flush(); name = substr($0, length(lead) + 1); gsub(/^["\047]|["\047]$/, "", name); sched = 0; next
    }
    /!ScheduleTrigger/ { sched = 1 }
    END { flush() }'
}

rows_kind=() rows_project=() rows_job=() rows_branch=()
# canary.skip: `job | reason`, a job that costs money on each run. It is listed, never started.
declare -A skip=()
while IFS='|' read -r name reason; do
  name=${name%"${name##*[![:space:]]}"}
  [[ -z $name || $name == \#* ]] || skip[$name]=${reason# }
done <"$skiplist"
stale=()
while read -r kind project _; do
  [[ -z $kind || $kind == \#* ]] && continue
  case $kind in
    onedev)
      [[ -n ${ODEV_HOST-} ]] || die "set ODEV_HOST for the OneDev canaries"
      id=$(onedev_id "$project")
      [[ -n $id ]] || die "no OneDev project $project"
      branch=$(odev api --host "$ODEV_HOST" "repositories/$id/default-branch" | tr -d '"\n')
      answers=$(onedev_read "$id" "$branch" .copier-answers.yml)
      jobs=$(onedev_jobs <<<"$(onedev_read "$id" "$branch" .onedev-buildspec.yml)")
      ;;
    github)
      branch=$(gh api "repos/$project" --jq .default_branch)
      answers=$(github_read "$project" .copier-answers.yml)
      jobs=
      for wf in $(gh api "repos/$project/contents/.github/workflows" --jq '.[].name'); do
        body=$(github_read "$project" ".github/workflows/$wf")
        if grep -E -q '^[[:space:]]+(schedule|workflow_dispatch):|^on:.*(schedule|workflow_dispatch)' <<<"$body"; then
          jobs+=$wf$'\n'
        fi
      done
      ;;
    *) die "canary.list: unknown forge '$kind'" ;;
  esac
  recorded=$(sed -n 's/^_commit: *//p' <<<"$answers" | head -n1 | tr -d "\"'")
  match=$(names_candidate "${recorded:-none}")
  [[ $match == yes ]] || stale+=("$project records _commit ${recorded:-none}")
  [[ -n $jobs ]] || die "$project: no scheduled or by-hand job found"
  while IFS= read -r j; do
    [[ -n $j ]] || continue
    rows_kind+=("$kind") rows_project+=("$project") rows_job+=("$j") rows_branch+=("$branch")
  done <<<"$jobs"
done <"$list"

if ((${#stale[@]})); then
  for s in "${stale[@]}"; do printf 'canary: %s, not %s\n' "$s" "${full:0:12}" >&2; done
  die "update each canary to the candidate first (docs/release.md); no job started"
fi

if ((! apply)); then
  printf 'dry run for %s; would run:\n' "${full:0:12}"
  for i in "${!rows_job[@]}"; do printf '  %-8s %-40s %s%s\n' "${rows_kind[$i]}" "${rows_project[$i]}" "${rows_job[$i]}" "${skip[${rows_job[$i]}]:+ -- SKIPPED: ${skip[${rows_job[$i]}]}}"; done
  printf 'add --apply to start them\n'
  exit 0
fi

# Each runner prints "<build id or run URL> <PASS|FAIL(reason)>" on one line.
run_onedev() { # project branch job
  local rc=0 id
  odev build run --host "$ODEV_HOST" --project "$1" --ref "$2" --job "$3" --wait --timeout "${timeout}s" >/dev/null 2>&1 || rc=$?
  id=$(odev build list --host "$ODEV_HOST" --project "$1" --limit 10 --json | jq -r --arg j "$3" '[.[] | select(.job == $j)][0].id // "?"')
  if ((rc == 0)); then echo "$id PASS"; else echo "$id FAIL($rc)"; fi
}
run_github() { # repo branch workflow
  local started id='' s c url end
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  gh workflow run "$3" --repo "$1" --ref "$2" >/dev/null 2>&1 || {
    echo "- FAIL(no_workflow_dispatch)"
    return
  }
  end=$((SECONDS + timeout))
  until [[ -n $id ]] || ((SECONDS >= end)); do
    id=$(gh run list --repo "$1" --workflow "$3" --event workflow_dispatch --limit 5 --json databaseId,createdAt \
      | jq -r --arg s "$started" '[.[] | select(.createdAt >= $s)][0].databaseId // empty')
    [[ -n $id ]] || sleep "$poll"
  done
  [[ -n $id ]] || {
    echo "- FAIL(run_not_found)"
    return
  }
  url=-
  until ((SECONDS >= end)); do
    read -r s c url < <(gh run view "$id" --repo "$1" --json status,conclusion,url --jq '[.status, .conclusion, .url] | join(" ")')
    if [[ $s == completed ]]; then
      if [[ $c == success ]]; then echo "$url PASS"; else echo "$url FAIL($c)"; fi
      return
    fi
    sleep "$poll"
  done
  echo "$url FAIL(timeout)"
}

table=$(printf '%-40s %-28s %-44s %s' CANARY JOB RUN RESULT)
failed=0
for i in "${!rows_job[@]}"; do
  if [[ -n ${skip[${rows_job[$i]}]-} ]]; then
    res="- SKIPPED(${skip[${rows_job[$i]}]})"
  elif [[ ${rows_kind[$i]} == onedev ]]; then
    res=$(run_onedev "${rows_project[$i]}" "${rows_branch[$i]}" "${rows_job[$i]}")
  else
    res=$(run_github "${rows_project[$i]}" "${rows_branch[$i]}" "${rows_job[$i]}")
  fi
  [[ ${res#* } == PASS || ${res#* } == SKIPPED* ]] || failed=1
  table+=$'\n'$(printf '%-40s %-28s %-44s %s' "${rows_project[$i]}" "${rows_job[$i]}" "${res% *}" "${res#* }")
done
printf '%s\n' "$table"
((! failed)) || die "a job failed; no pass record for ${full:0:12}"
mkdir -p "$out"
printf 'candidate %s\npassed %s\n%s\n' "$full" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$table" >"$out/$full.pass"
printf 'canary: all jobs passed; wrote %s\n' "$out/$full.pass"
