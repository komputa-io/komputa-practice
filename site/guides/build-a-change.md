---
title: Build a change
description: Take a bug fix or a small feature from the prompt to the merge, with the checks that its risk needs.
sidebar:
  order: 1
---

Use this guide for one pull request: a bug fix, a small feature, a refactor or a docs change. For work that needs many pull requests, use [Run large work as a program](/guides/large-work).

## Before you start

- The practice is installed and `~/Code/komputa-practice/hooks/check-live.sh` exits 0. See the [Quickstart](/start/quickstart).
- The repo has the project template's gate, `scripts/gate.sh`. To add it, see [Bring the practice to an existing codebase](/guides/existing-codebase).

## Steps

1. **Ask for the change and its checks.** Say what must be true when it is done. For example:

   ```text
   Fix the rounding of the invoice total: a line of 3 at 33p must total 99p.
   Open a pull request when it is done.
   ```

2. **Read the tier.** The agent puts the change in a tier and says why. The tier sets the process:

   | Tier | When | Checks |
   |---|---|---|
   | 1. Change | A fix, docs, a refactor: nothing a user sees changes | The tests that cover it, one run of the real behaviour, and you read the diff |
   | 2. Feature | A change that a user sees | A short plan with acceptance checks, and a verifier subagent that runs them |
   | 3. High risk | Security, money, private content, data that cannot be restored, a service others depend on | Tier 2, plus one test for each high risk and one adversarial review on another model |

   If the tier looks wrong, say so now. The tier follows the risk, not the size.

3. **Let it build.** The agent writes the tests that the risk needs: the domain rules, the happy path, and one failure case for each high risk. A fix for a defect that a user hit carries one test that fails before the fix and passes after it. It runs the gate while it works:

   ```sh
   scripts/gate.sh          # the sections that the change touches
   scripts/gate.sh --full   # everything, before the pull request
   ```

4. **Read the report.** The agent opens the pull request and reports the commands it ran and what they printed. For tier 2 and up, the report includes what the verifier ran and found.

5. **Decide each duplicate the pull request adds.** In a project made from the template, the Duplicate code check comments on the pull request with each duplicate Deslop finds in the added lines, and fails until each one has a decision. The agent fixes it, or keeps it with one line in `.deslop-decisions`, `<cluster id> keep <reason>`, and pushes. A cluster that a later edit changes gets a new id and needs a new decision.

6. **Merge when every check passed on the last commit.** Check that CI ran on the pull request's head commit, then merge that commit:

   ```sh
   gh pr checks <number>
   gh pr merge <number> --merge --match-head-commit <full head sha>
   ```

## Check it worked

- CI passed on the head commit of the pull request.
- The report names a run of the real behaviour and its output, not only "tests pass".

## What can go wrong

- **A hook refuses a command.** The agent sees a line that starts with `BLOCKED:` and says what the hook allows instead. For example, the only forced push allowed is a lease with the exact SHA, on a branch that is not the default. Do not turn the hook off.
- **The agent wants to delete or skip a test to get green.** The rules forbid it. The fix goes in the code, or in a test that was wrong.
- **The agent finds other work on the way.** It keeps the pull request to what you asked for. A defect a user would hit, or one that costs money, data or trust, gets its own issue; a small finding goes in the repo's standing low-priority issue.
- **The gate fails on its time budget.** The message names the slowest step. A budget rises only with a reason in `gate_budget_reason` in `.copier-answers.yml`.

## Next steps

- [The quality funnel](/explanation/quality-funnel): why each check sits where it does.
- [The rules](/reference/rules): the tier table and the test rules in full.
