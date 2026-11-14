---
title: FAQ
description: Short answers to the questions people ask first, each with a link to the page that holds the detail.
sidebar:
  order: 3
---

## Do I need herdr?

No. herdr is for a worker in a pane that you can watch. One Claude Code session needs none of it. See [The life of a program](/explanation/life-of-a-program).

## Does it work with another agent, such as Codex CLI?

Partly. The house skills are plain Agent Skills, so any agent that reads skills can use them. The secret hook also reads Codex's `apply_patch`. A tool that cannot read `@` imports needs the rules pasted into its own instructions. See [Set up the practice for daily use](/guides/deploy#links-or-copies).

## When is there no verifier?

For a tier 1 change: a fix, docs or a refactor, with nothing a user sees changing. You read the diff and the run instead. See [Build a change](/guides/build-a-change).

## A hook blocked something I needed. What do I do?

Read the `BLOCKED:` line: it says what the hook allows instead. A hook refuses only what must never run or cannot be undone. If the hook is wrong, change it in a pull request with a test; do not switch it off. See [Hooks](/reference/hooks).

## Can I use it on a codebase without tests?

Yes. The gate fails at first, and says so. Add tests that follow risk: the domain rules and the happy path of each feature first. See [Bring the practice to an existing codebase](/guides/existing-codebase).

## How do I update my setup after a `git pull`?

Linked skills and imported rules update at once. Copy the hooks again and run `hooks/check-live.sh`. See [Configuration](/guides/configure#after-a-pull-of-the-practice).

## Which languages does it support?

The house skills cover C# and .NET, Python, TypeScript and shell scripts, plus architecture, services and delivery in any language. The project template also sets up Rust. A language gets a house skill when an active repo uses it.

## Next steps

- [Quickstart](/start/quickstart): install the practice.
- [Guides](/guides): the tasks you do with it.
