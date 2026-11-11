#!/bin/bash
# Feed each gate a tool payload and check its exit code: 2 blocks, 0 passes.
# Secret samples are built by concatenation so this file holds no secret.
# block-dangerous-git.sh and its tests live in komputa-practice/hooks/.

DIR=$(dirname "$0")
FAIL=0

check() { # check <want> <hook> <json>
  echo "$3" | "$DIR/$2" 2>/dev/null
  local got=$?
  if [[ "$got" != "$1" ]]; then
    echo "FAIL $2 want $1 got $got: $3"
    FAIL=1
  fi
}

bash_cmd() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
read_file() { jq -nc --arg f "$1" '{tool_name:"Read",tool_input:{file_path:$f}}'; }

key="gh""p_$(printf 'a%.0s' {1..36})"
check 2 block-secret-write.sh "$(jq -nc --arg c "token=$key" '{tool_input:{file_path:"x",content:$c}}')"
check 2 block-secret-write.sh "$(jq -nc --arg c "-----BEGIN OPENSSH ""PRIVATE KEY-----" '{tool_input:{new_string:$c}}')"
check 2 block-secret-write.sh "$(jq -nc --arg c "sk-ant-""$(printf 'b%.0s' {1..30})" '{tool_input:{edits:[{new_string:$c}]}}')"
# shellcheck disable=SC2016 # the $( ) is literal file content
check 0 block-secret-write.sh '{"tool_input":{"content":"token=$(secret-tool github token)"}}'

# block-secret-write.sh reads a Codex apply_patch: only its "+" lines.
patch() { jq -nc --arg c "$1" '{tool_name:"apply_patch",tool_input:{command:$c}}'; }
nl=$'\n'
check 2 block-secret-write.sh "$(patch "*** Begin Patch${nl}*** Add File: a.env${nl}+TOKEN=$key${nl}*** End Patch")"
check 2 block-secret-write.sh "$(patch "*** Begin Patch${nl}*** Update File: a.txt${nl}@@${nl} keep${nl}-old=1${nl}+new=$key${nl}*** End Patch")"
check 2 block-secret-write.sh "$(jq -nc --arg c "+x=$key" '{tool_name:"apply_patch",tool_input:{input:$c}}')"
check 2 block-secret-write.sh "$(jq -nc --arg c "+x=$key" '{tool_name:"apply_patch",tool_input:$c}')"
check 0 block-secret-write.sh "$(patch "*** Begin Patch${nl}*** Update File: a.txt${nl}@@${nl}-TOKEN=$key${nl}+TOKEN=\$(secret-tool github)${nl}*** End Patch")"
check 0 block-secret-write.sh "$(patch "*** Begin Patch${nl}*** Delete File: a.env${nl}*** End Patch")"
check 0 block-secret-write.sh "$(patch "*** Begin Patch${nl}*** Update File: a.txt${nl}@@${nl} TOKEN=$key${nl}+other=1${nl}*** End Patch")"
# A token split over an added line and a context line, or over two added
# lines with a context line between, is not a token in the file.
check 0 block-secret-write.sh "$(patch "*** Update File: a${nl}+${key:0:20}${nl} ${key:20}")"
check 0 block-secret-write.sh "$(patch "*** Update File: a${nl}+${key:0:20}${nl} ctx${nl}+${key:20}")"
# The same rule and message for Claude and Codex.
claude_msg=$(jq -nc --arg c "$key" '{tool_name:"Write",tool_input:{content:$c}}' | "$DIR/block-secret-write.sh" 2>&1)
codex_msg=$(patch "+$key" | "$DIR/block-secret-write.sh" 2>&1)
if [[ -z "$claude_msg" || "$claude_msg" != "$codex_msg" ]]; then
  echo "FAIL block-secret-write.sh: Claude and Codex messages differ: '$claude_msg' / '$codex_msg'"
  FAIL=1
fi
# Hostile payloads. A value of the wrong type or a missing key is not text: pass.
for p in '{}' '{"tool_input":null}' '{"tool_input":"x"}' '{"tool_input":[1]}' \
  '{"tool_input":{"content":5,"new_string":{"a":1},"edits":"x"}}' \
  '{"tool_input":{"edits":[1,"s",null,{"new_string":7}]}}' \
  '{"tool_name":7,"tool_input":{"content":null}}' '{"tool_name":"apply_patch"}' \
  '{"tool_name":"apply_patch","tool_input":{"command":42}}' \
  '{"tool_name":"apply_patch","tool_input":["+x"]}' '[1,2]' '"text"' 'null' '7'; do
  check 0 block-secret-write.sh "$p"
done
# A wrong-typed sibling does not hide a token in a right-typed key.
check 2 block-secret-write.sh "$(jq -nc --arg c "$key" '{tool_input:{content:5,edits:[1,{new_string:$c}]}}')"
# Not one JSON value: refused, since the gate cannot read it.
for p in '{bad' '' '{}{}' '{"tool_input":{"content":"x"}} trailing'; do
  check 2 block-secret-write.sh "$p"
done
# Non-UTF-8 bytes next to a token, and on their own.
check 2 block-secret-write.sh "$(printf '{"tool_input":{"content":"\xff\xfe %s \xc3"}}' "$key")"
check 2 block-secret-write.sh "$(printf '{"tool_name":"apply_patch","tool_input":{"command":"+\xff%s"}}' "$key")"
check 0 block-secret-write.sh "$(printf '{"tool_input":{"content":"\xff\xfe\xc3 plain"}}')"
# Paths with spaces and newlines: the path is never read, the added text is.
check 2 block-secret-write.sh "$(patch "*** Add File: my dir/a file.env${nl}+T=$key")"
check 0 block-secret-write.sh "$(patch "*** Add File: odd${nl}+name.txt${nl}+plain")"
check 2 block-secret-write.sh "$(jq -nc --arg c "$key" '{tool_name:"Write",tool_input:{file_path:"a b\nc.txt",content:$c}}')"
# Size: no limit. A 20 MB patch is read whole; a token at its end is found.
big=$(mktemp)
head -c 20000000 /dev/zero | tr '\0' 'a' | fold -w 100 | sed 's/^/+/' >"$big"
start=$SECONDS
check 0 block-secret-write.sh "$(jq -nc --rawfile c "$big" '{tool_name:"apply_patch",tool_input:{command:$c}}')"
printf '+T=%s\n' "$key" >>"$big"
check 2 block-secret-write.sh "$(jq -nc --rawfile c "$big" '{tool_name:"apply_patch",tool_input:{command:$c}}')"
rm -f "$big"
echo "block-secret-write.sh: two 20 MB patches in $((SECONDS - start)) s"

check 2 block-credential-read.sh "$(read_file /repo/.env)"
check 2 block-credential-read.sh "$(read_file /repo/.env.local)"
check 2 block-credential-read.sh "$(read_file /tmp/u/.ssh/id_ed25519)"
check 2 block-credential-read.sh "$(bash_cmd 'cat ~/.claude/.credentials.json')"
check 2 block-credential-read.sh "$(bash_cmd 'source .env && run')"
check 2 block-credential-read.sh "$(bash_cmd 'grep KEY .env.local')"
check 2 block-credential-read.sh "$(bash_cmd 'cat .env .env.example')"
check 0 block-credential-read.sh "$(read_file /repo/.env.example)"
check 0 block-credential-read.sh "$(read_file /tmp/u/.ssh/id_ed25519.pub)"
check 0 block-credential-read.sh "$(read_file /repo/src/environment.ts)"
check 0 block-credential-read.sh "$(bash_cmd 'secret-tool github token')"
check 0 block-credential-read.sh "$(bash_cmd 'cat .env.example')"
check 0 block-credential-read.sh "$(bash_cmd 'cp .env.example .env')"
check 0 block-credential-read.sh "$(bash_cmd 'echo A=1 > .env')"
check 0 block-credential-read.sh "$(bash_cmd 'cat > .env <<EOF')"
check 0 block-credential-read.sh "$(bash_cmd 'touch .env && ls -la')"
# Forms that print no value: counts, match tests, key names.
check 0 block-credential-read.sh "$(bash_cmd 'grep -c ^KEY= .env; stat -c %a .env')"
check 0 block-credential-read.sh "$(bash_cmd 'grep -q ^KEY= .env && echo present')"
check 0 block-credential-read.sh "$(bash_cmd "grep -o '^[A-Z_]*' .env")"
check 0 block-credential-read.sh "$(bash_cmd "grep -oE '^[A-Za-z_][A-Za-z0-9_]*' .env")"
check 0 block-credential-read.sh "$(bash_cmd 'cut -d= -f1 .env')"
check 0 block-credential-read.sh "$(bash_cmd "sed 's/=.*//' .env")"
check 0 block-credential-read.sh "$(bash_cmd "awk -F= '{print \$1}' .env")"
check 0 block-credential-read.sh "$(bash_cmd 'cat .env | cut -d= -f1')"
check 0 block-credential-read.sh "$(bash_cmd 'cat .env | wc -l')"
check 0 block-credential-read.sh "$(bash_cmd "ssh h 'pct exec 1 -- sh -c \"cd /x && grep -c K= .env\"'")"
check 0 block-credential-read.sh "$(bash_cmd 'grep -rn foo src/ && stat .env')"
# Still refused: anything that can print a value.
check 2 block-credential-read.sh "$(bash_cmd "grep -o '^[A-Z_]*=.*' .env")"
check 2 block-credential-read.sh "$(bash_cmd "grep -o '^[[:print:]]*' .env")"
check 2 block-credential-read.sh "$(bash_cmd 'cut -d= -f2 .env')"
check 2 block-credential-read.sh "$(bash_cmd 'cut -d= -f1- .env')"
check 2 block-credential-read.sh "$(bash_cmd 'grep -c K .env; cat .env')"
check 2 block-credential-read.sh "$(bash_cmd 'cat .env | sort')"
check 2 block-credential-read.sh "$(bash_cmd "ssh h 'cat /opt/x/.env'")"
check 2 block-credential-read.sh "$(bash_cmd "ssh h 'sh -c \"grep -c K .env && head .env\"'")"
check 2 block-credential-read.sh "$(bash_cmd 'cat ~/.ssh/id_ed25519 | cut -d= -f2')"
# Key-name forms print the whole line of a file that is not KEY=VALUE.
check 2 block-credential-read.sh "$(bash_cmd 'cut -d= -f1 ~/.ssh/id_ed25519')"
check 2 block-credential-read.sh "$(bash_cmd 'cat ~/.netrc | cut -d= -f1')"
check 2 block-credential-read.sh "$(bash_cmd "sed 's/=.*//' ~/.claude/.credentials.json")"
check 0 block-credential-read.sh "$(bash_cmd 'grep -c machine ~/.netrc')"

[[ "$FAIL" = 0 ]] && echo "all hook tests pass"
exit $FAIL
