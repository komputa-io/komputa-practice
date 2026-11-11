#!/bin/bash
# A Claude Code PreToolUse gate for Bash, Edit, MultiEdit and Write. It keeps a worker from deleting or weakening a
# test to get green (issue #77; the rule is in rules/working-rules.md, "Never delete or weaken a test to get green").
# It acts only when HERDR_WORKER=1, which the one who starts a worker sets, so the operator's own sessions are not touched.
# For a worker it refuses:
#  - rm, git rm, unlink or find -delete of a test path (tests/, test_*, *_test.*, *.test.*, *.spec.*);
#  - a Write or an Edit that leaves a test file empty;
#  - an Edit that adds a skip or an xfail to a test file, or comments out an assert.
# HERDR_TEST_PRUNE=1 lets a deletion through. The lead sets it for a worker that prunes tests in a reviewed PR
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

[[ ${HERDR_WORKER:-} == 1 ]] || exit 0

here=$(dirname "$(readlink -f "$0")")
command -v python3 >/dev/null || {
  echo "BLOCKED [test gate: python3 is missing]: the hook cannot read the call." >&2
  exit 2
}
python3 -I "$here/block-test-weakening.py"
