#!/bin/bash
# A Claude Code PreToolUse gate for Bash and the claude-in-chrome tools. It keeps a worker's browser off the
# operator's screen (issue #69). The working rules say never to open a window on the operator's screen: a worker
# runs a GUI program on its own hidden display. This gate acts only when HERDR_WORKER=1, which the one who starts a worker sets,
# so the operator's own sessions are not touched.
# For a worker it refuses:
#  - a command that opens a URL or file in the operator's browser: xdg-open, gio open, sensible-browser,
#    x-www-browser, gnome-open, open, python -m webbrowser;
#  - a browser binary started without --headless, and Playwright with --headed or headless false;
#  - every mcp__claude-in-chrome__ tool: it drives the operator's real Chrome and their sign-ins.
# It cannot see inside a program: a dev server that opens a browser by itself (Strapi's autoOpen) needs its own
# config, which the worker brief names. Set BROWSER=none for the worker too, which many dev servers honour.
# Exit 2 refuses with one BLOCKED line. Any other failure refuses too, as in the other gates.
set -uo pipefail
# shellcheck disable=SC2329 # run by the EXIT trap
on_exit() {
  local rc=$?
  if ((rc != 0 && rc != 2)); then
    echo "BLOCKED [screen gate: internal error]: the hook failed (exit $rc), so the call is refused. Check the hook." >&2
    exit 2
  fi
}
trap on_exit EXIT

[[ ${HERDR_WORKER:-} == 1 ]] || exit 0

refuse() {
  local what=${2//[$'\n\r\t']/ }
  ((${#what} > 120)) && what="${what:0:120}..."
  echo "BLOCKED [screen gate: $1]: $what. A worker never opens a window on the operator's screen: use headless Chromium or a hidden Xvfb display." >&2
  exit 2
}

command -v jq >/dev/null || refuse "jq is missing" "the hook cannot read the call"
INPUT=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$INPUT" 2>/dev/null) || refuse "malformed payload" "not JSON"

case $tool in
  mcp__claude-in-chrome__*) refuse "the operator's Chrome" "$tool" ;;
  Bash) ;;
  *) exit 0 ;;
esac

cmd=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null) || refuse "malformed payload" "no command"
# Each simple command starts after ; & | ( or a newline. A match inside a quoted word elsewhere is not a start.
nl=$'\n'
start="(^|[;&|(\`$nl]|\\\$\\()[[:space:]]*([A-Za-z_]+=[^[:space:]]*[[:space:]]+|env[[:space:]]+|nohup[[:space:]]+|setsid[[:space:]]+|exec[[:space:]]+)*"
opener="${start}(xdg-open|gio[[:space:]]+open|sensible-browser|x-www-browser|gnome-open|kde-open[0-9]*|open)([[:space:]]|\$)"
browser="${start}(google-chrome(-stable)?|chromium(-browser)?|chrome|firefox|brave(-browser)?|microsoft-edge(-stable)?|vivaldi|librewolf|epiphany)([[:space:]]|\$)"
shell_c="(^|[;&|(\`$nl])[[:space:]]*(ba|z|da|k)?sh[[:space:]]+-[a-z]*c[[:space:]]+['\"][[:space:]]*(xdg-open|gio[[:space:]]+open|sensible-browser|x-www-browser|gnome-open|open)([[:space:]]|\$)"
if [[ $cmd =~ $shell_c ]]; then
  refuse "opens the operator's browser" "${BASH_REMATCH[0]}"
fi
if [[ $cmd =~ $opener ]]; then
  refuse "opens the operator's browser" "${BASH_REMATCH[0]}"
fi
if [[ $cmd =~ webbrowser ]] && [[ $cmd =~ (python3?|py)[[:space:]].*(-m[[:space:]]+webbrowser|webbrowser\.open) ]]; then
  refuse "opens the operator's browser" "python webbrowser"
fi
if [[ $cmd =~ $browser ]] && [[ $cmd != *--headless* ]]; then
  refuse "a browser with a window" "${BASH_REMATCH[0]}"
fi
if [[ $cmd =~ (--headed|headless[[:space:]]*[:=][[:space:]]*(false|False|0)) ]]; then
  refuse "a browser with a window" "${BASH_REMATCH[0]}"
fi
exit 0
