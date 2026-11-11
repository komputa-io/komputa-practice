# Bash

```bash
#!/usr/bin/env bash
# Build mytool from main and install it on PATH. Safe to re-run. Twin: install.ps1.
#   scripts/install.sh      MYTOOL_INSTALL_DIR overrides ~/.local/bin
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}
```

## Stop at the line that failed

- **Open every script with those lines.** Without `inherit_errexit`, a failure
  part-way through `$(…)` is ignored. Without the `ERR` trap, a quiet failure
  (`grep -q`, `[[ ]]`) exits with no message.
- **Drop `-e` only on purpose, with a comment saying why**: a hook that must not
  die mid-decision (a gate that dies fails open), a health check, a harness that
  counts failures.
- **Check a status by hand wherever `-e` is off**: in an `if` or `while`
  condition, left of `&&` or `||`, after `!`, and in any function called from
  one. shellcheck's `check-set-e-suppressed` marks those calls.
- **Count with `i=$((i + 1))`.** `((i++))` returns 1 when `i` is 0, and `-e` ends
  the script.
- **Never pipe into a reader that stops early** (`| head -1`, `| grep -q`). Ask
  the command for less (`git log -1`), or search a captured string
  (`grep -q x <<<"$out"`). With long output the reader closes the pipe, the
  writer exits 141, and `pipefail` fails the script.
- **A pipe returns the exit code of its last command.** When you pipe a test
  run (`| tail`, `| grep`), check `${PIPESTATUS[0]}` or set `pipefail` before a
  commit, push or PR depends on it. This applies to one-off commands too, not
  only to scripts.
- **Capture output before looping over it** (`out=$(cmd)`, then `<<<"$out"`). A
  failure inside `< <(cmd)` is ignored even under `-e`.
- **Read an optional argument as `${1-}`.** Under `set -u` a bare `$1` dies
  before the usage can print.

## Exits and messages

- **Exit 1 through `die()` on an error, and 2 with usage on misuse**, both to
  stderr.
- **A Claude Code hook never exits 2 for misuse.** In a hook, 2 means block.
- **Every exit path names its reason.** A success prints one summary line with
  counts in and out.
- **Write data with `printf '%s\n'`. `echo` is fine for a fixed message.**
  `echo "$v"` prints nothing when `$v` is `-n`.

## Traps in the language

- **Escape a literal `&` in `${v//pat/rep}` as `\&`.** Current bash inserts the
  match there.
- **Give `ssh` inside a `while read` loop `-n`.** Without it ssh reads the loop's
  stdin, and the loop ends after the first line.
- **Homelab scripts target the bash that Debian stable ships**: no `${ cmd; }`,
  `GLOBSORT` or `source -p`, which only newer bash has.
