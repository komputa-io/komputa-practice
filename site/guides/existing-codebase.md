---
title: Bring the practice to an existing codebase
description: Add the project template to a repo that already exists, review what it adds, and get its gate green.
sidebar:
  order: 3
---

Use this guide to start using the practice in a repo that you already have. The project template adds the gate, the git hooks, the lint and build config, and a seeded `CLAUDE.md`. It keeps the files that you already own.

## Before you start

- The practice is installed. See the [Quickstart](/start/quickstart).
- You have `uv` and a clean working tree on a new branch.
- You have an environment file: the answers that all your repos share. Copy `instances/example.yml` from the practice repo to a place outside any repo, and fill in the secret command and the forge (`onedev` or `github`).

## Steps

1. **Run the template in the repo.**

   ```sh
   uvx --exclude-newer "7 days" copier copy --data-file <environment.yml> https://github.com/komputa-io/komputa-practice.git .
   ```

   Copier asks about the project: its kind, its languages, and how many tenants and users it has now and later. The four tenant and user questions have no default. Each answer is a decision that the architecture rules read.

2. **Review what it added.** The template adds its files as new, untracked files. A file that it seeds once, such as `README.md`, `CLAUDE.md` or `pyproject.toml`, is left alone when you already have one. Read the diff before you commit:

   ```sh
   git status --short
   ```

3. **Run the full gate.**

   ```sh
   scripts/gate.sh --full
   ```

   On a repo that has its own checks, the first run usually fails, and each failure says what to do. For example, on a Python repo with an old `check.sh` and no tests:

   ```text
   gate: python: pytest collected no tests
   gate: check.sh is a second gate script; fold its checks into scripts/gate.local.sh and remove it
   ```

4. **Fold your old checks into the gate.** `scripts/gate.sh` is the only gate. Move each check of an old gate script into `scripts/gate.local.sh`, which the gate runs with `full` or `fast`. Then remove the old script, and the CI steps that call it. `scripts/gate.md` in your repo has the rules and an example.

5. **Record the large files.** The fast gate refuses a staged file over about 5,000 tokens. A file that is already over the cap goes in a baseline, and may shrink but never grow:

   ```sh
   scripts/gate.sh --size-baseline
   ```

6. **Check the CI file.** The template seeds one for your forge: `.onedev-buildspec.yml` on OneDev, `.github/workflows/gate.yml` on GitHub. Each runs the full gate on every pull request into `main` and every push to `main`, split into one job per language when one image cannot hold every toolchain. If the repo already had a file at that path, the template left it alone: make it run `scripts/gate.sh --full`.

7. **Open a pull request** with the template's files, the folded checks and the CI file. Merge it when the gate is green on its head commit.

## Check it worked

- `scripts/gate.sh --full` ends with `gate: every check passed`.
- `.copier-answers.yml` is committed. It records the template version and your answers.

## Keep it current

When the template has a new release, update the repo from inside it:

```sh
uvx --exclude-newer "7 days" copier update --data-file <environment.yml>
```

`copier update` merges the template's changes into the files that it keeps in step, and leaves the seeded files alone.

## Next steps

- [Build a change](/guides/build-a-change): your first pull request with the practice.
- [How it fits](/explanation/how-it-fits): what belongs in the practice, in a project repo and in your environment.
