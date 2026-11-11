# Failures, retries and timeouts

```ts
// Good (illustrative): one Result shape, and one error whose kind decides what happens next
export type Result<T, E> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly error: E };
export type ApiError =
  | { readonly kind: "invalid"; readonly fields: Readonly<Record<string, readonly string[]>> }
  | { readonly kind: "auth" | "not-found" | "permanent"; readonly status: number }
  | { readonly kind: "transient"; readonly status: number; readonly retryAfterSeconds: number | undefined };
```

- **Turn every failed response into one `ApiError` in the API module, classified
  there once**: 401 and 403 are `auth`, 408, 429 and 5xx are `transient`,
  ProblemDetails field errors are `invalid`, anything else is `permanent`.
  Acme re-declared its error type in three auth pages because `apiFetch`
  threw the body away.
- **Decide failure on `response.ok`, never on `error`.** openapi-fetch returns
  `error` as `undefined` or `""` when a failure has no body, and
  openapi-react-query's hooks, which test `if (error)`, resolve a bodyless 401 as
  success with `null` (checked 2026-09-24). Use those hooks only behind a
  middleware that gives every failure a body.
- **Inside a `queryFn` or `mutationFn`, throw an `Error` whose `cause` is the
  `ApiError`.** TanStack Query's error state is how the component receives it.
  This is the one place a failure throws, and `only-throw-error` refuses a plain
  object.
- **The `QueryClient` retries only a `transient` failure, with a jittered
  `retryDelay` that honours `retryAfterSeconds`.** Its default retries every
  failed query three times, a 401 included, on a plain doubling.
- **Join the caller's `signal` to a timeout on every request**:
  `AbortSignal.any([signal, AbortSignal.timeout(ms)])`. `fetch` has no timeout
  sized for the upstream.
- **Rethrow an `AbortError`. Return a `TimeoutError` as `transient`.** The first
  is the caller cancelling; the second is the upstream being slow.
- **Catch an error from an event handler or an async callback into state.** An
  error boundary only sees what throws during render.
