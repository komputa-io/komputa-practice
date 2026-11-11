#!/usr/bin/env bash
# Tests for scripts/docs-reference.sh. Each case copies the script into a
# throwaway tree, adds a script with a given header, and checks the page.
#   scripts/tests/docs-reference.test.sh
set -Eeuo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
gen=$(cd -- "$here/.." && pwd)/docs-reference.sh
root=$(mktemp -d "${TMPDIR:-/tmp}/docs-ref-test.XXXXXX")
trap 'rm -rf -- "$root"' EXIT

pass=0 fail=0
ok() {
  pass=$((pass + 1))
  printf 'ok    %s\n' "$1"
}
bad() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
}

n=0
# newtree: a tree with the generator and one script; sets $tree.
newtree() {
  n=$((n + 1))
  tree=$root/t$n
  mkdir -p "$tree/scripts" "$tree/hooks"
  cp -- "$gen" "$tree/scripts/docs-reference.sh"
}
# build: run the generator in $tree; sets $rc.
build() {
  rc=0
  bash "$tree/scripts/docs-reference.sh" "$tree/out.md" >/dev/null 2>"$tree/err" || rc=$?
}

newtree
# shellcheck disable=SC2016 # backticks are test data, not a command
printf '#!/usr/bin/env bash\n# Does a thing.\n# ```\n# <script>x</script>\n# ````\n# More.\nexit 0\n' >"$tree/hooks/evil.sh"
build
# The fence must be longer than the longest run (4), so 5 backticks open and close it.
opens=$(grep -c -x '`````text' "$tree/out.md" || true)
closes=$(grep -c -x '`````' "$tree/out.md" || true)
if ((rc == 0 && opens == 1 && closes == 1)) && grep -q -x '```' "$tree/out.md"; then
  ok "a header line of backticks stays inside a longer fence"
else
  bad "a header line of backticks stays inside a longer fence (rc=$rc opens=$opens closes=$closes)"
fi

newtree
printf '#!/usr/bin/env bash\n# Plain header.\nexit 0\n' >"$tree/hooks/plain.sh"
build
if ((rc == 0)) && grep -q -x '```text' "$tree/out.md"; then
  ok "a plain header gets a three-backtick fence"
else
  bad "a plain header gets a three-backtick fence (rc=$rc)"
fi

newtree
printf '#!/usr/bin/env bash\nexit 0\n' >"$tree/hooks/bare.sh"
build
if ((rc != 0)) && grep -q 'bare.sh' "$tree/err"; then
  ok "a script with no header comment fails the build and names the script"
else
  bad "a script with no header comment fails the build and names the script (rc=$rc)"
fi

newtree
printf '#!/usr/bin/env bash\n\n# A comment after a blank line is not a header.\nexit 0\n' >"$tree/hooks/blank.sh"
build
if ((rc != 0)); then
  ok "a blank line after the shebang line means no header, and fails"
else
  bad "a blank line after the shebang line means no header, and fails"
fi

newtree
printf '#!/usr/bin/env python3\n"""Python doc line.\n\nMore text.\n"""\nimport os\n' >"$tree/hooks/py"
build
if ((rc == 0)) && grep -q '^Python doc line\.' "$tree/out.md" && ! grep -q 'import os' "$tree/out.md"; then
  ok "a Python module docstring is the header"
else
  bad "a Python module docstring is the header (rc=$rc)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
