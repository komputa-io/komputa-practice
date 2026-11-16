#!/bin/bash
# shellcheck disable=SC2016,SC2088 # single-quoted payloads are literal commands to judge
# Feed block-foreground-wait.sh payloads and check its exit code: 2 blocks, 0 passes.
#   block-foreground-wait.test.sh [hook]   (default: the hook beside it)
DIR=$(cd "$(dirname "$0")" && pwd)
HOOK=${1:-$DIR/block-foreground-wait.sh}
FAIL=0 RUN=0
STUB=$(mktemp -d)
trap 'rm -rf -- "$STUB"' EXIT
printf '#!/bin/bash\n[[ $1 == get && -n ${STUB_HC-} ]] || exit 1\nprintf "%%s" "$STUB_HC"\n' >"$STUB/hc"
chmod +x "$STUB/hc"

check() { # check <want> <worker: 1|0> <command> [background: true|false]
  local got err hcjson payload
  RUN=$((RUN + 1))
  if [[ $2 == 1 ]]; then hcjson='{"parent":"t1","template":"owner"}'; else hcjson='{"parent":null,"template":null}'; fi
  payload=$(jq -nc --arg c "$3" --argjson b "${4:-false}" '{tool_name: "Bash", tool_input: {command: $c, run_in_background: $b}}')
  err=$(printf '%s' "$payload" | HC_TERMINAL_ID=t9 STUB_HC="$hcjson" PATH="$STUB:$PATH" "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [[ $got != "$1" ]]; then
    echo "FAIL want $1 got $got: ${3:0:200}"
    FAIL=$((FAIL + 1))
  elif [[ $got == 2 && ($err != BLOCKED* || $err == *$'\n'* || $err != *background*) ]]; then
    echo "FAIL a refusal must be one BLOCKED line that names the background fix, got: $err"
    FAIL=$((FAIL + 1))
  fi
}

check 2 1 'gh pr checks 311 --watch'
check 2 1 'sleep 40; timeout 540 gh pr checks 311 --watch'
check 2 1 'gh run watch 123'
check 2 1 '~/.config/herdr-core/merge-on-green 311 0123456789abcdef0123456789abcdef01234567'
check 2 1 'hc wait t1p2'
check 2 1 'git push && sleep 2m'
check 2 1 'sleep 11'
check 0 1 'sleep 5 && ls'
check 0 1 'sleep 10'
check 0 1 'gh pr checks 311'
check 0 1 'git commit -m "mention gh pr checks --watch and sleep 40"'
check 0 1 '~/.config/herdr-core/merge-on-green 311 0123456789abcdef0123456789abcdef01234567' true
check 0 1 'sleep 40; gh pr checks 311 --watch' true
check 2 1 'until gh pr checks 311 | grep -q pass; do sleep 5; done' true
check 2 1 'while true; do curl -s localhost; sleep 5; done' true
check 0 1 'timeout 600 bash -c '"'"'until gh pr checks 311 | grep -q pass; do sleep 5; done'"'"'' true
check 0 1 'for i in $(seq 1 60); do gh pr checks 311 | grep -q pass && break; sleep 5; done' true
check 0 1 'while IFS= read -r l; do echo "$l"; done < file' true
check 0 0 'gh pr checks 311 --watch'
check 0 0 'until false; do sleep 1; done' true
if ((FAIL == 0)); then echo "block-foreground-wait: $RUN checks passed"; else
  echo "block-foreground-wait: $FAIL of $RUN failed"
  exit 1
fi
