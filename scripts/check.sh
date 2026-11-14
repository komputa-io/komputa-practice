#!/usr/bin/env bash
# Runs every check in this repo. CI runs this same command.
#   scripts/check.sh
# It finds scripts and tests from git, so a new one is checked with no edit
# here. It runs every step, then names each step that failed.
# Exit 0: all steps passed. 1: a step failed. 2: wrong arguments.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR

(($# == 0)) || {
  printf 'usage: scripts/check.sh\n' >&2
  exit 2
}
cd -- "$(git rev-parse --show-toplevel)"

# A workstation's git settings must not change a result. CI has none.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

failed=()
step() {
  local name=$1
  shift
  printf '\n== %s\n' "$name"
  "$@" || failed+=("$name")
}

# Tools come through uv at a fixed age, so a workstation and CI run the same
# versions and a release gets seven days before it reaches a check.
tool() { uvx --exclude-newer "7 days" "$@"; }

files=()
while IFS= read -r -d '' f; do
  # archive/ holds retired work. Only the scrub check reads it.
  [[ $f == archive/* ]] && continue
  [[ -f $f && ! -L $f ]] && files+=("$f")
done < <(git ls-files -z --cached --others --exclude-standard)

scripts=() tests=()
for f in "${files[@]}"; do
  [[ $f == *.test.sh ]] && tests+=("$f")
  # head reads a binary file as bytes, so one with no shebang drops out here.
  if LC_ALL=C head -n 1 -- "$f" | LC_ALL=C grep -q -E '^#!.*[/ ](ba)?sh( |$)'; then
    scripts+=("$f")
  fi
done

run_tests() {
  local t rc=0
  for t in "${tests[@]}"; do
    "./$t" || rc=1
  done
  return "$rc"
}

# The herdr skill and its templates name no model: the role's line in pstack-models.md sets it, so a model name here
# is a second home for the choice and it drifts.
no_model_names() {
  local f rc=0
  for f in "${files[@]}"; do
    [[ $f == skills/herdr/SKILL.md || $f == skills/herdr/assets/templates/* ]] || continue
    if grep -n -i -E '\b(opus|sonnet|haiku|fable)\b' -- "$f"; then
      printf 'check: %s names a model; the role line in pstack-models.md sets it\n' "$f" >&2
      rc=1
    fi
  done
  return "$rc"
}

# The docs site's scripts and config: node reports a syntax error in each.
js_syntax() {
  local f rc=0
  for f in "${files[@]}"; do
    [[ $f == scripts/*.mjs ]] || continue
    node --check -- "$f" || rc=1
  done
  return "$rc"
}

# The app (Sitrep Live): lint, the protocol copy, types and tests. It needs its dependencies (`npm ci` in app/). mise gives
# the Node that app/mise.toml pins; CI has that Node already.
app_checks() {
  [[ -f app/package.json ]] || return 0
  [[ -d app/node_modules ]] || {
    printf 'check: app/node_modules is missing; run npm ci in app/\n' >&2
    return 1
  }
  local run=()
  command -v mise >/dev/null && run=(mise exec --)
  local s rc=0
  for s in lint check:protocol typecheck test; do
    (cd app && "${run[@]}" npm run --silent "$s") || rc=1
  done
  return "$rc"
}

# The herdr mod (Sitrep Live in the herdr window): its pure logic, with Node's own test runner on the Node that app/ pins.
herdr_checks() {
  [[ -f herdr/sitrep-live/logic.test.mjs ]] || return 0
  local run=()
  command -v mise >/dev/null && run=(mise exec --)
  (cd app && "${run[@]}" node --test ../herdr/sitrep-live/logic.test.mjs)
}

step scrub scripts/scrub-check.sh
step 'no model names' no_model_names
step shellcheck tool --from shellcheck-py shellcheck -- "${scripts[@]}"
# actionlint reads the workflows and runs shellcheck on their `run:` text. actionlint-py downloads the pinned
# actionlint release when it first runs.
step actionlint tool --from 'actionlint-py==1.7.12.25' actionlint
step shfmt tool --from shfmt-py shfmt -d -- "${scripts[@]}"
step 'ruff format' tool ruff format --check .
step 'ruff check' tool ruff check .
step 'js syntax' js_syntax
step app app_checks
step 'herdr mod' herdr_checks
step 'skill refs' scripts/check-skill-refs.sh
step 'shell tests' run_tests

printf '\n'
if ((${#failed[@]})); then
  printf 'check: failed: %s\n' "$(
    IFS=,
    printf '%s' "${failed[*]}"
  )" >&2
  exit 1
fi
printf 'check: all steps passed\n'
