#!/usr/bin/env python3
"""Prints a scorecard of a program from its git history: merged pull requests by kind, and the lines each kind added.

    scripts/program-scorecard.py [--repo DIR] [--branch REF] [--since DATE] [--until DATE]
                                 [--kind NAME=REGEX]... [--src PREFIX]... [--skip REGEX]

A pull request is a first-parent commit on the branch that names it: a merge commit "Merges PR #7 from fix-3"
(OneDev) or "Merge pull request #7 from owner/fix-3" (GitHub), whose branch name gives the kind, or a squash
commit "fix(verify): keep the pid (#7)", whose conventional-commit type gives the kind. The default kinds are
the branch kinds of hooks/block-branch-name.sh: build (feat... or pr-<n>), fix, docs, refactor,
chore (chore... or ci...), perf, test and prune; each other name is "other". Lines are split by path:
test (tests/, /tests/, .test.), source (under --src, default src/) and other. A path that matches --skip is left
out (default: migrations, lock files and an `archive/` folder).

It also prints the measures of "What success is" (`rules/working-rules.md`): pull requests merged for each day,
the median hours from the first commit of a pull request to its merge, fix pull requests as a share of all, and
the count of test functions in the tree before the first merge and at the last one. A squash merge keeps no
branch commits, so the lead time counts merge commits only. Last, the Deslop keep lines that merges added to and
removed from `.deslop-decisions`: a keep is a copy left in place, so a count that grows with each pull request
means the duplicate gate is waved through, not acted on.

Each reading names the practice version it was made with: `_commit:` in the repo's `.copier-answers.yml` at each
pull request, so readings from different repos and versions can be compared.

Use it to compare two periods of one repo, for example a period with workers and a period in one session.
Exit codes: 0 printed, 1 no pull request found, 2 wrong arguments or not a git repo.
"""

import argparse
import itertools
import re
import subprocess
import sys

TEST_FUNCTION = r"^\s*(async\s+)?def test_|^\s*\[(Test|Fact|Theory|TestMethod)\b|^\s*(it|test)\("
# OneDev names the branch whole ("fix/3-name"); GitHub puts the owner before it ("owner/fix-3").
SUBJECT = re.compile(r"Merges PR #(\d+) from (\S+)|Merge pull request #(\d+) from [^/\s]+/(\S+)")
SQUASH = re.compile(r"\(#(\d+)\)$")
# A squash merge keeps no branch name: "feat(today): …" gives "feat".
TYPE = re.compile(r"^([a-z]+)(\([^)]*\))?!?:")
# The branch kinds hooks/block-branch-name.sh enforces: <kind>/<name>. A feat branch is a build; pr-<n> is OneDev's.
KINDS = [
    "build=^pr-\\d|^feat",
    "fix=^fix",
    "docs=^docs",
    "refactor=^refactor",
    "chore=^chore|^ci",
    "perf=^perf",
    "test=^test",
    "prune=^prune",
]


def git(repo, *args):
    done = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, check=False)
    if done.returncode != 0:
        print(f"program-scorecard: git {args[0]} failed: {done.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return done.stdout.strip().split("\n") if done.stdout.strip() else []


def tests_at(repo, commit, skip):
    """The count of test functions in the tree of one commit: Python, C# and JavaScript test declarations."""
    done = subprocess.run(
        ["git", "-C", repo, "grep", "-c", "-E", TEST_FUNCTION, commit, "--"],
        capture_output=True, text=True, check=False,
    )  # fmt: skip
    rows = (row.removeprefix(f"{commit}:").rsplit(":", 1) for row in done.stdout.splitlines())
    return sum(int(row[1]) for row in rows if len(row) == 2 and not skip.search(row[0]))


def keeps_changed(repo, window, branch):
    """Keep lines that merges on the branch added to and removed from .deslop-decisions."""
    diff = git(repo, "log", "--first-parent", "--diff-merges=first-parent", "-p", "--format=", *window, branch,
               "--", ".deslop-decisions")  # fmt: skip
    keep = re.compile(r"^\S+\s+keep\s")
    added = sum(
        1 for d in diff if d.startswith("+") and not d.startswith("+++") and keep.match(d[1:])
    )
    removed = sum(
        1 for d in diff if d.startswith("-") and not d.startswith("---") and keep.match(d[1:])
    )
    return added, removed


def lead_hours(repo, commit, merged):
    """Hours from the first commit of a pull request's branch to its merge."""
    stamps = git(repo, "log", "--format=%at", f"{commit}^1..{commit}^2")
    return (merged - min(int(s) for s in stamps)) / 3600 if stamps else 0.0


def version_at(repo, commit):
    """The practice version a repo was on at one commit: `_commit:` in its .copier-answers.yml, or None."""
    done = subprocess.run(
        ["git", "-C", repo, "show", f"{commit}:.copier-answers.yml"],
        capture_output=True, text=True, check=False,
    )  # fmt: skip
    found = re.search(r"^_commit:\s*(\S+)", done.stdout, re.MULTILINE)
    return found[1] if found else None


def lines_of(repo, commit, src, skip):
    """Added source, added test, deleted test and added other lines of one merge against its first parent."""
    source = test = test_gone = other = 0
    for row in git(repo, "diff", "--numstat", f"{commit}^1", commit):
        added, gone, path = row.split("\t", 2)
        if added == "-" or skip.search(path):
            continue
        if path.startswith("tests/") or "/tests/" in path or ".test." in path:
            test, test_gone = test + int(added), test_gone + int(gone)
        elif path.startswith(tuple(src)):
            source += int(added)
        else:
            other += int(added)
    return source, test, test_gone, other


def main():
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n\n")[0], allow_abbrev=False
    )
    parser.add_argument("--repo", default=".")
    parser.add_argument("--branch", default="origin/main")
    parser.add_argument("--since")
    parser.add_argument("--until")
    parser.add_argument("--kind", action="append", metavar="NAME=REGEX")
    parser.add_argument("--src", action="append", metavar="PREFIX")
    parser.add_argument("--skip", default=r"Migrations/|\.lock$|lock\.json$|-lock\.|^archive/")
    args = parser.parse_args()
    skip = re.compile(args.skip)
    kinds = [(name, re.compile(rx)) for name, rx in (k.split("=", 1) for k in args.kind or KINDS)]
    # git reads a bare date ("2026-11-16") as that day at the current time of day; a window starts and ends at midnight.
    window = [
        f"--{k}={v}T00:00:00" if re.fullmatch(r"\d{4}-\d{2}-\d{2}", v) else f"--{k}={v}"
        for k, v in (("since", args.since), ("until", args.until))
        if v
    ]

    rows = []
    commits = []
    versions = []
    for line in git(
        args.repo, "log", "--first-parent", "--format=%H%x1f%at%x1f%P%x1f%s", *window, args.branch
    ):
        commit, when, parents, subject = line.split("\x1f", 3)
        merge = len(parents.split()) > 1
        named = SUBJECT.search(subject) if merge else None
        if named:
            label = named[2] or named[4]
        elif not merge and SQUASH.search(subject):
            typed = TYPE.match(subject)
            label = typed[1] if typed else ""
        else:
            continue
        kind = next((name for name, rx in kinds if rx.search(label)), "other")
        rows.append(
            (
                kind,
                int(when),
                lines_of(args.repo, commit, args.src or ["src/"], skip),
            )
        )
        commits.append((commit, merge))
        versions.append(version_at(args.repo, commit))
    if not rows:
        print("program-scorecard: no merged pull request found", file=sys.stderr)
        return 1

    times = sorted(when for _, when, _ in rows)
    hours = (times[-1] - times[0]) / 3600
    print(f"{len(rows)} pull requests merged over {hours:.1f} hours")
    # git log lists the newest first; name the versions oldest first.
    seen = {v: versions.count(v) for v in reversed(versions) if v}
    print(
        "practice version (.copier-answers.yml): "
        + ", ".join(f"{v} for {n} pull request{'s' if n > 1 else ''}" for v, n in seen.items())
        if seen
        else "practice version: not recorded (no .copier-answers.yml)"
    )
    print(f"{'kind':8} {'PRs':>4} {'source +':>9} {'test +':>8} {'test -':>8} {'other +':>8}")
    for kind in [name for name, _ in kinds] + ["other"]:
        mine = [counts for k, _, counts in rows if k == kind]
        totals = [sum(c[i] for c in mine) for i in range(4)]
        print(
            f"{kind:8} {len(mine):>4} {totals[0]:>9} {totals[1]:>8} {totals[2]:>8} {totals[3]:>8}"
        )
    source = sum(c[0] for _, _, c in rows)
    test = sum(c[1] - c[2] for _, _, c in rows)
    builds = sum(1 for k, _, _ in rows if k == kinds[0][0])
    print(
        f"net test lines for each source line: {test / source:.2f}" if source else "no source lines"
    )
    print(
        f"pull requests of another kind for each {kinds[0][0]} pull request: {(len(rows) - builds) / builds:.1f}"
        if builds
        else ""
    )
    stamps = sorted(when for k, when, _ in rows if k == kinds[0][0])
    gaps = sorted((b - a) / 3600 for a, b in itertools.pairwise(stamps))
    if gaps:
        print(f"median hours from one {kinds[0][0]} merge to the next: {gaps[len(gaps) // 2]:.1f}")
    days = max(hours / 24, 1.0)
    print(f"pull requests merged for each day: {len(rows) / days:.1f}")
    leads = sorted(
        lead_hours(args.repo, c, when) for (c, merge), (_, when, _) in zip(commits, rows) if merge
    )
    print(
        f"median hours from the first commit of a pull request to its merge: {leads[len(leads) // 2]:.1f}"
        if leads
        else "median hours from the first commit of a pull request to its merge: not known (squash merges only)"
    )
    fixes = sum(1 for k, _, _ in rows if k == "fix")
    print(f"fix pull requests as a share of all: {100 * fixes / len(rows):.0f} %")
    # git log lists the newest merge first.
    print(
        f"test functions in the tree: {tests_at(args.repo, commits[-1][0] + '^1', skip)} before the first merge,"
        f" {tests_at(args.repo, commits[0][0], skip)} at the last"
    )
    added, removed = keeps_changed(args.repo, window, args.branch)
    print(f"Deslop keeps: {added} added, {removed} removed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
