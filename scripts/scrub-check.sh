#!/usr/bin/env bash
# Refuses a commit or a push when the tree holds a private item.
#   scrub-check.sh [--staged | --rev <commit>]
# With no option it checks the working tree: tracked files and untracked
# files that git does not ignore. --staged checks the index (pre-commit).
# --rev checks the tree of one commit (pre-push).
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

mode=worktree rev=
case ${1-} in
  '') ;;
  --staged) mode=staged ;;
  --rev)
    [[ -n ${2-} ]] || die "usage: scrub-check.sh [--staged | --rev <commit>]"
    mode=rev rev=$2
    ;;
  *) die "usage: scrub-check.sh [--staged | --rev <commit>]" ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
cd -- "$(git rev-parse --show-toplevel)"
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
email address	[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}
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

# Files in scope, NUL-separated.
case $mode in
  worktree) git ls-files -z --cached --others --exclude-standard >"$tmp/files" ;;
  staged) git ls-files -z --cached >"$tmp/files" ;;
  rev) git ls-tree -r -z --name-only "$rev" >"$tmp/files" ;;
esac

# Reads one file's content in scope to stdout.
content() {
  case $mode in
    # Only a regular file: a FIFO would block the read, and git cannot
    # commit one anyway.
    worktree) if [[ -f $1 ]]; then cat -- "$1" 2>/dev/null || true; fi ;;
    staged) git cat-file blob ":$1" 2>/dev/null || true ;;
    rev) git cat-file blob "$rev:$1" 2>/dev/null || true ;;
  esac
}

found=0
report() {
  printf '%s\n' "$1" >&2
  found=1
}

# A text tool cannot read a binary file, so a binary file refuses until a
# person has looked at it and listed it in .scrub-binary-ok.
binary_ok=$tmp/binary-ok
content .scrub-binary-ok | sed -e 's/\r$//' -e '/^#/d' -e '/^$/d' >"$binary_ok"

# A lock file's integrity hash is base64 text. A short denylist item can
# occur inside it by chance, and a hash holds no private item, so a denylist
# hit on such a line in the root package-lock.json, or app/package-lock.json, is dropped. The line must
# have the real shape: sha512- plus 88 base64 characters (86 and "=="). The
# patterns still run.
drop_integrity() {
  if [[ $1 == package-lock.json || $1 == app/package-lock.json ]]; then
    grep -v -E '^[0-9]+: *"integrity": "sha512-[A-Za-z0-9+/]{86}==",?$' || true
  else
    cat
  fi
}

while IFS= read -r -d '' f; do
  # The path itself can hold a private item.
  shown=$(printf '%q' "$f")
  if [[ -s $tmp/deny ]] && printf '%s\n' "$f" | grep -q -i -F -f "$tmp/deny"; then
    report "$shown: file name: denylist entry"
  fi
  while IFS=$'\t' read -r kind regex; do
    case=(-i)
    [[ $kind != "home path" ]] || case=()
    if printf '%s\n' "$f" | grep -q "${case[@]}" -E -e "$regex"; then
      report "$shown: file name: $kind"
    fi
  done <"$tmp/patterns"

  # A symlink in the tree is its target path, and a worktree read would
  # follow it out of the repo; check the target text instead.
  if [[ $mode == worktree && -L $f ]]; then
    readlink -- "$f" >"$tmp/blob"
  else
    content "$f" >"$tmp/blob"
  fi
  if [[ -s $tmp/blob ]] && ! grep -q -I '' "$tmp/blob"; then
    if ! grep -q -x -F -e "$f" "$binary_ok"; then
      report "$shown: binary file; check it by hand and list it in .scrub-binary-ok"
    fi
    continue
  fi

  if [[ -s $tmp/deny ]]; then
    while IFS= read -r line; do
      report "$shown:$line: denylist entry"
    done < <(grep -n -i -F -f "$tmp/deny" -- "$tmp/blob" | drop_integrity "$f" | cut -d: -f1)
  fi
  while IFS=$'\t' read -r kind regex; do
    case=(-i)
    [[ $kind != "home path" ]] || case=()
    while IFS= read -r line; do
      report "$shown:$line: $kind"
    done < <(grep -n "${case[@]}" -E -e "$regex" -- "$tmp/blob" | cut -d: -f1)
  done <"$tmp/patterns"
done <"$tmp/files"

if ((found)); then
  printf 'scrub-check: private items found; replace each with a placeholder (<home>, <forge-url>, <secret-tool>)\n' >&2
  exit 1
fi
printf 'scrub-check: clean (%s, %d denylist entries)\n' "${rev:-$mode}" "$(wc -l <"$tmp/deny")"
