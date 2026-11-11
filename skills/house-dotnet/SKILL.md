---
name: house-dotnet
description: "The house rules for C# and .NET. Use when you write, review or set up C# code: ASP.NET Core minimal API endpoints, EF Core, Aspire, TUnit tests, analyzers, .editorconfig, NuGet packages and Directory.Packages.props, or a .NET solution; or when a C# change brings in repositories, Moq, xUnit, FluentAssertions, Task.WhenAll fan-out or a bare resilience handler. Covers ErrorOr with TypedResults, Vogen, slices with Scrutor decorators, named query filters, Testcontainers, the analyzer set, central package management and lock files. Not for language-neutral design questions."
metadata:
  author: "Komputa"
  version: "0.1"
---

# House .NET

This skill gives the C# form of `house-architecture`. It does not repeat that
skill's rules or reasons. `house-otel` holds what a service emits and the
service patterns (retries, deadlines, the outbox).

Where any other installed skill says otherwise, this skill wins. A repo's
`AGENTS.md` or `CLAUDE.md` or an ADR wins over this skill for that repo.

Common defaults from other skills, examples and training. Where one shows the
left side, write the right side:

| A skill or example shows | Write instead |
|---|---|
| `CancellationToken ct = default` | A required token. Default it only in tests. |
| `!` "with a clear invariant" | `!` only with a comment that names the invariant. Narrow first (`is { } x`, `OfType<T>()`). |
| Constructors that assign `_fields` | Primary constructors. |
| A generic `Result`, a per-operation result record, `IActionResult`, `new { error }` | `ErrorOr<T>`, a `Results<…>` union, one `ToProblem()`. |
| A handler that returns `T?` with null for "not found", or a `bool` or `TryX` for an expected failure | `ErrorOr<T>` with `Error.NotFound` or the matching `ErrorType`. |
| A handler's success record named `Result` | `Response`. A result is the outcome; the response is the data in it. |
| Railway chaining with `.Then()`, `.Bind()` or `.Match()` across steps | Early returns: `if (result.IsError) return result.Errors;`. |
| A network failure thrown as an exception | `Error.Failure` with a kind in metadata ([endpoints.md](references/endpoints.md)). |
| `readonly record struct` value objects that throw | Vogen. |
| Services, repositories, `I*ReadStore`, `I*WriteStore` | A slice handler on the DbContext. |
| Entities as public positional records changed with `with` | Private state and methods that return `ErrorOr<Success>`, for an entity with rules. |
| `Update()` on an untracked entity | `AsTracking()`. |
| EF InMemory, `postgres:latest` | Testcontainers with the production image and a template database. |
| xUnit, `IAsyncLifetime`, FluentAssertions, Moq, NSubstitute, Verify.Xunit | TUnit (`IAsyncInitializer`, `[ClassDataSource<T>(Shared = SharedType.PerTestSession)]`), `await Assert.That`, hand fakes, Verify.TUnit. |
| `ValidateDataAnnotations()` alone | A generated `[OptionsValidator]` plus `ValidateOnStart()`. |
| `Version="*"`, "add the latest stable", a global `dotnet-outdated --upgrade` | The version rules in [build.md](references/build.md). |
| A global dotnet tool | A local tool in `.config/dotnet-tools.json`. |
| `_ = Task.Run(...)` for background work; actors as a default | A hosted loop. Actors only where the plan chose them. |
| A bare `AddStandardResilienceHandler()` | The configured handler in [resilience.md](references/resilience.md). |
| `new Meter(name, version)`; health only in `IsDevelopment()` | `IMeterFactory`; health mapped always ([composition.md](references/composition.md)). |
| `EnforceCodeStyleInBuild` only in CI | Always on. |
| CSharpier | `dotnet format`. |
| `Task.WhenAll` over an unbounded collection | `Parallel.ForEachAsync` with `MaxDegreeOfParallelism`, or a bounded `Channel`. |

## References

Read the one that matches the task:

- [endpoints.md](references/endpoints.md): ErrorOr in every handler, TypedResults,
  ProblemDetails, Blazor pages, validation, upstream failures.
- [resilience.md](references/resilience.md): the resilience handler, slow
  upstreams, cancellation, subprocesses, fan-out.
- [data.md](references/data.md): EF Core migrations, transactions, named filters,
  tracking, set operations, locks, the outbox.
- [domain-types.md](references/domain-types.md): Vogen, entities with rules,
  predicates, enums, the Domain project.
- [composition.md](references/composition.md): slices, Scrutor, OpenAPI, options,
  security headers, logging, time, health, meters.
- [tests.md](references/tests.md): TUnit, the database, HTTP fakes, contract
  suites, Verify.
- [build.md](references/build.md): analyzers, `.editorconfig`, packages, lock
  files, tools, the gate.

## Short rules that apply everywhere

- Every handler returns `ErrorOr<T>`, whatever calls it: an endpoint, a Blazor
  page, a job or a consumer. Its caller reads the result with an early return
  and maps the error kind in one place ([endpoints.md](references/endpoints.md)).
- One use case is one `public static class` in `<App>.Features`, a class
  library with no ASP.NET Core reference, so every host can call it. Each host
  (API, Blazor, CLI, worker) is a thin adapter in its own project, and its
  types stay `internal`. The entities, IDs and value types live in
  `<App>.Domain`, with no I/O. The DbContext and migrations live in
  `<App>.Infrastructure`, which maps them
  ([composition.md](references/composition.md)).
- Log with `[LoggerMessage]` methods. Any other log call uses a message
  template, never an interpolated string. CA1848 and CA2254 enforce it.
- Use `[GeneratedRegex]` for a fixed pattern.
- Leave `ConfigureAwait(false)` out of application code. A library turns CA2007
  and MA0004 back on.
- A comment keeps only a trap, a dated measurement, a reversal or an upstream
  constraint link. No tracker IDs in code.
- Doc comments only on a public API used outside the repo. A published package
  sets `GenerateDocumentationFile` and makes CS1591 an error.
