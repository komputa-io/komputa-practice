#!/bin/bash
# shellcheck disable=SC2016 # single-quoted patterns are literal text to find
# Tests for practice-watch and watcherctl, against stub hc and systemctl commands on PATH.
#   watcher/practice-watch.test.sh
DIR=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
FAIL=0 RUN=0
mkdir "$T/bin"
cat >"$T/bin/hc" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG"
case $1 in
  ls)
    [[ -n ${STUB_LS-} ]] || exit 1
    case $* in
      *lead.to=*) printf '%s' "${STUB_LS_LEADTO:-{\"terminals\":[]\}}" ;;
      *watch.old=1*) printf '%s' "${STUB_LS_OLD:-{\"terminals\":[]\}}" ;;
      *watch=on*) printf '%s' "$STUB_LS" ;;
      *) printf '%s' "${STUB_LS_LIVE:-$STUB_LS}" ;;
    esac
    ;;
  get) v="STUB_GET_$2" && printf '%s' "${!v:-$STUB_GET}" ;;
  kill | rm) exit 0 ;;
  read) printf '%s' "${STUB_READ-}" ;;
  send) exit "${STUB_SEND_RC:-0}" ;;
  label) exit 0 ;;
  run) [[ -z ${STUB_RUN_FAIL-} ]] || exit 1; printf '{"address":"t8"}' ;;
esac
EOF
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$STUB_LOG"\n' >"$T/bin/systemctl"
cat >"$T/bin/loginctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG"
[[ $1 == show-user ]] && printf '%s' "${STUB_LINGER-}"
exit 0
EOF
printf '#!/bin/bash\nprintf "%%s\\n" "$1" >>"$STUB_ALERTS"\n' >"$T/alert"
chmod +x "$T/bin/hc" "$T/bin/systemctl" "$T/bin/loginctl" "$T/alert"

ok() { # ok WHAT CONDITION...: count a case; report it when the condition fails
  local what=$1
  shift
  RUN=$((RUN + 1))
  if ! "$@"; then
    echo "FAIL $what"
    FAIL=$((FAIL + 1))
  fi
}
logged() { grep -q -- "$1" "$T/log" 2>/dev/null; }
not_logged() { ! logged "$1"; }
alerts() { [[ $([[ -f $T/alerts ]] && wc -l <"$T/alerts" || echo 0) == "$1" ]]; }

LS='{"terminals":[{"address":"t7"}]}'
now=$(date +%s%3N)
# get STATE STATUS MINUTES_AGO [LABELS_JSON]: what hc get says about t7.
get() { jq -nc --arg st "$1" --arg s "$2" --argjson ms "$((now - $3 * 60000))" --argjson l "${4:-{\}}" \
  '{address:"t7", state:$st, status:{state:$s}, status_ms:$ms, cwd:"/repo", labels:({watch:"on"} + $l)}'; }
watch() { # watch ARGS...: run practice-watch with the stubs; output in $T/out
  rm -f "$T/log"
  env PATH="$T/bin:$PATH" STUB_LOG="$T/log" STUB_ALERTS="$T/alerts" STUB_LS="$LS" WATCH_ALERT_CMD="$T/alert" \
    XDG_RUNTIME_DIR="$T" WATCH_NOW_MS="$now" WATCH_START_WAIT=0 "$DIR/practice-watch" "$@" >"$T/out" 2>&1
}

# An idle session past the quiet time gets one nudge, and its count goes up.
STUB_GET=$(get live "done" 40) watch pass --apply
ok "an idle session is nudged" logged '^send t7 \[practice-watch\] This session has been idle for 40 minutes'
ok "the nudge names the labels that stop it" logged 'hc label t7 watch=waits'
ok "the nudge count goes up" logged '^label t7 watch.nudges=1$'
# A dry run says so and sends nothing.
STUB_GET=$(get live idle 40) watch pass
ok "a dry run sends nothing" not_logged '^send'
ok "a dry run says what it would do" grep -q 'would nudge' "$T/out"
# Working, or idle for less than the quiet time: nothing.
STUB_GET=$(get live working 90) watch pass --apply
ok "a working session is left alone" not_logged '^send'
STUB_GET=$(get live idle 10) watch pass --apply
ok "a session idle for 10 minutes is left alone" not_logged '^send'
# Blocked on a prompt: an alert, never a send; once, not on every pass.
rm -f "$T/alerts"
STUB_GET=$(get live blocked 40) watch pass --apply
ok "a blocked session gets no send" not_logged '^send'
ok "a blocked session is an alert" alerts 1
key=$(grep -o 'watch.alerted=[^ ]*' "$T/log" | head -1 | cut -d= -f2)
STUB_GET=$(get live blocked 40 "{\"watch.alerted\":\"$key\"}") watch pass --apply
ok "the same blocked state is told once" alerts 1
# Out of nudges: an alert, no more nudges.
rm -f "$T/alerts"
STUB_GET=$(get live "done" 40 '{"watch.nudges":"12"}') watch pass --apply
ok "a session out of nudges gets no send" not_logged '^send'
ok "a session out of nudges is an alert" alerts 1
# An ended session is an alert.
rm -f "$T/alerts"
STUB_GET=$(get exited "done" 40) watch pass --apply
ok "an ended session is an alert" alerts 1
# A send that does not go through is not counted.
STUB_SEND_RC=1 STUB_GET=$(get live "done" 40) watch pass --apply
ok "a failed send is not counted" not_logged '^label t7 watch.nudges'
# When hc does not answer, nothing is decided and the pass still exits 0.
LS='' STUB_GET=$(get live "done" 40) watch pass --apply
ok "a pass with hc down exits 0" test $? = 0
ok "a pass with hc down sends nothing" not_logged '^send'
# A context past the cap: one request for a handoff, in place of the idle nudge; once, not on every pass.
screen() { printf '❯ \n  repo main  ctx %sk\n' "$1"; }
STUB_READ=$(screen 260) STUB_GET=$(get live working 5) watch pass --apply
ok "a big context is asked for a handoff" logged "^send t7 \[practice-watch\] This session's context is 260k tokens"
ok "the handoff request is recorded" logged '^label t7 watch.handoff=260k$'
ok "the handoff request names the handover command" logged 'practice-watch handover <the handoff file> t7 --apply'
STUB_READ=$(screen 260) STUB_GET=$(get live "done" 40) watch pass --apply
ok "the handoff request replaces the idle nudge" not_logged 'has been idle'
STUB_READ=$(screen 300) STUB_GET=$(get live working 5 '{"watch.handoff":"260k"}') watch pass --apply
ok "the handoff request is sent once" not_logged '^send'
STUB_READ=$(screen 240) STUB_GET=$(get live working 5) watch pass --apply
ok "a context under the cap is left alone" not_logged '^send'
# handover: a fresh session in the old one's folder, space and tab, with its command and the handoff; the old one
# leaves the watch only once the fresh one has started.
touch "$T/handoff.md"
fg=$(jq -nc '{state:"live", cwd:"/shell", foreground:{argv:["claude","--permission-mode","x","Continue the work from the handoff at /old.md. Read it first. This session is on the practice watch."], cwd:"/repo"},
  labels:{watch:"waits", "herdr.space":"sp1", "herdr.tab":"tb1"}}')
STUB_GET=$fg watch handover "$T/handoff.md" t7
ok "a handover dry run starts nothing" not_logged '^run'
STUB_GET=$fg watch handover "$T/handoff.md" t7 --apply
ok "handover starts the fresh session as the lead, with only the new handoff" logged "^run --json --bg --no-parent --cwd /repo --label watch=on --label lead=1 --label herdr.space=sp1 --label herdr.tab=tb1 --label lead.from=t7 -- claude --permission-mode x Continue the work from the handoff at $T/handoff.md. Read it first. This session is on the practice watch.$"
ok "handover takes the old session off the watch and the lead, and marks it old" logged '^label t7 watch= watch.nudges= watch.alerted= watch.handoff= lead= watch.old=1$'
# The old session's workers, and those that already reported to it, now report to the fresh one (#331).
STUB_LS_LIVE='{"terminals":[{"address":"t9","parent":"t7"},{"address":"t5","parent":"t3"}]}' STUB_LS_LEADTO='{"terminals":[{"address":"t4"}]}' \
  STUB_GET=$fg watch handover "$T/handoff.md" t7 --apply
ok "handover points the old session's workers at the fresh one" logged '^label t9 lead.to=t8$'
ok "handover moves workers that reported to the old session" logged '^label t4 lead.to=t8$'
ok "handover leaves another lead's workers alone" not_logged '^label t5'
STUB_RUN_FAIL=1 STUB_GET=$fg watch handover "$T/handoff.md" t7 --apply
ok "a failed start leaves the old session on the watch" not_logged '^label t7'
ok "a failed start says so" grep -q 'did not start the fresh session' "$T/out"
# The old session's own launch prompt and a resume stay behind; its options and their values go with it. A line of the
# prompt that starts with - broke the 09:03 handover of 13 Nov: claude read it as an unknown option and exited.
launched=$(jq -nc '{state:"live", foreground:{argv:["claude","--model","sonnet","--permission-mode","bypassPermissions","--resume","abc-123","Plan Sitrep Live as a program.","- The spec (draft 4): x"], cwd:"/repo"}, labels:{}}')
STUB_GET=$launched STUB_GET_t8='{"state":"live"}' watch handover "$T/handoff.md" t7 --apply
ok "handover keeps the options and their values, and drops the old prompt and the resume" logged "^run --json --bg --no-parent --cwd /repo --label watch=on --label lead=1 --label lead.from=t7 -- claude --model sonnet --permission-mode bypassPermissions Continue the work from the handoff at $T/handoff.md. Read it first. This session is on the practice watch.$"
STUB_GET=$launched STUB_GET_t8='{"state":"finished","exit_code":1}' STUB_READ="error: unknown option '- The spec'" watch handover "$T/handoff.md" t7 --apply
ok "a fresh session that dies at start leaves the old session on the watch" not_logged '^label t7'
ok "a fresh session that dies at start says so, with what it said" grep -q "did not stay up.*t7 stays on the watch" "$T/out"
ok "the dead start's own words are shown" grep -q "unknown option" "$T/out"
# An old session (from a handover) closes once it has been idle for WATCH_CLOSE_H hours (default 3), and not while a
# terminal it started still runs. t7 is the watched lead; t5 is the old one.
old() { jq -nc --argjson ms "$((now - $1 * 60000))" '{address:"t5", state:"live", status:{state:"done"}, status_ms:$ms, labels:{"watch.old":"1"}}'; }
OLD='{"terminals":[{"address":"t5"}]}' ALL='{"terminals":[{"address":"t7"},{"address":"t5"}]}'
STUB_LS_OLD=$OLD STUB_LS_LIVE=$ALL STUB_GET_t5=$(old 200) STUB_GET=$(get live working 1) watch pass --apply
ok "an old session idle for 3 hours closes" logged '^kill t5$'
ok "a closed session is removed, which closes its pane" logged '^rm t5$'
STUB_LS_OLD=$OLD STUB_LS_LIVE=$ALL STUB_GET_t5=$(old 100) STUB_GET=$(get live working 1) watch pass --apply
ok "an old session idle for less stays open" not_logged '^kill'
STUB_LS_OLD=$OLD STUB_LS_LIVE=$ALL STUB_GET_t5=$(old 200) STUB_GET=$(get live working 1 | jq -c '.parent="t5"') watch pass --apply
ok "an old session with a live worker stays open" not_logged '^kill'
STUB_LS_OLD=$OLD STUB_LS_LIVE=$ALL STUB_GET_t5=$(old 200) STUB_GET=$(get live working 1) watch pass
ok "a dry run closes nothing" not_logged '^kill'
ok "a dry run says what it would close" grep -q 't5: would close' "$T/out"

# on, waits and off set the labels on the named terminal.
watch on t7
ok "on watches, resets the counts and marks the lead" logged '^label t7 watch=on watch.nudges=0 watch.alerted= watch.handoff= lead=1 watch.old=$'
watch waits t7
ok "waits stops the nudges" logged '^label t7 watch=waits$'
watch off t7
ok "off sets watch=off, so a pass does not watch it again, and keeps the lead" logged '^label t7 watch=off watch.nudges= watch.alerted= watch.handoff=$'

# A pass watches each live top-level agent session that has no watch label, as the lead. One that opted out (watch=off), a
# worker (it has a parent), a plain shell and an old session are left alone.
term() { jq -nc --arg a "$1" --arg p "$2" --arg prog "$3" --argjson l "$4" '{address:$a, state:"live", parent:(if $p == "" then null else $p end), foreground:{argv:[$prog, "--x"]}, status:{state:"working"}, labels:$l}'; }
export STUB_LS_LIVE='{"terminals":[{"address":"a1"},{"address":"a2"},{"address":"a3"},{"address":"a4"},{"address":"a5"}]}'
export STUB_GET_a1 STUB_GET_a2 STUB_GET_a3 STUB_GET_a4 STUB_GET_a5
STUB_GET_a1=$(term a1 "" /opt/claude/claude '{}')
STUB_GET_a2=$(term a2 "" claude '{"watch":"off"}')
STUB_GET_a3=$(term a3 t1 claude '{}')
STUB_GET_a4=$(term a4 "" /usr/bin/bash '{}')
STUB_GET_a5=$(term a5 "" codex '{"watch.old":"1"}')
STUB_GET=$(get live working 1) watch pass
ok "a dry run says it would watch a new top-level session" grep -q 'a1: would watch it as the lead' "$T/out"
ok "a dry run sets no label" not_logged '^label'
STUB_GET=$(get live working 1) watch pass --apply
ok "a new top-level agent session is watched as the lead" logged '^label a1 watch=on watch.nudges=0 watch.alerted= watch.handoff= lead=1$'
ok "an opted-out session, a worker, a shell and an old session are not" not_logged '^label a[2-5] '
unset STUB_LS_LIVE STUB_GET_a1 STUB_GET_a2 STUB_GET_a3 STUB_GET_a4 STUB_GET_a5

# watcherctl: a dry run writes nothing; install writes both units for this checkout; uninstall removes them.
ctl() {
  rm -f "$T/log"
  env PATH="$T/bin:$PATH" STUB_LOG="$T/log" WATCHER_UNIT_DIR="$T/units" "$DIR/watcherctl" "$@" >"$T/out" 2>&1
}
ctl install
ok "an install dry run writes nothing" test ! -e "$T/units"
ok "an install dry run leaves linger alone" not_logged '^enable-linger'
STUB_LINGER=yes ctl install --apply
ok "install leaves linger alone when it is already on" not_logged '^enable-linger'
ctl install --apply
ok "install writes the service" grep -qF "ExecStart=$DIR/practice-watch pass --apply" "$T/units/practice-watch.service"
ok "install writes the timer" grep -q '^OnUnitActiveSec=5min$' "$T/units/practice-watch.timer"
ok "install turns on linger, so the watcher runs after logout" logged "^enable-linger ${USER:-$(id -un)}\$"
ctl enable
ok "enable starts the timer" logged '^--user enable --now practice-watch.timer$'
ctl uninstall --apply
ok "uninstall removes both units" test ! -e "$T/units/practice-watch.service" -a ! -e "$T/units/practice-watch.timer"

echo "$RUN cases, $FAIL failed"
[[ $FAIL == 0 ]] && echo "all watcher tests pass"
((FAIL == 0))
