# Composition, options, time and logs

```csharp
// Good (illustrative): Program composition, handlers found by a Scrutor scan, then wrapped
services.Scan(scan => scan.FromAssemblyOf<Program>()
    .AddClasses(c => c.AssignableTo(typeof(IHandler<,>)).Where(t => !t.IsGenericTypeDefinition), // not the decorators
        publicOnly: false)                                                                    // slices are internal
    .AsImplementedInterfaces().WithScopedLifetime());
services.Decorate(typeof(IHandler<,>), typeof(ValidationDecorator<,>));  // FluentValidation, before the handler
services.Decorate(typeof(IHandler<,>), typeof(LoggingDecorator<,>));     // sees validation failures too
services.Decorate(typeof(IHandler<,>), typeof(TelemetryDecorator<,>));   // outermost (house-otel)
services.AddValidatorsFromAssemblyContaining<Program>(includeInternalTypes: true);
services.AddOpenApi(o =>
{
    o.MapVogenTypesInOpenApiMarkers();  // generated from [OpenApiMarker<GoalId>] on `partial class OpenApiMarkers`
    o.CreateSchemaReferenceId = t => t.Type.DeclaringType is { } slice
        ? $"{slice.Name}{t.Type.Name}" : OpenApiOptions.CreateDefaultSchemaReferenceId(t);  // CreateGoalRequest, not Request
});
```

## Slices

- **A new app or service puts its slices in one class library**,
  `<App>.Features/<Feature>/<UseCase>.cs`, with no ASP.NET Core framework
  reference, so no slice can see an `HttpContext` or a component. Each host is
  its own project that references it: `<App>.Api` (minimal API endpoints),
  `<App>.Web` (Blazor), `<App>.Cli`, `<App>.Worker`. Start with the hosts the
  first release needs. Plus `<App>.Domain`, `<App>.Infrastructure`, AppHost
  and ServiceDefaults.
- **The references run one way: Domain, then Infrastructure, then Features,
  then the hosts.** Each project references only the ones before it.
- **`<App>.Domain` holds the entities, the Vogen IDs, the value types and the
  pure rules.** It references Vogen and ErrorOr, and no other package or
  project. The build refuses EF Core, Npgsql, ASP.NET Core, an HTTP client or a
  project reference there.
- **`<App>.Infrastructure` holds the DbContext, the EF configurations, the
  migrations and the external clients.** It maps the Domain types and never
  defines an entity or a value type. The migration service and any other host
  reach the data through it, without referencing the use cases.
- **One `Add<Area>` per feature area in Features registers its handlers.** Each
  host adds its own adapters (`Map<Area>` in the API host), called from a short
  `Program.cs`.
- **One use case is one `public static class` in Features, with public nested
  request, response and handler types**, so every host can call it. A type in
  a host project stays `internal`: CA1515 flags a public type in an
  application.
- **Hand internal types to the scanners where a host has them**: Scrutor `publicOnly: false`,
  FluentValidation `includeInternalTypes: true`, and
  `<InternalsVisibleTo Include="Api.Tests" />`. FluentValidation skips an
  internal validator silently, and its request passes unchecked.
- **Filter the decorators out of the scan.** They implement `IHandler<,>` too
  and would come back as extra handlers. The last decorator registered is the
  outermost.
- **An app with a named duty to keep a record audits commands with one decorator
  that commits the record with the change.** `AuditDecorator<TRequest, TResponse>`
  has `where TRequest : IAudited`, so queries skip it. Register it first, so it
  sits inside validation. It opens the transaction inside
  `CreateExecutionStrategy().ExecuteAsync(…)`, clears the change tracker, calls
  the handler, adds the row, and commits. A handler under it opens no transaction.
- **An audit row holds the verified actor and tenant, the use case, the target ID,
  the outcome, a UTC time from `TimeProvider` and the trace ID.** Never the request
  body: it carries personal data and secrets. The app's database role may only
  insert into that table.
- **A refused or failed command is a log line from the logging decorator**, because
  a rollback removes its row.
- **Do not audit in a `SaveChanges` interceptor.** It misses `ExecuteUpdateAsync`
  and `ExecuteDeleteAsync`, and it sees rows, not use cases.
- **Inject `IHandler<TRequest, TResponse>` in every caller**: endpoints, Blazor
  pages and components, CLI commands, jobs and consumers. A page never injects
  the DbContext, so the decorators run for it too.
  No MediatR or AutoMapper: both now need a commercial licence unless you release
  your own source under RPL 1.5. No MassTransit: v9 is commercial and needs a
  licence key. Use Wolverine (MIT) where a plan chooses a bus.
- **Keyed services replace a factory full of `switch` statements.**
- **The AppHost runs a JavaScript front end with the API the current Aspire
  release names.** Check the release notes; do not copy a name from an old
  example.

## OpenAPI

- **Serve OpenAPI with the built-in `AddOpenApi()` and `MapOpenApi()`, and
  Scalar's `MapScalarApiReference()`.** Give a lambda endpoint `.WithSummary()`,
  since XML comments reach the document only from a named method.
- **Name schemas after their slice with `CreateSchemaReferenceId`.** Without it
  two slices share one `Request` schema. Measured: `PUT /goals/{id}` documented
  CreateGoal's body.
- **Map value objects for OpenAPI**:
  `[assembly: VogenDefaults(openApiSchemaCustomizations: OpenApiSchemaCustomizations.GenerateOpenApiMappingExtensionMethod)]`
  in Api, and the marker above. Without it `GoalId` is an empty schema.
- **Write the document at build time** with
  `Microsoft.Extensions.ApiDescription.Server` and `<OpenApiDocumentsDirectory>`,
  so CI diffs it and regenerates the TypeScript client.

## Options

- **Validate options with a generated
  `[OptionsValidator] internal sealed partial class LlmOptionsValidator : IValidateOptions<LlmOptions>;`**,
  registered as a singleton beside `ValidateOnStart()`. It reports every
  DataAnnotations failure. Hand-write a validator only for a rule across fields.
- **Register `ValidateOnStart()` options and hosted services only when
  `Assembly.GetEntryAssembly()?.GetName().Name is not "GetDocument.Insider"`.**
  Build-time OpenAPI starts the host without production configuration, so
  validation fails the build and the loop starts.

## Time and background work

- **Inject `TimeProvider`, and test with `FakeTimeProvider`.** Acme grew two
  dozen copies of one hand-rolled clock stub (measured 2026-09-24).
- **Background work is a hosted loop**: a `BackgroundService` whose
  `PeriodicTimer` is built from the injected clock
  (`new PeriodicTimer(interval, clock)`), calling a decorated handler in a new
  scope, with a per-tick catch so one bad tick cannot stop the host.
- **Use `FrozenDictionary` for a static lookup and a source-generated
  `JsonSerializerContext` for JSON.**

## Security headers

- **A host a browser can reach sets one header policy, first in the pipeline**:
  NetEscapades `AddDefaultApiSecurityHeaders()` for JSON,
  `AddDefaultSecurityHeaders()` for HTML. A test reads the headers on a 200 and
  a 500. A host that only our services call needs none.
- **A named policy loosens one route only**, such as the Scalar page. HTML adds
  `base-uri 'none'` and a `script-src` with nonces; the preset sets neither.
- **Never add `X-XSS-Protection`, `Expect-CT` or `Public-Key-Pins`.** Old examples
  still show them.
- **Set `AddServerHeader = false` on Kestrel.** `RemoveServerHeader()` cannot
  remove what Kestrel adds.
- **Behind a proxy, run `UseForwardedHeaders` first, or let the proxy write HSTS.**
  The library sends HSTS only on HTTPS responses, so it goes missing with no
  error. An API listens on HTTPS only; HSTS does not protect a non-browser caller.

## Logs, meters and health

Every log line carries the trace ID, meters come from the host, and health is
always mapped but never public. (What a service emits is in `house-otel`.) The
.NET wiring:

- **Turn on `IncludeScopes` in the console formatter**
  (`AddJsonConsole(o => o.IncludeScopes = true)`), which puts `TraceId` and
  `SpanId` on every stdout line.
- **Create meters from `IMeterFactory`.** Suppress CA2000 on `Create` with the
  reason: the factory disposes them.
- **Map `/alive` (checks tagged `live`) and `/health` outside any
  `IsDevelopment()` block**, restricted by network. The Aspire template maps them
  only in Development.
- **Give `/health` `.WithRequestTimeout(…)`, `.CacheOutput(…)`, a `timeout:` on
  each `AddCheck`, and a JSON `ResponseWriter` that names each check.** The
  default writer returns a bare `Healthy`.
