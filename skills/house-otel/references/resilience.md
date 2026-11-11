# Failures, retries and deadlines

```python
# Good (hevy-core, client.py): only methods safe to repeat are retried; POST never is
IDEMPOTENT_METHODS = frozenset({"GET", "HEAD", "DELETE"})
RETRY_STATUSES = frozenset({429, 500, 502, 503, 504})
```

## Classify once

- **Classify a failure once, at the boundary, as transient, auth or
  permanent.** Treat unknown as permanent, so a parse bug does not spin in
  retries.
- **Carry the class as a value** (a result's kind or error metadata), never as
  text to parse.

## Retries

- **Give each call path exactly one retry owner.** If a library, handler,
  workflow or durable engine retries, the layers around it do not. Acme's
  HTTP layer refused a Garmin 429 that its workflow then retried three times.
- **Retry only an idempotent request**: GET or HEAD, a PUT or DELETE the upstream
  documents as idempotent, or a POST that carries an idempotency key the
  upstream honours. A retried DELETE that gets 404 has succeeded. Komputa
  retried email sends up to 16 times (komputa #106).
- **Back off exponentially, with jitter, up to a cap.** Retries fired in lockstep
  hit a recovering upstream all at once.
- **Slow down on a 429**: no immediate retry, and honour `Retry-After`, which is
  either seconds or an HTTP date, with a cap.
- **Move an auth failure (401 or 403) to a reconnect state. Never retry it.** A
  client that retried a dead credential got the workstation banned, and the ban
  looked like "cannot find server".
- **A circuit breaker sits outside the timeout**, sized to the upstream's real
  call volume, so it can see timeouts and can trip at a few calls an hour.

## Deadlines

- **Pass the caller's remaining time down**: a forwarded cancellation token, an
  `AbortSignal`, a remaining-seconds budget. Never a fresh full timeout. An outer
  timeout is longer than the attempts inside it.
- **Give every network call and subprocess a timeout sized for its upstream**:
  seconds for REST, minutes for an LLM or a sidecar that logs in. Aspire's
  30-second default silently killed Acme's LLM calls, and the cancellation
  looked like throttling.

## External APIs

- **An unofficial or scraped API runs as its own sidecar process.**
- **Gate readiness on a signal that can only be true after the work**, never on
  the absence of an error. A Nextcloud upgrade check passed 2.5 minutes before
  the upgrade finished.
