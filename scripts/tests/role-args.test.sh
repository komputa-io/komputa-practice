#!/usr/bin/env bash
# Tests for skills/herdr/assets/role-args.sh: the sheet's rules, and a template's command starting claude with them.
#   scripts/tests/role-args.test.sh
set -Eeuo pipefail
unset HC_TERMINAL_ID # the script reads the label of the terminal it runs in; a test must not

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
script=$repo/skills/herdr/assets/role-args.sh
root=$(mktemp -d "${TMPDIR:-/tmp}/role-args-test.XXXXXX")
trap 'rm -rf -- "$root"' EXIT

mkdir -p "$root/bin" "$root/home/.config/herdr-core"
cp "$script" "$root/home/.config/herdr-core/role-args"
printf '#!/bin/sh\nprintf "%%s\\n" "$*"\n' >"$root/bin/claude"
chmod +x "$root/bin/claude"

sheet=$root/sheet.md
cat >"$sheet" <<'SHEET'
lead: opus @high
feature, refactoring: sonnet
bug-fix: sonnet @low
bug-fix report: haiku
judgment and prose: opus
broken: not a model!
auto-role: auto
default effort: medium
SHEET

fail=0
expect() {
  local name=$1 want=$2 got=$3
  if [[ $got == "$want" ]]; then printf 'ok    %s\n' "$name"; else
    printf 'FAIL  %s\n      want: %s\n      got:  %s\n' "$name" "$want" "$got"
    fail=1
  fi
}
run() { PSTACK_MODELS=$sheet "$script" "$@" 2>/dev/null; }

expect 'a role in a multi-role line' '--model sonnet --effort medium' "$(run refactoring)"
expect 'default effort fills a value with none' '--model opus --effort medium' "$(run 'judgment and prose')"
expect 'own @effort beats default effort; a role that prefixes another gets its own line' '--model sonnet --effort low' "$(run bug-fix)"
expect 'a longer name does not match a shorter line' '' "$(run bug)"
expect 'no such line prints nothing' '' "$(run verifier)"
expect 'an unreadable value prints nothing' '' "$(run broken)"
expect 'auto prints nothing' '' "$(run auto-role)"
expect 'the first role with a line wins' '--model sonnet --effort medium' "$(run verifier feature)"
expect 'no sheet prints nothing' '' "$(PSTACK_MODELS=$root/none "$script" feature 2>/dev/null)"
expect 'no sheet says so on stderr' 'yes' "$(PSTACK_MODELS=$root/none "$script" feature 2>&1 >/dev/null | grep -q 'no model sheet' && echo yes)"
sed -i 's/^default effort: medium/default effort: session/' "$sheet"
expect 'default effort: session adds no effort' '--model opus' "$(run 'judgment and prose')"

# A template's command, through sh -c, with a stub claude that prints its argv.
cmd=$(sed -n 's/^command: //p' "$repo/skills/herdr/assets/templates/reviewer.md")
expect 'the reviewer template starts claude with the sheet line' '--model opus' \
  "$(HOME=$root/home PATH=$root/bin:$PATH PSTACK_MODELS=$sheet sh -c "$cmd")"

# A move-up and a role label come from the terminal's labels: a stub hc prints them.
# shellcheck disable=SC2016 # the stub expands it when it runs
printf '#!/bin/sh\nprintf "%%s\\n" "$HC_STUB_LABELS"\n' >"$root/bin/hc"
chmod +x "$root/bin/hc"
printf 'verifier: sonnet @high\n' >>"$sheet"
withlabels() { HC_TERMINAL_ID=t9 HC_STUB_LABELS=$1 PATH=$root/bin:$PATH PSTACK_MODELS=$sheet "$script" "${@:2}" 2>/dev/null; }
expect 'a model label moves the worker up' '--model fable --effort max' "$(withlabels '{"labels":{"model":"fable @max"}}' feature)"
expect 'a role label tries its line first' '--model sonnet --effort high' "$(withlabels '{"labels":{"role":"verifier"}}' 'judgment and prose')"
expect 'no labels uses the template role' '--model opus' "$(withlabels '{"labels":{}}' 'judgment and prose')"

# jq missing: the labels cannot be read; say so on stderr and use the sheet. A PATH with the stubs and bash only has no jq.
mkdir -p "$root/nojq"
ln -s "$(command -v bash)" "$root/nojq/bash"
ln -s "$(command -v sed)" "$root/nojq/sed"
ln -s "$(command -v head)" "$root/nojq/head"
ln -s "$root/bin/hc" "$root/nojq/hc"
nojq=$(HC_TERMINAL_ID=t9 HC_STUB_LABELS='{"labels":{"model":"fable"}}' PATH=$root/nojq PSTACK_MODELS=$sheet "$script" feature 2>&1)
expect 'no jq: warns that labels cannot be read, and uses the sheet' \
  "role-args: jq is not on PATH, so the labels model= and role= cannot be read; using the sheet
--model sonnet" "$nojq"

exit "$fail"
