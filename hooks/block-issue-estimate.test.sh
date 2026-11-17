#!/bin/bash
# Feed block-issue-estimate.sh payloads and check its exit code: 2 blocks, 0 passes.
#   block-issue-estimate.test.sh [hook]   (default: the hook beside it)
DIR=$(cd "$(dirname "$0")" && pwd)
HOOK=${1:-$DIR/block-issue-estimate.sh}
FAIL=0 RUN=0
check() { # check <want> <command>
  RUN=$((RUN + 1))
  local got
  jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' | "$HOOK" 2>/dev/null
  got=$?
  if [[ $got != "$1" ]]; then
    echo "FAIL want $1 got $got: $2"
    FAIL=$((FAIL + 1))
  fi
}

GOOD='Estimate: M (S–L). Basis: #298, #301 (both M).'
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf 'Why\n\n%s\n' "$GOOD" >"$TMP/good.md"
printf 'Why\n\nno line here\n' >"$TMP/bad.md"

# Each way to give the body, on each tool: with the line passes, without it is refused.
check 0 "gh issue create --title t --body '$GOOD'"
check 2 "gh issue create --title t --body 'No estimate'"
check 0 "gh issue create -t t -b \"$GOOD\""
check 2 'gh issue create -t t -b "Estimate soon"'
check 0 "gh issue create -t t --body=\"$GOOD\""
check 0 "gh issue create -t t --body-file $TMP/good.md"
check 2 "gh issue create -t t -F $TMP/bad.md"
check 0 $'gh issue create -t t -F - <<\'EOF\'\nWhy\nEstimate: S (S-S).\nEOF'
check 2 $'gh issue create -t t -F - <<\'EOF\'\nWhy only\nEOF'
check 0 'gh issue create -t t -F - <<<"Estimate: L (M-XL)."'
check 2 'gh issue create -t t -F - <<<"nothing"'
check 0 $'gh issue create -t t -b "$(cat <<\'EOF\'\nWhy\nEstimate: XL (L–XL). Basis: new area.\nEOF\n)"'
check 2 $'gh issue create -t t -b "$(cat <<\'EOF\'\nWhy\nEOF\n)"'
check 0 "odev issue create --title t --body '$GOOD'"
check 2 "odev issue create --title t --body 'none'"
check 0 "odev issue create --title t --body-file $TMP/good.md"
check 2 "odev issue create --title t --body-file $TMP/bad.md --field Type=Bug"
check 2 'odev issue create --title t'
check 2 'gh issue create --title t'

# Wrappers before the command are seen through.
check 2 "cd /tmp/repo && gh issue create -t t -b none"
check 2 "GH_TOKEN=x gh issue create -t t -b none"
check 2 "env X=1 odev issue create -t t -b none"
check 2 "gh -R owner/repo issue create -t t -b none"
check 2 "odev --project a/b issue create -t t -b none"
check 0 "cd /tmp/repo && gh issue create -t t -b '$GOOD'"
check 2 'echo done; gh issue create -t t -b none'

# Malformed lines are refused.
check 2 "gh issue create -t t -b 'Estimate: XXL (S–L).'"
check 2 "gh issue create -t t -b 'Estimate: m (S–L).'"
check 2 "gh issue create -t t -b 'Estimate: L (S–M).'"
check 2 "gh issue create -t t -b 'Estimate: S (M–L).'"
check 2 "gh issue create -t t -b 'Estimate: M'"
check 2 "gh issue create -t t -b 'Estimate: M (S–L)'"
check 2 "gh issue create -t t -b 'Estimate: M (S to L).'"
check 0 "gh issue create -t t -b 'Estimate: M (S-L).'"
check 0 "gh issue create -t t -b 'Estimate: XL (XL–XL).'"

# A person's issue is triaged in; a body it cannot read passes; any other command passes.
check 0 'gh issue create -t t -b none --label needs-triage'
check 0 'gh issue create -t t -b none -l bug,needs-triage'
check 0 'odev issue create -t t -b none --field Triage=needs-triage'
# shellcheck disable=SC2016 # the $BODY is literal command text
check 0 'gh issue create -t t -b "$BODY"'
check 0 "gh issue create -t t -F $TMP/missing.md"
check 0 'gh issue create -t t -F - < body.md'
check 0 'cat body.md | gh issue create -t t -F -'
check 0 'gh issue create -t t --web'
check 0 'gh issue list'
check 0 'gh issue comment 5 -b "create issue"'
check 0 'gh pr create -t t -b none'
check 0 'echo gh issue create -b none'
check 0 'git commit -m "gh issue create -b none"'
check 0 'ls -la'

# The repo opt-out.
OPT=$(mktemp -d)
git -C "$OPT" init -q && git -C "$OPT" config komputa.estimate-rule off
RUN=$((RUN + 1))
(cd "$OPT" && jq -nc '{tool_name:"Bash",tool_input:{command:"gh issue create -t t -b none"}}' | "$HOOK" 2>/dev/null) || {
  echo "FAIL opt-out did not pass"
  FAIL=$((FAIL + 1))
}
rm -rf "$OPT"

if ((FAIL == 0)); then echo "block-issue-estimate: $RUN checks passed"; else
  echo "block-issue-estimate: $FAIL of $RUN failed"
  exit 1
fi
