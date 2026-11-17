# Change

Two principles underlie this file. Remove what is not needed before you add
anything. Replace an API by moving every caller to the new one, then deleting
the old one.

## Naming

- **Domain concepts use glossary terms** from `CONTEXT.md`, strictly. A gate
  greps for its `_Avoid_` terms.
- **Slices are named per use case**: `Features/CompleteWorkout/`, not
  `Features/Workouts/`.
- **Test names describe behaviour**: `Completing_a_workout_records_volume`,
  `test_a_cleared_scene_keeps_no_copy`, `it("records volume")`. Not
  `Method_State_Result`.
- **No abbreviations** beyond well-known ones and glossary terms.
- **Casing and prefixes are the linters' job** (`.editorconfig` and analysers,
  ruff `N`, ESLint naming). Do not restate them in prose.

## Refactoring scope

- **The diff stays on task.** "Leave it better" applies only inside code the
  change already touches.
- **Clean-up outside the task becomes an issue.** Do not fold it in.
- **A bug fix covers every place with the same fault.** The same fault
  elsewhere is the same bug, not clean-up.
- **Look-alike code that changes for different reasons stays apart.** Two
  copies are cheaper than a wrong shared shape. A review that flags them as
  duplication is wrong here.
- **A deepening pass** (merge shallow modules into deeper ones) is triggered by
  friction: a hard feature, repeat bugs, or an agent that could not find
  things. Not by a calendar.
- **Never refactor code that is being retired.**

## Breaking changes

- **Aim at the end state.** A planned rewrite or migration builds the target
  shape, not a chain of stable in-between states. Planned breakage between its
  steps is fine on the branch when it is scoped and can be undone. The full
  checks pass at the end.
- **Inside the repo, move every caller and delete the old way in one change.**
  No shim, adapter or flag that only exists during the move. Update the tests to
  the new contract, and delete tests that only held the old internals.
- **A contract with outside users goes expand, migrate, contract**: add the new
  way, move every caller, then delete the old way. Never leave two ways in
  place.
- **A stored or queued message changes format in two releases**, readers first.
  Its type is an explicit discriminator, never a class name.

## Deployment and release

- **Deploying is not releasing.** Work users must not see yet, or a risky change
  to a path they depend on, deploys switched off behind one flag at its entry
  point. Off is the default, and a failed flag read means off. A change that a
  redeploy can undo needs no flag.
- **A release flag is the migrate step of add, migrate, delete.** The PR that adds
  it opens the issue that deletes it, flag and old path together. Only a kill
  switch stays, and its definition says so.
- **A flag change is a deployment.** It gets a review and a health check, and it
  reaches users in stages where the host has stages.
- **A flag cannot undo stored data.** Schema and message changes still go add,
  migrate, delete.
- **An options value is the first flag.** Add a flag service only when you need
  targeting by tenant or percentage, with an ADR.

## Performance

- **Measure first.** A performance claim states the number before and after,
  and how it was measured.
- **Cheap defaults everywhere**: projections and no-tracking queries, no N+1,
  cancellation passed down, streaming, pagination.
- **Pooling, caching, spans and compiled queries only on a measured hot path.**
- **Benchmarks live with the code** (BenchmarkDotNet, pytest-benchmark) and run
  by hand or before a release, not in CI.
- **Budgets come from users** and become alerts (`house-otel`).

## Compatibility and versioning

- **Every project has one semver version** for its whole life: one source of
  truth in the repo, a git tag per release, and visible at run time (a UI footer
  or about page, `--version`, `/version` or a field in `/health`). The gate's
  `scripts/version-check.sh` holds the first part and the tag job holds the
  second; the template's reference page "Versioning" says how.
- **A published package** gets a version bump with every change to its source.
  CI refuses a source change without one.
- **A CLI extends only within a major version**: commands, flags, JSON fields
  and exit codes. A break goes add, deprecate with a warning on stderr, migrate
  the skills and scripts that use it, remove in the next major.
- **Each CLI command's JSON output has a contract test.**
- **Internal code has no compatibility rules.**

## Comments and docs

- **A comment explains only what the code cannot**: a trap, a dated
  measurement, a reversal of an earlier choice, or a link to an upstream
  constraint. Delete a comment that repeats the code.
- **No tracker IDs in code** (`#123`, `PROJ-45`). They rot. A link to an
  upstream issue that explains a constraint is fine.
- **Doc comments only on a public API used outside the repo.**
- **A README is for people**: what the project is, how to run it, how to test
  it.
- **The agent instructions file (`AGENTS.md` or `CLAUDE.md`) holds only what an
  agent cannot discover** from the code, the tests and the tools.
- **The agent instructions file has a project map**: one line per top-level
  folder, saying what belongs there, not what is in it. The change that adds,
  removes or repurposes a top-level folder updates the map. It stays in that
  file, because every session loads it. Past about 15 lines (a monorepo), the
  map moves to `docs/` and the file keeps a one-line pointer to it.
- **Decisions go in ADRs, terms go in `CONTEXT.md`** (see
  [domain.md](domain.md), "The glossary").
- **Keep no `STATUS.md`, `DECISIONS.md` or other status log in a repo.** Open
  work is an issue. A hard-to-reverse decision is an ADR. A pause note stays
  outside the working tree.
- **No doc repeats the code or the environment.** It drifts and misleads.

## Dependencies

The language skills give the mechanics. These rules hold in every language.

Hand-pinned versions go stale: nobody remembers to bump them, and the project
misses fixes until something breaks. So versions stay fresh by themselves, and
the lock file, not a hand pin, makes a build reproducible.

- **Declare a range, not a pin**: a floor, and the next major as the ceiling.
  The lock file records the exact versions that were tested.
- **A weekly job refreshes the lock within those ranges and opens a PR** with
  the forge's CLI. The gate decides whether it merges. Nobody bumps versions
  by hand, except for a security fix.
- **The job never crosses a major version. It opens an issue instead**, because
  a major needs a person to read the changelog.
- **Only versions at least seven days old are taken**, by the job or by hand.
- **A security fix is the one exception, and it does not wait.** When an
  advisory (a CVE or a GHSA) covers a version we use, take the first fixed
  version within the range at once, even when it is under seven days old, in
  its own PR named for the advisory. Where the cooldown is set per package
  (uv's `exclude-newer-package`, npm's `min-release-age-exclude`), add the
  exemption for that package and remove it once the version is seven days old.
- **A build that fails on a known advisory is the signal, not noise.** Never
  silence the audit (`NuGetAudit`, `npm audit`) to get green. Apply the
  exception.
- **No preview version without a reason recorded beside it.**
- **Confirm a new package is the intended one** on its registry: the publisher,
  the repository link and the release history. A look-alike name is a supply
  chain attack.
- **Commit the lock file**, and restore from it in CI.
- **Every tool the gate runs comes through the repo**: a dev dependency in the
  lock file, or a runner with the seven-day cooldown (`uvx --exclude-newer
  "7 days" <tool>`). Never a global install, so the workstation and CI run the
  same checks.
