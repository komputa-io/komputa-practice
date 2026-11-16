---
title: Repo layout
description: What each folder and file of the practice repo holds.
---

Each path in the practice repo, and what it holds.

| Path | Contents |
|------|----------|
| `copier.yml`, `template/` | The project template: a Copier template that starts a repo with the house standards and keeps it current (the gate, the build checks, the PR template, the seeded `CLAUDE.md`). Copier reads `copier.yml` from the repo root. |
| `standards/` | The template's own tests and Python project, and its README. It was the `project-standards` repo; its history is kept. |
| `instances/example.yml` | What an environment file holds: the answers your repos share that this repo must not (the secret command and the forge, `onedev` or `github`). Keep your own copy outside the repo. |
| `skills/house-*/` | The house rules for how code is shaped and run: `house-architecture`, the language skills (`house-dotnet`, `house-python`, `house-typescript`, `house-shell`), `house-otel` and `house-delivery`. Each rule holds with or without an agent framework. |
| `skills/standards-feedback/` | Turns review findings into changes to the house rules, or into a check in the template, so a mistake is fixed where it starts. |
| `skills/herdr/SKILL.md` | The herdr skill: when to use a worker, how to brief, start, show, wait for, replace and clean up one. |
| `skills/herdr/assets/templates/` | `hc` worker templates: `owner`, `implementer`, `fixer` and `reviewer`. |
| `skills/herdr/assets/role-args.sh`, `operator-run.sh`, `merge-on-green.sh`, `stall-watch.sh` | Installed in `~/.config/herdr-core/`: `role-args` picks a worker's model from the model sheet; `operator-run '<command>'` opens a pane under the agent's own that shows a command, waits for Enter and runs it; `merge-on-green <pr> <sha>` queues the merge, waits for the checks and names a billing refusal (`--no-merge <pr> <sha> <msg file>` only waits, then sends the parent the owner's code-ready message); `stall-watch` is a lead's background command that exits naming a worker stuck on one status for over 5 minutes. |
| `archive/herdr/` | The scripts, systemd units and tests that ran unattended leads and workers, archived on 10 November 2026. No check covers them. `archive/README.md` has the detail. |
| `skills/herdr/evals/trigger.json` | Queries that must, and must not, trigger the skill. |
| `rules/working-rules.md` | Rules to copy into your global `~/.claude/CLAUDE.md`. |
| `rules/leadonly-rules.md` | Rules for a lead that starts workers. Not loaded by default. |
| `docs/model-selection.md` | How each agent's model is chosen: the role lines and the move-up rule. |
| `docs/quality-funnel.png` | The quality funnel picture. `docs/quality-funnel.html` is its source. |
| `scripts/program-scorecard.py` | Reads the merged pull requests of a repo from git and prints a scorecard: pull requests by kind, the lines each added, and the measures of "What success is". |
| `scripts/scheduled-failures.py` | Posts to Mattermost `#alerts` each failed scheduled OneDev job (Update dependencies, Deslop nightly) that it has not reported before. Run it from a timer; it needs `ODEV_HOST`, `ODEV_TOKEN` and the `#alerts` webhook. |
| `docs/context-economics.md` | Where the tokens go when agents run as workers: what we measured on a real project, what we learned, and why the budget and wait rules say what they say. |
| `hooks/block-secret-write.sh` | A Claude Code `PreToolUse` hook for Write and Edit (and Codex `apply_patch`). It refuses content that matches a secret pattern, and names the machine's secret tool from `HOOK_SECRET_TOOL`. |
| `hooks/block-credential-read.sh` | A Claude Code `PreToolUse` hook for Read and Bash. It refuses reading a credential file (SSH keys, `.netrc`, `.env`, the Claude credentials); counts and key names pass. |
| `hooks/hooks.test.sh` | Tests for the secret and credential hooks, with hostile payloads. |
| `hooks/gates.json` | The `PreToolUse` entries that register these hooks in `~/.claude/settings.json`. |
| `hooks/check-live.sh` | Compares each hook that `~/.claude/settings.json` registers with its copy here, since the live hooks are plain copies. |
| `hooks/block-dangerous-git.sh` | A Claude Code `PreToolUse` hook for Bash. It refuses destructive git commands, every forced push except a pinned lease, and a remote branch delete that would lose commits. |
| `hooks/block-dangerous-git.test.sh` | Tests for the hook. |
| `hooks/block-destructive-delete.sh` | A Claude Code `PreToolUse` hook for Bash. It refuses deletes that cannot be undone: a forge repo, project or org, a wiki space, and a recursive `rm` of another checkout, a folder directly under home or another session's tmp folder. |
| `hooks/block-destructive-delete.test.sh` | Tests for the delete hook, with its hostile inputs. |
| `hooks/block-operator-screen.sh` | A Claude Code `PreToolUse` hook for Bash and the `claude-in-chrome` tools. In a worker only (an `hc` terminal started from a template or by a parent, as `hc get` on its own address shows), it refuses commands that open the operator's browser, a browser without `--headless`, and every `claude-in-chrome` tool. |
| `hooks/block-operator-screen.test.sh` | Tests for the hook. |
| `hooks/block-foreground-wait.sh` | A Claude Code `PreToolUse` hook for Bash. In a worker only, it refuses a call that is not a background command and runs `gh pr checks --watch`, `gh run watch`, `merge-on-green`, `hc wait` or a `sleep` over 10 s. It also refuses an `until` or `while true` loop with no `timeout`, even in the background. |
| `hooks/block-foreground-wait.test.sh` | Tests for the hook. |
| `hooks/block-test-weakening.sh` | A Claude Code `PreToolUse` hook for Write and Edit. It refuses an edit that deletes or weakens a test (`block-test-weakening.py` holds the logic). |
| `hooks/block-test-weakening.test.sh` | Tests for the hook. |
| `watcher/practice-watch` | The one watcher: a pass that puts each top-level agent session in `hc` on the watch unless it is labelled `watch=off`, then, for each session labelled `watch=on`, nudges one gone idle and alerts once on one blocked, out of nudges or ended. `site/explanation/the-watcher.md` explains it. |
| `watcher/watcherctl` | Installs, removes, switches on and off the watcher's systemd user timer (`install`, `uninstall`, `enable`, `disable`, `status`). `install` also turns on linger, so the timer runs after logout. |
| `watcher/practice-watch.test.sh` | Tests for both, against stub `hc` and `systemctl`. |
| `scripts/check.sh` | Runs every check in this repo. CI (`.github/workflows/check.yml`) runs the same command. |
| `scripts/scrub-check.sh` | The check that keeps private items out of this repo. |
| `site/` | The pages of the docs site. `scripts/docs-prepare.mjs` adds the imported repo files and the generated reference pages, and nothing else is published. |
| `blume.config.ts`, `theme.css`, `public/` | The docs site's config, its brand colours and fonts, and its logo and favicon. |
| `wrangler.jsonc`, `.github/workflows/docs-deploy.yml` | The Cloudflare Worker that serves `docs.komputa.io`, and the guarded job that deploys it. |
| `scripts/docs-prepare.mjs`, `scripts/docs-reference.sh`, `scripts/docs-smoke.mjs`, `scripts/docs-figures.py` | The docs build: the content folder and generated pages, the hooks page, the smoke check, and the light and dark diagram PNGs. |

## Next steps

- [How it fits](/explanation/how-it-fits): what belongs in the practice, a project and your environment.
- [Contribute to the practice](/guides/contribute): how to change each part.
