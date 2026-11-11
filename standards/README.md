# The project template

A Copier template that starts a repo with the house standards, and keeps it up
to date with them. `copier.yml` and `template/` sit at the root of this repo,
because Copier reads `copier.yml` from a repo's root. This folder holds the
template's own tests and its Python project. It was the `project-standards`
repo until 11 November 2026; its history is kept here.

## Use

```bash
# A new repo, or adopting an existing one (review the diff before committing):
uvx --exclude-newer "7 days" copier copy --data-file <environment.yml> <this repo's URL> <repo>
# Later, inside a repo that has .copier-answers.yml:
uvx --exclude-newer "7 days" copier update --data-file <environment.yml>
```

The environment file holds the answers your repos share and the template must
not: see `instances/example.yml`. Template releases are tags (`v1.0.0` and on);
`copier update` moves a repo to the newest tag.

Run the template's tests from this folder: `uv run --locked pytest -n auto`.

Copier runs through `uvx` with the seven-day cooldown, never a global install.

`.onedev-buildspec.yml` is seeded once, so `copier update` does not change it.
A repo whose weekly "Update dependencies" job still has a "Build odev" step must
delete that step by hand and drop `PATH="$PWD/.git/bin:$PATH"` from its export
line. `scripts/update-deps.sh` now opens the PR with curl.

## What it writes

Seeded once, then the repo's own: `CLAUDE.md`, `CONTEXT.md`, `README.md`,
`docs/adr/README.md`, `.gitignore`, `.onedev-buildspec.yml`, `global.json`,
`Directory.Packages.props`, `.config/dotnet-tools.json`, `tsconfig.json`,
`next.config.ts`, `pyproject.toml`, `.secrets.baseline`.

`CLAUDE.md` declares the project profile that `house-architecture` reads
(tenants and users, now and later) from four questions with no default.

Kept in step by `copier update`: everything else. That is the gate
(`scripts/gate.sh`), the pre-commit hook (`.githooks/pre-commit`, which runs
`gate.sh --fast`), the weekly dependency refresh (`scripts/update-deps.sh`),
the PR template (`.onedev/pull-request-template.md`, checked by `odev pr create`),
`.editorconfig`, `.shellcheckrc`, and each language's lint and build config.

The coding rules themselves live in the house skills in agent-skills. This
template only wires a repo to them.

## One gate, and the repo's own checks

`scripts/gate.sh` is the only gate script. CI, the hooks and agents run it. A
repo's own checks (Go vet and tests, `node --test` per package, hook tests) go
in `scripts/gate.local.sh`, which the repo owns and `copier update` never
touches. The gate runs it with one argument, `full` or `fast`. The
template does not seed it: a repo with no extra checks has no such file.
Adoption folds any old gate script into it and removes the old script.

A full run on a clean tree records the tree and its sections in
`.git/gate-passed`. The next full run on the same tree and sections exits at
once, so an agent that runs the gate again before a PR waits for nothing. A
change to the tree, an untracked file or other sections run it again. CI checks
out fresh and always runs it. Delete the file to force a run. A stamp from an
`--only` run covers only its sections.

When `uv.lock` holds `pytest-xdist`, a run of the whole Python suite uses
`pytest -n auto`: one worker per core. A new repo locks it from the start. An
older repo turns it on with `uv add --dev pytest-xdist`, and caps the workers
with `--maxprocesses N` in its `pytest.toml` addopts when its tests need it.
The gate's `-n auto` overrides an `-n` in addopts, so cap with
`--maxprocesses`, not `-n`.

The gate has two tiers. `gate.sh --fast` runs on commit. The full gate runs
before a PR and in CI. No hook runs on push. A partial run on push must map
files to tests, and that mapping was where the defects were (issue #46).

`gate.sh --fast` refuses a staged file over 5,000 tokens (bytes / 4): a large
file costs tokens on every later call of an agent that read it. Lock files,
generated code, test data, the template's own files and binary files do not
count. `.gate-size-baseline` lists the files that were over the cap when the
repo took up the check, one "<tokens> <path>" line each. A listed file may
shrink and never grow, and the gate takes it off the list when it is under the
cap. `scripts/gate.sh --size-baseline` writes the list from the tracked files.

`scripts/gate.sh` with no argument checks only what the diff touches. It maps
each path changed since the merge base (committed, staged, unstaged or
untracked, deleted too) to the sections that read it, and runs those sections
in full. Docs (`*.md`, `docs/`, the ADR folder) run no section. A path with no
safe mapping (for example `.editorconfig` or a template file) runs every
section, and so does a missing merge base or an empty diff; the gate says which
on one line. The `local` section runs beside any section it picks. A non-empty
`CI` variable, `--full` and `--only` skip the mapping. `scripts/gate.sh --full`
is the whole gate: run it before a PR. CI runs it.

Each section writes its duration to `.gate/<mode>.<section>`. The gate puts a
`.gitignore` of its own in `.gate`, so no repo needs a line for it. A section
over its budget fails the gate and names its slowest tests: pytest's
`--durations` list for Python, and the slowest timed steps (the test runs, the
shell linters, `gate.local.sh`) for the other sections. The budgets are
`gate_fast_budget` (5 s) and `gate_full_budget` (none), per section. A project raises one only with a written
`gate_budget_reason` in its answers file. One run sets the result, so a loaded
CI runner can trip a full budget; that is why the full budget is off until a
project sets it.

A full run prints one line: the source lines and the test lines that
the branch adds against its merge base, and their ratio. It never fails on it.
The budget for tests is the operator's, and it follows risk: see "Tests follow
risk" in `komputa-practice` (`rules/working-rules.md`). A test file is one
named like a test, one under a `tests`, `test`, `__tests__` or `*.Tests` folder,
or one under a folder in the `test_folders` answer.

Rust is a language answer beside Python, .NET and TypeScript. Its section runs
`cargo fmt --check`, `cargo clippy -D warnings`, `cargo deny check` and
`cargo test`, all with `--locked`, in `rust_dir`. The fast gate runs rustfmt on
each staged `.rs` file. `rust-toolchain.toml` and the CI image pin the
`rust_version` answer, and `scripts/install-cargo-deny.sh` installs a pinned
cargo-deny by its sha256. Stable cargo has no release-age filter, so the weekly
refresh asks crates.io for the date of each new version and takes only one that
is at least seven days old.

For .NET, a security fix skips that wait. NuGetAudit fails the restore and
names each package with a known advisory; the weekly refresh takes that
package's newest version within its major first, then refreshes the rest with
the wait. `Directory.Build.props` also refuses a project whose name ends in
`.Features` when it uses the Web or Razor SDK or references ASP.NET Core: the
use cases there are called by every host (house-architecture, "Hosts"). A project whose name ends in
`.Domain` may reference no other project and no I/O package (EF Core, Npgsql,
ASP.NET Core, an HTTP client, Aspire): it holds the entities and pure rules.

`scripts/gate.sh --only SECTION` runs one section: a language, `shell` or
`local`. CI uses it to run each language in its own image when there is more
than one toolchain (no image has both the .NET SDK and Node).

## Projects in subfolders

`python_dir`, `dotnet_dir` and `node_dir` name the folder of each language's
project (default `.`). That language's config files go there, and the gate, the
weekly refresh and CI run it there. Root files (`.editorconfig`,
`.gitignore`, the gate, the hook, CI) stay at the repo root.

## Other questions

- `shell_exclude`: folders of vendored or retired scripts (for example
  `.ralph`, `archive`) that shellcheck and shfmt skip.
- `dotnet_test_runner`: `mtp` (TUnit, xUnit v3) sets the Microsoft.Testing.Platform
  runner in `global.json`; `vstest` (xUnit v2, NUnit) leaves it out, because
  that setting breaks them.
- `dotnet_lock_files`: restore from `packages.lock.json` in locked mode. Say no
  when a package comes from a feed only CI can read.
- `nuget_feed`, `nuget_feed_name`, `nuget_feed_packages`: a private NuGet feed
  for the listed package patterns. `nuget.config` reads its login from
  `NUGET_<NAME>_USERNAME` and `_PASSWORD`; CI sets them from the job secrets
  `NUGET_USER` and `NUGET_TOKEN`.
- `npm_allow_scripts`: the npm packages whose install scripts are approved (for
  example `[sharp, protobufjs]`), written to `.npmrc` as `allow-scripts`.

## Private package index

A Python repo can take some packages from a private index, such as the OneDev
registry. Give `private_index` (the index URL) and `private_packages` (a list).
Then:

- `uv.toml` exempts those packages from the seven-day cooldown, because the
  registry records no upload dates.
- A new repo's `pyproject.toml` gets the index (`explicit = true`) and a
  `[tool.uv.sources]` pin for each package. uv allows those only in
  `pyproject.toml`, so an existing repo adds them by hand; `uv.toml` shows how.
- The seeded `.onedev-buildspec.yml` sets `UV_INDEX_<NAME>_USERNAME` and
  `_PASSWORD` in CI and the weekly job from the job secrets `PKG_USER` and
  `PKG_TOKEN`. Use a read-only account for them.

## Test

```bash
uv run pytest -q
```

The tests render every language combination, check each one gets only its own
bundles, run the rendered scripts through shellcheck and shfmt, and time the
pre-commit hook against its five-second budget.
