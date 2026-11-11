#!/bin/bash
# Refuse a write that puts a credential into a file.
# Enforces the CLAUDE.md rule: never put a secret in a file.
#
# What it reads, by tool:
#   Claude Code Write, Edit, MultiEdit: tool_input.content, .new_string and
#     each .edits[].new_string.
#   Codex apply_patch: the patch text in tool_input.command (or .input, or a
#     bare string tool_input). Only the added lines ("+" lines) count: a
#     removed line is a secret leaving the file, and a context line is already
#     in it. Each line is judged alone, so two halves of a token on two lines
#     are not a token.
# A value of the wrong type is not text and is skipped. A payload that is not
# one JSON value (malformed, empty, or two values) is refused: the gate cannot
# tell what it writes.
# No size limit: jq reads the whole payload and matches in one pass (a 20 MB
# patch takes about 4 s).

SECRET_PATTERNS=(
  "-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "AKIA[0-9A-Z]{16}"
  "gh[pousr]_[A-Za-z0-9]{36}"
  "github_pat_[A-Za-z0-9_]{22,}"
  "glpat-[A-Za-z0-9_-]{20}"
  "sk-ant-[A-Za-z0-9_-]{20,}"
  "sk-(proj-)?[A-Za-z0-9]{32,}"
  "xox[baprs]-[A-Za-z0-9-]{10,}"
)

if ! command -v jq >/dev/null; then
  echo "BLOCKED: jq is not installed, so the secret check cannot read this write. Install jq." >&2
  exit 2
fi

# Prints the first pattern that an added text matches, or nothing.
# shellcheck disable=SC2016 # $ti, $t and $ARGS are jq variables
if ! hit=$(jq -s -r '
  def text: select(type == "string");
  if length == 1 then .[0] else error("not one payload") end
  | (if type == "object" then . else {} end) as $p
  | $p.tool_input as $ti
  | [ if $p.tool_name == "apply_patch" then
        ($ti | if type == "object" then (.command | text), (.input | text) else text end)
        | split("\n")[] | select(startswith("+")) | .[1:]
      else
        $ti | select(type == "object")
        | (.content | text), (.new_string | text),
          (.edits | select(type == "array") | .[] | select(type == "object") | .new_string | text)
      end ] as $t
  | first($ARGS.positional[] as $re | select(any($t[]; test($re))) | $re) // empty
' --args -- "${SECRET_PATTERNS[@]}" 2>/dev/null); then
  echo "BLOCKED: the hook payload is not one JSON value, so the secret check cannot read this write." >&2
  exit 2
fi

if [[ -n "$hit" ]]; then
  echo "BLOCKED: the content matches secret pattern '$hit'. Do not write secrets to files. Read a secret at run time with: ${HOOK_SECRET_TOOL:-<secret-tool>} <service> [field]" >&2
  exit 2
fi

exit 0
