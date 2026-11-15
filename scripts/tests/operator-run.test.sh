#!/usr/bin/env bash
# Tests for skills/herdr/assets/operator-run.sh with a stub herdr-app that records its argv: no pane is opened.
#   scripts/tests/operator-run.test.sh
set -Eeuo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
script=$repo/skills/herdr/assets/operator-run.sh
root=$(mktemp -d "${TMPDIR:-/tmp}/operator-run-test.XXXXXX")
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/nojq"
jq_dir=$(dirname "$(command -v jq)")
full=$root/bin:$jq_dir:/usr/bin:/bin

# The stub: `ls` prints a tree with two terminals; `do` records one argument for each line.
cat >"$root/bin/herdr-app" <<'STUB'
#!/bin/sh
if [ "$1" = ls ]; then
  echo '{"tabs":[{"panes":[{"terminal":"t-other","pane":"p-other"},{"terminal":"t-mine","pane":"p-mine"}]}]}'
else
  printf '%s\n' "$@" >"$STUB_LOG"
fi
STUB
chmod +x "$root/bin/herdr-app"
ln -s "$root/bin/herdr-app" "$root/nojq/herdr-app"
ln -s "$(command -v bash)" "$root/nojq/bash"

fail=0
expect() {
  local name=$1 want=$2 got=$3
  if [[ $got == "$want" ]]; then printf 'ok    %s\n' "$name"; else
    printf 'FAIL  %s\n      want: %s\n      got:  %s\n' "$name" "$want" "$got"
    fail=1
  fi
}
# refusal <env assignments...>: stderr of a refused run, and its exit code.
refusal() { env -u HC_TERMINAL_ID "$@" "$script" x 2>&1 >/dev/null | tr '\n' ' ' || true; }
code() { env -u HC_TERMINAL_ID "$@" "$script" x >/dev/null 2>&1 && echo 0 || echo $?; }

# shellcheck disable=SC2016 # the text must stay unexpanded
cmd='echo "a b" $HOME; ls '\''x y'\'' && true'
HC_TERMINAL_ID=t-mine STUB_LOG=$root/log PATH=$full "$script" "$cmd"
mapfile -t got <"$root/log"
expect 'splits down the caller pane, not another' 'do pane.split --direction down --pane p-mine' "${got[*]:0:6}"
expect 'argv is JSON with the command as one intact element' "$cmd" "$(jq -r '.[4]' <<<"${got[7]}")"
expect 'argv has five elements: bash -c script _ command' '5' "$(jq length <<<"${got[7]}")"

expect 'no HC_TERMINAL_ID refuses' 'operator-run: HC_TERMINAL_ID is not set, so this is not a Herdr terminal; give the command in a code block ' "$(refusal PATH="$full")"
expect 'unknown terminal refuses' 'operator-run: no pane found for terminal t-none ' "$(refusal HC_TERMINAL_ID=t-none PATH="$full")"
expect 'no jq refuses' 'operator-run: jq is not on PATH ' "$(refusal HC_TERMINAL_ID=t-mine PATH="$root/nojq")"
expect 'no herdr-app refuses' 'operator-run: herdr-app is not on PATH ' "$(refusal HC_TERMINAL_ID=t-mine PATH="$jq_dir:/usr/bin:/bin")"
expect 'a refusal exits 1' '1' "$(code PATH="$full")"

exit "$fail"
