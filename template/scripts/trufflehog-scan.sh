#!/usr/bin/env bash
# Scans the whole history of the checked-out branch for secrets that are still live.
#   scripts/trufflehog-scan.sh [--out FILE]
# Runs TruffleHog over every commit reachable from HEAD (the default branch in the
# nightly job), with --only-verified: TruffleHog calls each credential's own provider
# to test whether it works, so the scan sends each candidate secret to that provider.
# One JSON line for each live secret goes to FILE (default .trufflehog/findings.jsonl).
# FILE holds the secret values: keep it out of logs, artifacts and caches, and let
# scripts/trufflehog-issues.sh turn it into issues, which never hold a value.
# TruffleHog's own log goes to stderr and holds counts only. Exit 0 on a clean scan or
# a scan with findings; 1 when TruffleHog fails. Runs inside the TruffleHog image.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'trufflehog-scan: %s\n' "$*" >&2
  exit 1
}

out=.trufflehog/findings.jsonl
case "${1-}" in
  '') ;;
  --out)
    (($# == 2)) || die "--out needs a file"
    out=$2
    ;;
  *)
    printf 'usage: scripts/trufflehog-scan.sh [--out FILE]\n' >&2
    exit 2
    ;;
esac

command -v trufflehog >/dev/null || die "trufflehog is not installed; run this in the pinned TruffleHog image"
# A mounted checkout belongs to another user, and git refuses it without this.
git config --global --add safe.directory "$PWD"
mkdir -p "$(dirname "$out")"
trufflehog git "file://$PWD" --branch HEAD --only-verified --json --no-update >"$out" \
  || die "TruffleHog failed"
printf 'trufflehog-scan: %s live secrets found\n' "$(wc -l <"$out" | tr -d ' ')" >&2
