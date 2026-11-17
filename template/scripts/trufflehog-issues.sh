#!/usr/bin/env bash
# Files one high-priority issue for each live secret that scripts/trufflehog-scan.sh found.
#   scripts/trufflehog-issues.sh --findings FILE [--forge github|onedev --post]
# Dry run by default: prints what it would file and changes nothing. With --post it files
# the issues through scripts/forge/<forge>.sh (needs jq; the forge variables are the ones
# that script names). Each issue holds a marker with a fingerprint (detector, commit, file,
# line), so a finding that has an issue, open or closed, is never filed again. At most
# CAP issues a night; the rest wait for the next night.
# A secret value never reaches an issue, the log or a file: the issue is built from named
# fields only (never Raw, RawV2, Redacted or ExtraData), and a check refuses to file any
# text that holds a value TruffleHog reported. Exit 0 on success, 1 on failure, 2 on misuse.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'trufflehog-issues: %s\n' "$*" >&2
  exit 1
}
usage() {
  printf 'usage: scripts/trufflehog-issues.sh --findings FILE [--forge github|onedev --post]\n' >&2
  exit 2
}

readonly CAP=10
findings='' forge='' post=0
while (($# > 0)); do
  case "$1" in
    --post) post=1 ;;
    --findings | --forge)
      (($# > 1)) || usage
      case "$1" in --findings) findings=$2 ;; *) forge=$2 ;; esac
      shift
      ;;
    *) usage ;;
  esac
  shift
done
[[ -f "$findings" ]] || usage
if ((post)); then [[ "$forge" =~ ^(github|onedev)$ ]] || usage; fi

# One compact object for each live finding: only fields that cannot hold the value.
# The fingerprint is a hash, so it is safe in a marker.
plan=$(jq -c 'select(.Verified == true) | .SourceMetadata.Data.Git as $g | {
    detector: .DetectorName, commit: ($g.commit // ""), file: ($g.file // ""), line: ($g.line // 0),
    secrets: [.Raw, .RawV2 | select(type == "string" and length >= 4)]}' "$findings" \
  | while IFS= read -r row; do
    fp=$(jq -r '[.detector, .commit, .file, (.line | tostring)] | join("|")' <<<"$row" | sha256sum | cut -c1-16)
    jq -c --arg fp "$fp" '.fp = $fp' <<<"$row"
  done | jq -sc 'unique_by(.fp)')
total=$(jq length <<<"$plan")

body_of() { # one finding on stdin: the issue text, never the value
  jq -r '"<!-- trufflehog: \(.fp) -->\n**TruffleHog found a live secret in the git history** (\(.detector); TruffleHog tested it with the provider and it works).\n\n"
    + "- File: `\(.file):\(.line)`\n- Commit: `\(.commit)`\n- Value: [redacted: it is never written to an issue or a log]\n\n"
    + "**What to do.** Revoke or rotate the credential first: it works now, and anyone with the repository can use it. Then remove it from the code. Rewriting history is optional once it is revoked. Closing this issue does not revoke it."'
}
title_of() { jq -r '"Live \(.detector) secret in \(.file):\(.line) (\(.fp[:8]))"'; }
leaks() { # 0 when TEXT (arg 2) holds any secret of the finding (arg 1)
  jq -e --arg t "$2" '.secrets | any(. as $s | $t | contains($s))' <<<"$1" >/dev/null
}

if ((! post)); then
  printf 'findings: %s, would file up to %s\n' "$total" "$CAP"
  while IFS= read -r row; do
    printf '%s\n' "$(title_of <<<"$row")"
  done < <(jq -c --argjson cap "$CAP" '.[:$cap][]' <<<"$plan")
  printf '(dry run: add --forge and --post to file issues)\n'
  exit 0
fi

helper="$(dirname "${BASH_SOURCE[0]}")/forge/$forge.sh"
[[ -x "$helper" ]] || die "no $helper"
filed=0 known=0
while IFS= read -r row; do
  text="$(title_of <<<"$row")"$'\n'"$(body_of <<<"$row")"
  # shellcheck disable=SC2310 # the status is the answer
  ! leaks "$row" "$text" || die "an issue text would hold a secret value; nothing filed for $(jq -r '.fp' <<<"$row")"
  fp=$(jq -r .fp <<<"$row")
  # A failed lookup must stop the run, not read as "not filed yet".
  marked=$("$helper" issue-marked "<!-- trufflehog: $fp -->") || die "could not list the issues; nothing more filed"
  if [[ -n "$marked" ]]; then
    known=$((known + 1))
    continue
  fi
  ((filed < CAP)) || continue
  "$helper" issue-create-high "$(title_of <<<"$row")" "$(body_of <<<"$row")"
  filed=$((filed + 1))
done < <(jq -c '.[]' <<<"$plan")
printf 'trufflehog-issues: %s findings, filed %s, already known %s\n' "$total" "$filed" "$known"
((total - known - filed == 0)) || printf 'trufflehog-issues: %s more wait for the next night\n' "$((total - known - filed))"
