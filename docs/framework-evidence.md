# Framework evidence: what the practice caught and what it cost

This page records one program that the practice built with unattended leads and workers, and what its history shows. Each change to the practice since then names its evidence here. The page also says what is not proved yet, and how the next period will be measured.

## The program

A web app for one user, built from 6 to 10 November 2026: 12 build pull requests, each with an owner and a verifier, under a lead that ran unattended. The numbers come from the repo's git history and its issue tracker.

## What we measured

`scripts/program-scorecard.py` reads the merged pull requests from git:

| Kind of pull request | Count | Source lines added | Test lines added | Test lines deleted | Other lines added |
|---|---|---|---|---|---|
| Build | 12 | 12,339 | 22,976 | 384 | 6,819 |
| Fix | 42 | 1,114 | 5,547 | 1,061 | 3,727 |
| Prune | 12 | 0 | 414 | 4,285 | 1,040 |
| Other (docs and process) | 19 | 71 | 767 | 108 | 20,858 |

- 85 pull requests merged in 92.8 hours.
- For each build pull request, 6.1 pull requests of another kind.
- 1.76 net test lines for each source line.
- "Other" is documents, reports and deploy scripts: 32,444 lines, 2.4 times the source.
- From one build merge to the next: a median of 2.8 hours. Four of the 11 gaps were 10, 13, 16 and 23 hours, and the other seven were 1 to 3 hours. The slowest pull request ran the full pstack multi-phase plan.

The tracker holds 142 issues from the same 93 hours. We sorted them by title into three groups:

| Group | Major | Normal | Minor | Total | Still open |
|---|---|---|---|---|---|
| Product: a defect in the app | 1 | 45 | 28 | 74 | 29 |
| Test flake: a test that fails under load or on a clock | 0 | 23 | 4 | 27 | 6 |
| Tooling and process: the gate, CI, the weekly job, deploy scripts | 4 | 30 | 7 | 41 | 11 |

- 57 of the 74 product issues name a verifier in their text. At least 25 of them say outright that the verifier found the defect ("Found by the PR 6 verifier at head ...").
- Of the 28 Minor product issues, 26 are still open.
- The 42 fix pull requests fixed: the product 9 times, a test flake 15 times, tooling and process 18 times.

## What it shows

1. **A verifier on the real artifact earns its place.** It is named in 57 of the 74 product issues, and at least 25 say outright that it found the defect, before a user did. They include a send on the wrong channel, a forged save that cleared a field, and a new address of a person who said no that got no block.
2. **Most repair work went into the scaffolding, not the product.** 33 of the 42 fix pull requests (79 %) fixed a flaky test or a tool. 68 of the 142 issues (48 %) are about tests and tools.
3. **The flakes come from load and clocks.** Many agents ran test suites at once on one machine, and the tests asserted on elapsed time. One session at a time removes the load.
4. **Too many tests were written, then removed.** 12 prune pull requests deleted 4,285 test lines, about 1 in 7 of all test lines written.
5. **Deep adversarial lanes fill a backlog that nobody works.** 26 of the 28 Minor product findings are still open.
6. **The paper is larger than the product.** Reports, plans and process documents are 2.4 times the source.

## What it does not show

- **No one-session baseline exists.** The numbers say where the cost went. They do not prove that one session builds the same app faster or better.
- The program did ship a working, deployed app in four days, with nobody at the keyboard for most of that time. This page does not weigh that.
- The groups come from keywords in titles, and the finder from a phrase in the issue text. Both are rough: the true count of verifier finds is between 25 and 57.
- It is one project, one operator and four days.

## A first one-session reading

On 10 November 2026 one session did the changes that this page lists, and then worked the open issues of four repos (this repo, the skills repo, the personal config repo and the project template). The same script read both periods:

| Measure | Leads and workers, this repo, 2 to 10 November | One session, four repos, 10 November |
|---|---|---|
| Pull requests merged | 48 in 194 hours | 14 in under 2 hours |
| Rework: pull requests that repair or finish an earlier one of the same period | 23 of 48 (the fix branches) | 4 of 14: the archive left rule text and pages untrue in three repos |
| Test lines added | 8,746 | 42 |
| Open issues closed | not counted | 30 of 67: about a third by a fix, the rest because their subject was retired or already fixed |

What this reading can carry:

- One session does small rule, document and tool changes fast, and each one passed the repo's full check at its head before the merge.
- It is not a like-for-like test. The session's work was small changes with no product feature in them, and its own defects have had no time to show. The fleet period built scripts with tests.
- Tokens were not measured for the session.

So the question stays open for product work. The next product pull requests run in one session, and their rows go into the table under "How we will know".

## What we changed, and the trade-off of each

| Change | Evidence | What we give up |
|---|---|---|
| Tests follow risk, with a budget in lines (PR #87) | 1.76 test lines for each source line, and 1 in 7 test lines pruned | Edge cases of low-risk input have no test |
| The scripts for unattended leads and workers went to `archive/herdr/` (PR #89) | 27 flake issues and 15 flake fixes from load on one machine, 41 tooling issues, a check of 3.7 minutes | Parallel builds and work overnight |
| Tier 3 is tier 2 plus a test for each High risk and one adversarial review (PR #89) | The slowest pull request ran the full plan for 23 hours, and 26 of 28 Minor findings stay open | Less adversarial depth on a high-risk change |
| One verifier for each pull request that changes behaviour stays | Named in 57 of 74 product issues, the finder in at least 25 | One more agent run for each such pull request |

## How the rules match practice outside

| Rule here | Practice outside | Source |
|---|---|---|
| One small pull request at a time, merged when its checks pass at the head | Small batches and trunk-based development | The DORA research ("Accelerate") |
| A short check on every pull request, and few end-to-end journeys | Fast feedback from continuous integration; many small tests, few large ones | DORA; the test sizes in "Software Engineering at Google"; the test pyramid |
| Tests follow risk, at the lowest layer that shows the behaviour | Risk-based testing | The ISTQB syllabus |
| A verifier that did not write the change runs the real artifact | Review by a second person, and a test of the running system | Google's code review guide |
| A defence at the highest layer that can hold it: design, then types and lints, then prose | Mistake-proofing (poka-yoke), and static analysis before review | Lean practice |
| Each rule names its evidence and its cost | A few outcome measures for delivery | DORA's four key measures |

The practice differs from these in one place. The outside sources assume that a person writes and a person reviews. Here an agent writes, an agent verifies and one person decides, so the person's time is the scarce part. That is why the funnel puts human review last.

## How we will know

The next period runs in one session. Read it with the same script. Count the defects from the tracker. Compare these five numbers with the table above:

| Measure | This program | Better means |
|---|---|---|
| Hours from one build merge to the next (median) | 2.8 | Lower |
| Pull requests of another kind for each build pull request | 6.1 | Lower |
| Share of fix pull requests that fix the product | 21 % | Higher |
| Net test lines for each source line | 1.76 | 1.0 or lower |
| Product defects found after merge, for each 1,000 source lines | not counted here | Not higher than with workers |

The first two measures are our form of DORA's lead time for changes and change failure rate.

A script comes back from the archive only when the one-session number is worse on the measure that the script serves, and the reason is the missing script.

## The measures of success, and their first readings

`rules/working-rules.md` now opens with "What success is". These measures say if it works. The scorecard prints
them from git, so no agent reports its own numbers.

| Measure | Good direction | Why |
|---|---|---|
| Pull requests merged for each day | Up | Working software reaches users sooner |
| Hours from the first commit of a pull request to its merge | Down | DORA's lead time for a change |
| Fix pull requests as a share of all | Down | A stand-in for DORA's change failure rate: work that repairs earlier work |
| Net test lines for each source line | Down, to under 1 | "Tests follow risk": a pull request adds no more test lines than source lines |
| Test functions in the tree | Down in a repo that was over-tested, then flat | The prunes work, and new work does not bring the volume back |

First readings, taken on 10 November 2026. "Before" is 3 to 9 November, with the worker fleet. "Day 1" is
10 November, in one session.

| Repo | Period | PRs | Each day | Lead time (h) | Fix share | Test lines for each source line | Test functions |
|---|---|---|---|---|---|---|---|
| The product | Before | 57 | 16.8 | 0.7 | 58 % | 0.86 | 0 to 723 |
| The product | Day 1 | 28 | 28.0 | 0.5 | 32 % | 0.09 | 723 to 702 |
| The product | Day 1, after prune 1 of 8 (Drafts) | 30 | 30.0 | 0.5 | 30 % | 0.06 | 723 to 673 |
| The product | Day 1, after prune 2 of 8 (Records) | 31 | 31.0 | 0.4 | 29 % | -0.01 | 723 to 609 |
| The product | Day 1, after prune 3 of 8 (Mail) | 32 | 32.0 | 0.5 | 28 % | -0.03 | 723 to 590 |
| The product | Day 1, after prune 4 of 8 (Library) | 33 | 33.0 | 0.5 | 27 % | -0.05 | 723 to 568 |
| The product | Day 1, after prune 5 of 8 (Send) | 34 | 34.0 | 0.5 | 26 % | -0.09 | 723 to 528 |
| The product | Day 1, after prune 6 of 8 (Nos) | 35 | 35.0 | 0.5 | 26 % | -0.09 | 723 to 527 |
| The product | Day 1, after prune 7 of 8 (Platform) | 36 | 36.0 | 0.5 | 25 % | -0.14 | 723 to 467 |
| The product | Day 1, after prune 8 of 8 (deploy scripts) | 37 | 37.0 | 0.5 | 24 % | -0.18 | 723 to 467 |
| The skills repo | Before | 18 | 6.0 | 0.1 | 28 % | 0.59 | 29 to 345 |
| The skills repo | Day 1 | 6 | 6.0 | 0.0 | 33 % | 0.20 | 345 to 352 |
| The template repo | Before | 7 | 7.0 | 12.4 | 86 % | 0.82 | 84 to 134 |
| The template repo | Day 1 | 10 | 10.0 | 0.1 | 60 % | -0.82 | 134 to 92 |
| The settings repo | Before | 37 | 7.0 | 0.0 | 0 % | 0.25 | 45 to 96 |
| The settings repo | Day 1 | 11 | 11.0 | 0.0 | 64 % | 0.31 | 96 to 102 |
| This repo | Before | 40 | 6.2 | 0.1 | 55 % | 0.97 | 18 to 332 |
| This repo | Day 1 | 12 | 12.0 | 0.1 | 17 % | 0.79 | 332 to 0 |

The rows "after prune N of 8" track the one-session prune of the product's tests, one feature slice for
each pull request. Each is read from 10 November 00:00 to that merge, so it includes the "Day 1" row.
Over the eight prunes, the product's test lines went from 24,464 to 19,016, and a pull request's CI build from
about 6 minutes to about 4.5. The plan aimed at about 10,000 lines; the Send core, the test fakes and the gate's
own tests hold most of what is left.

Read them with care:

- One day is a short period, and day 1 was spent on the framework itself, not on product features.
- The fix share reads the branch name. A branch named `fix/...` counts; a repair on another branch does not.
- Lead time starts at the first commit, so the time an agent thinks before that commit is not in it.
- The count of test functions matches the test declarations of Python, C# and JavaScript by pattern. It leaves
  out an `archive/` folder, which is why this repo ends at 0: its tests were for the archived scripts.
- No measure here shows a defect that reached a user. Until one does, the fix share is the nearest sign.

Take the next reading after a week of work, and add its rows:

```bash
scripts/program-scorecard.py --repo <repo> --since '2026-11-10 00:00' --src '' \
  --kind 'build=^(pr-|feat)' --kind 'fix=^(fix|class-)' --kind 'prune=^prune'
```

The outside evidence for these measures, and against some of our first ideas, is in
`docs/research/2026-11-10-agent-success-criteria.md`.

## How to measure your own project

```sh
scripts/program-scorecard.py --repo <repo> --kind 'build=^pr-\d' --kind 'fix=^(fix|class-)' --kind 'prune=^prune'
scripts/program-scorecard.py --repo <repo> --since '2026-11-10 12:00'
```

Give `--kind` the branch-name pattern of each kind in your repo. For the issues, list them from your forge, sort them by title into product, test flake and tooling, and count who found each one.
