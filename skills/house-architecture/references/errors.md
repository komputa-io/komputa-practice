# Errors

## Order of preference

1. **Define the error out of existence.** Make the operation idempotent, the
   function total, or the type valid by construction. A delete of something
   already gone has succeeded.
2. **Return a result** for a failure the caller must handle, whoever the caller
   is: an endpoint, a page, a job, a message consumer, a CLI command or a test.
3. **Throw an exception** only for a bug or an infrastructure fault.

A pure calculation that cannot fail returns a plain value, not a result.

## Results

- **A result carries a kind** (ErrorType in ErrorOr, a `FailureKind` enum or
  `kind` union). Callers branch on the kind, never on the message text.
- **Not found is a failure kind, not an empty value.** A lookup that can miss
  returns a result with a not-found kind, never `null`, `None`, `undefined` or a
  default. An empty list is the right answer only for a search, where no match
  is a normal outcome.
- **Read results with early returns.** No nested matching more than one level.
- **A failed upstream call is a classified value**: transient, auth or
  permanent. Unknown counts as permanent, so a parse bug does not spin in
  retries. `house-otel` holds what each class does.

## Exceptions

- **Never use an exception for control flow.**
- **Validate once, at the boundary.** Inside the boundary, trust the types.
- **Catch in one place per host**: the ProblemDetails middleware in a web
  API, one error boundary at the root of a UI (a Blazor circuit, a desktop or
  mobile app), the per-tick catch in a hosted loop, the per-message catch in a
  consumer, the top level of a CLI.
- **Never swallow an error.** An intentional ignore names why in a comment. Lint
  holds the rule: ruff `BLE001` and `S110`, the .NET analysers.

## At the edge

- Each kind of caller maps result kinds in one function: a web API to one
  ProblemDetails shape, a page to its error state, a CLI to an exit code, a
  consumer to retry or dead-letter. Not one mapping per endpoint or page.
- A CLI maps an invalid input to a non-zero exit code with one line on stderr,
  and nothing on stdout.
- A message names the problem in the user's terms: the field, the value and what
  was expected.
