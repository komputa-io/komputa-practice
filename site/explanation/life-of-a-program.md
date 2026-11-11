---
title: The life of a program
description: One program from the plan to the retirement of its lead, and the check at each step.
---

A program is a set of pull requests that one lead drives. The lead plans, briefs, starts owners, verifies and merges. It never writes the code that it verifies.

![The life of a program: plan, brief, start, build and report, verify, merge, finish, hand over, retire. Each step names the rule or check that holds it.](/figures/life-of-a-program.png)

## The steps

| Step | What happens | What holds it |
|---|---|---|
| 1. Plan | The lead puts each pull request in a tier and states the size before the operator's go. | The tier table in the [rules](/reference/rules). |
| 2. Brief | The lead writes one brief to `.audit/<task>.brief.md`. It holds the goal, the worktree, the definition of done, a budget and the report contract. It names the risks that the tests cover. | The "Delegated build work" rules. |
| 3. Start | The lead starts each owner. The role line in `pstack-models.md` sets the model. The lead answers the folder trust question. | The role lines. See [Model selection](/explanation/model-selection). |
| 4. Build and report | The owner builds one pull request in its own worktree. It pushes its branch and drives CI to green. It writes a report file, then sends one short message. | `block-dangerous-git.sh`, `block-operator-screen.sh`, `block-test-weakening.sh`. |
| 5. Verify | A verifier agent runs the acceptance checks on the real artifact and reads the diff. A finding counts only when a run shows it. | The tier 2 and tier 3 rows of the tier table. |
| 6. Merge | The lead merges when every check passed at the head commit. A change to a live service waits for the operator's yes. | The checks at the head commit. |
| 7. Finish | The lead closes the owner's pane. | The report file: the lead closes a pane only after it. |
| 8. Hand over | When the lead's context passes the lead cap, it writes a handoff. A fresh lead starts from it. | The lead's budget in the rules. |
| 9. Retire | The old lead ends only after its workers end. | The lead. |

## A program that runs for hours

The service that started a quiet lead again from its newest handoff is in `archive/herdr/` since 10 November 2026. Nothing runs it.

## The limits that keep it cheap

- One brief holds about two deliverables, so an owner finishes under about 200k tokens.
- A worker whose context passes 300k tokens finishes its unit and reports `PARTIAL`.
- A lead hands over near 250k tokens.

[Context economics](/explanation/context-economics) has the numbers behind these limits.
