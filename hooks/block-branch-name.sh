#!/bin/bash
# A Claude Code PreToolUse gate for Bash. Every branch is named <kind>/<name>, so the scorecard, Sitrep Live and the
# proof page can count pull requests by kind. Kinds: feat fix docs refactor chore perf test ci prune. The name is
# lower-case words joined by - (dots allowed), with the issue number first when there is one: fix/312-spec-drift.
# Bots name their own branches, so dependabot/ and renovate/ pass.
# It refuses a git command that makes, renames or copies a branch with another name: git switch -c/-C,
# git checkout -b/-B/--orphan, git worktree add -b/-B (or a bare path, which names the branch after the folder),
# git branch <new>, git branch -m/-M/-c/-C, and git stash branch. Text in quotes and heredoc bodies is not a command.
# A name it cannot read (a $variable) passes, and so does a command inside bash -c or a push to refs/heads/: the
# check step in CI reads the real branch with this same hook. A repo opts out with: git config komputa.branch-rule off.
#   echo '{"tool_name":"Bash","tool_input":{"command":"git switch -c fix/1-x"}}' | block-branch-name.sh
# Exit 2 refuses with one BLOCKED line. Any other failure refuses too, as in the other gates.
set -uo pipefail
# shellcheck disable=SC2329 # run by the EXIT trap
on_exit() {
  local rc=$?
  if ((rc != 0 && rc != 2)); then
    echo "BLOCKED [branch name: internal error]: the hook failed (exit $rc), so the call is refused. Check the hook." >&2
    exit 2
  fi
}
trap on_exit EXIT
command -v jq >/dev/null || exit 1
command -v awk >/dev/null || exit 1

KINDS='feat|fix|docs|refactor|chore|perf|test|ci|prune'
GOOD="^(($KINDS)/[a-z0-9]+([.-][a-z0-9]+)*|(dependabot|renovate)/.+)\$"

INPUT=$(cat)
[[ $(jq -r '.tool_name // ""' <<<"$INPUT" 2>/dev/null) == Bash ]] || exit 0
cmd=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null) || exit 1
[[ $cmd == *git* ]] || exit 0

judge() { # judge <name>: refuses a name outside the convention
  local name=$1
  [[ -z $name || $name == *'$'* || $name =~ $GOOD ]] && return 0
  [[ $(git config --get komputa.branch-rule 2>/dev/null) == off ]] && return 0
  echo "BLOCKED [branch name]: '$name' is not <kind>/<name>. Use one of $KINDS, then lower-case words joined by -, with the issue number first when there is one: fix/312-spec-drift, feat/sitrep-sign-in." >&2
  exit 2
}

# One command per line. Outside quotes, ; & | ( ) { } and a newline end a command. Inside quotes they are text, and
# the quotes go, so a quoted name is judged as written. A heredoc body is text: skipped to its end word.
commands() {
  awk '
    BEGIN { q = "" }
    {
      line = $0
      if (stop != "") { t = line; if (strip) sub(/^\t+/, "", t); if (t == stop) stop = ""; next }
      out = ""
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (q != "") { if (c == q) q = ""; else out = out (c ~ /[;&|(){}]/ ? " " : c); continue }
        if (c == "\"" || c == "\x27") { q = c; continue }
        if (c == "<" && substr(line, i, 3) == "<<<") { out = out "<<<"; i += 2; continue }
        if (c == "<" && substr(line, i, 2) == "<<" && stop == "") {
          rest = substr(line, i + 2); strip = sub(/^-/, "", rest)
          if (match(rest, /^[ \t]*[\x27"]?[A-Za-z_][A-Za-z0-9_]*/)) {
            w = substr(rest, RSTART, RLENGTH); gsub(/[ \t\x27"]/, "", w); pending = w
          }
        }
        # The & of a redirection (2>&1, >&2, &>file) is not a separator.
        if (c == "&" && (substr(line, i - 1, 1) ~ /[<>]/ || substr(line, i + 1, 1) == ">")) { out = out c; continue }
        out = out (c ~ /[;&|(){}]/ ? "\n" : c)
      }
      if (q != "") { printf "%s ", out; next }
      print out
      if (pending != "") { stop = pending; pending = "" }
    }
  ' <<<"$cmd"
}

while IFS= read -r seg; do
  read -ra all <<<"$seg"
  # Drop redirections and their targets (2>&1, 2>/dev/null, > out.txt, &>log): they name no branch.
  w=() skip=0
  for x in "${all[@]}"; do
    if ((skip)); then skip=0 && continue; fi
    if [[ $x =~ ^[0-9]*(\>\>?|\<|\>\&|\<\&)$ || $x =~ ^\&\>\>?$ ]]; then skip=1 && continue; fi
    [[ $x =~ ^([0-9]*[\<\>]|\&\>) ]] && continue
    w+=("$x")
  done
  # git as the command itself: after VAR=value words and env, then, do, else, !, time, command or exec.
  i=0
  while ((i < ${#w[@]})) && [[ ${w[i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= || ${w[i]} =~ ^(env|then|do|else|!|time|command|exec)$ ]]; do
    ((i++))
  done
  [[ ${w[i]-} == git ]] || continue
  ((i++))
  # git's own options before the subcommand: -C <dir>, -c <key=value>.
  while ((i < ${#w[@]})) && [[ ${w[i]} == -* ]]; do
    [[ ${w[i]} == -C || ${w[i]} == -c ]] && ((i++))
    ((i++))
  done
  sub=${w[i]-}
  args=("${w[@]:i+1}")
  case $sub in
    switch | checkout)
      for ((j = 0; j < ${#args[@]}; j++)); do
        case ${args[j]} in
          --create=* | --force-create=* | --orphan=*) judge "${args[j]#*=}" ;;
          --create | --force-create | --orphan) judge "${args[j + 1]-}" ;;
          --*) ;;
          # A short flag group that ends in the flag that names a new branch: -c, -C, -b, -B, -qb.
          -*[cCbB]) judge "${args[j + 1]-}" ;;
        esac
      done
      ;;
    worktree)
      [[ ${args[0]-} == add ]] || continue
      named=0 detach=0 rest=()
      for ((j = 1; j < ${#args[@]}; j++)); do
        case ${args[j]} in
          -b | -B) named=1 && judge "${args[j + 1]-}" && ((j++)) ;;
          -d | --detach) detach=1 ;;
          --reason | --orphan) ((j++)) ;;
          -*) ;;
          *) rest+=("${args[j]}") ;;
        esac
      done
      # git worktree add <path> with no commit makes a branch named after the folder.
      ((named == 0 && detach == 0 && ${#rest[@]} == 1)) && judge "$(basename "${rest[0]}")"
      ;;
    branch)
      names=() move=0 other=0 dashdash=0
      for a in "${args[@]}"; do
        if ((dashdash)); then names+=("$a") && continue; fi
        case $a in
          --) dashdash=1 ;;
          -m | -M | --move | -c | -C | --copy) move=1 ;;
          -f | --force | --no-track | --track | -t) ;;
          -*) other=1 ;;
          *) names+=("$a") ;;
        esac
      done
      ((other == 0 && ${#names[@]} > 0)) || continue
      if ((move == 1)); then judge "${names[-1]}"; else judge "${names[0]}"; fi
      ;;
    stash)
      [[ ${args[0]-} == branch ]] && judge "${args[1]-}"
      ;;
  esac
done < <(commands)
exit 0
