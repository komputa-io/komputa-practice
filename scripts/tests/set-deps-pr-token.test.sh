#!/bin/bash
# Tests for scripts/set-deps-pr-token.sh with a stub gh: the token is on no argv and in no output.
#   scripts/tests/set-deps-pr-token.test.sh
DIR=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
FAIL=0
mkdir "$T/bin"
cat >"$T/bin/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG.argv"
cat >>"$STUB_LOG.stdin"
STUB
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" STUB_LOG="$T/log"
out=$(printf 'tok-SECRET-123' | "$DIR/set-deps-pr-token.sh" --apply o/a o/b 2>&1)
[[ $(grep -c 'secret set DEPS_PR_TOKEN --repo' "$T/log.argv") == 2 ]] || {
  echo "FAIL gh not called once per repo"
  FAIL=1
}
[[ $(cat "$T/log.stdin") == 'tok-SECRET-123tok-SECRET-123' ]] || {
  echo "FAIL token not on gh stdin"
  FAIL=1
}
grep -q SECRET "$T/log.argv" && {
  echo "FAIL token on an argv"
  FAIL=1
}
[[ $out == *SECRET* ]] && {
  echo "FAIL token printed"
  FAIL=1
}
rm -f "$T"/log.*
"$DIR/set-deps-pr-token.sh" o/a >/dev/null </dev/null
[[ ! -e "$T/log.argv" ]] || {
  echo "FAIL dry run called gh"
  FAIL=1
}
((FAIL)) && exit 1
echo "ok"
