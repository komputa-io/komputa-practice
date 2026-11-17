#!/usr/bin/env bash
# Tags a release: creates v<version> at HEAD when no such tag exists on the remote.
# Managed by the project template; the "Tag release" CI job runs it on the default
# branch. It never moves, deletes or replaces a tag: an existing tag stays, and a
# tag that points elsewhere is reported, not changed.
#   scripts/tag-release.sh [--dry-run]
# Exit 0: tagged, or the tag was already there. 1: no valid version, or the push failed.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR

dry=0
[[ "${1-}" != --dry-run ]] || dry=1

here=$(dirname -- "${BASH_SOURCE[0]}")
version=$("$here/version-check.sh" --print) || {
  printf 'tag-release: no version declared; run scripts/version-check.sh\n' >&2
  exit 1
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]*)?$ ]] || {
  printf "tag-release: '%s' is not semver; run scripts/version-check.sh\n" "$version" >&2
  exit 1
}
tag=v$version
head=$(git rev-parse HEAD)

# The tag as the remote holds it: the commit it names, an annotated tag's target too.
remote=$(git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}" | awk '{print $1}' | tail -n 1)
if [[ -n "$remote" ]]; then
  if [[ "$remote" == "$head" ]]; then
    printf 'tag-release: %s is already at HEAD\n' "$tag"
  else
    printf 'tag-release: %s already exists at %s, not HEAD (%s). Left alone. Bump the version for a new release.\n' "$tag" "${remote:0:12}" "${head:0:12}"
  fi
  exit 0
fi
if ((dry)); then
  printf 'tag-release: would tag %s at %s\n' "$tag" "${head:0:12}"
  exit 0
fi
git tag -a "$tag" -m "Release $version" "$head"
# No --force: a tag that appeared since the check makes the push fail, and it stays.
git push origin "refs/tags/$tag"
printf 'tag-release: tagged %s at %s\n' "$tag" "${head:0:12}"
