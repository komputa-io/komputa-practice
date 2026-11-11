#!/usr/bin/env bash
# Compares each hook that ~/.claude/settings.json registers with its copy in
# this folder. The live hooks are plain copies, so nothing else keeps them in
# step, and checks each one blocks when it cannot start. Exit 1 on either.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
settings=${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
command -v jq >/dev/null || {
  echo "check-live: jq is not installed" >&2
  exit 2
}
rc=0
while IFS= read -r cmd; do
  live=${cmd/#\~/$HOME}
  name=$(basename "$live")
  if [[ ! -f $here/$name ]]; then
    echo "no copy here: $name" >&2
    rc=1
  elif ! cmp -s "$live" "$here/$name"; then
    echo "differs: $name (cp $here/$name $live, after review)" >&2
    rc=1
  else
    echo "in step: $name"
  fi
done < <(jq -r '.hooks[][]?.hooks[]?.command // empty' "$settings" | sort -u)
# A hook that cannot start exits 126 or 127, and Claude Code then runs the
# tool call unless the registration says "onFailure": "block".
while IFS= read -r cmd; do
  echo "not blocking on failure: $(basename "$cmd")" >&2
  rc=1
done < <(jq -r '.hooks[][]?.hooks[]? | select(.onFailure != "block") | .command' "$settings")
exit $rc
