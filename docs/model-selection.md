# How each agent's model is chosen

One file holds every model choice: `~/.claude/pstack-models.md`, the sheet. The operator edits it. Nothing in this repo names a model.

## Two layers

| Agent | Who sets its model | How |
|---|---|---|
| A pstack subagent (`swarm`, `arena`, `how`, `why`, `interrogate`, …) | pstack, per call | The skill reads its own role line in the sheet, or its default when the sheet has none. |
| An `hc` worker (owner, implementer, fixer, reviewer, verifier) | The template | Its `command:` runs `role-args` (`skills/herdr/assets/role-args.sh`, installed as `~/.config/herdr-core/role-args`) with the role's line. It reads the sheet and prints `--model <m> [--effort <e>]` for `claude`. The lead moves one worker up with `hc run <template> --label 'model=<m> [@<e>]'`. |

A `claude` with no `--model` runs on the `"model"` in `settings.json`, which is not a role choice.

## Roles and lines

| Role | Line in the sheet |
|---|---|
| `owner`, `implementer` | `feature` |
| `fixer` | `bug-fix` |
| `reviewer` | `judgment and prose` |
| `verifier` | `verifier`, else `judgment and prose` |

A lead (a session labelled `lead=1`; the watcher labels each top-level session so) is held to the `lead` line exactly. Sitrep Live warns ("lead off plan") when a lead runs another model family, stronger without a move-up reason or weaker at all, or, when the line names an effort and the session reports one, another effort. Nothing starts a lead on its line, so switch it with `/model` and `/effort`. A worker is flagged only when it runs a stronger model than its line.

A tier 2 verifier runs as `verifier`: the lead starts the reviewer template with `--label role=verifier`, and `role-args` tries that line first. `reviewer` stays for adversarial review.

A value is a model with an optional effort, as in `<model> @<effort>`. Without an effort, `default effort:` applies; `session` adds none. With no sheet, no such line or an unreadable value, `role-args` prints nothing and says so on stderr, so `claude` runs on the `"model"` in `settings.json`. `app/server/src/fleet/analysis/runner.ts` reads the same line format.

## The move-up rule

A worker or a subagent runs on its role's model. It moves up only in one of two cases:

- (a) The feature needs more than the role line: a subtle algorithm, a cross-cutting design or a hard review.
- (b) Two fix rounds on the role's model failed the same check.

Say in your reply which one you moved up and why, as `feature: <reason>` or `fix-rounds: <n> failed on <check>`. The rule itself is in `rules/working-rules.md`.

## What enforces each part

| Part | What holds it |
|---|---|
| The herdr skill, templates and `role-args` name no model | `scripts/check.sh`, step `no model names` |
| A worker's model comes from the sheet | `role-args` and `scripts/tests/role-args.test.sh` |
| A move-up has a reason | Prose only |

Until 10 November 2026 a launcher held the last two: it read the role's line, refused a move-up with no reason and wrote each launch to a log. The launcher is in `archive/herdr/scripts/`, and `archive/herdr/model-selection.html` draws that flow.
