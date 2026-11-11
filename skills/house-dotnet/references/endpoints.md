# Handlers, endpoints and pages

```csharp
// Good (illustrative): App.Features/Goals/CreateGoal.cs, one use case that every host can call
public static class CreateGoal
{
    public sealed record Request(string Name, decimal TargetKg);
    public sealed record Response(GoalId Id, string Name);

    public sealed class Validator : AbstractValidator<Request> { ... }
    public sealed class Handler(AppDbContext db, TimeProvider clock) : IHandler<Request, Response>
    {
        public async Task<ErrorOr<Response>> HandleAsync(Request request, CancellationToken cancellationToken) { ... }
    }
}

// Good (illustrative): App.Api/Goals/GoalEndpoints.cs, the API host's adapter
internal static class GoalEndpoints
{
    public static RouteHandlerBuilder MapCreateGoal(RouteGroupBuilder group) =>
        group.MapPost("/", async Task<Results<Created<CreateGoal.Response>, ProblemHttpResult>> (
                CreateGoal.Request request, IHandler<CreateGoal.Request, CreateGoal.Response> handler,
                CancellationToken cancellationToken) =>
            (await handler.HandleAsync(request, cancellationToken)).Match<Results<Created<CreateGoal.Response>, ProblemHttpResult>>(
                created => TypedResults.Created($"/goals/{created.Id}", created),
                errors => errors.ToProblem()))
        .WithSummary("Creates a goal and returns its ID.");
}
// Bad (komputa, ScheduleEndpoints.cs): IResult and an anonymous object, so OpenAPI has no contract
return Results.Ok(new { scheduleId, status = "updated" });
```

- **Every handler returns `ErrorOr<T>`, whoever calls it.** Its success type is
  a `Response` record (a list query's `IReadOnlyList<Row>` counts), never a
  type named `Result`. Not found is `Error.NotFound`, never `null`.
- **An endpoint `Match`es the handler's `ErrorOr<T>` into a
  `Results<…>` union of named `sealed record`s built with `TypedResults`.**
  Collections are `IReadOnlyList<T>`. The union is the OpenAPI contract; `IResult`
  and anonymous objects document nothing.
- **One `ToProblem(this IReadOnlyList<Error> errors)` per service maps
  `ErrorType` to a status**: Validation 400, Unauthorized 401, Forbidden 403,
  NotFound 404, Conflict 409, anything else 500.
- **An upstream failure is `Error.Failure` from one `UpstreamError` factory that
  puts its kind in `Metadata["kind"]`** (`transient`, `auth_expired`,
  `permanent`). ErrorOr has no transient type. The retry owner reads the kind,
  and the telemetry decorator marks `Failure` as ours.
- **An exception reaches `AddProblemDetails()` and `UseExceptionHandler()`, which
  answer 500.** The logging decorator logs it. The middleware does not log an
  exception its handler handled, so the decorator's line is the one record.
- **Return early on an error** (`if (result.IsError) return result.Errors;`).
  Do not chain `.Then()`, so the failing step is the line you read.
- **The slice's FluentValidation `Validator` checks the request, run by the
  validation decorator for every caller.** Leave out `AddValidation()`: it runs
  only on endpoints, with a second failure shape.
- **Call `ThrowIfNull` only at a public library API**, never on a DI-injected
  parameter.

## Blazor pages

```csharp
// Good (illustrative): App.Web/Goals/GoalPage.razor, @code
var result = await UseCases.HandleAsync<GoalDetail.Request, GoalDetail.Response>(
    new GoalDetail.Request(GoalId.From(Id)), _cts.Token);
if (result.IsError)
{
    Navigation.Show(result.Errors);   // the one page mapping, beside ToProblem()
    return;
}
_goal = result.Value;
```

- **A page reaches a handler only through one `UseCases` service per Blazor
  host.** It creates a scope for each call, sets the tenant from
  `AuthenticationStateProvider`, and resolves `IHandler<,>`, so the decorators
  run and no DbContext outlives the call ([data.md](data.md)). A page never
  injects the DbContext.
- **A page calls the handler and reads its `ErrorOr<T>` with one early return**,
  the same as an endpoint. No `null` check stands in for not found.
- **One page mapping per app maps `ErrorType` to what the user sees**: NotFound
  calls `NavigationManager.NotFound()`, Validation puts each error on its field
  through the form's `ValidationMessageStore`, Unauthorized and Forbidden go to
  sign-in or the forbidden page. Any other kind is a bug at a page, so it throws
  to the error boundary.
- **A page passes a real token**: a `CancellationTokenSource` that the page
  cancels when it is disposed. `CancellationToken.None` belongs in tests only.
