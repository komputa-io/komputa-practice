#!/usr/bin/env bash
# Refuses a commit or a push when the tree holds a private item.
#   scrub-check.sh [--staged | --rev <commit> | --range <rev-list spec>]
# With no option it checks the working tree: tracked files and untracked
# files that git does not ignore. --staged checks the index (pre-commit).
# --rev checks the tree of one commit (pre-push). --range checks the tree of
# every commit that `git rev-list <spec>` names (CI: base..head), so a commit
# that skipped the local hooks is still read.
#
# Two sources of private items:
#  - A denylist outside the repo, one literal per line, '#' starts a comment,
#    matched without case. Path: $SCRUB_DENYLIST, else
#    ~/.config/komputa/public-denylist.txt. It is never committed, because
#    it names the items it keeps out. A missing denylist refuses.
#  - The patterns below: home paths, private IP ranges, personal domains,
#    secret-tool calls, email addresses, homelab hostnames, forge URLs and
#    API-key shapes. Each one is written so that it does not match its own
#    source line, so this file passes its own check.
# Output names the file, the line and the kind of item, never the item.
# A file that cannot be read is not clean: the check exits 2 and names it.
# Exit 0: clean. 1: private items found. 2: the check could not run.
set -Eeuo pipefail
shopt -s inherit_errexit
# Byte-wise matching: the same result in every locale, and a file with a
# stray non-UTF-8 byte is still read as text.
export LC_ALL=C

die() {
  printf 'scrub-check: %s\n' "$*" >&2
  exit 2
}

usage="usage: scrub-check.sh [--staged | --rev <commit> | --range <rev-list spec>]"
mode=worktree rev='' range=''
case ${1-} in
  '') ;;
  --staged) mode=staged ;;
  --rev)
    [[ -n ${2-} ]] || die "$usage"
    mode=rev rev=$2
    ;;
  --range)
    [[ -n ${2-} ]] || die "$usage"
    range=$2
    ;;
  *) die "$usage" ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
cd -- "$(git rev-parse --show-toplevel)"
if [[ -n $range ]]; then
  # Each commit runs on its own, so a private item added and then removed
  # inside the range is still found. A bad range is an error, not an empty one.
  commits=$(git rev-list "$range") || die "cannot list commits for: $range"
  rc=0
  for c in $commits; do
    "$0" --rev "$c" || rc=$?
    ((rc < 2)) || exit "$rc"
  done
  exit "$rc"
fi
if [[ $mode == rev ]]; then
  git rev-parse --verify --quiet "$rev^{commit}" >/dev/null || die "no such commit: $rev"
fi

denylist=${SCRUB_DENYLIST:-$HOME/.config/komputa/public-denylist.txt}
[[ -f $denylist ]] || die "no denylist at $denylist; create it (one private item per line)"
[[ -r $denylist ]] || die "cannot read the denylist at $denylist"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/scrub-check.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

# Blank lines and comments go first: an empty pattern matches every line.
# A CRLF file keeps no stray \r on its entries.
sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' \
  -- "$denylist" >"$tmp/deny"

# The email pattern's parts are bounded: git grep's regex engine backtracks on a very long line with an unbounded one.
# kind<TAB>extended regex, matched without case, except a home path: Linux home
# folders are lowercase, and /Home/ in a URL (github.com/NuGet/Home) is not one.
# A bare /~api/ path passes: it is the same on every OneDev server, and a forge
# URL with a host is still refused.
cat >"$tmp/patterns" <<'EOF'
home path	/home/[a-z_][a-z0-9_.-]*
private IP	(^|[^0-9.])(192\.168|10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}
personal domain	[k]hn\.family
secret tool	(get|set)[-]secret
former employer	[k]walee
email address	[a-z0-9._%+-]{1,64}@[a-z0-9-]{1,63}(\.[a-z0-9-]{1,63})*\.[a-z]{2,}
homelab host	(^|[^a-z0-9])(homelab[0-9]+|hl[0-9]{2}|ws[0-9]{2}(-[a-z]+)?|lxc-?[0-9]{2,4})([^a-z0-9]|$)
forge URL	(https?|ssh)://[^[:space:]]*(onedev|:661[01])
Anthropic key	sk-ant-[a-z0-9_-]{20,}
OpenAI-style key	(^|[^a-z0-9])sk-[a-z0-9]{32,}
GitHub token	(gh[pousr]_[a-z0-9]{30,}|github_pat_[a-z0-9_]{30,})
AWS key	akia[0-9a-z]{16}
Google key	aiza[0-9a-z_-]{35}
Slack token	xox[abprs]-[0-9a-z-]{10,}
private key	-----begin [a-z ]*private key-----
EOF

# Files in scope, NUL-separated. Only the file-name checks and the symlinks read this list.
case $mode in
  worktree) git ls-files -z --cached --others --exclude-standard >"$tmp/files" ;;
  staged) git ls-files -z --cached >"$tmp/files" ;;
  rev) git ls-tree -r -z --name-only "$rev" >"$tmp/files" ;;
esac

# The git grep that reads every file in scope. -z gives "path NUL line NUL text".
# A rev prefixes each path with "<rev>:". git grep reports a file it cannot read on
# stderr and still exits 0, so any stderr text is a refusal (see "unreadable").
scan() {
  case $mode in
    worktree) git grep --untracked --exclude-standard "$@" -- ;;
    staged) git grep --cached "$@" -- ;;
    rev) git grep "$@" "$rev" -- ;;
  esac
}

# Reads one file's content in scope to stdout (the binary allow-list only).
content() {
  case $mode in
    worktree) if [[ -f $1 ]]; then cat -- "$1"; fi ;;
    staged) git cat-file blob ":$1" ;;
    rev) git cat-file blob "$rev:$1" ;;
  esac
}

found=0 unreadable=0
report() {
  printf '%s\n' "$1" >&2
  found=1
}

# A text tool cannot read a binary file, so a binary file refuses until a
# person has looked at it and listed it in .scrub-binary-ok.
binary_ok=$tmp/binary-ok
# shellcheck disable=SC2310 # a missing list is an empty list; content only reads
{ content .scrub-binary-ok 2>/dev/null || true; } | sed -e 's/\r$//' -e '/^#/d' -e '/^$/d' >"$binary_ok"

# A lock file's integrity hash is base64 text. A short denylist item can
# occur inside it by chance, and a hash holds no private item, so a denylist
# hit on such a line in the root package-lock.json, or app/package-lock.json, is dropped. The line must
# have the real shape: sha512- plus 88 base64 characters (86 and "=="). The
# patterns still run.
integrity_re='^ *"integrity": "sha512-[A-Za-z0-9+/]{86}==",?$'

# scan_kind <kind> <denylist 1|0> <git grep args>: one git grep; reports each hit as
# file:line: kind. The hit's text is read only to apply the integrity exemption.
scan_kind() {
  local kind=$1 deny=$2 path lineno text
  shift 2
  local errs=$tmp/grep-err
  while IFS= read -r -d '' path && IFS= read -r -d '' lineno && IFS= read -r text; do
    [[ $mode != rev ]] || path=${path#"$rev":}
    if [[ $deny == 1 && ($path == package-lock.json || $path == app/package-lock.json) ]] \
      && [[ $text =~ $integrity_re ]]; then
      continue
    fi
    report "$(printf '%q' "$path"):$lineno: $kind"
  done < <(scan -n -z -I "$@" 2>"$errs")
  if [[ -s $errs ]]; then
    unreadable=1
    printf 'scrub-check: cannot read the file(s) below; the check cannot call them clean\n' >&2
    cat -- "$errs" >&2
  fi
}

# The denylist, then each pattern: one git grep for each kind.
if [[ -s $tmp/deny ]]; then
  scan_kind "denylist entry" 1 -i -F -f "$tmp/deny"
fi
while IFS=$'\t' read -r kind regex; do
  case=(-i)
  [[ $kind != "home path" ]] || case=()
  scan_kind "$kind" 0 "${case[@]}" -E -e "$regex"
done <"$tmp/patterns"

# A private item in a path: one grep over the file list for the denylist, one for each kind.
name_hits() {
  local kind=$1 name
  shift
  while IFS= read -r -d '' name; do
    report "$(printf '%q' "$name"): file name: $kind"
  done < <(grep -z "$@" <"$tmp/files" || true)
}
if [[ -s $tmp/deny ]]; then
  name_hits "denylist entry" -i -F -f "$tmp/deny"
fi
while IFS=$'\t' read -r kind regex; do
  case=(-i)
  [[ $kind != "home path" ]] || case=()
  name_hits "$kind" "${case[@]}" -E -e "$regex"
done <"$tmp/patterns"

# A binary file: one that has content but that -I skips. Not on the allow-list: refuse.
# shellcheck disable=SC2310 # no match is exit 1; a read error already refused above
scan -l -z -a -e '^' >"$tmp/all-content" 2>/dev/null || true
# shellcheck disable=SC2310 # same
scan -l -z -I -e '^' >"$tmp/text-content" 2>/dev/null || true
while IFS= read -r -d '' path; do
  [[ $mode != rev ]] || path=${path#"$rev":}
  if ! grep -q -x -F -e "$path" "$binary_ok"; then
    report "$(printf '%q' "$path"): binary file; check it by hand and list it in .scrub-binary-ok"
  fi
done < <(comm -z -23 <(sort -z "$tmp/all-content") <(sort -z "$tmp/text-content"))

# A symlink in the worktree is its target path, and git grep does not read it: check the target text.
if [[ $mode == worktree ]]; then
  while IFS= read -r -d '' f; do
    [[ -L $f ]] || continue
    shown=$(printf '%q' "$f")
    readlink -- "$f" >"$tmp/blob"
    if [[ -s $tmp/deny ]] && grep -q -i -F -f "$tmp/deny" "$tmp/blob"; then
      report "$shown:1: denylist entry"
    fi
    while IFS=$'\t' read -r kind regex; do
      case=(-i)
      [[ $kind != "home path" ]] || case=()
      if grep -q "${case[@]}" -E -e "$regex" "$tmp/blob"; then
        report "$shown:1: $kind"
      fi
    done <"$tmp/patterns"
  done <"$tmp/files"
fi
if ((unreadable)); then
  printf 'scrub-check: a file could not be read, so the tree is not checked\n' >&2
  exit 2
fi
if ((found)); then
  printf 'scrub-check: private items found; replace each with a placeholder (<home>, <forge-url>, <secret-tool>)\n' >&2
  exit 1
fi
if [[ ! -s $tmp/deny ]]; then
  printf 'scrub-check: warning: the denylist holds no entries; only the patterns ran\n' >&2
fi
printf 'scrub-check: clean (%s, %d denylist entries)\n' "${rev:-$mode}" "$(wc -l <"$tmp/deny")"
