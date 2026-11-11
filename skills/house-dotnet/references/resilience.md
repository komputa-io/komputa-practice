# Resilience, cancellation and fan-out

Each call path has exactly one retry owner. Retry only an idempotent request.
Pass the caller's remaining time down, never a fresh full timeout. (The full
service rules are in `house-otel`.) This file gives the .NET mechanics.

```csharp
// Good (illustrative): ServiceDefaults, the stock envelope, idempotent methods only, 429 left to the workflow
http.AddStandardResilienceHandler(o =>
{
    o.Retry.ShouldHandle = args => ValueTask.FromResult(HttpClientResiliencePredicates.IsTransient(args.Outcome)
        && args.Outcome.Result?.StatusCode != HttpStatusCode.TooManyRequests);
    o.Retry.DisableForUnsafeHttpMethods(); // after ShouldHandle: it wraps the predicate already set
});
// Good (illustrative): a slow upstream replaces the envelope on its own client
#pragma warning disable EXTEXP0001 // RemoveAllResilienceHandlers is [Experimental]; a pragma inside the chain misses it
services.AddHttpClient<ILlmClient, LiteLlmClient>()
    .RemoveAllResilienceHandlers()
    // An LLM answers in minutes. No retry here: the digest workflow owns it.
    // Breaker first (outer), so a timeout counts as a failure; sized for a few calls an hour.
    .AddResilienceHandler("llm", pipeline => pipeline
        .AddCircuitBreaker(new HttpCircuitBreakerStrategyOptions
        {
            SamplingDuration = TimeSpan.FromMinutes(15), MinimumThroughput = 3,
            FailureRatio = 0.5, BreakDuration = TimeSpan.FromMinutes(1),
        })
        .AddTimeout(TimeSpan.FromMinutes(2)));
#pragma warning restore EXTEXP0001
```

## HTTP clients

- **Keep `AddStandardResilienceHandler` in ServiceDefaults for REST, with the
  predicate set before `DisableForUnsafeHttpMethods()`.** Unconfigured, it
  retries every method, 429 included. Where the upstream documents PUT or DELETE
  as idempotent, list the blocked methods with `DisableFor(…)` instead.
- **A slow upstream gets its own pipeline**: `RemoveAllResilienceHandlers()` then
  `AddResilienceHandler`, with the sizing and its reason in a comment. Loosening
  ServiceDefaults for one client loosens it for all. Leave the retry strategy out
  to mean "no retry"; Polly rejects `MaxRetryAttempts = 0`.
- **Add the circuit breaker before the timeout, with `MinimumThroughput` set to
  the upstream's real volume.** The first strategy added is the outermost, so
  only an outer breaker sees a timeout. Polly's default of 100 calls a window
  never trips at a few calls an hour.
- **Use `IHttpClientFactory` (typed or named clients).** Never `new HttpClient()`
  per call.

## Cancellation and subprocesses

- **A `CancellationToken` is required, never `= default`, outside tests.** A
  caller's deadline then always arrives. CA1068 and CA2016 enforce its position
  and forwarding.
- **Bound a subprocess with `WaitForExitAsync` on a linked token with
  `CancelAfter`.** On cancellation, call `Kill(entireProcessTree: true)`.

## Fan-out and concurrency

- **Cap one-off fan-out**: `Parallel.ForEachAsync` with
  `MaxDegreeOfParallelism`, or a bounded `Channel<T>`. Never `Task.WhenAll` over
  a collection with no upper size.
- **Producer and consumer through a bounded `Channel<T>`** read by a hosted
  service, with an explicit `BoundedChannelFullMode`.
- **No `_ = Task.Run(...)` for background work.** Use a hosted loop
  ([composition.md](composition.md)).
- **`SemaphoreSlim` where an `await` sits inside the critical section**; `lock`
  cannot hold one. Use `System.Threading.Lock` (MA0158) for a plain lock. Split
  the state first if you can.
