#!/bin/bash
# shellcheck disable=SC2016 # the backticks are literal Markdown
# Tests for scripts/check-skill-refs.sh against a fake Claude config and skill folders.
#   scripts/tests/check-skill-refs.test.sh
DIR=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
FAIL=0 RUN=0
mkdir -p "$T/config/plugins" "$T/plugin/skills/reflect" "$T/skills/house-a"
: >"$T/plugin/skills/reflect/SKILL.md"
jq -n --arg p "$T/plugin" '{plugins: {"pstack@market": [{installPath: $p}]}}' >"$T/config/plugins/installed_plugins.json"
check() { # check WANT WHAT TEXT: a house skill that says TEXT exits WANT
  printf '%s\n' "$3" >"$T/skills/house-a/SKILL.md"
  RUN=$((RUN + 1))
  CLAUDE_CONFIG_DIR="$T/config" "$DIR/check-skill-refs.sh" "$T/skills/house-a" >/dev/null 2>&1
  local got=$?
  [[ $got == "$1" ]] || {
    echo "FAIL $2: want exit $1, got $got"
    FAIL=$((FAIL + 1))
  }
}
check 0 "an installed plugin skill passes" 'Use `pstack:reflect` for that.'
check 1 "a plugin skill that is gone fails" 'Use `pstack:retired` for that.'
check 0 "an image tag is only a warning" 'Run `postgres:latest`.'
RUN=$((RUN + 1))
out=$(CLAUDE_CONFIG_DIR="$T/none" "$DIR/check-skill-refs.sh" "$T/skills/house-a" 2>&1)
[[ $? == 0 && $out == *skipped* ]] || {
  echo "FAIL with no plugin list it skips and says so: $out"
  FAIL=$((FAIL + 1))
}
echo "$RUN cases, $FAIL failed"
[[ $FAIL == 0 ]] && echo "all skill-refs tests pass"
((FAIL == 0))
