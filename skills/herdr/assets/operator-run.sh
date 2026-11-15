#!/usr/bin/env bash
# Opens a pane under the calling agent's own Herdr pane that shows a command, waits for the operator to press Enter, runs
# it and leaves a shell. The command reaches the pane as one argv element, so nothing is evaluated before Enter.
#   operator-run.sh '<command>'
# Exit 0: the pane was opened. 1: not in Herdr (HC_TERMINAL_ID unset), herdr-app or jq missing, or the pane not found.
# 2: wrong arguments.
set -Eeuo pipefail
shopt -s inherit_errexit

die() {
  printf 'operator-run: %s\n' "$1" >&2
  exit 1
}

(($# == 1)) && [[ -n $1 ]] || {
  printf 'usage: operator-run.sh <command>\n' >&2
  exit 2
}
[[ -n ${HC_TERMINAL_ID:-} ]] || die 'HC_TERMINAL_ID is not set, so this is not a Herdr terminal; give the command in a code block'
command -v herdr-app >/dev/null || die 'herdr-app is not on PATH'
command -v jq >/dev/null || die 'jq is not on PATH'

pane=$(herdr-app ls 2>/dev/null | jq -r --arg t "$HC_TERMINAL_ID" '[.. | objects | select(.terminal? == $t) | .pane] | first // empty' 2>/dev/null || true)
[[ -n $pane ]] || die "no pane found for terminal $HC_TERMINAL_ID"

# shellcheck disable=SC2016 # the pane's bash expands $1 when it runs
inner='printf "%s\n" "$1"; read -r -p "Press Enter to run: "; eval "$1"; exec bash'
argv=$(jq -nc --arg inner "$inner" --arg cmd "$1" '["bash", "-c", $inner, "_", $cmd]')
# shellcheck disable=SC1010 # `do` is a herdr-app subcommand here
herdr-app do pane.split --direction down --pane "$pane" --argv "$argv" >/dev/null
