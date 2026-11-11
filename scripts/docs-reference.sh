#!/usr/bin/env bash
# Writes the hooks reference page from each hook's header comment.
#   scripts/docs-reference.sh [OUTPUT_FILE]
# It reads hooks/*. A header is the run of comment
# lines right after the shebang line. The page says only what a header says.
# The default output is .site/reference/scripts.md (the build folder, ignored
# by git). Run `npm run docs:build` and the page is fresh.
# Exit codes: 0 written, 1 a script has no header comment, 2 wrong arguments.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR

(($# <= 1)) || {
  printf 'usage: scripts/docs-reference.sh [OUTPUT_FILE]\n' >&2
  exit 2
}
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
out=${1:-.site/reference/scripts.md}
mkdir -p -- "$(dirname -- "$out")"

# header FILE: the comment block after the shebang, with "# " removed. A
# Python script has its module docstring (a line that starts with three
# double quotes, right after the shebang line) as its header instead.
header() {
  awk '
    NR == 1 && /^#!/ { next }
    NR == 2 && /^"""/ { doc = 1 }
    doc {
      line = $0
      if (NR == 2) sub(/^"""/, "", line)
      if (line ~ /"""[[:space:]]*$/) { sub(/"""[[:space:]]*$/, "", line); print line; exit }
      print line
      next
    }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$1"
}

# fence TEXT: a code fence longer than any run of backticks in TEXT, so a
# header line of backticks cannot end the fence early.
fence() {
  local longest
  longest=$(printf '%s\n' "$1" | { grep -o '`*' || true; } | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
  ((longest < 3)) && longest=2
  printf '%*s' "$((longest + 1))" '' | tr ' ' '`'
}

section() {
  local title=$1 dir=$2 f name text ticks
  printf '## %s\n\n' "$title"
  for f in "$dir"/*; do
    [[ -f $f && ! -L $f && $f != *.test.sh ]] || continue
    name=${f##*/}
    LC_ALL=C head -n 1 -- "$f" | LC_ALL=C grep -q '^#!' || continue
    # shellcheck disable=SC2016 # backticks are Markdown, not a command
    printf '### `%s`\n\n' "$name"
    # shellcheck disable=SC2016 # backticks are Markdown, not a command
    printf 'Source: `%s`\n\n' "$f"
    text=$(header "$f")
    if [[ -z ${text//[[:space:]]/} ]]; then
      printf 'docs-reference: %s has no header comment after the shebang line\n' "$f" >&2
      return 1
    fi
    ticks=$(fence "$text")
    printf '%stext\n%s\n%s\n\n' "$ticks" "$text" "$ticks"
  done
}

{
  printf -- '---\ntitle: Hooks reference\n'
  printf 'description: Every hook, from its own header comment.\n---\n\n'
  printf 'This page is generated from the header comment of each script. '
  printf 'Do not edit it. Change the header, and the next build changes this page.\n\n'
  section 'Hooks' hooks
} >"$out"
printf 'docs-reference: wrote %s\n' "$out"
