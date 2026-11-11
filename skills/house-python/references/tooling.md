# Tooling, dependencies and the gate

```toml
[tool.ruff]
line-length = 100
lint.select = ["F", "E9", "B", "W291", "BLE001", "RUF100", "RUF006", "G", "DTZ", "PLR0915", "S113", "TID251"]  # + "ASYNC" where async

[tool.pyright]
pythonVersion = "3.N"  # the requires-python floor
reportMatchNotExhaustive = "error"
reportUnnecessaryTypeIgnoreComment = "error"

[tool.uv]
exclude-newer = "7 days"
```

## Project

- **A new repo starts on the oldest Python still in bugfix support**, set as both
  `requires-python` and pyright's `pythonVersion`. Without `pythonVersion`,
  pyright checks against whatever interpreter it finds.
- **Manage the project with uv, build with Hatchling on a `src/` layout, and
  commit `uv.lock`.**
- **Dev tools go in the `dev` dependency group** (`[dependency-groups]`), never
  an extra. An extra is published metadata; a group is not.
- **The repo's own ruff selection wins** over a skill that says ruff `ALL`. The
  `*-core` family keeps its broader selection.

## Versions and the cooldown

- **Each dependency has a floor and the next major as its ceiling**
  (`>=X.Y,<X+1`), and below 1.0 the next minor, because 0.x packages break in
  minors. `uv tool install` ignores `uv.lock`, so the ceiling is all an installed
  tool has.
- **Hold new releases back with `exclude-newer = "7 days"` in the project's
  `[tool.uv]`.** `uv.lock` records the span, not a date, so the cutoff rolls. Set
  in a user `uv.toml` instead, it lands in the lock and fails `--locked` where
  it is not set. Let a security fix through with
  `exclude-newer-package = { <name> = false }`.
- **Tools are dev-group dependencies with ranges** (ruff, `pyright[nodejs]`), held
  exact by `uv.lock`. In an MCP config or a skill, run a tool as
  `uvx --exclude-newer "7 days" <tool>`: the newest version that is at least a
  week old. Never `@latest`, which skips the cooldown, and never a hand pin.
- **A weekly job runs `uv lock --upgrade` and opens a PR.** ruff adds rules and
  formatter changes in minors, so a refresh can fail the gate. That PR is where
  you see it and fix it. The job never crosses a major; it opens an issue.

## The gate

- **Run everything with `--locked`.** The gate is `uv run --locked` over
  `ruff check`, `ruff format --check`, `pyright --warnings` (standard mode) and
  `pytest`. An image runs `uv sync --locked --no-dev`. A stale lock then fails
  instead of re-locking.
- **A suppression gives its reason**: `# noqa: RULE - why` or
  `# pyright: ignore[rule] - why`. `RUF100` and
  `reportUnnecessaryTypeIgnoreComment` fail one that no longer suppresses
  anything.
- **Delete `[tool.mypy]`.** Config for a checker that never runs claims a check
  that does not exist.
