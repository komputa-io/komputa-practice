#!/bin/bash
# Matt Pocock's git-guardrails (github.com/mattpocock/skills,
# skills/misc/git-guardrails-claude-code), without the plain `git push`
# pattern: agents push their own branches.
#
# A forced push is refused: the long force flag, -f in any short-flag group,
# a +refspec, --mirror, --force-if-includes alone, and a lease with no SHA.
# One form passes, the restack in pstack's merge-safety reference:
#   git push --force-with-lease=refs/heads/<b>:<sha> <remote> HEAD:refs/heads/<b>
# The lease names a branch and its exact SHA (7 to 40 hex), every refspec
# pushes a leased branch, and no leased branch is main, master or the remote's
# default. Only real git commands are judged: text in a quoted argument
# of another program (an issue body, a message) is data. A quoted argument of
# bash -c, sh -c, eval, ssh, xargs, su or watch is commands, so it is judged,
# and so is the body of $(...) and `...`. A variable in the lease cannot be
# checked, so it is refused. A git alias or a configured +refspec is not seen.
#
# `git branch -D` passes when deleting loses nothing: every commit on each
# branch it names is also reachable from another local branch, a
# remote-tracking branch or a tag. That covers a branch merged into main
# (local or remote), a pushed branch, and a throwaway branch tagged first.
# When the first check fails, the hook fetches origin once (15 s cap) and
# checks again, so a PR merged on the server since the last fetch passes.
# `-d` cannot do this job when the checkout sits on another branch.
# A redirect after the names (2>&1, >/dev/null) is not a name. Any branch with
# commits found nowhere else, or an unknown or unparseable name, keeps the
# block.
#
# A remote branch delete (--delete, -d or a :branch refspec) follows the same
# rule, after one fetch: nothing is lost, and it is never main, master or the
# remote's default. --prune is refused, because it names no branch to judge.
#
# `git reset --hard`, `git clean` with force, and `git checkout` or
# `git restore` of a dot path (., .., ./x, ../x), :/ or * are refused.
# `git checkout --ours .` and `--theirs .` pass: they resolve a conflict. So
# does `-p`, which asks a person about each change.
#
# A branch change (`git switch`, `git checkout <branch>`, `-b`, a detach) is
# refused when hc lists another live claude-code or codex terminal whose folder
# is in the same work tree (a linked worktree is its own). A path checkout
# (`-- <path>`) and `git restore` pass. With no HC_TERMINAL_ID, no hc, or no
# answer from hc in 3 s, it passes. The refusal names the terminal.
#
# Two layers judge these. A raw scan of the text refuses the plain spellings
# wherever they appear, also in a variable-led command or a quoted message:
# it fails safe, because it needs no parse. The word parse then catches what
# the scan cannot see: reordered flags, abbreviations and `git -C`.
#
# Heredoc bodies are data, not commands, so they are not scanned: a script
# or file that mentions a pattern does not trip the hook. A heredoc whose
# opening line names a shell (bash, sh, eval, ssh, ...) is still scanned.
#
# This hook stops mistakes. It does not stop an agent that sets out to get past
# it. Does not catch: code in another language (python3 -c, or a heredoc fed to
# it); text piped to a shell (echo ... | bash); a command in a variable or a
# script file; a git alias; a word built by quoting tricks ($'..', $".."); a path
# in a variable; `git checkout` or `git restore` of a path with no leading dot; a forced
# `git checkout -f` or `git switch -f`; `git stash drop`, `git update-ref -d` and
# other commands not named above.
#
# A payload that is not one JSON object, a Bash call with no command string, or
# a missing jq or awk is refused. Any other failure inside the hook also refuses
# (exit 2), because exit 1 would let the call run.

# No -e: a failed test is a normal answer here. Every path ends in exit 0 or
# exit 2, and the trap turns any other exit into a refusal.
set -uo pipefail
# shellcheck disable=SC2329 # run by the EXIT trap
on_exit() {
  local rc=$?
  if ((rc != 0 && rc != 2)); then
    echo "BLOCKED [git hook: internal error]: the hook failed (exit $rc), so the call is refused. Check the hook." >&2
    exit 2
  fi
}
trap on_exit EXIT

refuse_payload() {
  echo "BLOCKED [git hook: malformed payload]: $1. Check the hook." >&2
  exit 2
}

if ! command -v jq >/dev/null || ! command -v awk >/dev/null; then
  refuse_payload "jq and awk are needed to read the command"
fi
INPUT=$(cat)
jq -e -s 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1 <<<"$INPUT" \
  || refuse_payload "the hook input is not one JSON object"
# str <filter>: a string field, or nothing. NUL becomes a space: bash cannot hold it.
str() { jq -j "$1 | if type == \"string\" then split(\"\\u0000\") | join(\" \") else empty end" <<<"$INPUT" 2>/dev/null; }
TOOL=$(str '.tool_name')
[[ -n $TOOL && $TOOL != Bash ]] && exit 0
jq -e '.tool_input.command | type == "string"' >/dev/null 2>&1 <<<"$INPUT" \
  || refuse_payload "a Bash call with no command string"
COMMAND=$(str '.tool_input.command')
CWD=$(str '.cwd')

# The git commands this hook judges. A line with none of them is dropped early.
GIT_WORDS='push|reset|clean|checkout|restore|branch|switch'
KEEP_LINE="$GIT_WORDS|^[ \\t{]*cd([ \\t]|\$)"

# BEGIN shared parser. Both hooks hold this block. A test keeps them the same.

# strip_heredocs: the command with every heredoc body removed; the line that
# opens it stays. A heredoc fed to a shell is commands, so its body stays. It
# reads the line as the shell does: <<< and quoted or commented text open no
# heredoc, and neither does a shift in (( )). A $(...) or `...` inside double
# quotes is commands, so a heredoc can open there. A quote stays open across
# lines.
strip_heredocs() {
  LC_ALL=C awk '
  function heredoc_delim(line, i, n, c, rest, d, found) {
    n = length(line); found = ""
    for (i = 1; i <= n; i++) {
      c = substr(line, i, 1)
      if (q == "\047") { if (c == q) q = ""; continue }
      if (c == "\\") { i++; continue }
      if (c == "`") {
        if (top > 0 && tick[top]) q = saved[top--]
        else { saved[++top] = q; tick[top] = 1; depth[top] = 0; q = "" }
        continue
      }
      if (q == "\"") {
        if (substr(line, i, 2) == "$(" && substr(line, i + 2, 1) != "(") {
          saved[++top] = q; tick[top] = 0; depth[top] = 0; q = ""; i++
        } else if (c == q) q = ""
        continue
      }
      if (top > 0 && !tick[top]) {
        if (c == "(") depth[top]++
        if (c == ")") { if (depth[top] > 0) depth[top]--; else q = saved[top--] }
      }
      if (c == "\047" || c == "\"") { q = c; continue }
      if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;&|(]/)) break
      if (substr(line, i, 2) == "((") {
        d = index(substr(line, i + 2), "))")
        if (!d) break
        i += d + 2; continue
      }
      if (substr(line, i, 3) == "<<<") { i += 2; continue }
      if (found == "" && substr(line, i, 2) == "<<") {
        rest = substr(line, i + 2)
        # A delimiter this cannot read opens nothing, so its body stays in the
        # scan: that can only refuse more.
        if (match(rest, /^-?[ \t]*[\\"\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/) \
            && substr(rest, RLENGTH + 1, 1) ~ /^($|[ \t;&|)<>])/) {
          d = substr(rest, 1, RLENGTH); sub(/^-?[ \t]*/, "", d); gsub(/[\\"\047]/, "", d); found = d
          i += 1 + RLENGTH
        } else i++
      }
    }
    return found
  }
  delim != "" { line = $0; sub(/^[\t ]+/, "", line); if (line == delim) delim = ""; next }
  {
    print
    found = heredoc_delim($0)
    # A heredoc that cat or tee writes to a file is data, whatever the file is
    # called (deploy.sh, ~/.ssh/x). Any other line that names a shell keeps its
    # body in the scan.
    shell = $0 ~ /(^|[^A-Za-z0-9_])(bash|sh|zsh|eval|source|ssh|xargs)([^A-Za-z0-9_]|$)/
    real_shell = $0 ~ /(^|[^A-Za-z0-9_.])(bash|sh|zsh|eval|source|ssh|xargs)([^A-Za-z0-9_.]|$)/
    writes = $0 ~ /(^|[;&])[ \t]*(cat|tee)[ \t][^|;&]*<<[^|]*$/
    if (found != "" && (!shell || (writes && !real_shell))) delim = found
  }'
}

# split_segments: one command per line. Splits on && || ; | & ( ) and
# newlines, not inside quotes, so a quoted message that names a command is
# text. The body of $(...) and `...` runs, also inside double quotes, so it
# becomes a command line of its own. A newline inside quotes becomes $QUOTED_NL
# (word_text restores it). A backslash-newline joins two lines and a comment is
# dropped, as the shell does, so a backslash in a comment joins nothing. With
# COMMENTS=keep a comment stays, for the second read that judge_both makes.
QUOTED_NL=$'\x1f'
split_segments() {
  LC_ALL=C awk -v nl="$QUOTED_NL" -v comments="${COMMENTS:-drop}" '
    { buf = buf $0 "\n" }
    END {
      n = length(buf); q = ""; top = 0; dep[0] = 0; esc = -1
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1); d = substr(buf, i, 2)
        if (c == "\n" && q != "") c = nl
        if (q == "\047") { if (c == "\047") q = ""; printf "%s", c; continue }
        if (q == "$\047") {
          if (c == "\\") { printf "%s", d; i++; continue }
          if (c == "\047") q = ""
          printf "%s", c; continue
        }
        if (c == "\\") { if (substr(buf, i + 1, 1) != "\n") printf "%s", d; i++; esc = i; continue }
        if (d == "$(" && substr(buf, i + 2, 1) != "(") {
          saved[++top] = q; bq[top] = 0; dep[top] = 0; q = ""; i++; printf "\n"; continue
        }
        if (c == "`") {
          if (top > 0 && bq[top]) q = saved[top--]
          else { saved[++top] = q; bq[top] = 1; dep[top] = 0; q = "" }
          printf "\n"; continue
        }
        if (q == "\"") { if (c == "\"") q = ""; printf "%s", c; continue }
        if (d == "${") brace++
        if (c == "}" && brace > 0) brace--
        if (comments == "drop" && c == "#" && !brace && esc != i - 1 && (i == 1 || substr(buf, i - 1, 1) ~ /[ \t\n;&|(]/)) {
          while (i < n && substr(buf, i + 1, 1) != "\n") i++
          continue
        }
        if (c == "\"" || c == "\047") { q = c; p = c; printf "%s", c; continue }
        if (d == "$\047") { q = d; p = d; printf "%s", d; i++; continue }
        if (d == "&&" || d == "||") { printf "\n"; i++; continue }
        if (c == "(") { dep[top]++; printf "\n"; continue }
        if (c == ")") {
          if (dep[top] > 0) dep[top]--
          else if (top > 0 && !bq[top]) q = saved[top--]
          printf "\n"; continue
        }
        if (c == ";" || c == "|" || c == "\n") { printf "\n"; p = c; continue }
        # A lone & ends a command; >& and &> are redirections.
        if (c == "&" && p != ">" && substr(buf, i + 1, 1) != ">") { printf "\n"; p = c; continue }
        p = c
        printf "%s", c
      }
      printf "\n"
    }'
}

# split_words: the words of each command line, one per line, quotes removed,
# then a line that holds only $SEG_END. A quoted word keeps its spaces. Only a
# line that matches $KEEP_LINE, with its quotes removed, matters, so the rest
# are dropped here, in one fork.
SEG_END=$'\x1e'
split_words() {
  LC_ALL=C awk -v rs="$SEG_END" -v keep="$KEEP_LINE" '
  {
    bare = $0
    gsub(/["\047\\]/, "", bare)
    if (bare !~ keep) next
    n = length($0); w = ""; have = 0; q = ""
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1); nx = substr($0, i + 1, 1)
      if (q == "\047") { if (c == "\047") q = ""; else w = w c; continue }
      if (q == "$\047") {
        if (c == "\\") { w = w nx; i++; continue }
        if (c == "\047") q = ""; else w = w c
        continue
      }
      if (q == "\"") {
        if (c == "\\" && index("\"\\$`", nx)) { w = w nx; i++; continue }
        if (c == "\"") q = ""; else w = w c
        continue
      }
      if (c == "\\") { w = w nx; i++; have = 1; continue }
      if (c == "\047" || c == "\"") { q = c; have = 1; continue }
      if (c == "$" && nx == "\047") { q = "$\047"; i++; have = 1; continue }
      if (c == " " || c == "\t") { if (have) print w; w = ""; have = 0; continue }
      w = w c; have = 1
    }
    if (have) print w
    print rs
  }'
}

# plain_text <text>: the text with the parser's own markers taken out, because
# they cannot come from the command.
plain_text() {
  local t=${1//$SEG_END/ }
  printf '%s' "${t//$QUOTED_NL/ }"
}

# word_text <word>: a quoted word's text with its newlines restored.
word_text() { printf '%s' "${1//$QUOTED_NL/$'\n'}"; }

# END shared parser.

# long_flag <word> <name>: the word is --name, or an abbreviation of it.
long_flag() { [[ ${1%%=*} == --?* && --$2 == "${1%%=*}"* ]]; }
# short_flag <word> <letter>: the word is a short-flag group that holds the letter.
short_flag() { [[ $1 == -[!-]* && $1 == *"$2"* ]]; }

# unique_commits <repo> <branch>: commits on <branch> that no other branch,
# remote-tracking branch or tag reaches. Empty output means nothing is lost.
unique_commits() {
  git -C "$1" rev-list "refs/heads/$2" --not --exclude="$2" --branches --remotes --tags 2>/dev/null
}

# nothing_lost <repo> <word>...: the words after `git branch`. True when each
# branch they name has all its commits somewhere else in the repo.
nothing_lost() {
  local repo=$1 w target=0 named=0 fetched=0
  shift
  for w in "$@"; do
    # A redirect (2>&1, >/dev/null, > file) is not a branch name. A bare
    # operator takes the next word as its target.
    if ((target)); then
      target=0
      continue
    fi
    if [[ $w =~ ^[0-9]*\&?(\>\>?|\<)(.*)$ ]]; then
      [[ -n ${BASH_REMATCH[2]} ]] || target=1
      continue
    fi
    if [[ $w == -* ]]; then
      [[ $w =~ ^-[dDfqv]+$ ]] || long_flag "$w" delete || long_flag "$w" force || long_flag "$w" quiet || return 1
      continue
    fi
    named=1
    [[ $w != *[\$\`\*\?]* ]] || return 1
    git -C "$repo" rev-parse --verify --quiet "refs/heads/$w" >/dev/null 2>&1 || return 1
    [[ -z $(unique_commits "$repo" "$w") ]] && continue
    if ((! fetched)); then
      fetched=1
      timeout 15 git -C "$repo" fetch --quiet --no-tags origin >/dev/null 2>&1
    fi
    [[ -z $(unique_commits "$repo" "$w") ]] || return 1
  done
  ((named))
}

# names_whole_tree <word>...: a word, not a flag, that is the whole tree.
names_whole_tree() {
  local w
  for w in "$@"; do
    case $w in
      . | .. | ./* | ../* | :/ | :/* | '*') return 0 ;;
    esac
  done
  return 1
}

# shared_checkout <dir> <subcommand> <word>...: prints why a branch change is
# refused: another live agent terminal works in the same work tree. Prints
# nothing for a command that keeps the branch (a path checkout, git restore),
# with no HC_TERMINAL_ID, no hc, or an hc that is silent for 3 s.
shared_checkout() {
  local dir=$1 sub=$2 w top ref=0 addr agent cwd t
  shift 2
  local -a args=("$@")
  for w in "${args[@]}"; do
    [[ $w == -- ]] && return
  done
  if [[ $sub == switch ]]; then
    ((${#args[@]})) && ref=1
  else
    for w in "${args[@]}"; do
      if short_flag "$w" b || short_flag "$w" B; then ref=1; fi
      if [[ $w != -* && $ref == 0 ]]; then
        [[ -e $dir/$w ]] || ref=1
        break
      fi
    done
  fi
  ((ref)) || return 0
  [[ -n ${HC_TERMINAL_ID:-} ]] && command -v hc >/dev/null || return 0
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0
  while IFS=$'\t' read -r addr agent cwd; do
    [[ -n $cwd ]] || continue
    t=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || continue
    if [[ $t == "$top" ]]; then
      printf 'git %s changes the branch in %s, where terminal %s (%s) also works. Work in your own worktree: git worktree add ../<repo>-<name> -b <branch> origin/main\n' "$sub" "$top" "$addr" "$agent"
      return
    fi
  done < <(timeout 3 hc ls --json 2>/dev/null | jq -r --arg me "$HC_TERMINAL_ID" \
    '.terminals[]? | select(.state == "live" and .address != $me and (.agent == "claude-code" or .agent == "codex")) | [.address, .agent, .cwd] | @tsv' 2>/dev/null)
}

# destructive_git <dir> <subcommand> <word>...: prints why the command loses
# work. Prints nothing when it does not.
destructive_git() {
  local dir=$1 sub=$2 w delete=0 force=0 staged=0 worktree=0
  shift 2
  case $sub in
    reset | clean | checkout | restore | branch | switch) ;;
    *) return ;;
  esac
  # A redirect can be glued to the word before it: --hard>/dev/null.
  local -a raw=("$@")
  set -- "${@%%[<>]*}"
  case $sub in
    switch) shared_checkout "$dir" switch "$@" ;;
    reset)
      for w in "$@"; do
        if long_flag "$w" hard; then
          printf 'git reset --hard discards uncommitted work\n'
          return
        fi
      done
      ;;
    clean)
      for w in "$@"; do
        if long_flag "$w" force || short_flag "$w" f; then
          printf 'git clean with force deletes untracked files\n'
          return
        fi
      done
      ;;
    checkout)
      for w in "$@"; do
        if long_flag "$w" ours || long_flag "$w" theirs || long_flag "$w" patch || short_flag "$w" p; then return; fi
      done
      if names_whole_tree "$@"; then
        printf 'git checkout of the whole tree discards uncommitted work\n'
      else
        shared_checkout "$dir" checkout "$@"
      fi
      ;;
    restore)
      for w in "$@"; do
        if long_flag "$w" patch || short_flag "$w" p; then return; fi
        if long_flag "$w" staged || short_flag "$w" S; then staged=1; fi
        if long_flag "$w" worktree || short_flag "$w" W; then worktree=1; fi
      done
      ((staged && ! worktree)) && return
      names_whole_tree "$@" && printf 'git restore of the whole tree discards uncommitted work\n'
      ;;
    branch)
      for w in "$@"; do
        if short_flag "$w" D; then delete=1 force=1; fi
        if long_flag "$w" delete || short_flag "$w" d; then delete=1; fi
        if long_flag "$w" force || short_flag "$w" f; then force=1; fi
      done
      if ((delete && force)) && ! nothing_lost "$dir" "${raw[@]}"; then
        printf 'git branch delete would lose commits, or a name cannot be checked\n'
      fi
      ;;
  esac
}

# default_branch <dir> <remote>: the remote's default branch, from its local
# HEAD ref, else from the remote itself (10 s cap). Fails when neither answers.
default_branch() {
  local ref
  if ref=$(git -C "$1" symbolic-ref --quiet --short "refs/remotes/$2/HEAD" 2>/dev/null); then
    printf '%s\n' "${ref#"$2"/}"
    return 0
  fi
  ref=$(GIT_TERMINAL_PROMPT=0 timeout 10 git -C "$1" ls-remote --symref "$2" HEAD 2>/dev/null \
    | awk '$1 == "ref:" && $3 == "HEAD" { sub(/^refs\/heads\//, "", $2); print $2; exit }')
  [[ -n $ref ]] && printf '%s\n' "$ref"
}

# remote_delete_why <dir> <remote> <branch>...: prints why deleting these
# remote branches is refused. Prints nothing when every commit survives.
remote_delete_why() {
  local dir=$1 remote=$2 default w b ref
  shift 2
  if [[ $remote == -* ]] || ! default=$(default_branch "$dir" "$remote"); then
    printf 'the default branch of remote %s is unknown\n' "$remote"
    return
  fi
  for w in "$@"; do
    if ! b=$(branch_of "$w"); then
      printf 'the remote delete of %s cannot be checked\n' "$w"
      return
    fi
    if [[ $b == main || $b == master || $b == "$default" ]]; then
      printf 'a delete of the default branch %s\n' "$b"
      return
    fi
  done
  if ! timeout 15 git -C "$dir" fetch --quiet --no-tags "$remote" >/dev/null 2>&1; then
    printf 'remote %s cannot be fetched to check the delete\n' "$remote"
    return
  fi
  for w in "$@"; do
    b=$(branch_of "$w")
    ref=refs/remotes/$remote/$b
    if ! git -C "$dir" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      printf 'remote %s has no branch %s to check\n' "$remote" "$b"
      return
    fi
    if [[ -n $(git -C "$dir" rev-list "$ref" --not --branches --tags --exclude="$remote/$b" --remotes 2>/dev/null) ]]; then
      printf 'the remote delete of %s would lose commits found nowhere else\n' "$b"
      return
    fi
  done
}

# branch_of <ref>: the branch a lease or refspec destination names, or fails.
branch_of() {
  local b=${1#refs/heads/}
  [[ -n $b && $b != refs/* && $b != HEAD && $b != -* ]] || return 1
  [[ $b != *[[:space:]\$\`\*\?\[\\~^:]* ]] || return 1
  printf '%s\n' "$b"
}

# forced_push <dir> <arg>...: the words after `git push`. Prints why the push
# is a refused forced push; prints nothing for a plain push or the lease form.
forced_push() {
  local dir=$1 w name val skip=0 ends=0 i includes=0 many=0 deleting=0 forced=""
  local -a leases=() pos=()
  shift
  for w in "$@"; do
    if ((skip)); then
      skip=0
      continue
    fi
    if ((ends)) || [[ $w != -* ]]; then
      # A redirect (2>&1, >/dev/null, > file) is not a refspec.
      if ((! ends)) && [[ $w =~ ^[0-9]*(\&?[<>]+|[<>]+\&)(.*)$ ]]; then
        [[ -n ${BASH_REMATCH[2]} ]] || skip=1
        continue
      fi
      pos+=("$w")
      continue
    fi
    case $w in
      --) ends=1 ;;
      --*)
        name=${w#--}
        name=${name%%=*}
        name=${name%%[<>]*}
        case $name in
          repo | receive-pack | exec | push-option) [[ $w == *=* ]] || skip=1 ;;
          mirror) forced="--mirror force-updates every ref" ;;
          pru*) [[ prune == "$name"* ]] && forced="--prune deletes remote branches" ;;
          de*) [[ delete == "$name"* ]] && deleting=1 ;;
          all | branches | tags) many=1 ;;
          no-force-with-lease) leases=() ;;
          force-w*)
            if [[ force-with-lease != "$name"* ]]; then
              forced="an unknown force option"
            elif [[ $w != *=* ]]; then
              forced="a lease with no expected SHA"
            else
              leases+=("${w#*=}")
            fi
            ;;
          force-i*) [[ force-if-includes == "$name"* ]] && includes=1 || forced="an unknown force option" ;;
          f*) [[ force == "$name"* || $name == force* ]] && forced="the force flag" ;;
        esac
        ;;
      *)
        # A short-flag group: f forces; o takes the rest, or the next word.
        for ((i = 1; i < ${#w}; i++)); do
          case ${w:i:1} in
            f) forced="-f" ;;
            d) deleting=1 ;;
            o)
              ((i + 1 == ${#w})) && skip=1
              break
              ;;
          esac
        done
        ;;
    esac
  done
  [[ -n $forced ]] && {
    printf '%s\n' "$forced"
    return
  }
  for w in "${pos[@]}"; do
    [[ $w == +* ]] && {
      printf 'the +refspec %s\n' "$w"
      return
    }
  done
  local -a gone=()
  for w in "${pos[@]:1}"; do
    if ((deleting)); then
      gone+=("$w")
    elif [[ $w == :?* ]]; then
      gone+=("${w#:}")
    fi
  done
  if ((${#gone[@]})); then
    val=$(remote_delete_why "$dir" "${pos[0]}" "${gone[@]}")
    [[ -n $val ]] && {
      printf '%s\n' "$val"
      return
    }
  fi
  if ((${#leases[@]} == 0)); then
    ((includes)) && printf -- '--force-if-includes with no lease\n'
    return
  fi
  ((many)) && {
    printf 'a lease with --all, --branches or --tags\n'
    return
  }
  ((${#pos[@]} >= 2)) || {
    printf 'a lease with no refspec\n'
    return
  }

  local remote=${pos[0]} default b
  local -A leased=() pushed=()
  for val in "${leases[@]}"; do
    if [[ ! $val =~ ^([^:]+):([0-9a-fA-F]{7,40})$ ]] || ! b=$(branch_of "${BASH_REMATCH[1]}"); then
      printf 'the lease %s does not name a branch and its 7 to 40 hex SHA\n' "$val"
      return
    fi
    leased[$b]=1
  done
  for w in "${pos[@]:1}"; do
    if ! b=$(branch_of "${w#*:}") || [[ -z ${leased[$b]-} ]]; then
      printf 'the refspec %s does not push a leased branch\n' "$w"
      return
    fi
    pushed[$b]=1
  done
  for b in "${!leased[@]}"; do
    [[ -n ${pushed[$b]-} ]] || {
      printf 'the lease for %s has no refspec\n' "$b"
      return
    }
  done
  if [[ $remote == -* ]] || ! default=$(default_branch "$dir" "$remote"); then
    printf 'the default branch of remote %s is unknown\n' "$remote"
    return
  fi
  for b in "${!leased[@]}"; do
    if [[ $b == main || $b == master || $b == "$default" ]]; then
      printf 'a lease on the default branch %s\n' "$b"
      return
    fi
  done
}

# Programs whose quoted argument is a command line, not text.
RUNNERS=" bash sh zsh dash ash ksh fish eval ssh xargs su runuser watch "

# git_verdict <dir> <text> <depth>: prints why a git command in <text> is
# refused. Prints nothing when every command passes.
git_verdict() {
  local dir=$1 text line w j why runner gdir bare base depth=$3
  local -a words=() next=()
  text=$(plain_text "$2")
  bare=${text//[\"\'\\$'\n']/}
  [[ $bare =~ $GIT_WORDS ]] || return
  if ((depth > 4)); then
    printf 'commands nested too deep to check\n'
    return
  fi
  while IFS= read -r line; do
    if [[ $line != "$SEG_END" ]]; then
      next+=("$line")
      continue
    fi
    words=("${next[@]}")
    next=()
    ((${#words[@]})) || continue
    if [[ ${words[0]} == cd ]]; then
      w=${words[1]:-$HOME}
      w=${w/#\~/$HOME}
      [[ $w == /* ]] || w=$dir/$w
      dir=$w
      continue
    fi
    runner=0
    for ((j = 0; j < ${#words[@]}; j++)); do
      w=${words[j]}
      # A program name is short. Trimming a long word takes bash many seconds.
      base=
      ((${#w} < 4096)) && base=${w##*/}
      if [[ -n $base && $RUNNERS == *" $base "* ]]; then
        runner=1
      elif ((runner)) && [[ $w == *[[:space:]]* || $w == *"$QUOTED_NL"* ]]; then
        why=$(git_verdict "$dir" "$(word_text "$w")" $((depth + 1)))
        [[ -n $why ]] && {
          printf '%s\n' "$why"
          return
        }
      elif [[ $base == git ]]; then
        gdir=$dir
        for ((j++; j < ${#words[@]}; j++)); do
          case ${words[j]} in
            -C)
              ((j++))
              gdir=${words[j]-}
              gdir=${gdir/#\~/$HOME}
              [[ $gdir == /* ]] || gdir=$dir/$gdir
              ;;
            -c | --config-env)
              ((j++))
              if [[ ${words[j]-} =~ ^(alias\..*push|remote\..*\.(push|mirror)) ]]; then
                printf 'git -c %s can force a push\n' "${words[j]}"
                return
              fi
              ;;
            --git-dir | --work-tree | --namespace | --exec-path) ((j++)) ;;
            -*) ;;
            *) break ;;
          esac
        done
        if [[ ${words[j]-} == push ]]; then
          why=$(forced_push "$gdir" "${words[@]:j+1}")
        else
          why=$(destructive_git "$gdir" "${words[j]-}" "${words[@]:j+1}")
        fi
        [[ -n $why ]] && {
          printf '%s\n' "$why"
          return
        }
      fi
    done
  done < <(split_segments <<<"$text" | split_words)
}

# refuse_command <why>: one line, then exit 2.
refuse_command() {
  local what=${COMMAND//[$'\n\r\t']/ }
  ((${#what} > 200)) && what="${what:0:200}..."
  echo "BLOCKED: '$what' is refused: $1. The user has prevented you from doing this. The one forced push allowed is a lease with the exact SHA, to a branch that is not the default: git push --force-with-lease=refs/heads/<branch>:<sha> <remote> HEAD:refs/heads/<branch>" >&2
  exit 2
}

SCAN=$(plain_text "$COMMAND" | strip_heredocs)

# The raw scan. It needs no parse, so it cannot be fooled by one. It reads the
# text twice, because a continuation can split a pattern in two. A dot followed
# by a word character is a dotfile (.gitignore), not the tree.
RAW_PATTERNS=(
  'reset --hard'
  'git clean -fd'
  'git clean -f'
  'git checkout (-- )?\.($|[^[:alnum:]_-])'
  'git restore (-- )?\.($|[^[:alnum:]_-])'
)
JOINED=$(plain_text "${COMMAND//$'\\\n'/}" | strip_heredocs)
for pattern in "${RAW_PATTERNS[@]}"; do
  if grep -qE -- "$pattern" <<<"$SCAN" || grep -qE -- "$pattern" <<<"$JOINED"; then
    refuse_command "it matches the pattern '$pattern'"
  fi
done

# A quoted or variable-led `git branch -D` cannot be checked by name, so it is
# refused. The word parse judges every other form.
while IFS= read -r segment; do
  if [[ $segment == *"git branch -D"* && $segment == *[\'\"\$\`]* ]]; then
    refuse_command "a git branch -D with a quoted or computed name cannot be checked"
  fi
done < <(sed -E 's/(&&|\|\||;|\|)/\n/g' <<<"$SCAN")

# A comment read wrongly can hide a command, and so can an apostrophe in a real
# comment read as a quote. Read it both ways: refuse when either read refuses.
WHY=$(git_verdict "${CWD:-$PWD}" "$SCAN" 0)
if [[ -z $WHY && $SCAN == *'#'* ]]; then
  WHY=$(COMMENTS=keep git_verdict "${CWD:-$PWD}" "$SCAN" 0)
fi
[[ -z $WHY ]] || refuse_command "$WHY"

exit 0
