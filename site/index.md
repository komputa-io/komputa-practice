---
title: Komputa Practice
description: How Komputa builds software with coding agents, the evidence behind each rule, and the parts that make it work.
---

This practice builds software with coding agents. The default is one Claude Code session that plans, builds and merges one pull request at a time. An agent that did not write the change verifies each pull request that changes behaviour. A [herdr](https://releases.herdr.dev) skill and worker templates serve the times when you want a worker in a pane that you can watch. [pstack](https://github.com/cursor/plugins/tree/main/pstack) sets the models and the playbooks. This repo adds the rules, the hooks and the evidence behind each rule.

This site is built from the files in the repo. It never holds a second copy of a rule.

<img class="figure-light" src="/figures/quality-funnel.png" alt="A funnel of five layers that catch mistakes: codebase, static analysis, verification, prose and human review, with an arrow that moves each lesson up.">
<img class="figure-dark" src="/figures/quality-funnel-dark.png" alt="A funnel of five layers that catch mistakes: codebase, static analysis, verification, prose and human review, with an arrow that moves each lesson up.">

## Where to start

| You are | Read |
|---|---|
| New to the practice | [Introduction](/start), then the [Quickstart](/start/quickstart) |
| Deciding whether to adopt it | [Introduction](/start), then [Framework evidence](/explanation/framework-evidence) |
| Changing a rule, a hook or the template | [How it fits](/explanation/how-it-fits), [The rules](/reference/rules) and the [Hooks](/reference/hooks) |
| An agent | [The rules](/reference/rules) and the [Hooks](/reference/hooks), or search these docs through `/mcp` |
