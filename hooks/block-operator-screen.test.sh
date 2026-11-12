#!/bin/bash
# shellcheck disable=SC2016 # single-quoted payloads are literal commands to judge
# Feed block-operator-screen.sh payloads and check its exit code: 2 blocks, 0 passes.
#   block-operator-screen.test.sh [hook]   (default: the hook beside it)
DIR=$(cd "$(dirname "$0")" && pwd)
HOOK=${1:-$DIR/block-operator-screen.sh}
FAIL=0 RUN=0
STUB=$(mktemp -d)
trap 'rm -rf -- "$STUB"' EXIT
printf '#!/bin/bash\n[[ $1 == get && -n ${STUB_HC-} ]] || exit 1\nprintf "%%s" "$STUB_HC"\n' >"$STUB/hc"
chmod +x "$STUB/hc"
# terminal <worker: 1|0> [prune label]: what hc get says about the hook's own terminal.
terminal() {
  if [[ $1 == 1 ]]; then
    jq -nc --arg p "${2-}" '{parent: "t1", template: "owner", labels: (if $p == "" then {} else {"test-prune": $p} end)}'
  else
    jq -nc '{parent: null, template: null, labels: {}}'
  fi
}

check() { # check <want> <worker: 1|0> <json>
  local got err
  RUN=$((RUN + 1))
  err=$(printf '%s' "$3" | HC_TERMINAL_ID=t9 STUB_HC="$(terminal "$2")" PATH="$STUB:$PATH" "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [[ $got != "$1" ]]; then
    echo "FAIL want $1 got $got: ${3:0:200}"
    FAIL=$((FAIL + 1))
  elif [[ $got == 2 && ($err != BLOCKED* || $err == *$'\n'*) ]]; then
    echo "FAIL a refusal must be one BLOCKED line, got: $err"
    FAIL=$((FAIL + 1))
  fi
}
bash_pl() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
blocks() { check 2 1 "$(bash_pl "$1")"; }
passes() { check 0 1 "$(bash_pl "$1")"; }

blocks 'xdg-open http://localhost:1337/admin'
blocks 'cd app && xdg-open index.html'
blocks 'echo done; gio open http://127.0.0.1:3000'
blocks 'open http://localhost:3000'
blocks 'sensible-browser http://localhost'
blocks 'FOO=1 xdg-open x.html'
blocks 'env BROWSER=x xdg-open x.html'
blocks 'nohup xdg-open x.html &'
blocks '(xdg-open http://localhost)'
blocks 'x=$(xdg-open http://localhost)'
blocks "bash -c 'xdg-open http://localhost'"
blocks 'sh -c "open http://localhost"'
blocks 'python3 -m webbrowser http://localhost:3000'
blocks 'python -c "import webbrowser; webbrowser.open(1)"'
blocks 'google-chrome http://localhost:3000'
blocks 'chromium --new-window http://localhost'
blocks 'firefox http://localhost'
blocks 'npx playwright test --headed'
blocks 'PWDEBUG=1 node run.js --headed'
blocks 'node -e "chromium.launch({ headless: false })"'
blocks 'node -e "chromium.launch({headless:false})"'

passes 'google-chrome --headless --screenshot=a.png http://localhost:3000'
passes 'chromium --headless=new --dump-dom http://localhost'
passes 'curl http://localhost:1337/admin'
passes 'git commit -m "fix xdg-open handling"'
passes 'echo "run xdg-open later"'
passes 'grep -r open src/'
passes 'docker compose open'
passes 'npx playwright test'
passes 'npm run dev'
passes 'BROWSER=none npm run dev'
passes 'ls /usr/bin/google-chrome'
passes 'git commit -m "open the door"'
passes "bash -c 'echo hi'"

for t in navigate tabs_create_mcp computer read_page javascript_tool; do
  check 2 1 "$(jq -nc --arg t "mcp__claude-in-chrome__$t" '{tool_name:$t,tool_input:{url:"http://localhost:1337"}}')"
done
check 0 1 '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
check 0 1 '{"tool_name":"mcp__other__navigate","tool_input":{}}'

# Not a worker: nothing is touched, even a browser open.
check 0 0 "$(bash_pl 'xdg-open http://localhost')"
check 0 0 '{"tool_name":"mcp__claude-in-chrome__navigate","tool_input":{}}'
# Who is a worker: hc get on the hook's own terminal. A parent alone is enough; outside an hc terminal
# nothing is a worker; when hc cannot answer, the call is refused.
# with_env <want> <json> <env assignment...>
with_env() {
  local want=$1 pl=$2 got err
  shift 2
  RUN=$((RUN + 1))
  err=$(printf "%s" "$pl" | env "$@" PATH="$STUB:$PATH" "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [[ $got != "$want" || ($got == 2 && $err != BLOCKED*) ]]; then
    echo "FAIL want $want got $got with $*: $err"
    FAIL=$((FAIL + 1))
  fi
}
open_pl=$(bash_pl 'xdg-open http://localhost')
with_env 2 "$open_pl" HC_TERMINAL_ID=t9 STUB_HC='{"parent":"t1","template":null,"labels":{}}'
with_env 0 "$open_pl" -u HC_TERMINAL_ID STUB_HC="$(terminal 1)"
with_env 2 "$open_pl" -u STUB_HC HC_TERMINAL_ID=t9
# A worker with a payload that is not JSON: refused.
check 2 1 'not json'

echo "$RUN cases, $FAIL failed"
[[ $FAIL == 0 ]] && echo "all screen-gate tests pass"
((FAIL == 0))
