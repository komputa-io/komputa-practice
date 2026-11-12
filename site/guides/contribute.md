---
title: Contribute to the practice
description: Change a rule, add a hook or a check, add a template question, or change these docs, with the checks each change needs.
sidebar:
  order: 8
---

This guide is for a maintainer who changes the practice itself. Every change goes through a pull request, and `scripts/check.sh` runs on each one in CI.

## Before you start

- A clone of the practice with its git hooks on: `git config core.hooksPath .githooks`.
- `uv`, `jq`, and Node 22.19 or later for the docs.
- The scrub denylist. See [Give a client a copy](/guides/deploy#give-a-client-a-copy).

Run every check before you open a pull request:

```sh
scripts/check.sh
```

It finds the scripts and the tests from git, so a new one needs no edit to the check.

## Change a rule

- A **working rule** lives in `rules/working-rules.md`. Before you add one, try each layer above prose: a check, a hook, a test. Say in the pull request which layer you chose and why no higher layer can hold it. When a check replaces a rule, remove the rule in the same change.
- A **house rule** lives in a house skill, `skills/house-*/SKILL.md`. `skills/CONVENTIONS.md` says how each one is written: complete on its own, worded for every caller, with no process steps. `scripts/check-skill-refs.sh` checks that each skill a skill names is installed.

## Add a hook

1. Write `hooks/block-<name>.sh`. Its header comment, right after the shebang, says what it refuses and why. The [Hooks](/reference/hooks) page is built from that header.
2. Write `hooks/block-<name>.test.sh` with hostile input: the commands that must be refused, and the ones that must pass.
3. Add its entry, with `"onFailure": "block"`, to `hooks/gates.json`.
4. Copy it to `~/.claude/hooks/`, register it, and run `hooks/check-live.sh`.

## Add a template question or a template check

The template is `copier.yml` and `template/`. Its tests are in `standards/`:

```sh
cd standards && uv run --locked pytest -n auto
```

A new check comes with a test that fails on the mistake and passes on the fix. The [Template questions](/reference/template-questions) page is built from `copier.yml`, so a new question's `help:` is its documentation.

## Change these docs

- A page lives in `site/`. A few repo files are imported instead: `scripts/docs-prepare.mjs` lists them. The Hooks, Skills and Template questions pages are generated: change their source, never the page.
- Each page is one kind: a tutorial, a guide, an explanation or a reference. It has a `title` and a one-sentence `description`, and ends with "Next steps".
- A diagram is an HTML file in `docs/`. Render it to a light and a dark PNG, look at both, and add each new PNG to `.scrub-binary-ok`:

  ```sh
  python3 scripts/docs-figures.py docs/<name>.html
  ```

  A page shows the pair with `<img class="figure-light" …>` and `<img class="figure-dark" …>`.
- Build and check the site:

  ```sh
  npm ci --ignore-scripts
  npm run docs:build && npm run docs:check && npm run docs:smoke
  npm run docs:dev     # a live preview on http://localhost:4321
  ```

  `docs:check` fails on a broken internal link. `docs:smoke` starts the built server and checks `llms.txt`, a Markdown copy, the MCP search, each tab's index page and every image.

- `package.json` pins `@astrojs/react` to 7.0.1 with an `overrides` entry, because a plain install of Blume 2.2.6 did not finish in 100 seconds without it (ADR 0040 in herdr-projects). Remove the entry when a Blume release drops the need, and check that `npm ci` still finishes fast.
- `DOCS_TARGET=cloudflare npm run docs:build` builds the Cloudflare Worker that `docs-deploy.yml` ships. Every other build is the Node server.

## Next steps

- [The quality funnel](/explanation/quality-funnel): where each kind of check belongs.
- [Turn a review finding into a rule](/guides/review-finding-to-rule): the usual reason for a change.
