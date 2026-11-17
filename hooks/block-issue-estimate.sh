#!/bin/bash
# A Claude Code PreToolUse gate for Bash. Every issue an agent files carries one line, so Sitrep Live can forecast:
#   Estimate: <size> (<low>–<high>). Basis: ...        sizes S M L XL, low <= size <= high, the dash is – or -
# It refuses `gh issue create` and `odev issue create` whose body has no such line. It reads the body from --body/-b
# (quoted), --body-file/-F <path> (a file; `-` is the heredoc or here-string of the same command), or the heredoc
# inside a "$(cat <<'EOF' ...)" body. A body it cannot read (a $variable, a missing file, stdin from a pipe) passes:
# CI cannot catch it, so the hook stays conservative. An issue that also sets needs-triage passes (a person files
# those in the web UI and they are triaged in), and so does any other command. Text in quotes is not a command.
# A repo opts out with: git config komputa.estimate-rule off.
#   echo '{"tool_name":"Bash","tool_input":{"command":"gh issue create -b hi"}}' | block-issue-estimate.sh
# Exit 2 refuses with one BLOCKED line. Any other failure refuses too, as in the other gates.
set -uo pipefail
# shellcheck disable=SC2329 # run by the EXIT trap
on_exit() {
  local rc=$?
  if ((rc != 0 && rc != 2)); then
    echo "BLOCKED [issue estimate: internal error]: the hook failed (exit $rc), so the call is refused. Check the hook." >&2
    exit 2
  fi
}
trap on_exit EXIT
command -v jq >/dev/null || exit 1

INPUT=$(cat)
[[ $(jq -r '.tool_name // ""' <<<"$INPUT" 2>/dev/null) == Bash ]] || exit 0
cmd=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null) || exit 1
[[ $cmd == *issue* && $cmd == *create* ]] || exit 0

SEP=$'\x01' BS=$'\\'
rank() { case $1 in S) echo 1 ;; M) echo 2 ;; L) echo 3 ;; XL) echo 4 ;; esac }

good_line() { # good_line <line>: a well-formed Estimate line
  local re='^Estimate: (S|M|L|XL) \((S|M|L|XL)[–-](S|M|L|XL)\)\.( .*)?$'
  [[ $1 =~ $re ]] || return 1
  local s l h
  s=$(rank "${BASH_REMATCH[1]}") l=$(rank "${BASH_REMATCH[2]}") h=$(rank "${BASH_REMATCH[3]}")
  ((l <= s && s <= h))
}

has_estimate() { # has_estimate <text>
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    good_line "${line%$'\r'}" && return 0
  done <<<"$1"
  return 1
}

refuse() {
  [[ $(git config --get komputa.estimate-rule off 2>/dev/null) == off ]] && exit 0
  echo "BLOCKED [issue estimate]: the issue body has no well-formed Estimate line. Add one line: 'Estimate: <size> (<low>–<high>). Basis: ...' where each size is S, M, L or XL and low <= size <= high, for example 'Estimate: M (S–L). Basis: #298, #301 (both M).' Base it on 3–5 similar closed issues in this project. Or add the needs-triage label if a person will triage it." >&2
  exit 2
}

# Split the command into words and commands. Outside quotes, ; & | ( ) { } and a newline end a command. Quotes join
# into the word and go; text inside them is literal. A word with $ or a backtick outside single quotes is dynamic
# (dyn). A heredoc body goes to the command that opened it; so does a here-string.
CMDS=() HERE=()
# shellcheck disable=SC2016 # the $( is literal text
CATHERE='$(cat <<' # a body that quotes its own heredoc is readable text
words=() dyns=() word="" has=0 dyn=0 q="" n=${#cmd}
hpend="" hstrip=0 hown=-1 hs=0
endword() {
  if ((has)); then
    words+=("$word")
    dyns+=("$dyn")
    if ((hs)); then HERE[${#CMDS[@]}]=$word hs=0; fi
    [[ $word == "<<<" ]] && hs=1
  fi
  word="" has=0 dyn=0
}
endcmd() {
  endword
  if ((${#words[@]})); then
    local i out=""
    for i in "${!words[@]}"; do out+="${words[i]}${SEP}${dyns[i]}${SEP}"; done
    CMDS+=("$out")
  fi
  words=() dyns=()
}
i=0
while ((i < n)); do
  c=${cmd:i:1}
  if [[ -n $q ]]; then
    if [[ $c == "$q" ]]; then
      q=""
    elif [[ $q == '"' && $c == "$BS" && ${cmd:i+1:1} =~ [\"\\\$\`] ]]; then
      word+=${cmd:i+1:1} && ((i++))
    else
      [[ $q == '"' && $c =~ [\$\`] ]] && dyn=1
      word+=$c
    fi
    ((i++))
    continue
  fi
  case $c in
    '"' | "'") q=$c has=1 ;;
    "$BS")
      word+=${cmd:i+1:1} has=1
      ((i++))
      ;;
    ' ' | $'\t') endword ;;
    '$' | '`')
      word+=$c has=1 dyn=1
      ;;
    '&')
      # The & of a redirection (2>&1, >&2, &>file) is not a separator.
      if [[ ${cmd:i-1:1} =~ [\<\>] || ${cmd:i+1:1} == ">" ]]; then word+=$c has=1; else endcmd; fi
      ;;
    ';' | '|' | '(' | ')' | '{' | '}') endcmd ;;
    $'\n')
      endword
      if [[ -n $hpend ]]; then
        body="" # read lines up to the end word
        rest=${cmd:i+1}
        while [[ -n $rest ]]; do
          line=${rest%%$'\n'*}
          [[ $rest == *$'\n'* ]] && rest=${rest#*$'\n'} || rest=""
          t=$line
          ((hstrip)) && t=${t#"${t%%[!$'\t']*}"}
          [[ $t == "$hpend" ]] && break
          body+=$line$'\n'
        done
        HERE[hown]=$body
        hpend=""
        i=$((n - ${#rest} - 1))
      fi
      endcmd
      ;;
    '<')
      if [[ ${cmd:i:3} == "<<<" ]]; then
        endword
        word="<<<" has=1
        endword
        ((i += 2))
      elif [[ ${cmd:i:2} == "<<" ]]; then
        rest=${cmd:i+2}
        hs2=0
        [[ ${rest:0:1} == "-" ]] && hs2=1 && rest=${rest:1}
        if [[ $rest =~ ^[[:space:]]*[\'\"]?([A-Za-z_][A-Za-z0-9_]*) ]]; then
          hpend=${BASH_REMATCH[1]} hstrip=$hs2 hown=${#CMDS[@]}
        fi
        endword
        word="<<" has=1
        ((i++))
      else
        word+=$c has=1
      fi
      ;;
    *) word+=$c has=1 ;;
  esac
  ((i++))
done
endcmd

judge() { # judge <command record> <heredoc or here-string body, empty when none>
  local rec=$1 here=$2 w=() d=() x
  while [[ -n $rec ]]; do
    x=${rec%%"$SEP"*} rec=${rec#*"$SEP"}
    w+=("$x")
    x=${rec%%"$SEP"*} rec=${rec#*"$SEP"}
    d+=("$x")
  done
  local k=0
  # The command itself: after VAR=value words and env, then, do, else, !, time, command or exec.
  while ((k < ${#w[@]})) && [[ ${w[k]} =~ ^[A-Za-z_][A-Za-z0-9_]*= || ${w[k]} =~ ^(env|then|do|else|!|time|command|exec)$ ]]; do
    ((k++))
  done
  [[ ${w[k]-} =~ (^|/)(gh|odev)$ ]] || return 0
  ((k++))
  # Global options before the subcommand: -R/--repo, -C/--dir, --host, --project, and flags.
  while ((k < ${#w[@]})) && [[ ${w[k]} == -* ]]; do
    [[ ${w[k]} =~ ^(-R|--repo|-C|--dir|--host|--project)$ ]] && ((k++))
    ((k++))
  done
  [[ ${w[k]-} == issue && ${w[k + 1]-} == create ]] || return 0
  k=$((k + 2))
  local body="" have=0 unreadable=0 file="" j=$k val val_dyn
  while ((j < ${#w[@]})); do
    x=${w[j]} val=${w[j + 1]-} val_dyn=${d[j + 1]-0}
    case $x in
      --body | -b | --body-file | -F)
        # Take the next word as the value; the word is not a label or a field.
        ((j++))
        if [[ $x == --body || $x == -b ]]; then
          have=1
          if ((val_dyn)) && [[ $val != *"$CATHERE"* ]]; then unreadable=1; else body=$val; fi
        else
          have=1 file=$val
          ((val_dyn)) && unreadable=1
        fi
        ;;
      --body=* | -b=*)
        have=1 body=${x#*=}
        ((d[j])) && [[ $body != *"$CATHERE"* ]] && unreadable=1
        ;;
      --body-file=* | -F=*) have=1 file=${x#*=} ;;
      --web | -w | --web=true | --editor | -e | --template | -T | --fill) unreadable=1 ;;
      -l | --label | -f | --field | -t | --title | -a | --assignee | -m | --milestone)
        ((j++))
        [[ $val == *needs-triage* ]] && return 0
        ;;
      *needs-triage*) return 0 ;;
    esac
    ((j++))
  done
  ((unreadable)) && return 0
  if ((have == 0)); then refuse; fi
  if [[ -n $file ]]; then
    if [[ $file == - ]]; then
      [[ -n $here ]] || return 0 # stdin from a pipe or a file: not readable here
      body=$here
    else
      [[ -r $file ]] || return 0
      body=$(<"$file")
    fi
  fi
  has_estimate "$body" || refuse
}

for ((idx = 0; idx < ${#CMDS[@]}; idx++)); do
  judge "${CMDS[idx]}" "${HERE[idx]-}"
done
exit 0
