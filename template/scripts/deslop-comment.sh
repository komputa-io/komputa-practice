#!/usr/bin/env bash
# Turns a Deslop JSON report into one pull request comment.
#   scripts/deslop-comment.sh --report FILE [--forge github|onedev --pr NUMBER --post]
# Dry run by default: prints the comment and posts nothing. With --post it finds
# its own earlier comment by the hidden marker and edits it, so a PR has one
# comment however often it is pushed. With no duplicates and no earlier comment
# it posts nothing. Needs jq.
# github: gh, with GH_TOKEN and GITHUB_REPOSITORY in the environment.
# onedev: curl and jq, with ODEV_HOST, ODEV_PROJECT and ODEV_TOKEN in the environment.
# The token stays in the environment: it is never an argument and never printed.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'deslop-comment: %s\n' "$*" >&2
  exit 1
}
usage() {
  printf 'usage: scripts/deslop-comment.sh --report FILE [--forge github|onedev --pr NUMBER --post]\n' >&2
  exit 2
}

report='' forge='' pr='' post=0
while (($# > 0)); do
  case "$1" in
    --post) post=1 ;;
    --report | --forge | --pr)
      (($# > 1)) || usage
      case "$1" in --report) report=$2 ;; --forge) forge=$2 ;; *) pr=$2 ;; esac
      shift
      ;;
    *) usage ;;
  esac
  shift
done
[[ -f "$report" ]] || die "no report at '$report'"
if ((post)); then
  [[ "$forge" =~ ^(github|onedev)$ && "$pr" =~ ^[1-9][0-9]*$ ]] || usage
fi

marker='<!-- deslop-pr -->'
count=$(jq '[.clusters[] | select(.intersects_diff)] | length' "$report")
body=$(jq -r --arg marker "$marker" '
  def lines: "`\(.path):\(.start_line)-\(.end_line)`";
  . as $r | [.clusters[] | select(.intersects_diff)] | sort_by(-.mass) as $all
  | ($all | length) as $n
  | $marker + "\n"
  + if $n == 0 then "**Deslop:** No new duplicates."
    else "**Deslop:** This PR adds \($n) duplicate\(if $n == 1 then "" else "s" end)"
      + " (\($r.metrics.diff.duplication_percent * 10 | round / 10)% of its added lines)."
      + ($all[:10] | to_entries | map(
          "\n\n\(.key + 1). **\(.value.kind | gsub("_"; " "))**: new \([.value.occurrences[] | select(.in_diff) | lines] | join(", "))"
          + (([.value.occurrences[] | select(.in_diff | not) | lines] | .[:3]) as $old
            | if ($old | length) > 0 then "; existing copy \($old | join(", "))" else "; no existing copy, both are new" end)
        ) | join(""))
      + if $n > 10 then "\n\n…and \($n - 10) more." else "" end
    end' "$report")

if ((! post)); then
  printf '%s\n\n(dry run: add --post to post it)\n' "$body"
  exit 0
fi

# Each forge: find_comment prints the id of our earlier comment, or nothing.
if [[ "$forge" == github ]]; then
  repo=${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY}
  find_comment() {
    gh api --paginate "repos/$repo/issues/$pr/comments" \
      --jq ".[] | select((.user.login | endswith(\"[bot]\")) and (.body | contains(\"$marker\"))) | .id" | sed -n 1p
  }
  edit_comment() { printf '%s' "$body" | gh api -X PATCH "repos/$repo/issues/comments/$1" -F body=@- >/dev/null; }
  add_comment() { printf '%s' "$body" | gh api -X POST "repos/$repo/issues/$pr/comments" -F body=@- >/dev/null; }
else
  # OneDev's REST API through curl: the image needs no odev, which has no release to pin.
  # The token goes in a header read from a file descriptor, so it is on no command line.
  : "${ODEV_HOST:?set ODEV_HOST}" "${ODEV_PROJECT:?set ODEV_PROJECT}" "${ODEV_TOKEN:?set ODEV_TOKEN}"
  api() {
    local path=$1
    shift
    curl -fsS --max-time 30 -H @<(printf 'Authorization: Bearer %s\n' "$ODEV_TOKEN") "$@" "${ODEV_HOST%/}/~api/$path"
  }
  pid=$(api pulls -G --data-urlencode "query=\"Project\" is \"$ODEV_PROJECT\" and \"Number\" is \"$pr\"" \
    --data-urlencode offset=0 --data-urlencode count=1 | jq -r '.[0].id // empty')
  [[ -n "$pid" ]] || die "OneDev has no pull request $pr in $ODEV_PROJECT"
  find_comment() {
    api "pulls/$pid/comments" | jq -r --arg marker "$marker" '[.[] | select(.content | contains($marker))] | .[0].id // empty'
  }
  # An update takes the bare text as its body, not JSON.
  edit_comment() { printf '%s' "$body" | api "pull-request-comments/$1" -X POST -H 'Content-Type: application/json' --data-binary @- >/dev/null; }
  add_comment() {
    local uid
    uid=$(api users/me | jq -r '.id')
    jq -n --argjson r "$pid" --argjson u "$uid" --arg c "$body" '{requestId: $r, userId: $u, content: $c}' \
      | api pull-request-comments -X POST -H 'Content-Type: application/json' --data-binary @- >/dev/null
  }
fi

id=$(find_comment)
if [[ -n "$id" ]]; then
  edit_comment "$id"
  printf 'deslop-comment: edited comment %s on #%s\n' "$id" "$pr"
elif ((count > 0)); then
  add_comment
  printf 'deslop-comment: commented on #%s\n' "$pr"
else
  printf 'deslop-comment: no duplicates and no earlier comment; nothing posted\n'
fi
