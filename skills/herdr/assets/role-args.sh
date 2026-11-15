#!/usr/bin/env bash
# Prints the `claude` arguments for a role line of the model sheet, so a template's command can start the worker on the
# model the sheet names: claude $(role-args.sh feature)
#   role-args.sh <role line name>...   e.g. feature, bug-fix, "judgment and prose", verifier; the first name with a line wins
# A terminal started with `--label model=<value>` (a move-up) uses that value, not the sheet; `--label role=<name>` tries
# that line first.
# Rules match app/server/src/fleet/analysis/runner.ts (modelOf), plus `default effort:`.
# The sheet is $PSTACK_MODELS, else ~/.claude/pstack-models.md.
# Output: `--model <m>` and, when there is an effort, `--effort <e>`. With no sheet, no such line or an unreadable value it
# prints nothing, says so on stderr, and claude runs on its own default.
# Exit 0: always, so a template still starts. 2: wrong arguments.
set -Eeuo pipefail
shopt -s inherit_errexit

(($# >= 1)) || {
  printf 'usage: role-args.sh <role line name>...\n' >&2
  exit 2
}
sheet=${PSTACK_MODELS:-$HOME/.claude/pstack-models.md}

# `<model> [@<effort>]`: print the arguments, or fail when the value is not one.
args_of() {
  local value=$1 default=$2 re='^([a-z][a-z0-9.-]*)([[:space:]]+@(low|medium|high|xhigh|max))?$'
  [[ $value =~ $re ]] || return 1
  local model=${BASH_REMATCH[1]} effort=${BASH_REMATCH[3]:-}
  [[ $model == inherit-parent || $model == auto ]] && return 1
  [[ -n $effort || ! $default =~ ^(low|medium|high|xhigh|max)$ ]] || effort=$default
  printf -- '--model %s' "$model"
  [[ -z $effort ]] || printf -- ' --effort %s' "$effort"
  printf '\n'
}

# Labels on this terminal, set by `hc run --label`: `model=<value>` is a move-up and wins over the sheet; `role=<name>`
# names a line to try before the template's own (`role=verifier` on the reviewer template).
if [[ -n ${HC_TERMINAL_ID:-} ]] && ! command -v jq >/dev/null; then
  printf 'role-args: jq is not on PATH, so the labels model= and role= cannot be read; using the sheet\n' >&2
elif [[ -n ${HC_TERMINAL_ID:-} ]] && command -v hc >/dev/null; then
  labels=$(hc get "$HC_TERMINAL_ID" 2>/dev/null | jq -r '.labels | "\(.model // "")|\(.role // "")"' 2>/dev/null || true)
  IFS='|' read -r label_model label_role <<<"$labels"
  if [[ -n ${label_model:-} ]]; then
    # shellcheck disable=SC2310 # args_of only prints; a failure is the answer, not an error
    args_of "$label_model" "" && exit 0
    printf 'role-args: label model=%s is not "<model> [@<effort>]"; using the sheet\n' "$label_model" >&2
  fi
  [[ -z ${label_role:-} ]] || set -- "$label_role" "$@"
fi

[[ -r $sheet ]] || {
  printf 'role-args: no model sheet at %s; claude runs on its default model\n' "$sheet" >&2
  exit 0
}

default=$(sed -n 's/^default effort:[[:space:]]*//p' "$sheet" | head -n 1 | sed 's/[[:space:]]*$//')
for role in "$@"; do
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == *:* ]] || continue
    IFS=, read -ra parts <<<"${line%%:*}"
    for p in "${parts[@]}"; do
      p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      [[ $p == "$role" ]] || continue
      value=$(printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      # shellcheck disable=SC2310
      args_of "$value" "$default" && exit 0
      printf 'role-args: "%s: %s" is not "<model> [@<effort>]"; claude runs on its default model\n' "$role" "$value" >&2
      exit 0
    done
  done <"$sheet"
done

printf 'role-args: %s has no "%s" line; claude runs on its default model\n' "$sheet" "$*" >&2
exit 0
