---
title: Komputa agent practice
description: How Komputa builds software with coding agents, the evidence behind each rule, and the parts that make it work.
---

This practice builds software with coding agents. The default is one Claude Code session that plans, builds and merges one pull request at a time. An agent that did not write the change verifies each pull request that changes behaviour. A [herdr](https://releases.herdr.dev) skill and worker templates serve the times when you want a worker in a pane that you can watch. [pstack](https://github.com/cursor/plugins/tree/main/pstack) sets the models and the playbooks. This repo adds the rules, the hooks and the evidence behind each rule.

This site is built from the files in the repo. It never holds a second copy of a rule.

![A funnel of five layers that catch mistakes: codebase, static analysis, verification, prose and human review, with an arrow that moves each lesson up.](/figures/quality-funnel.png)

## The parts

In one session, the session is the lead and the owner, and the verifier is one subagent. The table is the form with workers.

| Part | What it is | Where to read more |
|---|---|---|
| Lead | Your own Claude Code session. It plans the work, writes one brief for each pull request, starts the owners and reads their reports. | [The life of a program](/explanation/life-of-a-program) |
| Owner | An `hc` worker in its own pane and git worktree. It builds one pull request and drives CI to green. | [The life of a program](/explanation/life-of-a-program) |
| Verifier | A short subagent that tries to break the owner's change on the real artifact. | [The life of a program](/explanation/life-of-a-program) |
| Trail | A `show-me-your-work` TSV file for each owner. It records each decision with its reason. | [The rules](/reference/rules) |
| herdr skill | The rules for how a lead starts, shows, steers and ends workers. | [The life of a program](/explanation/life-of-a-program) |
| Templates | The role files for `owner`, `implementer`, `fixer` and `reviewer`. | [Model selection](/explanation/model-selection) |
| Hooks | Gates that refuse a command that must never run. | [Hooks reference](/reference/scripts) |
| Rules | The working rules, and the check that holds each one. | [The rules](/reference/rules) |

## Read in this order

1. [The quality funnel](/explanation/quality-funnel): the idea that the rest follows from.
2. [Framework evidence](/explanation/framework-evidence): what the practice caught, what it cost, and what is not proved yet.
3. [The life of a program](/explanation/life-of-a-program): one program from plan to retirement.
4. [Model selection](/explanation/model-selection) and [Context economics](/explanation/context-economics): why the sizes and models are what they are.
5. [The rules](/reference/rules) and the [Hooks reference](/reference/scripts): look things up.
