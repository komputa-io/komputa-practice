#!/usr/bin/env bash
# Runs every check in this repo. CI runs this same command.
#   scripts/check.sh
# It finds scripts and tests from git, so a new one is checked with no edit
# here. It runs the steps in parallel, prints each step's output together in
# the order below, then names each step that failed.
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

out=$(mktemp -d "${TMPDIR:-/tmp}/check.XXXXXX")
trap 'rm -rf -- "$out"' EXIT

# launch <id> <command...>: runs it in the background; its output and exit code go to $out/<id>.
launch() {
  local id=$1
  shift
  (
    rc=0
    "$@" >"$out/$id.log" 2>&1 || rc=$?
    echo "$rc" >"$out/$id.rc"
  ) &
}
# collect <id>: waits for it, prints its output, returns its exit code.
collect() {
  local id=$1
  until [[ -f $out/$id.rc ]]; do wait -n 2>/dev/null || sleep 0.1; done
  cat -- "$out/$id.log"
  return "$(<"$out/$id.rc")"
}

names=() ids=()
n=0
step() {
  local name=$1
  shift
  n=$((n + 1))
  names+=("$name") ids+=("s$n")
  launch "s$n" "$@"
}

# parallel <function arg-lists...>: runs each command line of a group at once; the group fails when any does.
# Each command's output stays together, in the order given.
run_all() {
  local g=$RANDOM$RANDOM i=0 rc=0 cmd
  for cmd in "$@"; do
    i=$((i + 1))
    # shellcheck disable=SC2086 # a command line of words, no quoting needed
    launch "$g-$i" $cmd
  done
  for ((j = 1; j <= i; j++)); do
    # shellcheck disable=SC2310 # collect returns the step's exit code; it is read here, not by set -e
    collect "$g-$j" || rc=1
  done
  return "$rc"
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
  local t cmds=()
  for t in "${tests[@]}"; do cmds+=("./$t"); done
  run_all "${cmds[@]}"
}

# The herdr skill, its templates and its role-args script name no model: the role's line in pstack-models.md sets it, so a model name here
# is a second home for the choice and it drifts.
no_model_names() {
  local f rc=0
  for f in "${files[@]}"; do
    [[ $f == skills/herdr/SKILL.md || $f == skills/herdr/assets/* ]] || continue
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
  local s cmds=()
  for s in lint check:protocol typecheck test; do cmds+=("app_script $s"); done
  run_all "${cmds[@]}"
}
app_script() { (cd app && "${run[@]}" npm run --silent "$1"); }

# The herdr mod (Sitrep Live in the herdr window): its pure logic, with Node's own test runner on the Node that app/ pins.
herdr_checks() {
  [[ -f herdr/sitrep-live/logic.test.mjs ]] || return 0
  local run=()
  command -v mise >/dev/null && run=(mise exec --)
  (cd app && "${run[@]}" node --test ../herdr/sitrep-live/logic.test.mjs)
}

# Dependency scan: Trivy over the lock files, same rules as the template's gate (template/scripts/gate.sh.jinja). HIGH or
# CRITICAL with a fix fails. Accept a finding in .trivyignore.yaml: each entry needs an id and a statement that says why.
# scripts/install-trivy.sh and scripts/trivy.pin are links to the template's own copies. The vulnerability database comes
# from a registry on each run; TRIVY_SKIP_DB_UPDATE=true scans offline with an earlier download in .gate/trivy.
trivy_scan() {
  local locks=() f ignore=.trivyignore.yaml
  while IFS= read -r f; do
    [[ -f $f ]] && locks+=("$f")
  done < <(git ls-files -- 'uv.lock' '*/uv.lock' 'package-lock.json' '*/package-lock.json' 'packages.lock.json' '*/packages.lock.json')
  ((${#locks[@]})) || return 0
  if [[ -f $ignore ]]; then
    awk '
      function check() { if (open && !has) { printf "%s: line %d: the entry has no statement (the reason)\n", FILENAME, open; bad = 1 } }
      /^[[:space:]]*-[[:space:]]+id:/ { check(); open = NR; has = 0 }
      /^[[:space:]]+statement:[[:space:]]*[^[:space:]]/ { has = 1 }
      END { check(); exit bad }
    ' "$ignore" >&2 || {
      printf 'check: %s: give each entry a statement that says why the finding is accepted\n' "$ignore" >&2
      return 1
    }
  fi
  local trivy copy=.gate/trivy-scan
  trivy=$(scripts/install-trivy.sh) || return 1
  rm -rf -- "$copy"
  for f in "${locks[@]}"; do
    mkdir -p -- "$copy/$(dirname -- "$f")"
    cp -- "$f" "$copy/$f"
  done
  local args=(fs --scanners vuln --include-dev-deps --severity "HIGH,CRITICAL" --ignore-unfixed --exit-code 1 --no-progress
    --skip-version-check --disable-telemetry --cache-dir .gate/trivy)
  [[ ! -f $ignore ]] || args+=(--ignorefile "$PWD/$ignore")
  timeout 600 "$trivy" "${args[@]}" "$copy" || {
    printf 'check: a lock file has a HIGH or CRITICAL vulnerability with a fix (named above), or Trivy could not get its database. Upgrade the package, or accept the finding with a reason in %s\n' "$ignore" >&2
    return 1
  }
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
# SkillSpector over skills/: static analysis only, no model, no network. Accepted findings: .skillspector-baselines/.
step 'skill scan' scripts/skill-scan.sh
step 'trivy' trivy_scan
step 'shell tests' run_tests

failed=()
for i in "${!ids[@]}"; do
  printf '\n== %s\n' "${names[$i]}"
  # shellcheck disable=SC2310 # same
  collect "${ids[$i]}" || failed+=("${names[$i]}")
done

printf '\n'
if ((${#failed[@]})); then
  printf 'check: failed: %s\n' "$(
    IFS=,
    printf '%s' "${failed[*]}"
  )" >&2
  exit 1
fi
printf 'check: all steps passed\n'
