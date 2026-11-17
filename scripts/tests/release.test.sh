#!/bin/bash
# Tests for scripts/release.sh and scripts/canary.sh with stub odev and gh:
#   a tag needs a canary pass record for that exact sha, and a canary on an older template stops the run.
#   scripts/tests/release.test.sh
DIR=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
FAIL=0
check() { # description, command that must succeed
  "${@:2}" || {
    echo "FAIL $1"
    FAIL=1
  }
}

# A template clone with an origin: two commits on main.
git init -q --bare "$T/origin.git"
git init -q -b main "$T/repo"
cd "$T/repo" || exit 1
git config user.email t@t && git config user.name t
git commit -q --allow-empty -m one && one=$(git rev-parse HEAD)
git commit -q --allow-empty -m two && two=$(git rev-parse HEAD)
git remote add origin "$T/origin.git" && git push -q origin main
export CANARY_DIR="$T/pass"
mkdir "$CANARY_DIR"
touch "$CANARY_DIR/$one.pass"

refused() { ! "$@" >/dev/null 2>&1; }
check "release refuses a sha with no record (another sha has one)" refused "$DIR/release.sh" --apply v9.0.1 "$two"
check "no tag was made" test -z "$(git tag)"
check "release with the record" "$DIR/release.sh" --apply -m msg v9.0.1 "$one" >/dev/null 2>&1
check "tag is on origin" git -C "$T/origin.git" rev-parse -q --verify refs/tags/v9.0.1 >/dev/null

# Stub forges: one OneDev canary whose _commit is $COMMIT, one job with a schedule.
mkdir "$T/bin"
cat >"$T/bin/odev" <<'STUB'
#!/bin/bash
echo "$*" >>"$STUB_LOG"
case "$*" in
  *"project list"*) echo '[{"id":7,"path":"app"}]' ;;
  *default-branch*) echo '"main"' ;;
  *file=.copier-answers.yml*) printf '{"base64Content":"%s"}' "$(printf '_commit: %s\n' "$COMMIT" | base64 -w0)" ;;
  *file=.onedev-buildspec.yml*) printf '{"base64Content":"%s"}' "$(printf -- '- name: Nightly\n  triggers:\n  - !ScheduleTrigger\n    cronExpression: x\n- name: Security review\n  triggers:\n  - !ScheduleTrigger\n' | base64 -w0)" ;;
  *"build run"*) ;;
  *"build list"*) echo '[{"id":41,"job":"Nightly"}]' ;;
esac
STUB
chmod +x "$T/bin/odev"
printf 'onedev app\n' >"$T/list"
export PATH="$T/bin:$PATH" STUB_LOG="$T/log" ODEV_HOST=http://x CANARY_LIST="$T/list" CANARY_POLL=0

: >"$T/log"
COMMIT=$one refused "$DIR/canary.sh" --apply "$two"
check "an older template started no job" test "$(grep -c 'build run' "$T/log" || true)" = 0
COMMIT=$two check "canary run on the candidate" "$DIR/canary.sh" --apply "$two" >/dev/null
check "a job on canary.skip is never started" test "$(grep -c 'job Security review' "$T/log" || true)" = 0
check "a skipped job is in the pass record" grep -q 'SKIPPED' "$CANARY_DIR/$two.pass"
check "pass record written" test -f "$CANARY_DIR/$two.pass"

((FAIL)) && exit 1
echo "ok"
