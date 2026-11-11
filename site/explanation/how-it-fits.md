---
title: How it fits
description: The three places the practice lives, how a project connects to it, and how a rule changes.
---

The practice keeps three kinds of thing apart, because each has a different
owner and a different audience.

| Part | What it holds | Who may have it |
|---|---|---|
| **The practice** (this repo) | The house rules (`skills/house-*`), the skill that feeds review findings back into them (`skills/standards-feedback`), the guard hooks (`hooks/`), the herdr skill, and these docs | Anyone you share the practice with |
| **A project repo** | Its code, and in its `CLAUDE.md` only what an agent cannot find in the code: the project profile, the forge, the project map | That project's team |
| **Your environment** | Your machines, your own tool skills, the forge address, the package registry, the secret tool | You alone |

Nothing in the practice names your environment. Where a hook or a rule needs
a fact about it, it reads a setting (for example `HOOK_SECRET_TOOL` for the
secret tool) or the project's `CLAUDE.md` names it (for example the forge).

## How the rules reach an agent

The house rules are Agent Skills: a folder with a `SKILL.md`. A skills tool
such as skillshare links each folder into every agent you use, so an agent
loads `house-architecture` and the language's house skill when its task
matches. The rules are written for any agent framework, or none.

The guard hooks run before a tool call. They are plain copies in the agent's
hooks folder (for Claude Code, `~/.claude/hooks/`), registered from
`hooks/gates.json`. `hooks/check-live.sh` reports a copy that drifted from
this repo, and a hook that would not block if it failed to start.

## Who wins when they disagree

1. The project's `CLAUDE.md`, or an ADR in that project, for that project.
2. The house skills, over any other installed skill or workflow.
3. Everything else.

## How a rule changes

A mistake that a house rule should have prevented is a defect in the rules,
not only in the code. After a review, `standards-feedback` sorts each finding:

- **The project only**: fix it, or open an issue, in that repo.
- **A rule is missing, unclear or contradicts another**: change the house skill here.
- **A rule is too deep** (only in a `references/` file, or written for one kind of caller): move it into `SKILL.md`.
- **A rule nothing enforces**: add a check that a tool runs (a build check, a gate step or a lint rule) and name it in the rule.
- **A rule needs a fact the project never declared**: add a question to the project template.

Prefer a check to more words. A merged change reaches every agent at its next
sync, and every project at its next template update.
