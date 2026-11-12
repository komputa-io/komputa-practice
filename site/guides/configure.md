---
title: Configuration
description: Every setting of the practice, the file that holds it, and how to change the common ones.
sidebar:
  order: 6
---

This page lists each setting of the practice and the file that holds it. The settings live on your machine or in each repo, never in the practice repo itself, so that the practice names nothing of your environment.

## Settings

| Setting | Where | What it controls |
|---|---|---|
| The rules import, and who "the operator" is | `~/.claude/CLAUDE.md` | Which rules every session loads, and whose word counts as the operator's |
| The hook entries, each with `"onFailure": "block"` | `~/.claude/settings.json` | Which guard hooks run, and that a hook that cannot start blocks the call instead of letting it through |
| `HOOK_SECRET_TOOL` | Your shell environment | The secret command that the secret hook names when it refuses a write |
| The model for each role | `~/.claude/pstack-models.md` | Which model each pstack role and each worker runs. See [Model selection](/explanation/model-selection) |
| The environment file | Your copy of `instances/example.yml`, outside any repo | The answers that all your repos share: the secret command and the forge |
| The template answers | `.copier-answers.yml` in each repo | The project's kind, languages, folders, gate budgets and package feeds. See [Template questions](/reference/template-questions) |
| The watcher settings | `~/.config/practice-watch.env` | Idle time, nudges, the alert command and call timeouts. See [The watcher](/explanation/the-watcher#settings) |
| The worker templates | `~/.config/herdr-core/templates/` | The owner, implementer, fixer and reviewer roles of herdr workers |
| The scrub denylist, `SCRUB_DENYLIST` | `~/.config/komputa/public-denylist.txt` by default | The private items that the scrub check refuses in the practice repo |
| `DOCS_SITE_URL` | The docs build's environment | The address of this docs site |

## Change the secret tool that a hook names

Set the variable in the shell that starts Claude Code, for example in `~/.bashrc`:

```sh
export HOOK_SECRET_TOOL=<your secret command>
```

Without it, the hook names `<secret-tool>` in its message.

## Change a model

Run `/pstack:setup-pstack` again, or edit the role's line in `~/.claude/pstack-models.md`. A worker runs on the model that its role line names.

## Change a template answer

Change the answer in `.copier-answers.yml`, then run `copier update` in the repo, so the files that the answer shapes change too:

```sh
uvx --exclude-newer "7 days" copier update --data-file <environment.yml>
```

A gate budget rises only with a reason in `gate_budget_reason`.

## After a pull of the practice

The linked skills and the imported rules change at once. The hooks are copies: copy them again, then check them.

```sh
~/Code/komputa-practice/hooks/check-live.sh
```

## Next steps

- [Template questions](/reference/template-questions): every answer `.copier-answers.yml` can hold.
- [Hooks](/reference/hooks): what each guard hook refuses.
