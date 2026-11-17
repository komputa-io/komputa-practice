#!/usr/bin/env bash
# Tags a template release and pushes the tag, only for a commit that passed the canary run.
#   scripts/release.sh [--apply] [-m <message>] <version> <sha>
# Run it in a clone of the template. It refuses unless scripts/canary.sh --apply wrote .canary/<sha>.pass for
# this exact sha, and the sha is on origin/main. The tag is annotated; the message is -m, or the merged pull
# request titles since the last tag. A dry run (the default) shows the tag and starts nothing.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'release: %s\n' "$*" >&2
  exit 1
}

apply=0 msg='' pos=()
while (($#)); do
  case "$1" in
    --apply) apply=1 ;;
    -m)
      shift || true
      msg=${1-}
      ;;
    -*) die "unknown option $1" ;;
    *) pos+=("$1") ;;
  esac
  shift
done
((${#pos[@]} == 2)) || die "usage: scripts/release.sh [--apply] [-m <message>] <version> <sha>"
version=${pos[0]}
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version '$version' is not vN.N.N"
full=$(git rev-parse --verify -q "${pos[1]}^{commit}") || die "'${pos[1]}' is not a commit here"
record=${CANARY_DIR:-$(git rev-parse --show-toplevel)/.canary}/$full.pass

[[ -f $record ]] || die "no canary pass record for ${full:0:12}: run scripts/canary.sh --apply ${full:0:12}"
git merge-base --is-ancestor "$full" origin/main || die "${full:0:12} is not on origin/main"
git rev-parse --verify -q "refs/tags/$version" >/dev/null && die "tag $version exists"

if [[ -z $msg ]]; then
  last=$(git describe --tags --abbrev=0 --match 'v*' "$full" 2>/dev/null || true)
  titles=$(git log --merges --first-parent --format=%b "${last:+$last..}$full" | grep -v '^$' || true)
  msg="Template $version"$'\n\n'$titles
fi

if ((! apply)); then
  printf 'dry run; would tag %s at %s and push it:\n%s\n' "$version" "${full:0:12}" "$msg"
  printf 'add --apply to do it\n'
  exit 0
fi
git tag -a "$version" -m "$msg" "$full"
git push origin "refs/tags/$version"
printf 'release: tagged and pushed %s at %s\n' "$version" "$full"
