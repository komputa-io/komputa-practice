# Outcomes, failures and deadlines

```python
# Good (illustrative): one frozen type per case, and pyright fails a match that misses one
@dataclass(frozen=True)
class Published:
    external_ref: str

@dataclass(frozen=True)
class Rejected:
    kind: FailureKind
    reason: str

PublishOutcome = Published | Rejected

# Bad (store-uploader, publishing/base.py): a flag lets impossible states exist
@dataclass(frozen=True)
class PublishResult:
    success: bool
    external_ref: str | None = None
```

## Outcomes

- **An expected failure is a case in an outcome union, taken apart with
  `match`**, for every caller: a route, a CLI command, a job or a consumer. A
  lookup that can miss returns a `not_found` case, never `None`. pyright's `reportMatchNotExhaustive` then fails every `match` that
  a new case skips.
- **Every failure case has a `kind: FailureKind`**, a `StrEnum` with the
  caller's mistakes (`invalid`, `not_found`, `conflict`, `unauthorized`) and our
  failures (`transient`, `auth_expired`, `permanent`). The retry owner reads it
  to decide whether to retry. The telemetry decorator marks the span an error
  only for ours.
- **A library raises its errors from one exception hierarchy with a category
  enum** (`hevy-core`, `errors.py`), set where the response is classified. A
  caller branches on the category, never on message text.

## Exceptions

- **Never write `except BaseException` or a bare `except:` without
  re-raising.** `CancelledError` and `KeyboardInterrupt` derive from
  `BaseException`, so that is where cancellation dies.
- **Catch in one place per process**: the CLI's top level, the service's
  exception handler, the per-tick catch in a loop.
- **An intentional ignore names why** in a `# noqa: BLE001 - why` comment.

## Deadlines and async

- **Pass `timeout=` to every `requests` call and `subprocess.run`.** `requests`
  waits forever by default. ruff `S113` flags a bare call.
- **One unit of work has one deadline.** Async code opens `asyncio.timeout` or
  `anyio.fail_after` once, and the awaits inside inherit it. Sync code passes a
  monotonic deadline down, and each call takes `timeout=min(own, remaining)`.
- **Go async only where I/O concurrency pays.**
- **Start concurrent tasks in a task group** (anyio's or `asyncio.TaskGroup`). A
  bare `create_task` can be collected mid-flight.
- **Cap fan-out** with an anyio `CapacityLimiter` or a semaphore. Producer and
  consumer meet through a bounded anyio memory object stream.
- **A service's background work is one loop per job in the lifespan's task
  group, catching per tick**, so one bad tick does not end the service.
