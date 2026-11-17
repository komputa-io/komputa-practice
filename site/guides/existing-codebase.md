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

5. **Record the large files.** The fast gate allows a staged source file over about 5,000 tokens (documents never count), and asks for a high-priority refactor issue on the forge. A file that is already over the cap goes in a baseline, so the gate asks again only when it grows. Open one refactor issue for each file the baseline lists:

   ```sh
   scripts/gate.sh --size-baseline
   ```

6. **Check the CI file.** The template seeds one for your forge: `.onedev-buildspec.yml` on OneDev, `.github/workflows/gate.yml` on GitHub. Each runs the full gate on every pull request into `main` and every push to `main`, split into one job per language when one image cannot hold every toolchain. If the repo already had a file at that path, Copier asks before it replaces it. Let it replace the file, then add your own jobs back below the template's: later updates merge the template's changes and keep your jobs.

   Every branch trigger in the file names the `default_branch` answer (`main` unless you set another, for example `master`). Set the answer in your environment file or on the Copier prompt, before the first copy.

   On OneDev, the jobs read job secrets. Set each one once, from your own shell, and never put a value in a file: `<secret command> <item> | odev secret set NAME --branches <default branch>`. `odev secret set` authorizes `main` when `--branches` is left out, so a project whose default branch is `master` or another name must pass it. The file's own comments show the exact line for each job.

   | Job secret | Job that reads it | When it is needed |
   |---|---|---|
   | `ONEDEV_COMMENT_TOKEN` | Duplicate code | Always. Set it with `--branches '**'`, because a pull request's build reads it. Use the token of an account that may only comment on pull requests. A missing secret fails this job, not CI |
   | `ONEDEV_ISSUES_TOKEN` | Deslop nightly, Secret scan nightly | Always. The token of an account that may write issues |
   | `ONEDEV_USER` and `ONEDEV_TOKEN` | Update dependencies | Always. The login and the token of an account that can push a branch and open a pull request. The "Merge dependency update" job uses the same two secrets, and the account must also be allowed to run jobs, because the job starts CI on a pull request whose merge preview moved |
   | `ONEDEV_TOKEN` | CI on main | Only with the `trust_green_ci` answer. A token that can read this project's builds, authorized on the default branch only |
   | `PKG_USER` and `PKG_TOKEN` | CI, CI on main, Update dependencies | Only with a private package index. A read-only account |
   | `NUGET_USER` and `NUGET_TOKEN` | CI, CI on main, Update dependencies | Only with a private NuGet feed. A read-only account |
   | `SECURITY_LLM_KEY` and `SECURITY_LLM_BASE` | Security review | Only with the `security_review` answer. An Anthropic API key, and `https://api.anthropic.com`. No server caps the key: the job's `--budget` is the only limit on a run. Limited to the default branch, as below |

   The CI file also holds a nightly secret scan, at the same time as the Deslop nightly. TruffleHog reads the whole history of the default branch and keeps only secrets that still work. It tests each one by calling the provider that issued it, so the candidate leaves your CI runner for that provider. Each live secret becomes one high-priority issue that names the file, line and commit and never holds the value: on GitHub, create the label `priority: high` first; on OneDev, the Priority field needs the value `Major`. The tool's image is pinned by digest, and the weekly dependency job moves the pin. A OneDev repo made before this job existed must copy the "Secret scan nightly" job from the template: the full gate names it as missing.

   CI itself needs no secret unless you use a private index or feed. On GitHub the workflows use repository secrets of the same names where they need any.

   On GitHub, the weekly refresh also needs the repository secret `DEPS_PR_TOKEN`: a fine-grained personal access token with Contents, Pull requests and Workflows read and write on that repo. Only the job that opens the pull request reads it, and the pull request's own gate then runs. Set it with `scripts/set-deps-pr-token.sh --apply owner/repo`. Turn on the repository setting "Allow auto-merge". The setting "Allow GitHub Actions to create and approve pull requests" is not needed.

   The CI file runs three security scans. The `house-delivery` [skill](/reference/skills) gives the rules for each one.

   | Scan | When it runs | What it finds |
   |---|---|---|
   | Trivy, in `scripts/gate.sh` | Each pull request | A known vulnerability in a dependency, from the Python, TypeScript and .NET lock files. Rust keeps `cargo deny` |
   | TruffleHog | Each night | A verified secret anywhere in the git history |
   | The `Security review` job: Strix and the Cloudflare security-audit skill | By hand and once a month, on `main` only, for a service or an app | Flaws that an agent finds when it reads the code. `scripts/security-issues.sh` files each finding as one issue |

   The `Security review` job needs its own scan host, because Strix needs the Docker socket and the job holds an LLM key. Give the host a GitHub runner with the labels `self-hosted, security` that serves private repos only, or a OneDev job executor named `security`. Limit the job's secrets to the default branch: on OneDev, `odev secret set ... --branches main`; on GitHub, put them in an environment named `security-review` that only the default branch can use, not in repository secrets. Run the job before a milestone closes and before a deploy.

7. **Open a pull request** with the template's files, the folded checks and the CI file. Merge it when the gate is green on its head commit.

## Check it worked

- `scripts/gate.sh --full` ends with `gate: every check passed`.
- `.copier-answers.yml` is committed. It records the template version and your answers.

## Keep it current

When the template has a new release, update the repo from inside it:

```sh
uvx --exclude-newer "7 days" copier update --data-file <environment.yml>
```

`copier update` merges the template's changes into the files that it keeps in step, the CI file included, and leaves the seeded files alone.

## Next steps

- [Build a change](/guides/build-a-change): your first pull request with the practice.
- [How it fits](/explanation/how-it-fits): what belongs in the practice, in a project repo and in your environment.
