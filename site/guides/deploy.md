---
title: Set up the practice for daily use
description: Choose links or copies, keep a machine in step after a pull, set up a team, give a client a copy, and remove the practice.
sidebar:
  order: 7
---

The [Quickstart](/start/quickstart) sets up one machine with links. This guide covers the choices after that: copies instead of links, keeping in step, a team, a client's copy, and removal.

## Links or copies

| | Links (the Quickstart) | Copies |
|---|---|---|
| Skills | `ln -s` into `~/.claude/skills/`, or skillshare | `cp -r` into `~/.claude/skills/` |
| Rules | An `@` import line in `~/.claude/CLAUDE.md` | The text pasted into your instructions file |
| Hooks | Copies in both cases | Copies |
| After a `git pull` | Skills and rules change at once | Copy each again |
| Use when | The machine has the clone | A machine without the clone, or a tool that cannot read `@` imports, such as Codex CLI |

To link the skills with [skillshare](https://github.com/runkids/skillshare) instead of `ln -s`, so that every tool it serves reads the clone:

```sh
for s in ~/Code/komputa-practice/skills/*/; do
  skillshare link -g "$s" --name "$(basename "$s")" --enable
done
skillshare sync -g
```

## Keep a machine in step

After each `git pull` of the practice:

1. When `hooks/` changed, copy the hooks again (the copy step in the [Quickstart](/start/quickstart#install-the-practice)), then check them:

   ```sh
   ~/Code/komputa-practice/hooks/check-live.sh
   ```

   A line that starts with `differs:` names a hook to copy again, after you read its change.

2. With copies, also copy the skills again, and paste the rules again when `rules/` changed.

## Set up a team

- Clone the practice to the same path on each machine, so the import line is the same everywhere.
- Keep one environment file for each organisation, outside any repo. Each repo takes its shared answers from it.
- `.copier-answers.yml` in each repo records the template version (`_commit`). `copier update` moves a repo to the newest release.

## Give a client a copy

The practice repo may go to a client, so every commit and push runs the scrub check. It refuses home paths, private IP addresses, email addresses, secret-tool calls, internal forge URLs, API-key shapes, host names, and each line of a denylist that lives outside the repo.

1. Switch on the repo's git hooks:

   ```sh
   git -C ~/Code/komputa-practice config core.hooksPath .githooks
   ```

2. Create the denylist at `~/.config/komputa/public-denylist.txt`, one private item on each line, or set `SCRUB_DENYLIST` to another path.

3. Run the check before you hand over a copy:

   ```sh
   ~/Code/komputa-practice/scripts/scrub-check.sh
   ```

   It prints the file, the line and the kind of each item, never the item. Replace each one with a placeholder such as `<home>` or `<secret-tool>`. A binary file fails until a person looks at it and adds its path to `.scrub-binary-ok`. A file that the check cannot read is not clean: the check exits 2 and names it. `--range <base>..<head>` reads every commit in a range, as CI does for each pull request.

   CI reads the denylist from the `SCRUB_DENYLIST` repository secret (one item per line). When the secret is not set, the job warns that it checked the patterns only.

## Remove the practice

1. Remove the skill links or copies from `~/.claude/skills/`.
2. Remove the import line from `~/.claude/CLAUDE.md`.
3. Remove the hook entries from the `PreToolUse` list in `~/.claude/settings.json`, then the hook files from `~/.claude/hooks/`.
4. When the watcher is installed: `watcher/watcherctl uninstall --apply`.

## Next steps

- [Configuration](/guides/configure): every setting and the file that holds it.
- [How it fits](/explanation/how-it-fits): what belongs in the practice, a project and your environment.
