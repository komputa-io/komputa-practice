#!/usr/bin/env python3
"""Prints a scorecard of a program from its git history: merged pull requests by kind, and the lines each kind added.

    scripts/program-scorecard.py [--repo DIR] [--branch REF] [--since DATE] [--until DATE]
                                 [--kind NAME=REGEX]... [--src PREFIX]... [--skip REGEX]

A pull request is a first-parent merge commit on the branch whose subject names it: "Merges PR #7 from fix-3"
(OneDev) or "Merge pull request #7 from owner/fix-3" (GitHub). The branch name gives the kind. The default kinds
are build (pr-<n>), fix (fix...) and prune (prune...); each other branch is "other". Lines are split by path:
test (tests/, /tests/, .test.), source (under --src, default src/) and other. A path that matches --skip is left
out (default: migrations, lock files and an `archive/` folder).

It also prints the measures of "What success is" (`rules/working-rules.md`): pull requests merged for each day,
the median hours from the first commit of a pull request to its merge, fix pull requests as a share of all, and
the count of test functions in the tree before the first merge and at the last one.

Use it to compare two periods of one repo, for example a period with workers and a period in one session.
`docs/framework-evidence.md` holds the first reading. Exit codes: 0 printed, 1 no pull request found, 2 wrong
arguments or not a git repo.
"""

import argparse
import itertools
import re
import subprocess
import sys

TEST_FUNCTION = r"^\s*(async\s+)?def test_|^\s*\[(Test|Fact|Theory|TestMethod)\b|^\s*(it|test)\("
# OneDev names the branch whole ("fix/3-name"); GitHub puts the owner before it ("owner/fix-3").
SUBJECT = re.compile(r"Merges PR #(\d+) from (\S+)|Merge pull request #(\d+) from [^/\s]+/(\S+)")
KINDS = ["build=^pr-\\d", "fix=^fix", "prune=^prune"]


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


def lead_hours(repo, commit, merged):
    """Hours from the first commit of a pull request's branch to its merge."""
    stamps = git(repo, "log", "--format=%at", f"{commit}^1..{commit}^2")
    return (merged - min(int(s) for s in stamps)) / 3600 if stamps else 0.0


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
    window = [f"--{k}={v}" for k, v in (("since", args.since), ("until", args.until)) if v]

    rows = []
    commits = []
    for line in git(
        args.repo, "log", "--first-parent", "--merges", "--format=%H %at %s", *window, args.branch
    ):
        commit, when, subject = line.split(" ", 2)
        named = SUBJECT.search(subject)
        if not named:
            continue
        branch = named[2] or named[4]
        kind = next((name for name, rx in kinds if rx.search(branch)), "other")
        rows.append(
            (
                kind,
                int(when),
                lines_of(args.repo, commit, args.src or ["src/"], skip),
            )
        )
        commits.append(commit)
    if not rows:
        print("program-scorecard: no merged pull request found", file=sys.stderr)
        return 1

    times = sorted(when for _, when, _ in rows)
    hours = (times[-1] - times[0]) / 3600
    print(f"{len(rows)} pull requests merged over {hours:.1f} hours")
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
    leads = sorted(lead_hours(args.repo, c, when) for c, (_, when, _) in zip(commits, rows))
    print(
        f"median hours from the first commit of a pull request to its merge: {leads[len(leads) // 2]:.1f}"
    )
    fixes = sum(1 for k, _, _ in rows if k == "fix")
    print(f"fix pull requests as a share of all: {100 * fixes / len(rows):.0f} %")
    # git log lists the newest merge first.
    print(
        f"test functions in the tree: {tests_at(args.repo, commits[-1] + '^1', skip)} before the first merge,"
        f" {tests_at(args.repo, commits[0], skip)} at the last"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
