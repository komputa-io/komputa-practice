#!/bin/bash
# shellcheck disable=SC2016 # single-quoted payloads are literal commands to judge
# Feed block-destructive-delete.sh Bash tool payloads and check its exit code:
# 2 blocks, 0 passes. The hook runs by its path, so a lost exec bit fails
# every case. It runs in a scratch home with its own checkouts, so no real
# path is judged.
#   block-destructive-delete.test.sh [hook]   (default: the hook beside it)

DIR=$(cd "$(dirname "$0")" && pwd)
HOOK=${1:-$DIR/block-destructive-delete.sh}
FAIL=0 RUN=0

root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
home=$root/home
tmpd=$root/tmp
uid=$(id -u)
slug=-work-slug
sid=0f1e2d3c-aaaa-bbbb-cccc-123456789abc
scratch=$tmpd/claude-$uid/$slug/$sid/scratchpad
mkrepo() { mkdir -p "$1" && git init -q "$1"; }
mkrepo "$home/Code/work"
mkrepo "$home/Code/sib"
mkrepo "$home/Code/my repo"
mkrepo "$home/Code/clients/acme/app"
mkrepo "$home/Code/work/worktrees/wt"
git init -q --bare "$home/Code/bare.git"
mkdir -p "$home/Documents/notes" "$home/.config/x" "$home/Code/sib/build" \
  "$home/Code/work/build/sub" "$home/Code/work/dir with space" "$scratch/x" \
  "$tmpd/claude-$uid/$slug/other-session/scratchpad" "$root/plain/a"
touch "$home/Code/sib/file.txt"
ln -s "$home/Code/sib" "$home/Code/work/out"
work=$home/Code/work

check() { # check <want> <json> [cwd for the hook process]
  local got err
  RUN=$((RUN + 1))
  err=$(cd "${3:-$work}" && printf '%s' "$2" | HOME=$home CLAUDE_CODE_TMPDIR=$tmpd "$HOOK" 2>&1 >/dev/null)
  got=$?
  printf '%s\n' "$err" >>"$root/stderr"
  if [[ $got != "$1" ]]; then
    echo "FAIL want $1 got $got: ${2:0:300}"
    FAIL=$((FAIL + 1))
  elif [[ $got == 2 && ($err != BLOCKED* || $err == *$'\n'*) ]]; then
    echo "FAIL a refusal must be one BLOCKED line, got: $err"
    FAIL=$((FAIL + 1))
  fi
}
pl() { # pl <command> [cwd]: a Claude Code Bash payload
  jq -nc --arg c "$1" --arg d "${2:-$work}" --arg s "$sid" \
    --arg t "$home/.claude/projects/$slug/$sid.jsonl" \
    '{session_id:$s,transcript_path:$t,cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'
}
blocks() { check 2 "$(pl "$1" "${2:-$work}")"; }
passes() { check 0 "$(pl "$1" "${2:-$work}")"; }

# rm -r of a sibling checkout: every flag order and spelling.
for flags in -rf -fr -Rf -rF -r '-r -f' '-f -R' --recursive '--recursive --force' \
  '--force --recursive' --rec -rfv '-v -r' '-rf --' '--no-preserve-root -rf' '-rf --one-file-system'; do
  blocks "rm $flags $home/Code/sib"
done
blocks 'rm -rf ../sib'
blocks 'rm -rf -- ../sib'
blocks 'rm -rf build ../sib'
blocks "rm -rf '../my repo'"
blocks 'rm -rf "../my repo"'
blocks 'rm -rf ../my\ repo'
blocks "rm -rf $home/Code/bare.git"
# Near misses: not recursive, or a single file.
passes "rm $home/Code/sib"
passes "rm -f $home/Code/sib/file.txt"
passes 'rm -d ../sib'
passes 'rmdir ../sib'

# ~ and $HOME forms, and paths directly under home.
blocks 'rm -rf ~/Code/sib'
# shellcheck disable=SC2016 # literal $HOME the hook must expand
{
  blocks 'rm -rf $HOME/Code/sib'
  blocks 'rm -rf "$HOME/Code/sib"'
  blocks 'rm -rf ${HOME}/Code/sib'
  blocks 'rm -rf "${HOME}"/Documents'
  passes 'rm -rf "$tmp"'
  passes 'rm -rf "$HOME_OLD/x"'
  passes 'rm -rf $(mktemp -d)'
}
blocks 'rm -rf ~/Documents'
blocks 'rm -rf ~/.config'
blocks 'rm -rf ~/not-made-yet'
blocks 'rm -rf ~/Documents/'
blocks 'rm -rf ~/Code/clients'
passes 'rm -rf ~/Documents/notes'
passes 'rm -rf ~nosuchuser/Code/sib'
passes 'rm -rf ~/Code/sib/build'

# Inside the checkout, and the built-in's own targets.
passes 'rm -rf build'
passes 'rm -rf ./build/sub'
passes "rm -rf $work/build"
passes "rm -rf '$work/dir with space'"
passes 'rm -rf worktrees/wt'
passes 'rm -rf build/*'
passes "rm -rf $work"
passes 'rm -rf .'
passes 'rm -rf ~'
passes 'rm -rf /'
passes "rm -rf $root/plain/a"
passes 'git rm -rf build'
passes 'git rm -r --cached ../sib'

# A .git folder holds unpushed commits: refused anywhere but the session's own folder.
blocks 'rm -rf .git'
blocks 'rm -rf ../sib/.git'
blocks 'rm -rf ./build/../.git/'
passes 'rm -rf .github'

# Symlinks and .. segments.
blocks 'rm -rf out/'
blocks 'rm -rf out/.'
passes 'rm -rf out'
blocks "rm -rf $work/../sib"
blocks 'rm -rf ./build/../../sib'
blocks 'rm -rf build/sub/../../../sib/'
passes 'rm -rf build/sub/..'

# Globs, {a,b} lists and a redirect glued to the target.
blocks 'rm -rf ~/Code/{x,sib}'
blocks 'rm -rf ../{a,b}/../sib'
blocks 'rm -rf ../sib>/dev/null'
blocks 'busybox rm -rf ../sib'
passes 'rm -rf build/{a,b}'
passes 'rm -rf ~/Code/{1..3}'
blocks 'rm -rf ~/Code/*'
blocks 'rm -rf ../s*'
blocks 'rm -rf ../[s]ib'
blocks 'rm -rf ../nomatch*' # a glob outside the checkout, matched or not

# cd, pushd, env -C and git -C earlier in the same command.
blocks "cd $home/Code && rm -rf sib"
blocks 'cd .. && rm -rf sib'
blocks 'cd ~/Code; rm -rf sib'
blocks 'pushd ~/Code >/dev/null && rm -rf sib'
blocks '(cd .. && rm -rf sib)'
blocks 'env -C .. rm -rf sib'
blocks "git -C $home/Code/sib rm -rf ."
blocks 'cd ../sib && rm -rf .'
passes 'cd ../sib && rm -rf build'
passes 'cd .. && rm -rf work/build'
passes 'cd - && rm -rf sib'

# Prefixes: sudo, env and other wrappers.
blocks 'sudo rm -rf ../sib'
blocks 'sudo -u alice rm -rf ../sib'
blocks 'sudo -n -E rm -rf ../sib'
blocks 'sudo -- rm -rf ../sib'
blocks 'env rm -rf ../sib'
blocks 'env FOO=1 BAR=2 rm -rf ../sib'
blocks 'env -i -u X rm -rf ../sib'
blocks "env -S 'rm -rf ../sib'"
blocks 'FOO=1 rm -rf ../sib'
blocks 'sudo -u alice env X=1 rm -rf ../sib'
blocks 'nice -n 5 ionice -c 3 rm -rf ../sib'
blocks 'timeout -s KILL 30 rm -rf ../sib'
blocks 'nohup rm -rf ../sib'
blocks 'command rm -rf ../sib'
blocks 'exec rm -rf ../sib'
blocks 'time rm -rf ../sib'
blocks '\rm -rf ../sib'
blocks '/usr/bin/rm -rf ../sib'
blocks 'xargs -n 1 rm -rf ../sib'
passes 'echo rm -rf ../sib'
passes 'sudo ls ../sib'
passes 'xargs -I{} rm -rf {}'

# Lists, pipes, subshells, substitutions and shells.
blocks 'git status; rm -rf ../sib'
blocks 'true && rm -rf ../sib'
blocks 'false || rm -rf ../sib'
blocks 'echo y | rm -rf ../sib'
blocks 'rm -rf ../sib &'
blocks "$(printf 'ls\nrm -rf ../sib')"
blocks '{ rm -rf ../sib; }'
blocks 'if true; then rm -rf ../sib; fi'
blocks 'for d in a; do rm -rf ../sib; done'
# shellcheck disable=SC2016 # literal substitutions the hook must see run
{
  blocks 'echo $(rm -rf ../sib)'
  blocks 'echo `rm -rf ../sib`'
  blocks 'odev issue create --body "$(rm -rf ../sib)"'
}
blocks "bash -c 'rm -rf ../sib'"
blocks 'sh -c "cd .. && rm -rf sib"'
blocks "eval 'rm -rf ../sib'"
blocks 'eval rm -rf ../sib'
blocks "su -c 'rm -rf ../sib'"
blocks "$(printf 'bash <<EOF\nrm -rf ../sib\nEOF')"
blocks "$(printf 'cat <<EOF | sh\nrm -rf ../sib\nEOF')"
blocks "$(printf 'cat <<EOF\nx\nEOF\nrm -rf ../sib')"
blocks "bash -c \"bash -c 'rm -rf ../sib'\""
passes "ssh host 'rm -rf /srv/sib'"

# Quoted and heredoc text that only mentions a delete is data.
passes 'odev issue create --body "never run rm -rf ~/Code/sib"'
passes "git commit -m 'gate: block gh repo delete and rm -rf ../sib'"
passes 'grep -rn "rm -rf" .'
passes "printf '%s' 'curl -X DELETE https://api.github.com/repos/o/r'"
passes 'echo "docmost delete-space -s eng"'
passes "$(printf "cat > n.md <<'EOF'\nrm -rf ~/Code/sib\ngh repo delete o/r --yes\nodev api -X DELETE projects/42\nEOF")"
passes "$(printf 'python3 - <<EOF\nimport os\nos.system("rm -rf ~/Code/sib")\nEOF')"
passes "hc send t4w 'do not rm -rf ../sib or docmost delete-space'"

# The session's own folder passes; another session's, or the root, does not.
passes "rm -rf $scratch/x"
passes "rm -rf $scratch/x/.git"
passes "rm -rf $scratch"
passes "rm -rf $tmpd/claude-$uid/$slug/$sid"
blocks "rm -rf $tmpd/claude-$uid/$slug/other-session"
blocks "rm -rf $tmpd/claude-$uid/$slug/other-session/scratchpad"
blocks "rm -rf $tmpd/claude-$uid"
blocks "rm -rf $scratch/../../other-session"

# Forge and wiki deletes.
blocks 'odev api -X DELETE projects/42'
blocks 'odev api -XDELETE /projects/42/'
blocks 'odev api --method DELETE projects/42'
blocks 'odev api --method=delete "projects/42?force=true"'
blocks 'odev --host https://git.example api -X DELETE projects/42'
blocks 'env ODEV_TOKEN=x odev api -X DELETE projects/42'
blocks 'curl -X DELETE https://forge.example/api/projects/42'
blocks 'curl -sSX DELETE -H "Authorization: token x" https://forge.example/api/projects/42'
blocks 'curl --request DELETE https://api.github.com/repos/o/r'
blocks 'curl --request=DELETE https://api.github.com/orgs/acme'
blocks 'curl -XDELETE https://gitea.example/api/v1/repos/o/r/'
blocks 'curl -X delete https://gitlab.example/api/v4/groups/7'
blocks 'wget --method=DELETE https://gitlab.example/api/v4/projects/7'
blocks 'wget -q --method DELETE https://gitea.example/api/v1/orgs/acme'
blocks 'http DELETE https://api.github.com/repos/o/r'
blocks 'xh delete https://gitea.example/api/v1/repos/o/r'
blocks 'curl -X POST https://wiki.example/api/spaces/delete -d "{\"spaceId\":\"1\"}"'
blocks 'gh repo delete o/r --yes'
blocks 'gh repo delete'
blocks 'gh api -X DELETE repos/o/r'
blocks 'gh api --method DELETE /orgs/acme'
blocks 'gh api repos/{owner}/{repo} -X DELETE'
blocks 'glab repo delete g/p --yes'
blocks 'glab api -X DELETE projects/7'
blocks 'tea repo delete --repo o/r'
blocks 'tea repos delete o/r'
blocks 'docmost delete-space -s eng'
blocks 'docmost --json delete-space --space eng'
blocks 'docmost --url https://wiki.example delete-space -s eng'
blocks 'sudo docmost delete-space -s eng'
blocks "ssh host 'gh repo delete o/r --yes'"
blocks "bash -c 'odev api -X DELETE projects/42'"
# shellcheck disable=SC2016 # a literal substitution
blocks 'echo "$(gh repo delete o/r --yes)"'
# Near misses: reads, writes, and deletes of a part of a project.
passes 'odev api projects/42'
passes 'odev api -X POST projects/42'
passes 'odev api -X DELETE projects/42/labels/3'
passes 'odev api -X DELETE issues/5'
passes 'curl https://api.github.com/repos/o/r'
passes 'curl -X DELETE https://api.github.com/repos/o/r/issues/comments/1'
passes 'curl -X PATCH https://api.github.com/repos/o/r'
passes 'curl -x proxy:8080 https://api.github.com/repos/o/r'
passes 'gh repo view o/r'
passes 'gh api repos/o/r'
passes 'gh api -X DELETE repos/o/r/git/refs/heads/old'
passes 'glab repo view g/p'
passes 'tea repos list'
passes 'docmost delete-page --page-id 1'
passes 'docmost list-spaces'
passes 'docmost search -q delete-space -s eng'
passes 'http GET https://api.github.com/repos/o/r'

# Git branch and worktree removals belong to block-dangerous-git.sh.
passes 'git branch -D old'
passes 'git worktree remove ../sib'

# Payload shape: wrong types, missing keys, malformed JSON.
check 2 '{'
check 2 '{"tool_name":"Bash"}{"tool_name":"Bash"}'
check 2 ''
check 2 '[]'
check 2 '"rm -rf ../sib"'
check 2 'null'
check 2 '{"tool_name":"Bash"}'
check 2 '{"tool_name":"Bash","tool_input":"rm -rf ../sib"}'
check 2 '{"tool_name":"Bash","tool_input":{"command":42}}'
check 2 '{"tool_name":"Bash","tool_input":{"command":["rm","-rf","../sib"]}}'
check 2 '{"tool_name":"Bash","tool_input":{"command":null}}'
check 0 '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
check 0 '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
check 2 "$(jq -nc --arg d "$work" '{tool_name:5,cwd:$d,tool_input:{command:"rm -rf ../sib"}}')"
check 0 "$(jq -nc --arg d "$work" '{tool_name:5,cwd:$d,tool_input:{command:"rm -rf build"}}')"
check 2 "$(jq -nc '{tool_name:"Bash",cwd:7,tool_input:{command:"rm -rf ../sib"}}')" "$work"
check 0 "$(jq -nc '{tool_name:"Bash",cwd:7,tool_input:{command:"rm -rf build"}}')" "$work"
check 2 "$(jq -nc --arg c "rm -rf ../sib" '{tool_name:"Bash",cwd:"/no/such/dir",tool_input:{command:$c}}')" "$work"
# Without a usable session_id or transcript_path the scratchpad is not ours.
check 2 "$(pl "rm -rf $scratch/x" | jq -c '.session_id = 5')"
check 2 "$(pl "rm -rf $scratch/x" | jq -c 'del(.transcript_path)')"
check 2 "$(pl "rm -rf $scratch/x" | jq -c '.session_id = ".."')"
check 2 "$(pl "rm -rf $scratch/x" | jq -c '.transcript_path = "x/../../\(.session_id).jsonl"')"

# Bytes that are not UTF-8 (jq reads them as U+FFFD), and NUL escapes.
check 2 "$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"rm -rf ../sib \xff\xfe"}}' "$work")"
check 0 "$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"rm -rf build/\xff"}}' "$work")"
check 2 "$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"rm -rf ../sib\\u0000"}}' "$work")"

# A very long command: 1 MB of other commands, then the delete. The payload
# is too big for an argument, so it goes through a file.
long() { # long <want> <tail>
  printf 'echo x; %.0s' $(seq 1 131072) >"$root/long"
  printf '%s' "$2" >>"$root/long"
  jq -nc --rawfile c "$root/long" --arg d "$work" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' >"$root/long.json"
  RUN=$((RUN + 1))
  (cd "$work" && HOME=$home CLAUDE_CODE_TMPDIR=$tmpd "$HOOK" <"$root/long.json" 2>/dev/null)
  local got=$?
  [[ $got == "$1" ]] || {
    echo "FAIL want $1 got $got: 1 MB command ending in $2"
    FAIL=$((FAIL + 1))
  }
}
start=$SECONDS
long 2 'rm -rf ../sib'
long 0 'rm -rf build'
long 0 'ls'
echo "three 1 MB commands judged in $((SECONDS - start)) s"
((SECONDS - start > 60)) && {
  echo "FAIL the 1 MB commands took $((SECONDS - start)) s"
  FAIL=$((FAIL + 1))
}

# The Codex payload shape: same keys, a Codex transcript path.
codex() {
  jq -nc --arg c "$1" --arg d "$work" '{session_id:"019a0000-0000-7000-8000-000000000000",
    transcript_path:"/x/.codex/sessions/2026/11/02/rollout-2026-11-02T09-00-00-019a.jsonl",
    cwd:$d,hook_event_name:"PreToolUse",model:"gpt-5.5",permission_mode:"bypassPermissions",
    tool_name:"Bash",tool_input:{command:$c},tool_use_id:"call_1",turn_id:"t1"}'
}
check 2 "$(codex 'rm -rf ../sib')"
check 2 "$(codex 'gh repo delete o/r --yes')"
check 0 "$(codex 'rm -rf build')"
check 0 "$(codex 'ls -la')"

# Quotes inside a word do not hide it.
blocks 'r"m" -rf ../sib'

# A line continuation joins the words.
blocks "$(printf 'rm -rf \\\n  ../sib')"
blocks "$(printf 'rm \\\n  -rf ../sib')"
blocks "$(printf 'gh repo \\\n  delete o/r')"
# Anything under a .git folder is its history.
blocks 'rm -rf .git/objects'
blocks 'rm -rf .git/*'
blocks 'rm -rf ../sib/.git/refs'
passes 'rm -rf .github/x'
passes "rm -rf $scratch/x/.git/objects"
# Text that looks like a heredoc or a quote does not hide a later command.
blocks "$(printf 'cat <<<foo\nrm -rf ../sib')"
blocks "$(printf 'echo "<<EOF"\nrm -rf ../sib')"
blocks "$(printf 'echo hi # <<EOF\nrm -rf ../sib')"
blocks "$(printf '(( a<<b ))\nrm -rf ../sib')"
blocks "$(printf "echo 'x\n<<EOF\n'\nrm -rf ../sib")"
blocks "$(printf "# do not, it's bad\nrm -rf ../sib")"
passes "$(printf 'cat > n.md <<"EOF"\nrm -rf ../sib\nEOF')"
passes '# rm -rf ../sib'

# A backslash joins lines only where the shell joins them.
blocks "$(printf '# note \\\nrm -rf ../sib')"
blocks "$(printf 'echo a\\\\\nrm -rf ../sib')"
blocks "$(printf "cat <<'EOF'\nfoo\\\\\nEOF\nrm -rf ../sib")"
blocks 'echo ${x:-$(echo }) # }; rm -rf .git'
blocks '[[ a == # ]]; rm -rf ../sib'
# A continuation inside a word, a quoted newline and a false comment.
blocks "$(printf 'r\\\nm -rf .git/objects')"
blocks "$(printf 'gh repo de\\\nlete a/b')"
blocks "$(printf "bash -c '# x\nrm -rf ../sib'")"
blocks 'echo \ # ; rm -rf ../sib'
blocks 'echo ${x:- #}; rm -rf ../sib'
blocks "ash -c 'rm -rf ../sib'"
blocks "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nIt'"'"'s done\nEOF\n)" && gh repo delete a/b')"
passes "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nnever rm -rf ../sib\nEOF\n)"')"

# A long list of targets (issue #21): up to the limit it is judged, and quickly; past it the gate refuses,
# because a hook that outlasts its timeout lets the delete run.
# The payload goes through a file: a 300 KB command is more than one argument can hold.
many() { seq 1 "$1" | sed "s|^|$work/gen/f|" | tr '\n' ' '; }
bigpl() { # bigpl <command-prefix> <count> [suffix]
  printf '%s%s%s' "$1" "$(many "$2")" "${3:-}" >"$root/big.txt"
  jq -nc --rawfile c "$root/big.txt" --arg d "$work" --arg s "$sid" \
    '{session_id:$s,cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'
}
start=$SECONDS
check 0 "$(bigpl 'rm -rf ' 3000)"
((SECONDS - start < 15)) || {
  echo "FAIL 3000 targets took $((SECONDS - start)) s"
  FAIL=1
}
check 2 "$(bigpl 'rm -rf ' 6000)"
check 2 "$(bigpl 'rm -rf ' 3000 "$home/Code/sib")"
check 2 "$(bigpl 'git rm -rf ' 6000)"
check 0 "$(bigpl 'rm ' 6000)"

# A glob outside the checkout and the session folder (the 2026-11-16 incident); the
# allowed cases beside it keep agents moving.
for c in "rm -f $tmpd/x[0-9]*" "rm $tmpd/*.log" 'rm -f ~/notes/*.md' "rm -rf $home/Code/sib/build/*" \
  'rm -f $TMPDIR/x*' 'rm -f "$TMPDIR"/x*' 'cd "$TMPDIR" && rm -f x*' 'rm -f ~nosuchuser/x*' 'rm -f /tmp/{x,y}[0-9]*' \
  'rm -rf /tmp/{a,b}*' 'rm -f /tmp/x{1,2}*' 'rm -f "/tmp/x*" /tmp/x*' 'rm -f /tmp/x* && echo "/tmp/x*"'; do blocks "$c"; done
for c in 'rm -f build/*.o' "rm -f $work/build/*.o" "rm -f $scratch/*.tmp" "rm -f $tmpd/x685579" "rm -f '$tmpd/x*'" 'rm -f "/tmp/x*"'; do passes "$c"; done

grep -q "internal error" "$root/stderr" && {
  echo "FAIL the gate failed inside:"
  grep "internal error" "$root/stderr"
  FAIL=$((FAIL + 1))
}
sed -E "s/\]: .*/]/" "$root/stderr" | grep . | sort | uniq -c | sort -rn
echo "$RUN cases, $FAIL failed"
[[ $FAIL == 0 ]] && echo "all delete-gate tests pass"
((FAIL == 0))
