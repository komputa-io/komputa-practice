#!/usr/bin/env bash
# Tests for skills/herdr/assets/report-to.sh with a stub hc on PATH.
#   scripts/tests/report-to.test.sh
set -Eeuo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script=$(cd -- "$here/../.." && pwd)/skills/herdr/assets/report-to.sh
root=$(mktemp -d "${TMPDIR:-/tmp}/report-to-test.XXXXXX")
trap 'rm -rf -- "$root"' EXIT
mkdir "$root/bin"
# The stub answers `get <t>` with $GET_<t> (else it fails, as for a removed terminal), `ls --label lead.from=<t>` with
# $FROM_<t>, and other `ls` calls with $LS.
cat >"$root/bin/hc" <<'STUB'
#!/bin/bash
case $1 in
  get) v=GET_$2 && [[ -n ${!v-} ]] && printf '%s' "${!v}" ;;
  ls) [[ $* =~ lead\.from=([a-z0-9]+) ]] && v=FROM_${BASH_REMATCH[1]} || v=LS
    printf '%s' "${!v:-{\"terminals\":[]\}}" ;;
esac
STUB
chmod +x "$root/bin/hc"
fail=0
# case WHAT WANT ENV...: run report-to as t9 with the stub answers in ENV; it must print WANT.
case_() {
  local what=$1 want=$2 got
  shift 2
  got=$(env PATH="$root/bin:$PATH" HC_TERMINAL_ID=t9 "$@" "$script" 2>&1) || true
  [[ $got == "$want" ]] && echo "ok    $what" && return
  echo "FAIL  $what: got '$got', want '$want'"
  fail=1
}
lead='{"terminals":[{"address":"t2","state":"live","cwd":"/repo"},{"address":"t6","state":"live","cwd":"/other"}]}'
old='{"state":"live","cwd":"/repo","labels":{"watch.old":"1"}}'
case_ "a live parent gets the report" t1 GET_t9='{"parent":"t1"}' GET_t1='{"state":"live","labels":{}}' LS="$lead"
case_ "lead.to from a handover wins over the parent" t2 GET_t9='{"parent":"t1","labels":{"lead.to":"t2"}}' GET_t2='{"state":"live","labels":{}}'
case_ "an old parent's report goes to the lead in its folder" t2 GET_t9='{"parent":"t1"}' GET_t1="$old" LS="$lead"
case_ "after two handovers, with two leads in the folder, the report follows lead.from" t3 GET_t9='{"parent":"t1"}' \
  GET_t1="$old" GET_t2="$old" FROM_t1='{"terminals":[{"address":"t2","state":"live"}]}' \
  FROM_t2='{"terminals":[{"address":"t3","state":"live"}]}' GET_t3='{"state":"live","labels":{}}' \
  LS='{"terminals":[{"address":"t3","state":"live","cwd":"/repo"},{"address":"t8","state":"live","cwd":"/repo"}]}'
case_ "with no lead in its folder, the old parent keeps it" t1 GET_t9='{"parent":"t1"}' GET_t1='{"state":"finished","cwd":"/gone","labels":{}}' LS="$lead"
exit "$fail"
