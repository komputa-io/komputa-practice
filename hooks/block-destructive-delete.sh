#!/bin/bash
# A Claude Code (and Codex) PreToolUse gate for Bash. It refuses deletes that
# cannot be undone. Under the working rules (rules/working-rules.md), an
# action that cannot be undone is the lead's or the operator's decision, not a
# worker's, so the operator must run it by hand. Only a deny reaches the agent
# before the call runs, so the gate refuses (exit 2, one line on stderr); it
# never only warns.
#
# Blocks:
#  - Forge and wiki deletes: `gh repo delete`, `glab repo delete`,
#    `tea repo(s) delete|rm`, `docmost delete-space`; an API DELETE of a
#    project, group, repo, org or space (`odev api`, `gh api`, `glab api`,
#    curl, wget, http/https, xh) given by -X, --request or --method, or as
#    httpie's method word; and any HTTP call to Docmost's `api/spaces/delete`.
#  - A recursive rm (-r, -R or --recursive, with or without -f, in any flag
#    order) whose target lies outside the current checkout and is a whole
#    checkout (a sibling repo or worktree root, or a bare repo), a path
#    directly under home, a folder that holds a checkout up to three levels
#    down, or a path under the session tmp root (<tmp>/claude-<uid>) outside
#    this session's own folder. `git rm -r` is judged the same way, from its
#    `git -C` folder.
#  - A recursive rm of a `.git` folder or anything under one, anywhere, the
#    current checkout included: it holds the commits that were never pushed.
#  - Any rm (recursive or not) with an unquoted glob (*, ? or [...]) whose
#    pattern lies outside the current checkout and this session's own folder
#    (`rm -f /tmp/x[0-9]*` once removed a file the agent had not made). Delete
#    only files you made, each by its exact path.
#  The target is resolved first: `cd` and `pushd` earlier in the same
#  command, `env -C`, `git -C`, `~`, `~user`, `$HOME`, `${HOME}`, `..`,
#  symlinked parents (and the link itself when the path ends in `/`), {a,b}
#  lists and globs.
#
# Allows:
#  - Other deletes strictly inside the current checkout: the git top level
#    of the payload's cwd. There is none when cwd is in no checkout, or when
#    the checkout is home or `/`.
#  - Deletes inside this session's own folder,
#    <tmp>/claude-<uid>/<transcript folder>/<session_id>/, built from the
#    payload's transcript_path and session_id (<tmp> is $CLAUDE_CODE_TMPDIR,
#    else /tmp). It holds the session's scratchpad.
#  - A glob inside the checkout or the session's own folder, a quoted glob
#    (a literal name) and an exact path anywhere.
#  - A non-recursive rm without a glob; a recursive rm of any other path (a temp folder, a
#    folder inside a sibling checkout, a deep folder under home); and a
#    symlink named without a trailing `/` (rm removes the link only).
#  - `/`, home itself, the working folder and its parents. Claude Code's own
#    dangerous-rm check asks a person for those even in bypass mode, so this
#    gate does not repeat it. That check does not run under Codex.
#  - git branch and worktree removals: block-dangerous-git.sh judges those.
#  - Text that only mentions a delete: heredoc bodies and quoted arguments
#    are data. A quoted argument of bash/sh -c, eval, su or watch is
#    commands, so it is judged, and so is the body of $(...) and `...`. An
#    ssh command string is judged for forge deletes only: its paths are on
#    another machine.
#
# Does not catch: a target in a variable other than $HOME, in a command
# substitution or in a {1..3} range (Claude Code's check prompts for an
# unresolved rm target); text piped to a shell (echo ... | bash); targets read
# by xargs or find -exec; find -delete,
# rsync --delete, mv to /dev/null and other tools that delete; rm over ssh;
# a delete inside a script file or an alias; an HTTP method override header;
# a forge's web UI. A rm of a subfolder of a sibling checkout is allowed:
# git can restore its tracked files.
#
# A payload that is not one JSON object, or a Bash call with no command
# string, is refused. Any other failure inside the gate also refuses (exit 2),
# because exit 1 would let the call run.

# No -e: a failed test is a normal answer here. Every path ends in exit 0 or
# exit 2, and the trap turns any other exit into a refusal.
set -uo pipefail
# shellcheck disable=SC2329 # run by the EXIT trap
on_exit() {
  local rc=$?
  if ((rc != 0 && rc != 2)); then
    echo "BLOCKED [delete gate: internal error]: the gate failed (exit $rc), so the call is refused. Check the hook." >&2
    exit 2
  fi
}
trap on_exit EXIT
unset GIT_DIR GIT_WORK_TREE

# refuse <rule> <what>: one line naming the rule, then exit 2.
refuse() {
  local what=${2//[$'\n\r\t']/ }
  ((${#what} > 200)) && what="${what:0:200}..."
  echo "BLOCKED [delete gate: $1]: $what. This cannot be undone, so the operator must do it by hand." >&2
  exit 2
}

INPUT=$(cat)
jq -e -s 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1 <<<"$INPUT" \
  || refuse "malformed payload" "the hook input is not one JSON object"
# str <filter>: a string field, or nothing. NUL becomes a space: bash cannot hold it.
str() { jq -j "$1 | if type == \"string\" then split(\"\\u0000\") | join(\" \") else empty end" <<<"$INPUT" 2>/dev/null; }
TOOL=$(str '.tool_name')
[[ -n $TOOL && $TOOL != Bash ]] && exit 0
jq -e '.tool_input.command | type == "string"' >/dev/null 2>&1 <<<"$INPUT" \
  || refuse "malformed payload" "a Bash call with no command string"
COMMAND=$(str '.tool_input.command')

# Fast path: no rm and no delete, nothing to judge.
LOWER=${COMMAND,,}
LOWER=${LOWER//[\"\'\\$'\n']/}
[[ $LOWER == *rm* || $LOWER == *delete* ]] || exit 0

CWD=$(str '.cwd')
[[ -n $CWD && -d $CWD ]] || CWD=$PWD
CWD=$(realpath -m -- "$CWD")
HOME_REAL=$(realpath -m -- "${HOME:-/}")
CHECKOUT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) && CHECKOUT=$(realpath -m -- "$CHECKOUT")
[[ $CHECKOUT == "$HOME_REAL" || $CHECKOUT == / ]] && CHECKOUT=
TMP_ROOT=$(realpath -m -- "${CLAUDE_CODE_TMPDIR:-/tmp}/claude-$(id -u)")
SESSION_DIR=
session=$(str '.session_id')
slug=$(str '.transcript_path')
slug=${slug%/*}
slug=${slug##*/}
safe='^[A-Za-z0-9._-]+$'
if [[ $session =~ $safe && $slug =~ $safe && $session != . && $session != .. && $slug != . && $slug != .. ]]; then
  SESSION_DIR=$TMP_ROOT/$slug/$session
fi

KEEP_LINE='[Rr][Mm]|[Dd][Ee][Ll][Ee][Tt][Ee]|^[ \t{]*(cd|pushd)([ \t]|$)'

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

SCAN=$(plain_text "$COMMAND" | strip_heredocs)

# expand_path <dir> <word>: the word as an absolute path, with ~, ~user,
# $HOME and ${HOME} expanded. Fails when it holds anything else that the
# shell would expand, or is relative to an unknown folder.
expand_path_r() {
  local dir=$1 w=$2 user home
  # shellcheck disable=SC2088,SC2016 # the literal text the command holds
  case $w in
    '~' | '~/'*) w=$HOME${w:1} ;;
    '~'*)
      user=${w%%/*}
      user=${user:1}
      home=$(getent passwd -- "$user" | cut -d: -f6) && [[ -n $home ]] || return 1
      w=$home${w:${#user}+1}
      ;;
    '$HOME' | '$HOME/'*) w=$HOME${w:5} ;;
    '${HOME}' | '${HOME}/'*) w=$HOME${w:7} ;;
  esac
  [[ $w == *[\$\`]* || $w == *\{*\}* ]] && return 1
  if [[ $w != /* ]]; then
    [[ -n $dir ]] || return 1
    w=$dir/$w
  fi
  REPLY=$w
}
# expand_path prints it; rm_args calls expand_path_r, so a long list of targets forks nothing (issue #21).
expand_path() {
  expand_path_r "$@" || return 1
  printf '%s\n' "$REPLY"
}

# braces <word>: the word with each {a,b} list expanded, as bash does; a
# {1..3} range or a nested list stays as it is. At most 1000 words.
braces() {
  local -a todo=("$1") parts=()
  local w alt n=0
  while ((${#todo[@]} && n < 1000)); do
    w=${todo[0]}
    todo=("${todo[@]:1}")
    if [[ $w =~ ^([^{]*)\{([^{}]*,[^{}]*)\}(.*)$ ]]; then
      IFS=, read -ra parts <<<"${BASH_REMATCH[2]},"
      for alt in "${parts[@]}"; do
        todo+=("${BASH_REMATCH[1]}$alt${BASH_REMATCH[3]}")
      done
    else
      printf '%s\n' "$w"
      n=$((n + 1))
    fi
  done
}

# canonical <abs>: the real path rm acts on, in REPLY. The last part is kept as it is
# (rm removes a symlink, not its target) unless the path ends in / or a dot.
# A path ends in / or a dot: its own real path. Otherwise: the real path of its parent.
# resolve_key <abs>: the path whose real path canonical needs.
resolve_key() {
  local p=$1
  if [[ $p == */ || $p == */. || $p == */.. ]]; then
    KEY=$p
  else
    KEY=${p%/*}
    KEY=${KEY:-/}
  fi
}
# REAL maps a path to its real path. resolve_all <abs>...: fills it with one realpath run for all
# the distinct paths, not one fork for each target (issue #21: 50,000 targets took minutes).
declare -A REAL=()
resolve_all() {
  local p key
  local -a keys=() out=()
  declare -A seen=()
  for p in "$@"; do
    resolve_key "$p"
    key=$KEY
    [[ -n ${seen[$key]+x} || -n ${REAL[$key]+x} || $key == *$'\n'* ]] && continue
    seen[$key]=1
    keys+=("$key")
  done
  ((${#keys[@]})) || return 0
  mapfile -t out < <(printf '%s\0' "${keys[@]}" | xargs -0 realpath -m -- 2>/dev/null)
  ((${#out[@]} == ${#keys[@]})) || return 0
  for ((p = 0; p < ${#keys[@]}; p++)); do
    REAL[${keys[p]}]=${out[p]}
  done
}
canonical() {
  local p=$1 parent
  resolve_key "$p"
  if [[ -n ${REAL[$KEY]+x} ]]; then
    parent=${REAL[$KEY]}
  else
    parent=$(realpath -m -- "$KEY")
  fi
  if [[ $p == */ || $p == */. || $p == */.. ]]; then
    REPLY=$parent
    return
  fi
  [[ $parent == / ]] && parent=
  REPLY=$parent/${p##*/}
}

# inside <path> <root>: true when path is root or below it.
inside() { [[ $2 == / || $1 == "$2" || $1 == "$2"/* ]]; }

# judge_target <path>: refuses a real path that cannot be safely deleted.
judge_target() {
  local t=$1 found
  [[ -n $SESSION_DIR ]] && inside "$t" "$SESSION_DIR" && return
  [[ $t == */.git || $t == */.git/* ]] && refuse "a checkout's .git folder (its history)" "rm -r $t"
  # / , home, the working folder and its parents: Claude Code's own check.
  [[ $t == / || $t == "$HOME_REAL" ]] && return
  inside "$CWD" "$t" && return
  [[ -n $CHECKOUT && $t == "$CHECKOUT"/* ]] && return
  inside "$t" "$TMP_ROOT" && refuse "another session's tmp folder" "rm -r $t"
  [[ ${t%/*} == "$HOME_REAL" ]] && refuse "a path directly under home" "rm -r $t"
  [[ -L $t ]] && return
  [[ -e $t/.git ]] && refuse "a whole checkout" "rm -r $t"
  [[ -f $t/HEAD && -d $t/objects && -d $t/refs ]] && refuse "a whole bare repo" "rm -r $t"
  [[ -d $t ]] || return
  found=$(timeout 5 find "$t" -mindepth 2 -maxdepth 4 -name .git -print -quit 2>/dev/null)
  case $? in
    0 | 1) ;;
    *) refuse "a folder too big to check for checkouts" "rm -r $t" ;;
  esac
  [[ -n $found ]] && refuse "a folder that holds a checkout (${found%/.git})" "rm -r $t"
}

MAX_TARGETS=5000

# glob_outside <word>...: refuses an unquoted glob whose pattern lies outside the
# checkout and this session's folder (the shell would expand it over files the
# agent did not make). A quoted glob names a literal file, so it passes. The
# parser strips quotes, so a word counts as quoted when the command holds it
# wrapped in quotes; a word that is quoted in one place and bare in another, or that
# cannot be resolved ($VAR, an unknown ~user, a relative path after an unknown cd), is refused.
glob_outside() {
  local w x abs pre rest
  for x in "$@"; do
    while IFS= read -r w; do
      [[ $w == *[*?[]* ]] || continue
      rest=${COMMAND//"'$w'"/}
      rest=${rest//"\"$w\""/}
      [[ $rest != "$COMMAND" && $rest != *"$w"* ]] && continue
      expand_path_r "$dir" "$w" || refuse "a glob that cannot be resolved" "rm $w. Delete only files you made, each by its exact path"
      pre=${REPLY%%[*?[]*}
      pre=${pre%/*}
      abs=$(realpath -m -- "${pre:-/}")
      [[ -n $SESSION_DIR ]] && inside "$abs" "$SESSION_DIR" && continue
      [[ -n $CHECKOUT ]] && inside "$abs" "$CHECKOUT" && continue
      refuse "a glob outside the checkout" "rm $w. Delete only files you made, each by its exact path"
    done < <(braces "${x%%[<>]*}")
  done
}

# rm_args <dir> <word>...: the words after rm (or git rm). Judges each
# target when the delete is recursive.
rm_args() {
  local dir=$1 w ends=0 skip=0 recursive=0 abs m any
  local -a targets=()
  shift
  for w in "$@"; do
    if ((skip)); then
      skip=0
      continue
    fi
    if ((! ends)) && [[ $w =~ ^[0-9]*(\&?[\<\>]+|[\<\>]+\&)(.*)$ ]]; then
      [[ -n ${BASH_REMATCH[2]} ]] || skip=1
      continue
    fi
    if ((ends)) || [[ $w != -* || $w == - ]]; then
      targets+=("$w")
    elif [[ $w == -- ]]; then
      ends=1
    elif [[ $w == --* ]]; then
      [[ ${#w} -gt 3 && recursive == "${w#--}"* ]] && recursive=1
    elif [[ $w == *[rR]* ]]; then
      recursive=1
    fi
  done
  glob_outside "${targets[@]}"
  ((recursive)) || return
  # The check costs time for each target. A hook that outlasts its timeout lets the delete run, so a list this long
  # is refused: the operator runs it by hand (issue #21). 5,000 targets take about 1 s; 50,000 took minutes.
  ((${#targets[@]} <= MAX_TARGETS)) || refuse "too many targets to check (${#targets[@]})" "rm -r ($((${#targets[@]})) targets)"
  mapfile -t targets < <(for w in "${targets[@]}"; do braces "${w%%[<>]*}"; done)
  local -a abss=()
  for w in "${targets[@]}"; do
    [[ -n $w ]] || continue
    expand_path_r "$dir" "$w" || continue
    abss+=("$REPLY")
  done
  resolve_all "${abss[@]}"
  for abs in "${abss[@]}"; do
    if [[ $abs == *[*?[]* ]]; then
      any=0
      while IFS= read -r m; do
        any=1
        canonical "$m"
        judge_target "$REPLY"
      done < <(compgen -G "$abs" | head -n 2000)
      ((any)) && continue
    fi
    canonical "$abs"
    judge_target "$REPLY"
  done
}

# is_delete_method <word>...: true when the words set the HTTP method to
# DELETE: -X DELETE, -XDELETE, -sX DELETE, --request[=]DELETE, --method[=]DELETE.
is_delete_method() {
  local w prev=""
  for w in "$@"; do
    w=${w,,}
    [[ $prev == 1 && $w == delete ]] && return 0
    prev=""
    case $w in
      --request=delete | --method=delete) return 0 ;;
      --request | --method) prev=1 ;;
      --*) ;;
      -*x) prev=1 ;;
      -*xdelete) return 0 ;;
    esac
  done
  return 1
}

# api_resource <word>...: true when a word is the API path of a whole
# project, group, repo, org or space.
api_resource() {
  local w
  for w in "$@"; do
    w=${w,,}
    [[ $w == *://* ]] && w=/${w#*://*/}
    w=${w%%[?#]*}
    while [[ $w == */ ]]; do w=${w%/}; done
    [[ $w =~ (^|/)(projects|groups|orgs|organizations|spaces)/[^/]+$ || $w =~ (^|/)repos/[^/]+/[^/]+$ ]] && return 0
  done
  return 1
}

# first_args <word>...: the words from the first one that is not an option.
first_args() {
  while (($#)) && [[ $1 == -* ]]; do shift; done
  printf '%s\n' "$@"
}

RUNNERS=" bash sh zsh dash ash ksh fish su runuser watch "
# Wrappers that run the command after their options, and the options of each
# that take the next word as a value.
declare -A OPT_ARGS=(
  [sudo]=" -u -g -h -p -C -D -r -t -U -T --user --group --host --prompt --close-from --chdir --role --type --other-user --command-timeout "
  [doas]=" -u -C " [nice]=" -n --adjustment " [ionice]=" -c -n -p -P -u --class --classdata "
  [stdbuf]=" -i -o -e --input --output --error " [timeout]=" -s -k --signal --kill-after "
  [env]=" -u --unset " [flock]=" -w -E --timeout --conflict-exit-code " [exec]=" -a "
  [xargs]=" -a -d -E -I -L -n -P -s --arg-file --delimiter --max-args --max-procs --max-chars --max-lines "
  [nohup]=" " [command]=" " [builtin]=" " [setsid]=" " [chronic]=" " [unbuffer]=" " [time]=" "
  [busybox]=" " [run0]=" -u -D --user --chdir --unit --property --setenv "
)

# judge_text <dir> <remote> <depth> <text>: judges every command in text.
# remote=1 judges forge deletes only (the paths are on another machine).
judge_text() {
  local dir=$1 remote=$2 depth=$3 text line w
  local -a words=() next=()
  text=$(plain_text "$4")
  if ((depth > 4)); then
    [[ ${text,,} == *rm* || ${text,,} == *delete* ]] && refuse "commands nested too deep to check" "${text:0:80}"
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
    while ((${#words[@]})) && [[ ${words[0]} == '{' || ${words[0]} == '!' || ${words[0]} =~ ^(then|do|else|elif|if|while|until|time)$ ]]; do
      words=("${words[@]:1}")
    done
    ((${#words[@]})) || continue
    if [[ ${words[0]} == cd || ${words[0]} == pushd ]]; then
      mapfile -t next < <(first_args "${words[@]:1}")
      w=${next[0]-~}
      next=()
      if [[ $w == - ]]; then
        dir=
      else
        dir=$(expand_path "$dir" "$w") || dir=
      fi
      continue
    fi
    judge_cmd "$dir" "$remote" "$depth" "${words[@]}"
  done < <(split_segments <<<"$text" | split_words)
}

# judge_cmd <dir> <remote> <depth> <word>...: one simple command. Finds the
# program at command position past assignments and wrappers.
judge_cmd() {
  local dir=$1 remote=$2 depth=$3 prog w i
  shift 3
  local -a a=("$@") rest=()
  while ((${#a[@]})); do
    w=${a[0]}
    if [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= || $w =~ ^[0-9]*[\<\>] ]]; then
      a=("${a[@]:1}")
      continue
    fi
    prog=${w##*/}
    if [[ -n ${OPT_ARGS[$prog]-} ]]; then
      a=("${a[@]:1}")
      # Options; those in OPT_ARGS take the next word as their value.
      while ((${#a[@]})) && [[ ${a[0]} == -* ]]; do
        w=${a[0]}
        a=("${a[@]:1}")
        [[ $w == -- ]] && break
        if [[ $prog == env && ($w == -C || $w == --chdir) ]]; then
          dir=$(expand_path "$dir" "${a[0]-}") || dir=
          a=("${a[@]:1}")
        elif [[ $prog == env && ($w == -S || $w == --split-string) ]]; then
          judge_text "$dir" "$remote" $((depth + 1)) "${a[*]}"
          return
        elif [[ ${OPT_ARGS[$prog]-} == *" $w "* ]]; then
          a=("${a[@]:1}")
        fi
      done
      [[ $prog == env ]] && while ((${#a[@]})) && [[ ${a[0]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do a=("${a[@]:1}"); done
      # timeout DURATION and flock FILE come before the command.
      [[ $prog == timeout || $prog == flock ]] && a=("${a[@]:1}")
    else
      break
    fi
  done
  ((${#a[@]})) || return
  prog=${a[0]##*/}
  rest=("${a[@]:1}")

  if [[ $RUNNERS == *" $prog "* || $prog == ssh ]]; then
    [[ $prog == ssh ]] && remote=1
    for w in "${rest[@]}"; do
      [[ $w == *[[:space:]]* || $w == *"$QUOTED_NL"* ]] && judge_text "$dir" "$remote" $((depth + 1)) "$(word_text "$w")"
    done
    return
  fi
  case $prog in
    eval) judge_text "$dir" "$remote" $((depth + 1)) "$(word_text "${rest[*]}")" ;;
    rm) ((remote)) || rm_args "$dir" "${rest[@]}" ;;
    git)
      for ((i = 0; i < ${#rest[@]}; i++)); do
        case ${rest[i]} in
          -C)
            ((i++))
            dir=$(expand_path "$dir" "${rest[i]-}") || dir=
            ;;
          -c | --git-dir | --work-tree | --namespace | --exec-path | --config-env) ((i++)) ;;
          -*) ;;
          *) break ;;
        esac
      done
      # git rm --cached deletes no file.
      [[ ${rest[i]-} == rm && " ${rest[*]:i+1} " != *" --cached "* ]] && ((! remote)) && rm_args "$dir" "${rest[@]:i+1}"
      ;;
    gh | glab | tea)
      mapfile -t a < <(first_args "${rest[@]}")
      if [[ ${a[0]-} == repo || ($prog == tea && ${a[0]-} == repos) ]] && [[ ${a[1]-} =~ ^(delete|rm|remove)$ ]]; then
        refuse "forge repo delete" "$prog ${a[0]} ${a[1]} ${a[2]-}"
      fi
      if [[ ${a[0]-} == api ]] && is_delete_method "${rest[@]}" && api_resource "${a[@]:1}"; then
        refuse "forge API delete of a whole repo, project or org" "$prog api DELETE"
      fi
      ;;
    odev)
      if [[ " ${rest[*]} " == *" api "* ]] && is_delete_method "${rest[@]}" && api_resource "${rest[@]}"; then
        refuse "forge API delete of a whole project" "odev api DELETE"
      fi
      ;;
    docmost)
      for ((i = 0; i < ${#rest[@]}; i++)); do
        case ${rest[i]} in
          --url | --email | --password | --auth-token) ((i++)) ;;
          -*) ;;
          *) break ;;
        esac
      done
      [[ ${rest[i]-} == delete-space ]] && refuse "wiki space delete" "docmost delete-space"
      ;;
    curl | wget | http | https | xh | xhs | curlie)
      for w in "${rest[@]}"; do
        [[ ${w,,} == *api/spaces/delete* ]] && refuse "wiki space delete" "$prog .../api/spaces/delete"
      done
      if [[ $prog =~ ^(http|https|xh|xhs|curlie)$ ]]; then
        for w in "${rest[@]}"; do
          [[ ${w,,} == delete ]] && api_resource "${rest[@]}" && refuse "forge or wiki API delete of a whole repo, project, org or space" "$prog DELETE"
        done
      fi
      is_delete_method "${rest[@]}" && api_resource "${rest[@]}" \
        && refuse "forge or wiki API delete of a whole repo, project, org or space" "$prog -X DELETE"
      ;;
  esac
}

# A comment read wrongly can hide a command, and so can an apostrophe in a real
# comment read as a quote. Read it both ways: each read refuses by itself.
judge_text "$CWD" 0 0 "$SCAN"
if [[ $SCAN == *'#'* ]]; then
  COMMENTS=keep judge_text "$CWD" 0 0 "$SCAN"
fi
exit 0
