#!/bin/bash
# Feed block-branch-name.sh payloads and check its exit code: 2 blocks, 0 passes.
#   block-branch-name.test.sh [hook]   (default: the hook beside it)
DIR=$(cd "$(dirname "$0")" && pwd)
HOOK=${1:-$DIR/block-branch-name.sh}
FAIL=0 RUN=0
check() { # check <want> <command>
  RUN=$((RUN + 1))
  local got
  jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' | "$HOOK" 2>/dev/null
  got=$?
  if [[ $got != "$1" ]]; then
    echo "FAIL want $1 got $got: $2"
    FAIL=$((FAIL + 1))
  fi
}

# Each way to make or rename a branch, with a good name and a bad one.
check 0 'git switch -c fix/312-spec-drift'
check 2 'git switch -c sitrep-live/fresh-sign-in'
check 0 'git checkout -b feat/sitrep-sign-in origin/main'
check 2 'git checkout -B Fix/Upper'
check 0 'git worktree add ../repo-x -b docs/new-here-cta origin/main'
check 2 'git worktree add -q ../repo-x -b template/deslop origin/main'
check 0 'git branch chore/bump-node-24.11'
check 2 'git branch feature/x'
check 0 'git branch -m old-name refactor/split-gate'
check 2 'git branch -M fix/1-ok bad_name'
check 2 'git switch --create=wip'
check 2 'cd /tmp && git -C repo switch -c nokind'

# Commands that make no branch, a name it cannot read, and git named inside text.
check 0 'git switch main'
check 0 'git branch -D sitrep-live/old'
check 0 'git branch --show-current'
# shellcheck disable=SC2016 # the $branch is literal command text
check 0 'git switch -c "$branch"'
check 0 'echo run git branch foo'
check 0 'git commit -m "git branch foo is wrong"'
check 0 'ls -la'

# The verifier's cases (PR 338): separators and git inside quotes or a heredoc body are text, bots name their own
# branches, wrappers before git are seen through, and the other ways to make a branch are judged.
check 0 'git commit -m "fix; git branch x"'
check 0 'git commit -m "a && git switch -c Bad"'
check 0 $'git commit -m "first line\ngit branch x"'
check 0 $'git commit -F - <<\'EOF\'\ngit branch x\nEOF'
check 2 $'cat <<EOF\nnotes\nEOF\ngit branch bad_name'
check 2 'git switch -c "Bad Name"'
check 0 'git switch -c dependabot/npm_and_yarn/vite-8.3.6'
check 2 'env X=1 git switch -c bad'
check 2 '(git switch -c bad)'
check 2 'if true; then git switch -c bad; fi'
check 2 'git checkout -qb bad'
check 2 'git branch -c old bad'
check 2 'git branch -- bad'
check 2 'git checkout --orphan bad'
check 2 'git stash branch bad'
check 2 'git worktree add ../bad'
check 0 'git worktree add --detach ../anything HEAD'
check 0 'git commit -F - <<<"git branch x"'

# A redirection is not a branch name and its & is not a separator (PR 341's verifier).
check 0 'git branch -m fix/1-x 2>&1'
check 0 'git switch -c fix/1-x 2>/dev/null'
check 0 'git branch -m old fix/1-x > out.txt'
check 0 'git branch fix/1-x &>/dev/null'
check 2 'git switch -c bad 2>&1 | tail -1'

if ((FAIL == 0)); then echo "block-branch-name: $RUN checks passed"; else
  echo "block-branch-name: $FAIL of $RUN failed"
  exit 1
fi
