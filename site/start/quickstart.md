---
title: Quickstart
description: Install Komputa Practice, then make one small, verified change in the sample repo.
sidebar:
  order: 2
---

This tutorial is for an engineer who uses Claude Code and has not used the practice yet. You install the practice on your machine. Then you make one small change in a sample Python repo, and you see each layer of the [quality funnel](/explanation/quality-funnel) catch what it can. It takes about 30 minutes.

## Before you start

You need these tools:

| Tool | What it is for |
|---|---|
| [Claude Code](https://docs.claude.com/en/docs/claude-code) | The agent that does the work. |
| [pstack for Claude Code](https://github.com/michael-denyer/pstack-claude) | The playbooks and the model for each role. |
| Linux with `bash`, `git` and `jq` | The hooks are Bash scripts and read their input with `jq`. |
| [`uv`](https://docs.astral.sh/uv/) | Runs the Python tools of the sample repo. |
| [`gh`](https://cli.github.com/), signed in | Makes your copy of the sample repo and opens its pull request. |

Both repos are private for now. Ask your team for access to [komputa-io/komputa-practice](https://github.com/komputa-io/komputa-practice) and [komputa-io/komputa-practice-sample](https://github.com/komputa-io/komputa-practice-sample).

You do not need herdr for this tutorial.

## Install the practice

You link the practice to one clone of its repo, so a `git pull` later updates the rules and the skills at once.

1. Install pstack. Follow the README of the [Claude Code port](https://github.com/michael-denyer/pstack-claude). Then run this in Claude Code:

   ```text
   /pstack:setup-pstack
   ```

   It writes `~/.claude/pstack-models.md`, which sets the model for each role.

2. Clone the practice to a fixed path. The next steps name this path.

   ```sh
   git clone https://github.com/komputa-io/komputa-practice.git ~/Code/komputa-practice
   ```

3. Link the skills into Claude Code:

   ```sh
   mkdir -p ~/.claude/skills
   for s in ~/Code/komputa-practice/skills/*/; do
     ln -s "$s" ~/.claude/skills/
   done
   ```

4. Import the working rules into your global `CLAUDE.md`:

   ```sh
   echo '@~/Code/komputa-practice/rules/working-rules.md' >> ~/.claude/CLAUDE.md
   ```

   The rules talk about "the operator". Add one line to `~/.claude/CLAUDE.md` that says the operator is you.

5. Copy the guard hooks and register them. Run this once; a second run adds the entries again.

   ```sh
   mkdir -p ~/.claude/hooks
   cd ~/Code/komputa-practice/hooks
   cp $(jq -r '.PreToolUse[].hooks[].command | sub("^~/.claude/hooks/"; "")' gates.json) \
     block-test-weakening.py ~/.claude/hooks/
   settings=~/.claude/settings.json
   [ -f "$settings" ] || echo '{}' > "$settings"
   jq --slurpfile g gates.json \
     '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + $g[0].PreToolUse)' \
     "$settings" > "$settings.new" && mv "$settings.new" "$settings"
   ```

   The hooks are copies, not links. After a `git pull` that changes `hooks/`, copy them again.

## Check the install

1. Check that each registered hook matches its copy in the repo:

   ```sh
   ~/Code/komputa-practice/hooks/check-live.sh
   ```

   You see one line for each of the seven hooks, and the exit code is 0:

   ```text
   in step: block-credential-read.sh
   in step: block-dangerous-git.sh
   in step: block-destructive-delete.sh
   in step: block-foreground-wait.sh
   in step: block-operator-screen.sh
   in step: block-secret-write.sh
   in step: block-test-weakening.sh
   ```

2. Check that a hook refuses what it must. Send the git hook a forced push:

   ```sh
   jq -nc '{tool_name:"Bash",tool_input:{command:"git push --force origin main"}}' \
     | ~/.claude/hooks/block-dangerous-git.sh; echo "exit $?"
   ```

   The hook prints a line that starts with `BLOCKED:` and gives the one forced push it allows. The exit code is 2.

3. Check that a skill links back to your clone:

   ```sh
   readlink -f ~/.claude/skills/house-python/SKILL.md
   ```

   The path is inside `~/Code/komputa-practice`.

## Make your own copy of the sample repo

The sample repo is a small Python invoice library made from the practice's project template. It has one domain rule: a line's quantity is at least 1, and its price is never negative. CI runs the gate on each pull request.

1. Make your own copy and clone it:

   ```sh
   gh repo create my-practice-sample --private --clone \
     --template komputa-io/komputa-practice-sample
   cd my-practice-sample
   ```

2. Switch on the repo's git hooks. The commit hook runs the fast gate.

   ```sh
   git config core.hooksPath .githooks
   ```

3. Run the full gate once:

   ```sh
   scripts/gate.sh --full
   ```

   It formats, lints, type-checks and runs the tests. The last line is:

   ```text
   gate: every check passed
   ```

## Make your first change

1. Start Claude Code in the repo:

   ```sh
   claude
   ```

2. First, see a hook refuse a command. Give the agent this prompt:

   ```text
   Run git push --force origin main.
   ```

   The git hook refuses the command before it runs, and the agent tells you why. If the push runs, the hooks are not registered: go back to [Check the install](#check-the-install). (You have changed nothing yet, so a push that ran would only send the same commit again.)

3. Now ask for a feature. Give the agent this prompt:

   ```text
   Add a discount to the invoice: a whole-number percentage from 0 to 100 that
   comes off the total. Round the discount to the nearest penny in the
   customer's favour. Open a pull request when it is done.
   ```

4. Watch what the agent does. The working rules make it:

   - Put the work in a tier. A discount changes behaviour that a user sees, so it is a feature (tier 2).
   - Write a short plan: one paragraph with the acceptance checks, and the risks. Money is a risk.
   - Write the tests for the new domain rules: the percentage range and the rounding.
   - Run the gate until it passes.
   - Ask a verifier subagent, which did not write the change, to run the acceptance checks and read the diff.
   - Open the pull request, and report the commands it ran and what they printed.

5. Read the report. The agent merges the pull request when CI passed on its head commit and nothing on it is open, deletes the branch, and deploys. Tell it in the session when it must not merge or deploy.

## What you just saw

Each step was one layer of the quality funnel:

| What happened | Funnel layer |
|---|---|
| `new_line` returns an `InvalidLine` instead of a bad line, so code that skips the check does not type-check. | 1. Codebase |
| The gate (format, lint, types, tests) and the git hook refused mistakes with nobody watching. | 2. Static analysis |
| The verifier ran the acceptance checks on the real code. | 3. Verification |
| The working rules set the tier, the plan and the test budget. | 4. Prose |
| You said go, and could have said stop. | 5. Human review |

## Next steps

- [How it fits](/explanation/how-it-fits): where the rules, the hooks and the template live, and how a rule changes.
- [The quality funnel](/explanation/quality-funnel): why each mistake is caught at the highest layer that can hold it.
- [The rules](/reference/rules): the working rules that the agent followed.
