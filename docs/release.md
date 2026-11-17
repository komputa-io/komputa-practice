# Release the template

A template release is a tag `vN.N.N` on `main`. Every project made from the template takes it later with
`copier update`. A fault in a CI job shows only when the job runs on a real project, so a release runs every
scheduled and by-hand job on the canary projects first. The tag follows only a green canary run.

The canaries are in `scripts/canary.list`: one OneDev project that uses npm and uv, one OneDev Python project and one
GitHub project.

## Steps

1. **Pick the candidate.** It is a commit on `origin/main`. Everything for the release is merged.
2. **Move each canary to the candidate.** In each canary, from a fresh clone, on a branch `chore/template-<version>`:
   `uvx --exclude-newer "7 days" copier update --vcs-ref <sha> --trust --defaults`, with the project's own answers.
   Then the by-hand steps for a seeded file the release changes (OneDev's `.onedev-buildspec.yml`; copier does not
   touch it). Open the PR, pass its CI, merge it. Each canary's default branch now records the candidate in
   `.copier-answers.yml`.
3. **Run the canary.** In the template clone, `ODEV_HOST=<OneDev URL> scripts/canary.sh <sha>` is a dry run: it lists
   the jobs. It refuses when a canary records another `_commit`. Then `scripts/canary.sh --apply <sha>` runs each job
   and prints one table. A job named in `scripts/canary.skip` (one that costs money on each run, such as Security
   review) is listed as skipped with its reason and never started. A pass writes `.canary/<sha>.pass`.
4. **Fix and repeat.** For a red job, read its log, fix the template, merge the fix, make a new candidate and go back to
   step 2. A pass record names one commit: a fix needs a new run.
5. **Tag.** `scripts/release.sh <version> <sha>` is a dry run. With `--apply` it makes the annotated tag and pushes it.
   It refuses without the pass record for that `<sha>`, or when `<sha>` is not on `origin/main`.
6. **Roll out** to every project (below).

A bare `git tag` skips the canary check. Use `scripts/release.sh`.

## Rollout

The operator says when to roll out and to which projects. One lead starts the workers; each worker owns a few projects
and the work is tier 1 for each project. The per-release items (what changed, which files, which by-hand lines) go in
the release's own brief. These rules hold for every release.

For each project, in the list's order:

1. A fresh clone in the worker's own folder, never the operator's checkout. Make the branch
   `chore/template-<version>` from the default branch. Every branch is `<kind>/<name>`.
2. Read the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`). When it is not `main`, pass
   `--data default_branch=<it>` to copier.
3. `uvx --exclude-newer "7 days" copier update --vcs-ref <version> --trust --defaults`, with the answers the project
   records in `.copier-answers.yml`. Never invent an answer. When one is missing, skip the project and say why. Keep the
   project's own code and the template's gate when a conflict arises.
4. **OneDev only, by hand.** Render a fresh copy of the release with the project's answers into a temp folder and copy
   the changed build-spec lines exactly as rendered (a schedule line keeps the project's slot). Change no other job. Run
   `odev buildspec check` before the commit.
5. `CI=1 scripts/gate.sh --full`. The drift check names each seeded build-spec line the project lacks: add it as the
   fresh render has it.
6. When the gate fails only on Trivy findings in lock files, do not upgrade packages in this PR. File one
   high-priority issue (OneDev `Priority=Major`, GitHub label `priority: high`) with a table of package, id, installed
   version and fixed versions; add each finding to `.trivyignore.yaml` with a statement that names the issue and an
   expiry date; run the gate again.
7. When the gate fails on the project's own code for another reason, fix it only if the fix is small and safe (a format
   or a lint rule). Otherwise skip the project and report it. Never weaken or delete a test, never turn a check off.
8. Commit, push, open the PR. Wait for its CI in the background, in a command wrapped in `timeout`. Start the next
   project while it runs.
9. On green, merge it. On red, read the build log and fix once; when it is still red, leave the PR open and report it.
   A job that fails only because the project lacks a job secret is not the worker's failure: merge when CI itself is
   green and list the project and the secret.
10. Leave the clone in place. The operator removes it.

Rules for the whole rollout:

- Never print a secret. Never open a window on the operator's screen. A forced push is only a lease with the literal
  SHA on the worker's own branch.
- Do not change a forge setting, an executor, branch protection or a secret: report what a project needs.
- Leave an open `chore/deps-weekly` or `chore/update-deps-*` PR. The next weekly run handles it.
- Do not touch a project that is not on the worker's list.
- The report has one line for each project: merged (PR number, head), left open (why) or skipped (why). Then the issues
  filed and the projects that need a secret.
- A worker past 250k tokens of context finishes its current project, reports PARTIAL and stops.
