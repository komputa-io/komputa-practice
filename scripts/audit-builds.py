#!/usr/bin/env python3
"""Audit the CI pattern across every project on a OneDev server and on GitHub.

    scripts/audit-builds.py --onedev <url> [--github <owner> ...]

Each project should hold the jobs the template seeds: Deslop on each pull
request, the Deslop nightly and the weekly dependency refresh, at its own
schedule_slot (copier.yml), so that projects on one server do not run at once.
It prints one line for each project: its template version, its slot, which of
the three it holds, and its two schedules. Then it names each pair of projects
that share a schedule, and the lowest free slots. A project whose description
starts with [ARCHIVED is named once and not checked.

Read only. It lists OneDev projects with odev, and reads each default branch
with a shallow, blob-less clone into a temporary folder that it removes; git
uses odev's credential helper. GitHub repos come through gh.
Exit 0 when every project conforms and no two share a schedule, 1 when one
does not, 2 on wrong arguments or a failed read.
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from dataclasses import dataclass, field, replace
from pathlib import Path

JOBS = ("Duplicate code", "Deslop nightly", "Update dependencies")


@dataclass(frozen=True)
class Project:
    name: str
    template: str
    slot: str
    held: tuple[str, ...]
    schedules: dict[str, str] = field(default_factory=dict)
    archived: bool = False

    @property
    def conforms(self) -> bool:
        return self.template != "none" and len(self.held) == len(JOBS)


def run(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=True).stdout


def answers(text: str) -> tuple[str, str]:
    commit = re.search(r"^_commit: (\S+)", text, re.MULTILINE)
    slot = re.search(r"^schedule_slot: (\d+)", text, re.MULTILINE)
    return (commit.group(1) if commit else "none", slot.group(1) if slot else "-")


def onedev_project(spec: str, copier: str, name: str) -> Project:
    """A project from its build spec: each job's block runs to the next `- name:`."""
    # A spec may indent its jobs list; read it as if each job started the line.
    lead = re.search(r"^( *)- name: ", spec, re.MULTILINE)
    if lead and lead.group(1):
        cut = lead.group(1)
        spec = "\n".join(line.removeprefix(cut) for line in spec.split("\n"))
    blocks = dict(re.findall(r"^- name: (.+)\n((?:(?!- name: ).*\n?)*)", spec, re.MULTILINE))
    held, schedules = [], {}
    for job in JOBS:
        block = blocks.get(job, "")
        cron = re.search(r"cronExpression: (.+)", block)
        trigger = "PullRequestUpdateTrigger" if job == "Duplicate code" else "ScheduleTrigger"
        if trigger in block:
            held.append(job)
        if cron:
            schedules[job] = cron.group(1).strip()
    return Project(name, *answers(copier), tuple(held), schedules)


def onedev(host: str) -> list[Project]:
    listed = json.loads(run("odev", "project", "list", "--host", host, "--limit", "1000", "--json"))
    archived = {p["path"] for p in listed if (p.get("description") or "").startswith("[ARCHIVED")}
    paths = [p["path"] for p in listed]
    found = []
    with tempfile.TemporaryDirectory() as tmp:
        for path in paths:
            repo = Path(tmp) / path.replace("/", "__")
            run(
                "git",
                "clone",
                "-q",
                "--depth",
                "1",
                "--filter=blob:none",
                "--no-checkout",
                f"{host.rstrip('/')}/{path}.git",
                str(repo),
            )

            def show(name: str, repo: Path = repo) -> str:
                done = subprocess.run(
                    ["git", "show", f"HEAD:{name}"],
                    cwd=repo,
                    check=False,
                    capture_output=True,
                    text=True,
                )
                return done.stdout if done.returncode == 0 else ""

            project = onedev_project(
                show(".onedev-buildspec.yml"), show(".copier-answers.yml"), path
            )
            found.append(replace(project, archived=path in archived))
    return found


def github(owner: str) -> list[Project]:
    repos = json.loads(
        run(
            "gh",
            "repo",
            "list",
            owner,
            "--limit",
            "200",
            "--no-archived",
            "--source",
            "--json",
            "nameWithOwner",
        )
    )
    found = []
    for r in repos:
        name = r["nameWithOwner"]

        def read(path: str, name: str = name) -> str:
            done = subprocess.run(
                ["gh", "api", f"repos/{name}/contents/{path}", "--jq", ".content"],
                check=False,
                capture_output=True,
                text=True,
            )
            return base64.b64decode(done.stdout).decode() if done.returncode == 0 else ""

        flows = {
            f: read(f".github/workflows/{f}")
            for f in ("gate.yml", "deslop-nightly.yml", "update-deps.yml")
        }
        held, schedules = [], {}
        if "deslop-pr.sh" in flows["gate.yml"]:
            held.append(JOBS[0])
        for job, f in ((JOBS[1], "deslop-nightly.yml"), (JOBS[2], "update-deps.yml")):
            cron = re.search(r"cron: '([^']+)'", flows[f])
            if cron:
                held.append(job)
                schedules[job] = cron.group(1)
        found.append(Project(name, *answers(read(".copier-answers.yml")), tuple(held), schedules))
    return found


def slot_of(p: Project) -> int | None:
    """The slot from the answers file, else from the nightly's time (01:00 plus 5 minutes a slot)."""
    if p.slot.isdigit():
        return int(p.slot)
    cron = re.match(r"0 (\d+) (\d+) ", p.schedules.get("Deslop nightly", ""))
    return (int(cron.group(2)) - 1) * 12 + int(cron.group(1)) // 5 if cron else None


def report(everything: list[Project]) -> int:
    projects = [p for p in everything if not p.archived]
    gone = sorted(p.name for p in everything if p.archived)
    for p in sorted(projects, key=lambda p: p.name):
        missing = [j for j in JOBS if j not in p.held]
        state = "ok" if p.conforms else "MISSING " + ", ".join(missing or ["the template"])
        times = "; ".join(f"{j}: {c}" for j, c in p.schedules.items())
        print(f"{p.name:40} {p.template:8} slot {p.slot:>3}  {state:45} {times}")
    shared = defaultdict(list)
    for p in projects:
        for job, cron in p.schedules.items():
            shared[(job, cron)].append(p.name)
    clashes = {k: v for k, v in shared.items() if len(v) > 1}
    for (job, cron), names in sorted(clashes.items()):
        print(f"SHARED {job} at '{cron}': {', '.join(sorted(names))}")
    if gone:
        print(f"archived, not checked ({len(gone)}): {', '.join(gone)}")
    used = {s for p in projects if (s := slot_of(p)) is not None}
    print("free slots:", ", ".join(str(s) for s in range(60) if s not in used)[:80])
    return 0 if all(p.conforms for p in projects) and not clashes else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument("--onedev", help="the OneDev server's URL")
    parser.add_argument("--github", nargs="*", default=[], help="GitHub owners whose repos to read")
    args = parser.parse_args()
    if not args.onedev and not args.github:
        parser.print_usage(sys.stderr)
        return 2
    try:
        projects = (onedev(args.onedev) if args.onedev else []) + [
            p for o in args.github for p in github(o)
        ]
    except subprocess.CalledProcessError as e:
        print(f"audit-builds: {' '.join(e.cmd[:3])} failed: {e.stderr.strip()}", file=sys.stderr)
        return 2
    return report(projects)


if __name__ == "__main__":
    sys.exit(main())
