#!/usr/bin/env python3
"""Tell the operator about scheduled OneDev jobs that failed.

    scripts/scheduled-failures.py [--job NAME ...] [--hours 26] [--dry-run]

Reads the newest builds of each named job (default: Update dependencies and
Deslop nightly) across every project, and posts one Mattermost message listing
each failed build that it has not reported before. Run it from a timer, once or
twice a day. It keeps the ids it reported in a state file, so a failure is
reported once.

Needs ODEV_HOST and ODEV_TOKEN (any account that can read the builds), and
MATTERMOST_WEBHOOK_URL (a #alerts incoming webhook), from the environment or
from ~/.config/claude-skills/mattermost.env. The webhook is a write capability:
it is never printed. The state file is $XDG_STATE_HOME/scheduled-failures.json,
or --state.
Exit 0 when it ran (with or without a failure), 2 on a failed read or post.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

JOBS = ["Update dependencies", "Deslop nightly"]
BAD = {"FAILED", "TIMED_OUT"}


def get(host: str, token: str, path: str, **params: object) -> Any:
    url = f"{host}/~api/{path}" + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def new_failures(builds: list[dict], seen: set[int], since: datetime) -> list[dict]:
    """The failed builds since the cutoff that were not reported before, oldest first."""
    found = [
        b
        for b in builds
        if b.get("status") in BAD
        and b["id"] not in seen
        and datetime.fromisoformat(b["submitDate"]) >= since
    ]
    return sorted(found, key=lambda b: b["submitDate"])


def message(host: str, rows: list[tuple[str, dict]]) -> str:
    lines = [f"**{len(rows)} scheduled OneDev job(s) failed**"]
    for path, b in rows:
        lines.append(
            f"- {path}: {b['jobName']} #{b['number']} {b['status'].lower()} "
            f"{b['submitDate'][:16]} {host}/{path}/~builds/{b['number']}"
        )
    return "\n".join(lines)


def webhook_url() -> str:
    url = os.environ.get("MATTERMOST_WEBHOOK_URL", "")
    env = Path.home() / ".config/claude-skills/mattermost.env"
    if not url and env.is_file():
        for line in env.read_text().splitlines():
            if line.startswith("MATTERMOST_WEBHOOK_URL="):
                url = line.split("=", 1)[1].strip().strip("'\"")
    return url


def main() -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("--job", action="append", help="a job name (repeatable)")
    ap.add_argument("--hours", type=float, default=26, help="how far back to look")
    ap.add_argument("--state", type=Path)
    ap.add_argument("--dry-run", action="store_true", help="print the message, post nothing")
    args = ap.parse_args()
    host, token = os.environ.get("ODEV_HOST", "").rstrip("/"), os.environ.get("ODEV_TOKEN", "")
    if not host or not token:
        print("scheduled-failures: set ODEV_HOST and ODEV_TOKEN", file=sys.stderr)
        return 2
    state = (
        args.state
        or Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "scheduled-failures.json"
    )
    seen: set[int] = set()
    if state.is_file():
        try:
            seen = {int(i) for i in json.loads(state.read_text())}
        except (OSError, ValueError, TypeError):
            print("scheduled-failures: state file unreadable; treated as empty")
    since = datetime.now(UTC) - timedelta(hours=args.hours)
    try:
        failed = []
        for job in args.job or JOBS:
            builds = get(host, token, "builds", query=f'"Job" is "{job}"', offset=0, count=100)
            failed += new_failures(builds, seen, since)
        paths: dict[int, str] = {}
        rows = []
        for b in failed:
            pid = b["projectId"]
            if pid not in paths:
                paths[pid] = get(host, token, f"projects/{pid}")["path"]
            rows.append((paths[pid], b))
    except (OSError, ValueError, KeyError) as e:
        print(f"scheduled-failures: read failed: {e}", file=sys.stderr)
        return 2
    if not rows:
        print("scheduled-failures: no new failed scheduled job")
        return 0
    text = message(host, rows)
    if args.dry_run:
        print(text)
        return 0
    url = webhook_url()
    if not url:
        print("scheduled-failures: no MATTERMOST_WEBHOOK_URL", file=sys.stderr)
        return 2
    try:
        req = urllib.request.Request(
            url, json.dumps({"text": text}).encode(), {"Content-Type": "application/json"}
        )
        urllib.request.urlopen(req, timeout=30).read()
    except Exception as e:  # noqa: BLE001 - the message may hold the webhook URL: print the type only
        print(f"scheduled-failures: post failed: {type(e).__name__}", file=sys.stderr)
        return 2
    state.parent.mkdir(parents=True, exist_ok=True)
    tmp = state.with_suffix(".tmp")
    tmp.write_text(json.dumps(sorted(seen | {b["id"] for _, b in rows})))
    tmp.replace(state)
    print(f"scheduled-failures: reported {len(rows)} failed job(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
