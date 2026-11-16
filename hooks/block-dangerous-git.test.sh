#!/bin/bash
# shellcheck disable=SC2016 # single-quoted payloads are literal commands to judge
# Feed block-dangerous-git.sh a Bash tool payload and check its exit code:
# 2 blocks, 0 passes.

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

check 2 block-dangerous-git.sh "$(bash_cmd 'git reset --hard HEAD~1')"
check 2 block-dangerous-git.sh "$(bash_cmd 'git push --force origin main')"
check 2 block-dangerous-git.sh "$(bash_cmd 'git branch -D old')"
check 0 block-dangerous-git.sh "$(bash_cmd 'git push origin feat/x')"

# git branch -D passes only for branches merged into origin's default branch.
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git init -q --bare -b main "$repo/origin.git"
git clone -q "$repo/origin.git" "$repo/work" 2>/dev/null
# Name the first branch main whatever init.defaultBranch says (CI has none).
git -C "$repo/work" symbolic-ref HEAD refs/heads/main
git -C "$repo/work" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
git -C "$repo/work" push -q origin HEAD:main 2>/dev/null
git -C "$repo/work" remote set-head origin main
git -C "$repo/work" branch merged
git -C "$repo/work" checkout -q -b unmerged
git -C "$repo/work" -c user.name=t -c user.email=t@t commit -q --allow-empty -m wip
git -C "$repo/work" checkout -q -b other main
git_cmd() { jq -nc --arg c "$1" --arg d "$repo/work" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -D merged')"
check 0 block-dangerous-git.sh "$(git_cmd "git -C $repo/work branch -D merged")"
check 0 block-dangerous-git.sh "$(git_cmd "cd $repo/work && git branch -D merged && git status")"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -D unmerged')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -D merged unmerged')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -D no-such-branch')"
# shellcheck disable=SC2016 # the $( ) is a literal command the hook must refuse
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -D $(git branch --format=x)')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -D merged && git reset --hard')"
check 2 block-dangerous-git.sh "$(jq -nc '{tool_name:"Bash",cwd:"/",tool_input:{command:"git branch -D merged"}}')"

# Deleting loses nothing when the commits survive elsewhere: a tag, a pushed
# branch, or a merge on the server that the hook's own fetch brings in.
commit_on() { # commit_on <branch>: a new branch from main with one commit
  git -C "$repo/work" checkout -q -b "$1" main
  git -C "$repo/work" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"
  git -C "$repo/work" checkout -q other
}
commit_on tagged
git -C "$repo/work" tag archive/tagged tagged
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -D tagged')"
commit_on pushed
git -C "$repo/work" push -q origin pushed 2>/dev/null
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -D pushed')"
# A redirect after the names is not a name (2026-11-01: "2>&1" blocked a
# pushed branch).
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -D pushed 2>&1 | tail -1')"
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -D pushed >/dev/null 2>&1 || true')"
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -D pushed > /dev/null')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -D unmerged 2>&1 | tail -1')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -D 2>&1')"
commit_on late
stale=$(git -C "$repo/work" rev-parse origin/main)
git -C "$repo/work" push -q origin late:main 2>/dev/null
git -C "$repo/work" update-ref refs/remotes/origin/main "$stale"
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -D late')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -D unmerged')"

# Heredoc bodies are data unless the heredoc feeds a shell.
check 0 block-dangerous-git.sh "$(bash_cmd "$(printf 'python3 - <<EOF\nprint(\"git reset --hard\")\nEOF')")"
check 0 block-dangerous-git.sh "$(bash_cmd "$(printf "cat > notes.md <<'EOF'\nnever run git clean -fd here\nEOF")")"
check 2 block-dangerous-git.sh "$(bash_cmd "$(printf 'bash <<EOF\ngit reset --hard\nEOF')")"
check 2 block-dangerous-git.sh "$(bash_cmd "$(printf 'cat <<EOF | sh\ngit reset --hard\nEOF')")"
check 2 block-dangerous-git.sh "$(bash_cmd "$(printf 'cat <<EOF\nx\nEOF\ngit reset --hard')")"
check 0 block-dangerous-git.sh "$(bash_cmd 'git status')"

# Forced pushes (#16). One form passes: a lease that names a branch that is not
# the default and its exact SHA, with a refspec that pushes that same branch.
git clone -q "$repo/origin.git" "$repo/push" 2>/dev/null
git -C "$repo/push" remote set-head origin main
git init -q --bare "$repo/trunk.git"
git -C "$repo/trunk.git" symbolic-ref HEAD refs/heads/trunk
git -C "$repo/push" push -q "$repo/trunk.git" HEAD:refs/heads/trunk 2>/dev/null
git -C "$repo/push" remote add tr "$repo/trunk.git" # no local tr/HEAD: ls-remote
git -C "$repo/push" remote add dv "$repo/origin.git"
git -C "$repo/push" update-ref refs/remotes/dv/develop HEAD
git -C "$repo/push" symbolic-ref refs/remotes/dv/HEAD refs/remotes/dv/develop
sha=$(git -C "$repo/push" rev-parse HEAD)
push_cmd() { jq -nc --arg c "$1" --arg d "$repo/push" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
lease() { printf -- '--force-with-lease=%s' "$1"; } # keeps the long flag out of greps
blocks() { check 2 block-dangerous-git.sh "$(push_cmd "$1")"; }
passes() { check 0 block-dangerous-git.sh "$(push_cmd "$1")"; }
# Every forced form is refused.
blocks 'git push -f origin main'
blocks 'git push -f origin feat'
blocks 'git push -uf origin feat'
blocks 'git push -vfn origin feat'
blocks 'git push origin feat -f'
blocks 'git push origin feat --force'
blocks 'git push --forc origin feat'
blocks 'git push origin +main'
blocks 'git push origin +HEAD:refs/heads/feat'
blocks 'git push origin feat +other'
blocks 'git push --force-if-includes origin feat'
blocks 'git push --mirror origin'
blocks "git push $(lease '') origin feat"
blocks 'git push --force-with-lease origin feat'
blocks 'git push --force-with origin feat'
blocks "git push $(lease refs/heads/feat) origin HEAD:refs/heads/feat"
blocks "git push $(lease feat) origin feat"
blocks "git push $(lease refs/heads/feat:) origin feat"
blocks "git push $(lease refs/heads/feat:origin/feat) origin feat"
# The lease form, but to a default branch or with a bad SHA or refspec.
blocks "git push $(lease "refs/heads/main:$sha") origin HEAD:refs/heads/main"
blocks "git push $(lease "master:$sha") origin master"
blocks "git push $(lease "develop:$sha") dv HEAD:refs/heads/develop"
blocks "git push $(lease "trunk:$sha") tr HEAD:refs/heads/trunk"
blocks "git push $(lease "feat:$sha") nosuchremote HEAD:refs/heads/feat"
blocks "git push $(lease "refs/heads/feat:${sha}0") origin HEAD:refs/heads/feat"
blocks "git push $(lease "refs/heads/feat:${sha:0:6}") origin HEAD:refs/heads/feat"
blocks "git push $(lease 'refs/heads/feat:zzzzzzzz') origin HEAD:refs/heads/feat"
blocks "git push $(lease "refs/heads/feat:$sha") origin HEAD:main"
blocks "git push $(lease "refs/heads/feat:$sha") origin HEAD:refs/heads/other"
blocks "git push $(lease "refs/heads/feat:$sha") origin HEAD:refs/heads/feat other"
blocks "git push $(lease "refs/heads/feat:$sha") origin HEAD:refs/tags/feat"
blocks "git push $(lease "refs/heads/feat:$sha") origin HEAD"
blocks "git push $(lease "refs/heads/feat:$sha") origin"
blocks "git push $(lease "refs/heads/feat:$sha") --all origin"
blocks "git push $(lease "refs/heads/feat:$sha") --force origin HEAD:refs/heads/feat"
blocks "git push $(lease "refs/heads/feat:$sha") -f origin HEAD:refs/heads/feat"
blocks "git push $(lease "refs/heads/feat:$sha") origin +HEAD:refs/heads/feat"
blocks "git push $(lease "refs/heads/feat:$sha") $(lease "refs/heads/main:$sha") origin HEAD:refs/heads/feat HEAD:main"
blocks "git push $(lease "refs/heads/fé:$sha") origin HEAD:refs/heads/fe"
# shellcheck disable=SC2016 # an unexpanded variable cannot be checked
blocks 'git push --force-with-lease="refs/heads/$b:$s" origin "HEAD:refs/heads/$b"'
# The push hides among other commands, in subshells, substitutions and shells.
blocks 'git status; git push -f origin feat'
blocks 'git status && git push origin +feat || true'
blocks 'echo x | git push -f origin feat'
blocks "$(printf 'git status\ngit push -f origin feat')"
blocks "(cd $repo/push && git push -f origin feat)"
blocks '{ git push -f origin feat; }'
# shellcheck disable=SC2016 # a literal substitution the hook must see run
{
  blocks 'echo $(git push -f origin feat)'
  blocks 'echo `git push -f origin feat`'
  blocks 'odev issue create --body "$(git push -f origin main)"'
}
blocks "bash -c 'git push -f origin main'"
blocks 'sh -c "cd /x && git push origin +main"'
blocks "eval 'git push --force origin main'"
blocks 'eval git push -f origin main'
blocks "ssh host 'git push -f origin main'"
blocks "ssh host \"bash -c 'git push -f origin main'\""
blocks 'echo main | xargs git push -f origin'
blocks "$(printf 'bash <<EOF\ngit push -f origin main\nEOF')"
blocks 'git -C /tmp push -f origin main'
blocks '/usr/bin/git push -f origin main'
blocks 'sudo -u alice env X=1 git push -f origin main'
blocks '\git push -f origin main'
blocks "git -c alias.p='push --force' p origin main"
blocks 'git -c remote.origin.mirror=true push origin'
# The lease form passes, quoted or not, short or long SHA.
passes "git push $(lease "refs/heads/feat:$sha") origin HEAD:refs/heads/feat"
passes "git push $(lease "feat:${sha:0:7}") origin feat"
passes "git push $(lease "refs/heads/feat:$sha") --force-if-includes origin HEAD:refs/heads/feat"
passes "git push \"$(lease "refs/heads/feat:$sha")\" origin 'HEAD:refs/heads/feat'"
passes "git push $(lease "refs/heads/fé-ü:$sha") origin HEAD:refs/heads/fé-ü"
passes "git push $(lease "refs/heads/feat:$sha") tr HEAD:refs/heads/feat"
passes "git push $(lease "refs/heads/feat:$sha") dv HEAD:refs/heads/feat"
passes "cd $repo/push && git push $(lease "refs/heads/feat:$sha") origin HEAD:refs/heads/feat 2>&1 | tail -1"
passes "bash -c 'git push $(lease "refs/heads/feat:$sha") origin HEAD:refs/heads/feat'"
# Ordinary pushes, and text that only mentions a forced push.
passes 'git push -u origin feat'
passes 'git push -o force origin feat'
passes 'odev issue create --title x --body "never run git push --force origin main"'
passes "hc send t4w 'do not git push -f; use the lease, not +main'"
passes 'git commit -m "hook: refuse git push -f and git push origin +main"'
passes "bash -c \"odev issue create --body 'git push --force is refused'\""
passes "$(printf 'cat > n.md <<EOF\ngit push --force origin main\nEOF')"

# A remote branch delete follows the git branch -D rule: nothing lost, and
# never the default branch.
git -C "$repo/push" branch gone main
git -C "$repo/push" push -q origin gone 2>/dev/null
passes 'git push origin --delete gone'
passes 'git push origin :gone'
passes 'git push -d origin gone'
blocks 'git push origin --delete main'
blocks 'git push origin :main'
blocks 'git push -d origin main'
blocks 'git push origin --del main'
blocks 'git push origin --delete pushed'
blocks 'git push origin :pushed'
blocks 'git push origin --delete gone main'
blocks 'git push origin gone :main'
blocks 'git push origin --delete no-such-branch'
blocks 'git push dv :develop'
blocks 'git push --prune origin'

# Quotes inside a word do not hide it.
blocks 'git pu"sh" --force origin main'
blocks 'git re"set" --hard'

# A line continuation joins the words.
blocks "$(printf 'git push \\\n  --force origin main')"
blocks "$(printf 'git \\\n  reset --hard')"
blocks "$(printf 'git branch \\\n  -D unmerged')"

# Destructive commands are judged by their words, in any order and spelling.
blocks 'git reset HEAD~1 --hard'
blocks 'git -C . reset --hard'
blocks 'git reset --har'
blocks '"git" "reset" "--hard"'
blocks "bash -c 'git reset HEAD~1 --hard'"
blocks 'git clean -f'
blocks 'git clean -df'
blocks 'git clean -xfd'
blocks 'git clean -d -f'
blocks 'git clean --force'
blocks 'git checkout .'
blocks 'git checkout -- .'
blocks 'git checkout HEAD -- .'
blocks 'git checkout -- :/'
blocks 'git restore .'
blocks 'git restore -- .'
blocks 'git restore --source=HEAD .'
blocks 'git restore -SW .'
blocks 'git restore --staged --worktree .'
passes 'git reset HEAD~1'
passes 'git reset --soft HEAD~1'
passes 'git clean -n'
passes 'git clean -dn'
passes 'git checkout feat'
passes 'git checkout -- src/a.txt'
passes 'git checkout .github/workflows/check.yml'
passes 'git restore .gitignore'
passes 'git restore --staged .'

check 2 block-dangerous-git.sh "$(git_cmd "git -C $repo/work branch -D unmerged")"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -df unmerged')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -fd unmerged')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -d -f unmerged')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch --delete --force unmerged')"
check 2 block-dangerous-git.sh "$(git_cmd 'git branch -rD origin/main')"
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -d unmerged')"
check 0 block-dangerous-git.sh "$(git_cmd 'git branch -df merged')"
check 0 block-dangerous-git.sh "$(git_cmd 'git branch --delete --force merged')"
check 0 block-dangerous-git.sh "$(git_cmd '"git" branch -D merged')"

# Text that looks like a heredoc or a quote does not hide a later command.
blocks "$(printf 'cat <<<foo\ngit reset --hard')"
blocks "$(printf 'echo "<<EOF"\ngit reset --hard')"
blocks "$(printf 'echo hi # <<EOF\ngit reset --hard')"
blocks "$(printf '(( a<<b ))\ngit reset --hard')"
blocks "$(printf "echo 'x\n<<EOF\n'\ngit reset --hard")"
blocks "$(printf "# do not, it's bad\ngit reset --hard")"
blocks "$(printf "# do not, it's bad\ngit push -f origin main")"
passes "$(printf 'python3 - <<"EOF"\ngit reset --hard\nEOF')"
passes "$(printf "cat <<-'EOF'\n\tgit reset --hard\n\tEOF")"

# A payload the hook cannot read is refused, so it cannot fail open.
check 2 block-dangerous-git.sh 'not json'
check 2 block-dangerous-git.sh ''
check 2 block-dangerous-git.sh '{"tool_input":{}}'
check 2 block-dangerous-git.sh '{"tool_input":{"command":5}}'
check 0 block-dangerous-git.sh '{"tool_name":"Read","tool_input":{"file_path":"x"}}'
nojq=$repo/nojq
mkdir -p "$nojq"
for t in cat awk grep sed git timeout; do ln -sf "$(command -v "$t")" "$nojq/$t"; done
bash_cmd 'git push -f origin main' >"$repo/payload"
PATH=$nojq "$DIR/block-dangerous-git.sh" <"$repo/payload" 2>/dev/null
got=$?
if [[ $got != 2 ]]; then
  echo "FAIL block-dangerous-git.sh with no jq want 2 got $got"
  FAIL=1
fi

# The verifier's findings on the first fix.
heredoc_arg() { printf '%s "$(cat <<'"'"'EOF'"'"'\n%s\nEOF\n)"%s' "$1" "$2" "${3-}"; }
passes "$(heredoc_arg 'git commit -m' 'Never run git reset --hard here')"
passes "$(heredoc_arg 'gh issue create --title x --body' 'Run git checkout -- . to reproduce')"
blocks "$(heredoc_arg 'git commit -m' "It's done" ' && git reset --hard')"
blocks "$(heredoc_arg 'git commit -m' "It's done" ' && git reset HEAD~1 --hard')"
blocks "$(heredoc_arg 'git commit -m' "It's done" ' && git push -f origin main')"
blocks "$(printf "bash -c '# x\ngit reset --hard'")"
blocks "$(printf "bash -c '# x\ngit reset HEAD~1 --hard'")"
blocks "$(printf "ssh host 'cd /srv/app\ngit push -f origin main'")"
blocks 'git reset --hard>/dev/null'
blocks 'git reset HEAD~1 --hard>/dev/null'
blocks 'git checkout .>/dev/null'
blocks "$(printf 'git re\\\nset --hard')"
blocks "$(printf 'git pu\\\nsh -f origin main')"
blocks 'echo \ # ; git reset HEAD~1 --hard'
blocks 'echo ${x:- #}; git reset HEAD~1 --hard'
blocks "echo >'a'&git reset HEAD~1 --hard"
blocks 'git restore ./*'
blocks 'git --attr-source HEAD reset --hard'
blocks '$GIT reset --hard'
blocks 'git reset --hard$X'
blocks "ash -c 'git reset HEAD~1 --hard'"
blocks "runuser -c 'git reset HEAD~1 --hard' me"
blocks "git -c alias.x='reset --hard' x"
blocks "$(printf 'x=\x1ey\ngit reset HEAD~1 --hard')"
passes 'git checkout --theirs .'
passes 'git checkout --ours .'
blocks 'git push origin --delete>/dev/null main'
blocks 'git checkout -- ./.'
passes 'git checkout -p .'
passes 'git restore -p .'
# A heredoc to a file is data, whatever the file is called.
passes "$(printf "cat > deploy.sh <<'EOF'\ngit reset --hard\nEOF")"
passes "$(printf "cat > ~/.ssh/notes.txt <<'EOF'\ngit reset --hard\nEOF")"
passes "$(printf 'cat <<\\EOF > notes.md\ngit reset --hard\nEOF')"
blocks "$(printf 'sh <<EOF\ngit reset --hard\nEOF')"
blocks "$(printf '/bin/bash <<EOF\ngit reset --hard\nEOF')"
# A delimiter the hook cannot read does not hide later lines.
blocks "$(printf 'cat <<E"O"F\nbody\nEOF\ngit reset --hard\nE')"
blocks "$(printf 'cat <<A.B\nbody\nA.B\ngit reset --hard\nA')"
# A backslash joins lines only where the shell joins them.
blocks "$(printf '# note \\\ngit push -f origin main')"
blocks "$(printf '# note \\\ngit reset HEAD~1 --hard')"
blocks "$(printf 'echo a\\\\\ngit reset HEAD~1 --hard')"
blocks "$(printf "cat <<'EOF'\nfoo\\\\\nEOF\ngit reset HEAD~1 --hard")"
# The raw scan keeps the old hook's reach.
blocks "tmux send-keys 'git checkout .' Enter"
blocks "tmux send-keys 'git restore .' Enter"
blocks "echo 'git branch -D unmerged' | sh"
blocks 'git checkout ..'
blocks 'git restore ..'
blocks 'git checkout ./src'
blocks 'git restore ./src'
blocks 'git checkout -- ../x'
passes 'git checkout .gitignore'
passes 'git restore .gitignore'
# A comment read wrongly does not hide a command.
blocks 'echo ${x:-$(echo }) # }; git push -f origin main'
blocks 'echo ${x:-`echo }`} # ; git push -f origin main'
blocks '[[ a == # ]]; git push -f origin main'
# A heredoc is data only when cat or tee writes it to a file.
blocks "$(printf './run.sh <<EOF\ngit reset --hard\nEOF')"
blocks "$(printf 'deploy.sh <<EOF\ngit reset --hard\nEOF')"
blocks "$(printf 'cat > f.sh <<EOF && bash f.sh\ngit reset --hard\nEOF')"
blocks "$(printf 'cat <<EOF | x.sh\ngit reset --hard\nEOF')"
passes "$(printf 'tee scripts/x.sh >/dev/null <<EOF\ngit reset --hard\nEOF')"
passes "$(printf "cd /tmp; cat > f.sh <<'EOF'\ngit reset --hard\nEOF")"
# The plain spellings stay refused wherever they appear, as a fail-safe.
blocks 'git commit -m "docs: never run git reset --hard"'
blocks 'gh issue create --body "git clean -fd is refused"'
# A refusal is one line.
err=$(push_cmd "$(printf 'echo a\ngit reset --hard\necho b')" | "$DIR/block-dangerous-git.sh" 2>&1 >/dev/null)
[[ $err == BLOCKED* && $err != *$'\n'* ]] || {
  echo "FAIL a refusal must be one line, got: $err"
  FAIL=1
}
err=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git -C /nonexistent/x branch -D foo"}}' | "$DIR/block-dangerous-git.sh" 2>&1 >/dev/null)
[[ $err == BLOCKED* && $err != *$'\n'* ]] || {
  echo "FAIL a refusal must be one line, got: $err"
  FAIL=1
}
# With no awk the hook refuses too.
noawk=$repo/noawk
mkdir -p "$noawk"
for t in cat jq grep sed git timeout; do ln -sf "$(command -v "$t")" "$noawk/$t"; done
PATH=$noawk "$DIR/block-dangerous-git.sh" <"$repo/payload" 2>/dev/null
got=$?
if [[ $got != 2 ]]; then
  echo "FAIL block-dangerous-git.sh with no awk want 2 got $got"
  FAIL=1
fi
# A long command stays cheap, also one that names a git word. The limit is CPU time (user and system), not wall
# time: a busy machine makes the hook late, not costly (issue #34).
body=$(head -c 200000 /dev/zero | tr '\0' 'x')
printf "gh issue create --body 'branch %s'" "$body" | jq -Rs '{tool_name:"Bash",tool_input:{command:.}}' >"$repo/long"
cpu=$({
  LC_ALL=C TIMEFORMAT='%U %S'
  time "$DIR/block-dangerous-git.sh" <"$repo/long" >/dev/null 2>&1
  echo $? >"$repo/long.rc"
} 2>&1)
got=$(<"$repo/long.rc")
if [[ $got != 0 ]] || awk -v t="$cpu" 'BEGIN { split(t, a, " "); exit !(a[1] + a[2] > 5) }'; then
  echo "FAIL a 200 KB command took $cpu CPU seconds (user, system), exit $got"
  FAIL=1
fi

# A branch change is refused when another live agent terminal works in the same work tree.
stub=$repo/stub
mkdir -p "$stub"
git -C "$repo/work" worktree add -q "$repo/wt" -b wtb main
cat >"$stub/hc" <<STUB
#!/bin/bash
echo '{"terminals":[{"address":"t9","agent":"claude-code","cwd":"'"\$HC_STUB_CWD"'","state":"live"},{"address":"me","agent":"claude-code","cwd":"$repo/work","state":"live"}]}'
STUB
chmod +x "$stub/hc"
sw() { # sw <want> <other's cwd> <command> [HC_TERMINAL_ID]
  HC_STUB_CWD=$2 HC_TERMINAL_ID=${4-me} PATH=$stub:$PATH check "$1" block-dangerous-git.sh "$(git_cmd "$3")"
}
sw 2 "$repo/work" 'git checkout -b x'
sw 2 "$repo/work/." 'git switch other'
sw 2 "$repo/work" 'git checkout other'
sw 0 "$repo/wt" 'git checkout -b x'
sw 0 "$repo/nowhere" 'git checkout -b x'
sw 0 "$repo/work" 'git checkout -b x' ''
sw 0 "$repo/work" 'git checkout -- file'
sw 0 "$repo/work" 'git checkout main -- file'
sw 0 "$repo/work" 'git restore file'

# Both hooks hold one copy of the shell parser. Change it in both.
shared() { sed -n '/^# BEGIN shared parser/,/^# END shared parser/p' "$DIR/$1"; }
if [[ -z $(shared block-dangerous-git.sh) ]] \
  || ! diff <(shared block-dangerous-git.sh) <(shared block-destructive-delete.sh) >/dev/null; then
  echo "FAIL the shared parser differs between the two hooks"
  FAIL=1
fi

[[ "$FAIL" = 0 ]] && echo "all hook tests pass"
exit $FAIL
