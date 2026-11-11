# Spans, metrics and logs

```csharp
// Good (illustrative): the outermost decorator on every handler
public async Task<ErrorOr<TResponse>> HandleAsync(TRequest request, CancellationToken cancellationToken)
{
    using var activity = telemetry.Source.StartActivity(Name);
    var started = clock.GetTimestamp();
    var outcome = "Exception";
    try
    {
        var result = await inner.HandleAsync(request, cancellationToken);
        outcome = result.IsError ? result.FirstError.Type.ToString() : "Success";
        if (result.IsError && result.FirstError.Type is ErrorType.Failure or ErrorType.Unexpected)
        {
            activity?.SetTag("error.type", result.FirstError.Code);
            activity?.SetStatus(ActivityStatusCode.Error, result.FirstError.Description);
        }
        return result;
    }
    catch (Exception ex) // recorded once, here, and rethrown
    {
        activity?.SetTag("error.type", ex.GetType().FullName);
        activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
        activity?.AddException(ex);
        throw;
    }
    finally
    {
        activity?.SetTag("usecase.outcome", outcome);
        var tags = new TagList { { "usecase.name", Name }, { "usecase.outcome", outcome } };
        telemetry.Duration.Record(clock.GetElapsedTime(started).TotalSeconds, tags);
    }
}
```

## The use case

- **Every use case gets a span and a `usecase.duration` histogram tagged
  `usecase.name` and `usecase.outcome`, from one decorator**: a handler decorator
  in C#, `@use_case(name)` in Python, `withUseCase(name, fn)` in TypeScript. The
  histogram's count is the outcome counter. Add no separate counter.
- **Declare the histogram's buckets in seconds**:
  `[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120]`. The
  SDKs default to millisecond-shaped buckets, so every use case under 5 seconds
  lands in one bucket and percentiles mean nothing.
- **A span is an error only when we failed**: an unexpected failure, an upstream
  failure or an exception sets the error status and `error.type`. A caller's
  mistake (validation, not found, conflict, unauthorized) is only an outcome tag.
  SigNoz counts error-status spans, so a sync failing on a dead upstream would
  otherwise read 0% errors.
- **Record an exception once, at the unit-of-work boundary.** The decorator, a
  logging layer and the framework's handler can otherwise triple-count one
  failure.
- **Stay on span events for exceptions while SigNoz reads only them.** OpenTelemetry
  is deprecating the span event API for new code, in favour of logs. SigNoz builds
  its Exceptions view from span events, and log records do not feed it. Move when
  that changes.
- **Loops and consumers call handlers, so they get the same span.** Work outside
  a handler starts its own span. Acme's background syncs logged with an
  empty `trace_id`.
- **Keep metric tags bounded** (use case, outcome, source, model). Every distinct
  value is a new time series. A user, tenant or entity ID goes on the span.
- **Make retries and breaker openings visible**: the resilience library's meter,
  or one structured log event per retry.
- **Prove a new instrument emits in its first caller's test.** Assert the exact
  metric, tag and span names that an alert or dashboard reads. A renamed tag
  empties an alert as surely as reworded log text.

## End-to-end traces

Where we own both ends (a web front end, an installed web app or a native mobile
app, and its API), one trace covers what the user waited for.

- **The client starts the trace at the user's action**: a page load, a
  navigation, or an action such as "save goal". That span is the root. The API
  call, the handler and the database work nest under it.
- **The client propagates W3C `traceparent` and `tracestate` to our API only**,
  never to a third party. The API's CORS allows both headers.
- **The backend uses parent-based sampling**, so it honours the client's
  decision and traces arrive whole.
- **A client span names the action and the screen or route, never the user's
  data.** No names, emails, search text or IDs that identify a person.
- **Web vitals go on the page-load span** as attributes, so a slow page and its
  slow API call sit in one trace.
- **Client spans export to a same-origin path proxied to the collector** (web),
  or to our own authenticated ingest endpoint (mobile). Never a public collector
  port.
- **A mobile client buffers spans while offline** and sends them later. Expect
  clock skew between device and server; order by the trace's structure, not by
  timestamps alone.
- **The Next.js server hop counts too**: set `@vercel/otel`'s
  `propagateContextUrls` to our API, since by default it propagates only to
  Vercel URLs.

- **A message carries the trace context.** The producer writes `traceparent`
  and `tracestate` into the message headers, or into the outbox row. The
  consumer starts its span from them: as the parent for one message, as a span
  link when one span handles a batch. Without it the trace ends at the queue.

## Identity

```yaml
OTEL_SERVICE_NAME: acme-api            # <product>-<component>
OTEL_EXPORTER_OTLP_ENDPOINT: http://<signoz-host>:4318
OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf   # .NET and the Python distro default to gRPC
OTEL_RESOURCE_ATTRIBUTES: deployment.environment.name=production,deployment.environment=production,service.namespace=acme,service.version=<semver>
```

- **Set these on every component.** Set both environment keys until SigNoz reads
  the new one. `service.version` is the project's semver.
- **Name the trace source and the meter after the application, and register
  both.** An unregistered source exports nothing, silently.
- **Switch telemetry off only with `OTEL_SDK_DISABLED=true` or an unset
  endpoint.** Nothing reads a custom `OTEL_ENABLED`; six services set it while
  exporting nothing.
- **Leave probe endpoints out of traces.** A 60-second probe otherwise writes
  1,440 traces a day.

## Logs and event IDs

- **An event's identity lives in code**: an EventId from its area's range in C#,
  with a test that each is unique; a dotted event name as the message in Python
  (`log.info("sheets.retry", extra={"op": op, "attempt": n})`). No registry
  document.
- **Values go in fields, never in the text**: named placeholders or `extra={}`,
  never `{0}` or an interpolated string. The failure path logs the exception
  object.
- **Every stdout line carries `trace_id`**, because Loki reads stdout.
- **A CLI or skill script gets no OTel**: an exit code, and one summary line
  with counts in and out. "Processed 0 of 0" must not look like success.

## Python services

- **Start a long-running Python service under `opentelemetry-instrument`**, with
  its instrumentation packages in `pyproject.toml`, including
  `opentelemetry-instrumentation-logging`. No runtime bootstrap. A sidecar that
  called an instrumentor without the distro got a no-op tracer, and its spans
  vanished.
- **Do not add a second MCP instrumentor.** FastMCP emits MCP spans itself.
- **Run one uvicorn worker per container, and never `--reload` outside
  development.** Both break instrumentation.

## LLM calls

- **An LLM call is a span named `{operation} {model}`** with
  `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`,
  `gen_ai.usage.input_tokens` (cache reads included) and
  `gen_ai.usage.output_tokens`, plus our own `llm.tokens` counter tagged by
  model, direction and purpose. The GenAI metric names changed twice in 2026, so
  the counter stays in our namespace.
- **Where a library already emits the GenAI conventions, register its source and
  meter** instead of writing a second span.

## Data or telemetry

- **What the product shows or bills on is stored as data** (LLM cost, usage,
  sync history, per user). **What an operator acts on is emitted as
  telemetry.** One number can be both.
