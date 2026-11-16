#!/bin/bash
# Tests for scripts/scheduled-failures.py against a fake OneDev API and a fake webhook: a failed scheduled build is posted
# once, a green or old one never, and a build already reported is not posted again.
#   scripts/tests/scheduled-failures.test.sh
DIR=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'kill "$SRV" 2>/dev/null; rm -rf -- "$T"' EXIT
mkdir -p "$T/api/~api/projects"
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000+00:00)
cat >"$T/api/~api/builds" <<JSON
[{"id":1,"projectId":7,"jobName":"Update dependencies","number":4,"status":"FAILED","submitDate":"$NOW"},
 {"id":2,"projectId":7,"jobName":"Update dependencies","number":5,"status":"SUCCESSFUL","submitDate":"$NOW"},
 {"id":3,"projectId":7,"jobName":"Update dependencies","number":2,"status":"FAILED","submitDate":"2020-01-01T00:00:00.000+00:00"}]
JSON
echo '{"path":"demo/app"}' >"$T/api/~api/projects/7"
cat >"$T/srv.py" <<'PY'
import http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers["Content-Length"])
        open(sys.argv[2], "ab").write(self.rfile.read(n) + b"\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass
import os; os.chdir(sys.argv[1])
http.server.HTTPServer(("127.0.0.1", int(sys.argv[3])), H).serve_forever()
PY
PORT=$((20000 + RANDOM % 20000))
python3 "$T/srv.py" "$T/api" "$T/posts" "$PORT" &
SRV=$!
sleep 1
export ODEV_HOST="http://127.0.0.1:$PORT" ODEV_TOKEN=x MATTERMOST_WEBHOOK_URL="http://127.0.0.1:$PORT/hook" HOME="$T/home"
RUN=0 FAIL=0
check() {
  RUN=$((RUN + 1))
  if [[ "$2" == "$3" ]]; then echo "ok    $1"; else
    echo "FAIL  $1: got [$3], want [$2]"
    FAIL=$((FAIL + 1))
  fi
}
run() { python3 "$DIR/scheduled-failures.py" --job "Update dependencies" --state "$T/state.json" 2>&1; }
out=$(run)
check "the failed recent build is reported" "scheduled-failures: reported 1 failed job(s)" "$out"
check "one post names the project, job and build" "1" "$(grep -c 'demo/app: Update dependencies #4 failed' "$T/posts")"
check "the green and the old build are not named" "0" "$(grep -c '#5\|#2' "$T/posts")"
out=$(run)
check "a build already reported is not posted again" "scheduled-failures: no new failed scheduled job" "$out"
check "it posted once" "1" "$(wc -l <"$T/posts")"
echo '{bad' >"$T/state.json"
out=$(run)
check "a corrupt state file is treated as empty and the failure is reported" "scheduled-failures: state file unreadable; treated as empty
scheduled-failures: reported 1 failed job(s)" "$out"
check "the state file is valid again" "1" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$T/state.json")"
rm -f "$T/state.json"
out=$(MATTERMOST_WEBHOOK_URL='htps//SECRETHOOK' run)
check "a malformed webhook is not printed" "0" "$(grep -c SECRETHOOK <<<"$out")"
check "a malformed webhook fails with the error type only" "scheduled-failures: post failed: ValueError" "$out"
echo "$RUN checks, $FAIL failed"
((FAIL == 0))
