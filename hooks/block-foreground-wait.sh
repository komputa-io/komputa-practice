#!/bin/bash
# A Claude Code PreToolUse gate for Bash. A worker never blocks on a wait: the operator sees a pane that does not
# move, and its parent hears nothing. In a worker it refuses a Bash call that is not run in the background and that
# runs `gh pr checks --watch`, `gh run watch`, `merge-on-green`, `hc wait`, or a `sleep` of more than 10 seconds
# (also after `;`, `&&`, `|`, `do`, `then`, `{`, `!`, in front of `timeout N`, or in a `bash -c` body), `watch`, and
# `odev pr checks --wait`. The fix it names: run the command as a background command.
# It also refuses, in the background too, an `until` or `while` loop that sleeps, in a call with no `timeout` command.
# It acts only in a worker, an hc terminal started from a template or by a parent, as block-operator-screen.sh does.
# Exit 2 refuses with one BLOCKED line. Any other failure refuses too, as in the other gates.
set -uo pipefail
# shellcheck disable=SC2329 # run by the EXIT trap
on_exit() {
  local rc=$?
  if ((rc != 0 && rc != 2)); then
    echo "BLOCKED [wait gate: internal error]: the hook failed (exit $rc), so the call is refused. Check the hook." >&2
    exit 2
  fi
}
trap on_exit EXIT

[[ -n ${HC_TERMINAL_ID-} ]] || exit 0
command -v jq >/dev/null || exit 1
me=$(hc get "$HC_TERMINAL_ID" --json 2>/dev/null) || exit 1
jq -e '.template != null or .parent != null' <<<"$me" >/dev/null || exit 0

refuse() {
  local what=${1//[$'\n\r\t']/ }
  ((${#what} > 120)) && what="${what:0:120}..."
  echo "BLOCKED [wait gate]: $what blocks the worker in the foreground. Run it as a background command (run_in_background), and go on working." >&2
  exit 2
}

INPUT=$(cat)
[[ $(jq -r '.tool_name // ""' <<<"$INPUT" 2>/dev/null) == Bash ]] || exit 0
background=$(jq -r '.tool_input.run_in_background // false' <<<"$INPUT" 2>/dev/null)
cmd=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null) || refuse "a malformed call"

nl=$'\n'
# A command position: after a separator, a loop or `if` keyword, `{`, `!`, `-- ` of `hc run`, or the open quote of a
# `bash -c` body. A quote after `echo` or `-m` is not one, so a message that names a wait passes.
kw="(do|then|else|elif|if|while|until|\{|!)[[:space:]]+"
start="(^|[;&|(\`$nl]|\\\$\\(|hc[[:space:]]+run[^;&|$nl]*--[[:space:]]|(ba|z|da)?sh[[:space:]]+-[a-z]*c[[:space:]]+['\"])[[:space:]]*(${kw}|[A-Za-z_]+=[^[:space:]]*[[:space:]]+|env[[:space:]]+|nohup[[:space:]]+|timeout[[:space:]]+[0-9.]+[smhd]?[[:space:]]+)*"
# A background wait needs a bound too: an until or while loop that sleeps can poll for ever, and each one leaves a
# shell behind. `timeout N` must be a command, not a word in a comment.
unbounded="${start}(until|while)[[:space:]]"
bound="${start}timeout[[:space:]]+[0-9]"
if [[ $cmd =~ $unbounded && $cmd == *sleep\ * && ! $cmd =~ $bound ]]; then
  echo "BLOCKED [wait gate]: an until or while loop that sleeps, with no timeout, can run for ever. Wrap it in 'timeout N bash -c ...' as a background command (run_in_background), and go on working." >&2
  exit 2
fi
[[ $background == true ]] && exit 0
waiting="${start}(gh[[:space:]]+pr[[:space:]]+checks[^;&|$nl]*--watch|gh[[:space:]]+run[[:space:]]+watch|watch[[:space:]]|odev[^;&|$nl]*(pr[[:space:]]+checks|build[[:space:]]+(run|rerun))[^;&|$nl]*--wait([[:space:]]|\$)|([^[:space:];&|]*/)?merge-on-green(\.sh)?([[:space:]]|\$)|hc[[:space:]]+wait([[:space:]]|\$))"
if [[ $cmd =~ $waiting ]]; then
  refuse "${BASH_REMATCH[0]#[;&|(\`$nl ]}"
fi
rest=$cmd
sleepre="${start}sleep[[:space:]]+([0-9]+(\.[0-9]+)?)([smhd]?)"
while [[ $rest =~ $sleepre ]]; do
  n=${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 3))]} unit=${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}
  case $unit in m) mult=60 ;; h) mult=3600 ;; d) mult=86400 ;; *) mult=1 ;; esac
  if awk -v n="$n" -v m="$mult" 'BEGIN { exit !(n * m > 10) }'; then
    refuse "sleep $n$unit"
  fi
  rest=${rest#*"${BASH_REMATCH[0]}"}
done
exit 0
