# Types, values and modules

```python
# Good (illustrative): one rule, raised by __post_init__ and turned into a value by parse
@dataclass(frozen=True)
class Kilograms:
    value: Decimal

    def __post_init__(self) -> None:
        if not (self.value.is_finite() and self.value > 0):
            raise ValueError(f"not a weight: {self.value}")

    @classmethod
    def parse(cls, raw: str) -> Self | Invalid:
        try:
            return cls(Decimal(raw))
        except (InvalidOperation, ValueError):
            return Invalid(field="weight", raw=raw)
```

## Data and values

- **Data is `@dataclass(frozen=True)`, and its sequences are tuples.** A frozen
  class that holds a list can still change.
- **A domain value with rules has a `parse` classmethod that returns it or an
  `Invalid`, and a `__post_init__` that raises on the same rule.** Python cannot
  hide a constructor, so the raise catches a call that skipped `parse`.
- **An ID that crosses modules is a `NewType`.** pyright then rejects a
  `WorkoutId` where a `GoalId` belongs.
- **Money is `Decimal` or whole pennies as `int`**, never `float`.
- **A fixed set is a `StrEnum`, or a `Literal[...]` for a small set in one
  signature.** Both serialise as plain strings.
- **A state machine is a union of frozen state types with a `kind` field and a
  pure `apply` function.**

## pydantic

- **Use pydantic only at a wire boundary**: a FastAPI or FastMCP signature, or
  an outside payload being parsed. Past it, a frozen dataclass does the job
  without the dependency.

## Annotations and signatures

- **Below a 3.14 floor, open every module with
  `from __future__ import annotations`. From 3.14, leave it out.** 3.14 defers
  annotations itself, and PEP 749 deprecates the import once 3.13 reaches end of
  life.
- **Import a name that FastAPI, pydantic or FastMCP reads from an annotation for
  real, never under `TYPE_CHECKING`.** They read annotations at run time, so the
  app starts and its first request fails.
- **Write `X | None` and `list[str]`, never `Optional` or `List`.**
- **Type a decorator with `ParamSpec`**, or pyright loses the wrapped function's
  signature.

## Seams and configuration

- **A dependency is a `Protocol` parameter, wired in the entry point. Each hand
  fake is typed as that `Protocol`.** pyright then fails when the seam, a caller
  or a fake drift apart. No DI container.
- **Read configuration once in the entry point**, as a frozen `Settings` from
  `Settings.load(os.environ)`, which returns it or an `Invalid` naming every
  missing variable. ruff `TID251` (banned-api) flags `os.environ` anywhere else.
