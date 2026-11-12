---
title: Introduction
description: Why Komputa Practice exists, what makes it different, and how its parts fit.
---

Komputa Practice is how Komputa builds software with coding agents. This page is for an engineer who wants to try it, and for a lead who decides whether to adopt it. To install it straight away, go to the [Quickstart](/start/quickstart).

## Why it exists

A coding agent writes code faster than a person can review it. When the person's review is the only check, it fills with mistakes that a cheaper check could have caught, and it becomes the slowest step.

The practice answers with one rule: catch each mistake at the highest layer that can hold it, and keep the person's review for what only a person can decide.

<img class="figure-light" src="/figures/quality-funnel.png" alt="A funnel of five layers that catch mistakes: codebase, static analysis, verification, prose and human review, with an arrow that moves each lesson up.">
<img class="figure-dark" src="/figures/quality-funnel-dark.png" alt="A funnel of five layers that catch mistakes: codebase, static analysis, verification, prose and human review, with an arrow that moves each lesson up.">

The practice changes on evidence. Until 10 November 2026 it ran unattended leads and workers. On one program, 33 of 42 fix pull requests repaired tests and tools, not the product. So the default is now one session that builds and merges one pull request at a time. [Framework evidence](/explanation/framework-evidence) gives the numbers, and says what they do not prove yet.

## What makes it different

- **One session, one pull request at a time.** The session plans, builds and merges. It sizes the process to the risk of each change, from a docs fix to a security change.
- **An agent that did not write the change verifies it.** For each change that a user would see, a verifier subagent runs the acceptance checks on the real code.
- **Hooks refuse what must never run.** A forced push, a secret written to a file, a delete that cannot be undone: a hook refuses each one before it runs. An agent can skip a rule; it cannot skip a hook.
- **Each rule names its evidence and its cost.** A rule that does not earn its cost goes to the archive.
- **One template keeps every repo current.** The project template starts a repo with the house standards, and `copier update` brings later changes to it.
- **The house rules work with any agent, or none.** They are plain Agent Skills.

## How it works

<img class="figure-light" src="/figures/how-it-fits.png" alt="How the pieces fit: the practice repo's rules, hooks and skills link into your agent setup, which Claude Code loads together with pstack's roles. Claude Code sends pull requests to your repo, which the project template started.">
<img class="figure-dark" src="/figures/how-it-fits-dark.png" alt="How the pieces fit: the practice repo's rules, hooks and skills link into your agent setup, which Claude Code loads together with pstack's roles. Claude Code sends pull requests to your repo, which the project template started.">

- **Rules, hooks and skills** live in the practice repo. You link the skills and import the rules into your agent setup (`~/.claude/`), and copy the hooks there.
- **pstack** gives the session its playbooks and the model for each role.
- **Claude Code**, in one session, loads all of it. It plans the work, builds each pull request, asks a verifier subagent to check it, and merges.
- **The project template** starts your repo with its gate, its CI and a seeded `CLAUDE.md`.

[How it fits](/explanation/how-it-fits) says who owns each part and how a rule changes. [The life of a program](/explanation/life-of-a-program) follows one program from the plan to the merge.

## Next steps

- [Quickstart](/start/quickstart): install the practice and make your first change.
- [Framework evidence](/explanation/framework-evidence): what the practice caught, what it cost, and what is not proved yet.
- [The quality funnel](/explanation/quality-funnel): each layer, and the rule to move a lesson up.
- [FAQ](/start/faq): short answers to the first questions.
