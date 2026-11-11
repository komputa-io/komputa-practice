# How each agent's model is chosen

One file holds every model choice: `~/.claude/pstack-models.md`, the sheet. The operator edits it. Nothing in this repo names a model.

## Two layers

| Agent | Who sets its model | How |
|---|---|---|
| A pstack subagent (`swarm`, `arena`, `how`, `why`, `interrogate`, …) | pstack, per call | The skill reads its own role line in the sheet, or its default when the sheet has none. |
| An `hc` worker (owner, implementer, fixer, reviewer, verifier) | The one who starts it | Read the role's line in the sheet, and start `claude --model <m> [--effort <e>]`. |

A `claude` with no `--model` runs on the `"model"` in `settings.json`, which is not a role choice.

## Roles and lines

| Role | Line in the sheet |
|---|---|
| `owner`, `implementer` | `feature` |
| `fixer` | `bug-fix` |
| `reviewer` | `judgment and prose` |
| `verifier` | `verifier`, else `judgment and prose` |

A tier 2 verifier runs as `verifier`. `reviewer` stays for adversarial review. Both use the reviewer template.

A value is a model with an optional effort, as in `<model> @<effort>`. Without an effort, `default effort:` applies.

## The move-up rule

A worker or a subagent runs on its role's model. It moves up only in one of two cases:

- (a) The feature needs more than the role line: a subtle algorithm, a cross-cutting design or a hard review.
- (b) Two fix rounds on the role's model failed the same check.

Say in your reply which one you moved up and why, as `feature: <reason>` or `fix-rounds: <n> failed on <check>`. The rule itself is in `rules/working-rules.md`.

## What enforces each part

| Part | What holds it |
|---|---|
| The herdr skill and templates name no model | `scripts/check.sh`, step `no model names` |
| A worker's model comes from the sheet | Prose only |
| A move-up has a reason | Prose only |

Until 10 November 2026 a launcher held the last two: it read the role's line, refused a move-up with no reason and wrote each launch to a log. The launcher is in `archive/herdr/scripts/`, and `archive/herdr/model-selection.html` draws that flow.
