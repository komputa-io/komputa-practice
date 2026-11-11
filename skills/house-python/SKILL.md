---
name: house-python
description: "The house rules for Python. Use for any Python task in our repos: writing, changing or reviewing .py code, SQLAlchemy models, FastAPI or FastMCP endpoints, click commands, pytest tests, async or concurrent calls, error handling, or pyproject.toml, uv.lock, ruff and pyright changes such as adding or bumping a dependency. Covers outcome unions with match, frozen dataclasses, Protocol seams with hand fakes, deadlines and task groups, SQLAlchemy 2.0, pytest-socket and anyio, uv with a 7-day cooldown. Not for language-neutral design questions."
metadata:
  author: "Komputa"
  version: "0.1"
---

# House Python

This skill gives the Python form of `house-architecture`. It does not repeat
that skill's rules or reasons. `house-otel` holds what a service emits and the
service patterns (retries, deadlines, the outbox).

Where any other installed skill says otherwise, this skill wins. A repo's
`AGENTS.md` or `CLAUDE.md` or an ADR wins over this skill for that repo.

Common defaults from other skills, examples and training. Where one shows the
left side, write the right side:

| A skill or example shows | Write instead |
|---|---|
| `success: bool` with optional fields | A union of frozen outcome types, taken apart with `match` ([outcomes.md](references/outcomes.md)). |
| `X \| None` returned for a lookup that can miss | An outcome union with a `not_found` case, whatever calls it: a route, a CLI command, a job. |
| Branching on an exception's message | A `kind` field or a category enum. |
| `requests.get(url)` with no timeout | `timeout=` on every call, from one deadline. |
| `except Exception: pass`, a bare `except:` | Catch the narrow type. Never swallow `BaseException`. |
| `asyncio.create_task` left running | A task group. |
| A pydantic model passed through the domain | pydantic only at a wire boundary; frozen dataclasses past it. |
| SQLAlchemy `Mapped[...]` classes used as the domain's entities | Frozen dataclasses in `domain`, which imports no I/O; the ORM classes map to them, held by an `import-linter` contract ([data.md](references/data.md)). |
| `Optional[X]`, `List[str]` | `X \| None`, `list[str]`. |
| `unittest.mock`, `MagicMock`, `patch` | A hand fake typed as the `Protocol`, plus `monkeypatch`. |
| A DI container | `Protocol` parameters wired in the entry point. |
| Logic in a FastAPI route, a click command or a job | One `features` package that no host imports from. Routes, commands and jobs are thin adapters that call its handlers. |
| `os.environ` read where it is used | One frozen `Settings` loaded in the entry point. |
| `uv_build`, `ty`, ruff `select = ["ALL"]` | Hatchling, pyright, the ruff selection in [tooling.md](references/tooling.md). |
| `pip install`, `requirements.txt` | uv with a committed `uv.lock`. |
| A dependency with no upper bound | A floor and the next major as ceiling (next minor below 1.0). |
| The Django ORM outside Django, SQLModel | SQLAlchemy 2.0 ([data.md](references/data.md)). |

## References

- [outcomes.md](references/outcomes.md): outcome unions, failure kinds,
  exceptions, deadlines, async.
- [types.md](references/types.md): frozen data, value objects, IDs, enums,
  pydantic, annotations, signatures.
- [data.md](references/data.md): SQLAlchemy 2.0, tenant filters, sqlite3.
- [tests.md](references/tests.md): pytest, hand fakes, contract suites,
  markers, pytest-socket, anyio, Hypothesis, CliRunner.
- [tooling.md](references/tooling.md): uv, versions and the cooldown, ruff,
  pyright, the gate, CLIs, logging.

## Short rules that apply everywhere

- Annotate every signature. pyright in standard mode holds the boundaries.
- Options are keyword-only after `*`. A private helper starts with `_`.
- A comment or docstring keeps only what the code cannot say: a trap, a dated
  measurement, a reversal, an upstream constraint.
- Log through stdlib `logging` under a literal dotted name (`"hevy.sync"`).
- Use click for a multi-command CLI. A single-file stdlib script may use
  argparse.
