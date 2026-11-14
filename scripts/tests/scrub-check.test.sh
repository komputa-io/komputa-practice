#!/usr/bin/env bash
# Tests for scripts/scrub-check.sh. Each case builds a throwaway git repo,
# plants an item, and checks the exit code and the output. Planted values are
# built from pieces, so this file passes the scrub check itself.
#   scripts/tests/scrub-check.test.sh
set -Eeuo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
check=$(cd -- "$here/.." && pwd)/scrub-check.sh
root=$(mktemp -d "${TMPDIR:-/tmp}/scrub-test.XXXXXX")
trap 'chmod -R u+rwx -- "$root" 2>/dev/null; rm -rf -- "$root"' EXIT

pass=0 fail=0
ok() {
  pass=$((pass + 1))
  printf 'ok    %s\n' "$1"
}
bad() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  [[ -s $root/out ]] && sed 's/^/      | /' "$root/out"
  return 0
}

deny=$root/deny.txt
printf '# test denylist\n\nzanzibarco\n' >"$deny"
export SCRUB_DENYLIST=$deny

n=0
newrepo() {
  n=$((n + 1))
  repo=$root/r$n
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email "test""@""example.invalid"
  git -C "$repo" config user.name test
  git -C "$repo" config commit.gpgsign false
  printf 'clean text\n' >"$repo/README.md"
}

# run <repo> [args...]: runs the check in the repo; sets $rc, output in $root/out.
run() {
  local dir=$1
  shift
  rc=0
  (cd -- "$dir" && timeout 20 "$check" "$@") >"$root/out" 2>&1 || rc=$?
}

# expect <name> <rc> [text that the output must hold]
expect() {
  local name=$1 want=$2 text=${3-}
  if [[ $rc != "$want" ]]; then
    bad "$name (exit $rc, want $want)"
  elif [[ -n $text ]] && ! grep -q -F -e "$text" "$root/out"; then
    bad "$name (output lacks: $text)"
  else
    ok "$name"
  fi
}

# The output must never repeat the planted value.
quiet_about() {
  local name=$1 value=$2
  if grep -q -F -e "$value" "$root/out"; then bad "$name (output shows the value)"; else ok "$name"; fi
}

# --- the tree is clean -------------------------------------------------------
newrepo
run "$repo"
expect "clean tree passes" 0 "clean"

# --- a bare forge API path and /Home/ in a URL pass -------------------------
newrepo
printf 'curl "forge.test/~''api/pulls"\nsee github.com/NuGet/Ho''me/issues/12552\n' >"$repo/notes.md"
run "$repo"
expect "a bare forge API path and /Home/ in a URL pass" 0 "clean"

# --- each pattern kind is red ------------------------------------------------
declare -A plant=(
  ["home path"]="see /ho""me/alice/notes"
  ["private IP"]="host at 192"".168.4.7 port 80"
  ["personal domain"]="https://wiki.k""hn.fam""ily/x"
  ["secret tool"]="run get""-secret api token"
  ["former employer"]="worked at Kwa""lee once"
  ["email address"]="mail a.person""@""example.org now"
  ["homelab host"]="ssh home""lab07 now"
  ["forge URL"]="http://git.example.org:66""10/proj"
  ["Anthropic key"]="key sk-""ant-api03-abcdefghijklmnopqrstuvwxyz0123"
  ["GitHub token"]="token gh""p_abcdefghijklmnopqrstuvwxyz0123456789"
  ["AWS key"]="AKI""AABCDEFGHIJKLMNOP"
  ["private key"]="-----BEGIN OPENSSH PRI""VATE KEY-----"
)
for kind in "${!plant[@]}"; do
  newrepo
  printf 'line one\n%s\n' "${plant[$kind]}" >"$repo/notes.md"
  run "$repo"
  expect "red on $kind" 1 "notes.md:2: $kind"
done

newrepo
printf 'Our client ZanzibarCo said hi\n' >"$repo/a.txt"
run "$repo"
expect "red on a denylist entry, any case" 1 "a.txt:1: denylist entry"
quiet_about "output hides the denylist value" "ZanzibarCo"

newrepo
printf 'host at %s\n' "10.20"".30.40" >"$repo/a.txt"
run "$repo"
quiet_about "output hides the pattern value" "10.20"".30.40"

# --- the three modes ---------------------------------------------------------
newrepo
git -C "$repo" add README.md && git -C "$repo" commit -q -m init
printf 'zanzibarco\n' >"$repo/staged.txt"
git -C "$repo" add staged.txt
rm "$repo/staged.txt"
run "$repo" --staged
expect "--staged reads the index, not the disk" 1 "staged.txt:1: denylist entry"

newrepo
printf 'zanzibarco\n' >"$repo/c.txt"
git -C "$repo" add c.txt && git -C "$repo" commit -q -m planted --no-verify
git -C "$repo" rm -q c.txt && git -C "$repo" commit -q -m removed
run "$repo" --rev HEAD~1
expect "--rev reads an old commit" 1 "c.txt:1: denylist entry"
run "$repo" --rev HEAD
expect "--rev HEAD is clean after removal" 0

newrepo
mkdir -p "$repo/scripts"
cp -- "$check" "$repo/scripts/"
mkdir -p "$repo/.githooks"
cp -- "$(dirname -- "$check")/../.githooks/pre-commit" "$repo/.githooks/"
git -C "$repo" config core.hooksPath .githooks
printf 'zanzibarco\n' >"$repo/p.txt"
git -C "$repo" add -A
rc=0
git -C "$repo" commit -q -m planted >"$root/out" 2>&1 || rc=$?
expect "pre-commit hook refuses the commit" 1 "p.txt:1: denylist entry"
git -C "$repo" rm -q --cached p.txt && rm "$repo/p.txt"
rc=0
git -C "$repo" commit -q -m clean >"$root/out" 2>&1 || rc=$?
expect "pre-commit hook allows a clean commit" 0

# --- hostile inputs: arguments and repo state --------------------------------
newrepo
run "$repo" --bogus
expect "unknown option refuses" 2 "usage"
run "$repo" --rev
expect "--rev without a commit refuses" 2 "usage"
run "$repo" --rev no-such-ref
expect "--rev with a bad commit refuses" 2 "no such commit"
mkdir -p "$root/notgit"
run "$root/notgit"
expect "outside a git repo refuses" 2 "not inside a git repository"

# --- hostile inputs: the denylist --------------------------------------------
newrepo
SCRUB_DENYLIST=$root/missing.txt run "$repo"
expect "missing denylist refuses" 2 "no denylist"
mkdir -p "$root/denydir"
SCRUB_DENYLIST=$root/denydir run "$repo"
expect "denylist that is a folder refuses" 2 "no denylist"
if ((EUID != 0)); then
  cp -- "$deny" "$root/locked.txt" && chmod 000 "$root/locked.txt"
  SCRUB_DENYLIST=$root/locked.txt run "$repo"
  expect "unreadable denylist refuses" 2 "cannot read"
fi
printf '# only comments\n\n   \n\t\n' >"$root/blank.txt"
SCRUB_DENYLIST=$root/blank.txt run "$repo"
expect "blank and comment lines match nothing" 0 "0 denylist entries"
printf 'zanzibarco\r\n' >"$root/crlf.txt"
printf 'zanzibarco\n' >"$repo/a.txt"
SCRUB_DENYLIST=$root/crlf.txt run "$repo"
expect "CRLF denylist still matches" 1 "a.txt:1: denylist entry"
printf '.*\n[a\n' >"$root/meta.txt"
rm "$repo/a.txt"
SCRUB_DENYLIST=$root/meta.txt run "$repo"
expect "denylist entries are literals, not regexes" 0

# --- hostile inputs: file names and file kinds -------------------------------
newrepo
mkdir -p "$repo/zanzibarco notes"
printf 'clean\n' >"$repo/zanzibarco notes/a.md"
run "$repo"
expect "private item in a folder name" 1 "file name: denylist entry"

newrepo
printf 'ok\n' >"$repo/odd: name"$'\n'"with newline.md"
printf 'zanzibarco\n' >"$repo/sp ace.md"
run "$repo"
expect "names with colon, newline and space" 1 "sp\\ ace.md:1: denylist entry"

newrepo
ln -s "/ho""me/alice/secret.txt" "$repo/link"
run "$repo"
expect "symlink target holds a home path" 1 "link:1: home path"

newrepo
printf 'zanzibarco\n' >"$root/outside.txt"
ln -s "$root/outside.txt" "$repo/out-link"
run "$repo"
if grep -q 'out-link:1: denylist entry' "$root/out"; then
  bad "symlink is not followed out of the repo"
else ok "symlink is not followed out of the repo"; fi

newrepo
printf 'zanzibarco\n' >"$repo/ro.txt"
chmod 444 "$repo/ro.txt"
run "$repo"
expect "read-only file is still read" 1 "ro.txt:1: denylist entry"

newrepo
mkfifo "$repo/pipe"
run "$repo"
expect "a FIFO in the worktree does not hang the check" 0

newrepo
{
  head -c 1000000 /dev/zero | tr '\0' 'a'
  printf ' zanzibarco\n'
} >"$repo/long.txt"
run "$repo"
expect "item at the end of a 1 MB line" 1 "long.txt:1: denylist entry"

newrepo
printf 'caf\xe9 \xff\xfe zanzibarco\n' >"$repo/latin1.txt"
run "$repo"
expect "non-UTF-8 text is still read" 1 "latin1.txt:1: denylist entry"

newrepo
printf '\x00\x01\x02zanzibarco' >"$repo/blob.bin"
run "$repo"
expect "binary file refuses" 1 "blob.bin: binary file"
printf 'blob.bin\n' >"$repo/.scrub-binary-ok"
run "$repo"
expect "listed binary file passes" 0

newrepo
: >"$repo/empty.txt"
run "$repo"
expect "empty file passes" 0

newrepo
printf 'zanzibarco\n' >"$repo/ignored.log"
printf '*.log\n' >"$repo/.gitignore"
run "$repo"
expect "ignored files are out of scope" 0

# --- a lock file's integrity hash -------------------------------------------
# A real sha512 hash: "sha512-" plus 86 base64 characters and "==". The word
# sits inside the 86.
hash_with() { printf '      "integrity": "sha512-%s%s==",\n' "$1" "$(printf 'A%.0s' $(seq 1 $((86 - ${#1}))))"; }
newrepo
hash_with zanzibarco >"$repo/package-lock.json"
run "$repo"
expect "denylist hit inside a real integrity hash passes" 0
printf '      "integrity": "sha512-AAzanzibarcoBB==",\n' >"$repo/package-lock.json"
run "$repo"
expect "denylist hit inside a short integrity value refuses" 1
printf '      "resolved": "zanzibarco",\n' >"$repo/package-lock.json"
run "$repo"
expect "denylist hit on another lock file line refuses" 1
newrepo
hash_with zanzibarco >"$repo/other.json"
run "$repo"
expect "integrity exemption holds only for package-lock.json" 1
newrepo
mkdir -p "$repo/packages/x"
hash_with zanzibarco >"$repo/packages/x/package-lock.json"
run "$repo"
expect "integrity exemption holds only for the root package-lock.json" 1
newrepo
mkdir -p "$repo/app"
hash_with zanzibarco >"$repo/app/package-lock.json"
run "$repo"
expect "integrity exemption holds for app/package-lock.json" 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
