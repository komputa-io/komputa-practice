#!/bin/bash
# Tests for scripts/program-scorecard.py against a throwaway repo: a merge commit pull request, two squash merges,
# and a template update to v1.2.0 between them.
#   scripts/tests/program-scorecard.test.sh
DIR=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
FAIL=0 RUN=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t
# Every commit at one second past midnight today, so a window that starts at today's date must reach back to it.
midnight="$(date +%F)T00:00:01"
export GIT_AUTHOR_DATE=$midnight GIT_COMMITTER_DATE=$midnight
g() { git -C "$T/repo" "$@" >/dev/null; }
put() { # put PATH LINES: write a file of LINES lines
  mkdir -p "$(dirname "$T/repo/$1")"
  seq "$2" >"$T/repo/$1"
}
git init -q -b main "$T/repo"
printf '_commit: v1.1.0\n' >"$T/repo/.copier-answers.yml"
put src/a.cs 1
g add -A && g commit -qm "start"
g switch -qc fix-1 && put src/a.cs 3 && put tests/a.test.cs 4 && g add -A && g commit -qm "fix a"
printf '# Deslop decisions\nc1 keep shape two tables\nc2 keep issue:#4 share later\n' >"$T/repo/.deslop-decisions"
g add -A && g commit -qm "keep two"
g switch -q main && g merge -q --no-ff fix-1 -m "Merge pull request #1 from owner/fix-1"
put src/b.cs 10 && put tests/b.test.cs 5 && g add -A && g commit -qm "feat(b): add b (#2)"
printf '_commit: v1.2.0\n' >"$T/repo/.copier-answers.yml" && g commit -qam "Template update to v1.2.0"
put src/b.cs 12 && g add -A && g commit -qm "fix(b): repair b (#3)"

out=$("$DIR/program-scorecard.py" --repo "$T/repo" --branch main 2>&1)
ok() { # ok WHAT PATTERN: the scorecard's output matches PATTERN
  RUN=$((RUN + 1))
  grep -qE -- "$2" <<<"$out" || {
    echo "FAIL $1: no /$2/ in:"
    echo "$out"
    FAIL=$((FAIL + 1))
  }
}
ok "a merge and two squash merges are three pull requests" '^3 pull requests merged'
ok "a feat squash merge is a build" '^build +1 +10 +5 '
ok "a fix branch and a fix squash merge are fixes" '^fix +2 +4 +4 '
ok "the keep lines a merge adds are counted" '^Deslop keeps: 2 added, 0 removed$'
ok "a commit with no pull request is not counted" '^other +0 '
ok "each pull request names its practice version" 'v1\.1\.0 for 2 pull requests, v1\.2\.0 for 1 pull request$'
ok "lead time counts the merge commit only" 'to its merge: [0-9.]+$'

# git reads a bare date as that day at the current time of day; the window must start at midnight.
out=$("$DIR/program-scorecard.py" --repo "$T/repo" --branch main --since "$(date +%F)" 2>&1)
ok "a window from today's date counts today's pull requests" '^3 pull requests merged'

echo "$RUN cases, $FAIL failed"
((FAIL == 0))
