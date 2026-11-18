#!/usr/bin/env bash
# Tests the template's OneDev helper filing issues, with a stub curl on PATH that acts as a OneDev
# whose Triage field is required: nothing reaches a server.
#   scripts/tests/onedev-issue.test.sh
set -Eeuo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
helper=$(cd -- "$here/../.." && pwd)'/template/scripts/forge/{% if forge == "onedev" %}onedev.sh{% endif %}'
root=$(mktemp -d "${TMPDIR:-/tmp}/onedev-issue-test.XXXXXX")
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin"

# The stub answers the project id, and files an issue only when its fields hold Triage, as OneDev does.
cat >"$root/bin/curl" <<'STUB'
#!/usr/bin/env bash
url=${*: -1}
case $url in
  */projects/ids/*) echo 7 ;;
  */issues)
    body=$(cat)
    if jq -e '.fields.Triage' <<<"$body" >/dev/null; then echo "$body" >>"$STUB_LOG"; echo 42; exit 0; fi
    echo 'Invalid fields: Triage (value must not be empty)'
    exit 22
    ;;
esac
STUB
chmod +x "$root/bin/curl"

fails=0
run() { PATH="$root/bin:$PATH" STUB_LOG="$root/log" ODEV_HOST=stub ODEV_PROJECT=p ODEV_TOKEN=t bash "$helper" "$@"; }

# shellcheck disable=SC2310 # the status is the answer
if run issue-create-high 'Live secret' 'body' 2>"$root/err" \
  && [[ $(jq -c '[.fields.Priority, .fields.Triage, .confidential]' "$root/log") == '["Major","needs-triage",false]' ]]; then
  echo "ok: issue-create-high files with Priority=Major and Triage=needs-triage"
else
  echo "FAIL: issue-create-high: $(cat "$root/err")"
  fails=$((fails + 1))
fi

rm -f "$root/log"
# shellcheck disable=SC2310 # the status is the answer
if run issue-create-security 'Finding' 'body' 2>"$root/err" \
  && [[ $(jq -c '[.fields.Triage, .confidential]' "$root/log") == '["needs-triage",true]' ]]; then
  echo "ok: issue-create-security files a confidential issue with Triage"
else
  echo "FAIL: issue-create-security: $(cat "$root/err")"
  fails=$((fails + 1))
fi

((fails == 0))
