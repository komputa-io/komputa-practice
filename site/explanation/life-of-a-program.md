---
title: The life of a program
description: One program from the plan to the hand over, in one session, and the check at each step.
---

A program is a set of pull requests that one Claude Code session drives. The session plans, builds, verifies and merges one pull request at a time. For a change that a user sees, a verifier subagent checks the work, because the session that wrote it does not.

<img class="figure-light" src="/figures/life-of-a-program.png" alt="The life of a program: plan, build, verify, merge, hand over. Each step names the rule or check that holds it. Verify and merge are where something other than the author checks the work.">
<img class="figure-dark" src="/figures/life-of-a-program-dark.png" alt="The life of a program: plan, build, verify, merge, hand over. Each step names the rule or check that holds it. Verify and merge are where something other than the author checks the work.">

## The steps

| Step | What happens | What holds it |
|---|---|---|
| 1. Plan | The session puts each pull request in a tier and states the size before the operator's go. | The tier table in the [rules](/reference/rules). |
| 2. Build | The session builds one pull request on its own branch. It writes the tests that the risks need and runs the gate. | "Tests follow risk" in the rules, the [hooks](/reference/hooks) and `scripts/gate.sh`. |
| 3. Verify | Tier 1: the session runs the real behaviour once. Tier 2 and up: a verifier subagent runs the acceptance checks on the real artifact and reads the diff. A finding counts only when a run shows it. | The tier table. |
| 4. Merge | The session merges when every check passed at the head commit. A change to a live service waits for the operator's yes. | The checks at the head commit. |
| 5. Hand over | When the context nears 250k tokens, the session writes a handoff file. A fresh session starts from it, not from the old conversation. | The [watcher](/explanation/the-watcher) asks for the handoff when nobody watches. |

Steps 2 to 4 repeat for each pull request. The next one starts from the merged result, so each review stays small.

## When a worker runs in a pane

Sometimes you want to watch a long build, or run it beside other work. Then the session becomes a lead and starts a worker with [herdr](/reference/skills). The steps change in three places:

- **Brief.** The lead writes the goal, the branch, the risks and the report contract to `.audit/<task>.brief.md`. One brief holds about two deliverables.
- **Build and report.** The worker builds in its own worktree, then writes a report file and sends the lead one short message. The lead reads the report and checks it against the repo before it merges.
- **Finish.** The lead closes the worker's pane after the final report. A lead that hands over ends only after its workers end.

The lead rules in [Lead rules](/reference/lead-rules) hold these steps.

## The limits that keep it cheap

- A session hands over near 250k tokens.
- A worker's brief holds about two deliverables, so the worker finishes under about 200k tokens.
- A worker whose context passes 300k tokens finishes its unit and reports `PARTIAL`.

[Context economics](/explanation/context-economics) has the numbers behind these limits.
