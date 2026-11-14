#!/usr/bin/env bash
# Finds duplicate code that a pull request adds, with Deslop.
#   scripts/deslop-pr.sh BASE_REF [--fail-over PERCENT] [--out DIR]
#   scripts/deslop-pr.sh --full [--embeddings URL] [--out DIR]
# Installs the release named in scripts/deslop.pin after checking its SHA-256,
# diffs BASE_REF's merge base against HEAD, and scans only what the diff adds.
# Reports go to DIR (default .deslop-pr): deslop-report.json and .txt.
# Warn only: findings never fail the run. --fail-over PERCENT fails it (exit 3)
# when the added lines are more duplicated than that. A failed download, a
# wrong checksum or a Deslop crash always fails it (exit 1).
# --full (the nightly scan) scans the whole tree, with no diff. With --embeddings
# URL it also asks Ollama there for behavioural matches, and fails when it cannot
# be reached (a report without them would look like their clusters were gone).
# DESLOP_DOWNLOAD_BASE replaces the release URL (tests use a file:// one).
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'deslop-pr: %s\n' "$*" >&2
  exit 1
}

(($# >= 1)) || {
  printf 'usage: scripts/deslop-pr.sh BASE_REF [--fail-over PERCENT] [--out DIR] | --full [--embeddings URL] [--out DIR]\n' >&2
  exit 2
}
base_ref=$1
shift
fail_over=
embeddings=
out=.deslop-pr
while (($# > 0)); do
  case "$1" in
    --fail-over | --out | --embeddings)
      (($# > 1)) || die "$1 needs a value"
      case "$1" in --out) out=$2 ;; --embeddings) embeddings=$2 ;; *) fail_over=$2 ;; esac
      shift
      ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version=$(sed -n 's/^version=//p' "$here/deslop.pin")
sha256=$(sed -n 's/^sha256=//p' "$here/deslop.pin")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$sha256" =~ ^[0-9a-f]{64}$ ]] || die "scripts/deslop.pin has no version and checksum"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
name=deslop-$version-linux-x64
url=${DESLOP_DOWNLOAD_BASE:-https://github.com/Nimblesite/Deslop/releases/download}/v$version/$name.tar.gz
curl -fsSL --retry 3 --max-time 120 -o "$work/$name.tar.gz" "$url" || die "could not download Deslop $version from $url"
printf '%s  %s\n' "$sha256" "$work/$name.tar.gz" | sha256sum --check --quiet - >&2 \
  || die "the Deslop $version download does not match the checksum in scripts/deslop.pin"
tar -xzf "$work/$name.tar.gz" -C "$work"

mkdir -p "$out"
scope=(--diff "$out/pr.diff" --only-changed)
if [[ "$base_ref" == --full ]]; then
  scope=()
  [[ -z "$embeddings" ]] || scope=(--embeddings required --embedding-endpoint "$embeddings")
else
  merge_base=$(git merge-base "$base_ref" HEAD) || die "no merge base between $base_ref and HEAD (is the history fetched?)"
  # Deslop reads a/ and b/ prefixes; a workstation's diff.mnemonicPrefix would change them.
  git -c diff.noprefix=false -c diff.mnemonicPrefix=false diff --no-ext-diff --src-prefix=a/ --dst-prefix=b/ "$merge_base" HEAD >"$out/pr.diff"
fi

gate=(--no-fail-over)
[[ -z "$fail_over" ]] || gate=(--fail-over "$fail_over")
rc=0
"$work/$name/deslop" . "${scope[@]}" --no-incremental --nohtml \
  --output "$out/deslop-report" "${gate[@]}" || rc=$?
[[ -f "$out/deslop-report.txt" ]] && cat "$out/deslop-report.txt"
case "$rc" in
  0) ;;
  3)
    printf 'deslop-pr: the added lines are more duplicated than %s%%\n' "$fail_over" >&2
    exit 3
    ;;
  *) die "Deslop crashed (exit $rc); see $out/logs" ;;
esac
