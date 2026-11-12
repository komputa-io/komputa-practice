#!/bin/bash
# A Claude Code PreToolUse gate for Bash, Edit, MultiEdit and Write. It keeps a worker from deleting or weakening a
# test to get green (issue #77; the rule is in rules/working-rules.md, "Never delete or weaken a test to get green").
# It acts only in a worker, an hc terminal started from a template or by a parent, so the operator's own sessions
# are not touched.
# For a worker it refuses:
#  - rm, git rm, unlink or find -delete of a test path (tests/, test_*, *_test.*, *.test.*, *.spec.*);
#  - a Write or an Edit that leaves a test file empty;
#  - an Edit that adds a skip or an xfail to a test file, or comments out an assert.
# The label test-prune=1 on the worker's terminal (hc run --label test-prune=1) lets a deletion through. The lead
# sets it for a worker that prunes tests in a reviewed PR
# (rules/working-rules.md, "Never delete or weaken a test to get green"). The judge is block-test-weakening.py beside this file.
# Exit 2 refuses with one BLOCKED line. Any other failure refuses too, as in the other gates.
set -uo pipefail
# shellcheck disable=SC2329 # run by the EXIT trap
on_exit() {
  local rc=$?
  if ((rc != 0 && rc != 2)); then
    echo "BLOCKED [test gate: internal error]: the hook failed (exit $rc), so the call is refused. Check the hook." >&2
    exit 2
  fi
}
trap on_exit EXIT

# A worker is an hc terminal that a template or a parent started (`hc run`); the operator's own session has
# neither. Outside an hc terminal nothing is a worker. If hc cannot answer, the call is refused.
[[ -n ${HC_TERMINAL_ID-} ]] || exit 0
command -v jq >/dev/null || exit 1
me=$(hc get "$HC_TERMINAL_ID" --json 2>/dev/null) || exit 1
jq -e '.template != null or .parent != null' <<<"$me" >/dev/null || exit 0
# Only the terminal's label opens the prune escape, never a variable the worker inherited or set.
HERDR_TEST_PRUNE=$(jq -r 'if .labels["test-prune"] == "1" then "1" else "" end' <<<"$me") || exit 1
export HERDR_TEST_PRUNE

here=$(dirname "$(readlink -f "$0")")
command -v python3 >/dev/null || {
  echo "BLOCKED [test gate: python3 is missing]: the hook cannot read the call." >&2
  exit 2
}
python3 -I "$here/block-test-weakening.py"
