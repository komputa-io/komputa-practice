#!/usr/bin/env bash
# Sets the repo secret DEPS_PR_TOKEN on each GitHub repo named, so the weekly
# dependency refresh can open its PR with a token that starts the gate.
#   scripts/set-deps-pr-token.sh [--apply] owner/repo ...
# A dry run (the default) lists the repos. --apply sets the secret. The token comes
# from stdin when stdin is not a terminal, else from the secret command in HOOK_SECRET_TOOL: `$HOOK_SECRET_TOOL github-deps-pr-token token`.
# It goes to gh on stdin only: never on a command line, never printed.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'set-deps-pr-token: %s\n' "$*" >&2
  exit 1
}

apply=0
repos=()
for a in "$@"; do
  case "$a" in
    --apply) apply=1 ;;
    -*) die "unknown option $a" ;;
    */*) repos+=("$a") ;;
    *) die "'$a' is not owner/repo" ;;
  esac
done
((${#repos[@]})) || die "usage: scripts/set-deps-pr-token.sh [--apply] owner/repo ..."

if ((! apply)); then
  printf 'dry run; would set DEPS_PR_TOKEN on:\n'
  printf '  %s\n' "${repos[@]}"
  printf 'add --apply to set it\n'
  exit 0
fi

if [[ -t 0 ]]; then
  [[ -n "${HOOK_SECRET_TOOL-}" ]] || die "pipe the token in, or set HOOK_SECRET_TOOL"
  token=$("$HOOK_SECRET_TOOL" github-deps-pr-token token)
else
  token=$(cat)
fi
[[ -n "$token" ]] || die "the token is empty"
for r in "${repos[@]}"; do
  printf '%s' "$token" | gh secret set DEPS_PR_TOKEN --repo "$r" >/dev/null
  printf 'set DEPS_PR_TOKEN on %s\n' "$r"
done
