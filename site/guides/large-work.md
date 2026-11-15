---
title: Run large work as a program
description: Plan a new app or a large feature as a set of pull requests, and run it in one session over hours or days.
sidebar:
  order: 2
---

Use this guide for work that needs many pull requests: a new app, a large feature or a migration. A program is that set of pull requests, driven by one session.

## Before you start

- You know how to [build one change](/guides/build-a-change).
- The repo has the project template. A new project starts from it: `uvx --exclude-newer "7 days" copier copy --data-file <environment.yml> https://github.com/komputa-io/komputa-practice.git <new-repo>`.

## Steps

1. **Ask for the plan, not the code.** For example:

   ```text
   Plan the CSV import feature as a program. Give each pull request its tier,
   its acceptance checks and its risks, and the size of the whole program.
   Do not start until I say go.
   ```

2. **Read the size before you say go.** The plan states the tier of each pull request, how many there are, and the wall time it expects. When it expects more than two hours, it also states the smallest version that meets the goal, and its time. Cut the scope here, not later.

3. **Say go.** The session then works on its own on reversible work. When it has a question about the work, it applies a sensible default, records it and carries on. It stops for you only for what cannot be undone: a delete, a message to people. It merges and deploys on its own, unless you tell it not to in the session.

4. **Let it merge and deploy one pull request at a time.** It deletes each merged branch. Each pull request goes through [Build a change](/guides/build-a-change). The next one starts from the merged result, so each review is small.

5. **For a project in milestones, set the threat model first.** The architecture doc states the threat model and the severity scale (impact times likelihood). Each milestone gets one review and one fix round. After that, only a high finding reopens it; the rest go to issues for the next planned work.

6. **Hand over before the context fills.** A long session writes a handoff file before its context gets too big. A fresh session starts from the handoff, not from the old conversation. When nobody watches, [the watcher](/explanation/the-watcher) asks for the handoff, starts the fresh session from it, and nudges a session that has gone idle.

## Check it worked

- Each pull request merged with its checks green on its head commit.
- The scorecard reads the merged pull requests from git:

  ```sh
  python3 ~/Code/komputa-practice/scripts/program-scorecard.py --repo . --since <first day>
  ```

  It counts merge commits and squash merges. It prints the practice version the repo was on (from `.copier-answers.yml`), the pull requests merged each day, the median hours from first commit to merge, and the share of fix pull requests. A high fix share means the plan or the checks missed something.

## What can go wrong

- **The plan has too many small pull requests.** The size sets the cost: each pull request costs a review and a CI run. Ask for fewer.
- **A question stops the program overnight.** Say in the go which defaults the session may apply. A conditional permission ("if you need to, you may…") is not scope: the session takes the path that does not need it, or asks.
- **You want to watch the work in a pane.** Run a worker with herdr. See [The life of a program](/explanation/life-of-a-program) and [Model selection](/explanation/model-selection).

## Next steps

- [The watcher](/explanation/the-watcher): keep a long session going while nobody watches it.
- [Context economics](/explanation/context-economics): why the handoff limits are where they are.
