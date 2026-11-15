# Lead-only rules

These rules are for a lead: an agent session that writes briefs and starts
workers. They add to `rules/working-rules.md`. One session that owns its
own pull requests does not need them. `archive/README.md` says what is
archived and how it returns.

## What holds these rules

| Rule | What holds it |
|---|---|
| The herdr skill, its templates and `role-args` name no model | `scripts/check.sh` refuses a model name there (`docs/model-selection.md`) |
| A worker opens no window on the operator's screen | `hooks/block-operator-screen.sh` (worker sessions only) refuses browser-opening commands and the `claude-in-chrome` tools. It acts only in a worker: an `hc` terminal started from a template or by a parent, as `hc get` on its own address shows |
| A worker never deletes or weakens a test to get green | `hooks/block-test-weakening.sh` (worker sessions only) refuses: `rm`, `git rm`, `unlink`, `shred`, `find -delete` and `mv` away of a test path; `truncate`, a truncating redirection (`>`, `: >`, `cat /dev/null >`, `2>`; `>>` is allowed), `cp`/`mv` onto an existing test, `tee` without `-a`, `sed -i`, `perl -i`, `git checkout -- <test>` and `git restore <test>`; a Write or Edit that empties a test file, and a Write or Edit that adds a skip or xfail or comments out an assert (a Write is compared with the file's current text). Names match in any letter case. Build output, caches, `*.pyc`/`*.log`/`*.txt` files and paths outside the git tree may be removed. `HERDR_TEST_PRUNE=1`, set by whoever starts the pruning worker, lets a delete, a move away and an emptying Write through, never a skip, a truncation, an overwrite or an in-place edit. NOT HELD, because text cannot decide them: `xargs rm`, `rm $VAR`, `eval`, `python -c "os.remove(...)"`, `rm -rf .`, `git clean`, a hard `git reset`, an assert changed to `assert True`, a test rewritten to one trivial test, a skip set in a config file, and a new test file written by a redirection (the reviewer's break-the-behaviour check is the layer for these). NOT ACTIVE UNTIL the operator registers the hook in the global settings, and only in a worker (an `hc` terminal started from a template or by a parent) |

## Rules

- Answer every dialog that a worker you start (`hc run`,
  `herdr-app do tab.new`) shows, for the operator, at once. Do not ask the
  operator. Read the screen first (`hc read`), then choose the option that
  lets the work go on: "Yes" for a permission prompt on reversible work,
  and for a deploy of merged work unless the operator said not to in this
  session. The exception is an action that cannot be undone: a deletion
  outside a worktree or scratch folder, any other write to a live service,
  or a message to people. For those, the lead decides from the evidence and
  records why; the worker waits. The git, delete and secret hooks still
  block what must never run.
- A worker runs on the model that its role line in `pstack-models.md`
  names. You may move a subagent or an `hc`
  worker up from it only in one of two cases:
  - (a) The feature needs more than the role line: a subtle algorithm, a
    cross-cutting design or a hard review.
  - (b) Two fix rounds on the role's model failed the same check.

  Say in your reply which one you moved up and why, as `feature: <reason>` or
  `fix-rounds: <n> failed on <check>`. Do not move up routine edits.

### Never delete or weaken a test to get green

A worker fixes the code or the test. It does not delete a test, skip it, mark it `xfail`, empty its file or
comment out an assert so that a check passes. When a test is wrong, the worker says why in its report and the
lead decides. `hooks/block-test-weakening.sh` refuses these in a worker session.

A prune in a reviewed PR is the one exception. To prune, apply "Tests follow risk" to the tests that exist: a
test that those rules would not write goes. Prune one feature slice in each PR. The lead starts the pruning
worker with `hc run --label test-prune=1` and names it in the brief. The PR text lists
what goes, so that the operator can reverse any.

## Delegated build work

- Every brief has a budget: wall time and context. Size a brief to finish
  under about 200k tokens: about two deliverables. Use three only when each
  one is small.
  Each turn rereads the whole context, so a session's cost grows with its
  context, not with its output. A worker whose context passes 300k tokens
  finishes its current unit, reports PARTIAL with what is left, and stops.
  A fresh worker continues from the report. The lead checks each worker's
  time and context at least once an hour.
- The lead has a budget too. When its own context passes about 250k
  tokens, the lead writes a handoff at the next quiet point and a fresh
  lead continues from it. A fresh lead starts near 30k.
- The lead waits out of its own context. It waits for a worker report or
  a CI result with one background wait that ends only on an event that
  needs it, never with a foreground
  wait that returns on every timeout or status change. Each return is a
  lead turn that rereads the lead's whole context.
