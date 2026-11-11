---
name: house-otel
description: "The house rules for running services, in every language. Use for any task that adds or changes a background, nightly or scheduled job; a call to an upstream or LLM API (retries, timeouts, 429s, circuit breakers); health checks; an alert, dashboard or monitor, including one that never fires; spans, metrics, logs or tracing; or a message another service must receive reliably (outbox, workflow engine). Covers failure classes and retry ownership, deadlines, idempotent writes, the durability ladder, the use-case span and histogram, OpenTelemetry setup, /alive and /health."
metadata:
  author: "Komputa"
  version: "0.1"
---

# House services and telemetry

These rules hold in every language. `house-dotnet`, `house-python` and
`house-typescript` give the wiring. Telemetry goes to SigNoz over OTLP; logs
also reach Loki through Alloy. Hosts and ports are in `~/.claude/machine.md`.

Where any other installed skill says otherwise, this skill wins. A repo's
`AGENTS.md` or `CLAUDE.md` or an ADR wins over this skill for that repo.

## The rules in one screen

**Failures and retries** ([references/resilience.md](references/resilience.md))
- Classify a failure once, at the boundary: transient, auth or permanent.
  Unknown counts as permanent.
- Each call path has exactly one retry owner.
- Retry only an idempotent request, with jittered exponential backoff and a cap.
  Honour `Retry-After` on a 429.
- An auth failure moves to a reconnect state. Never retry it.
- Pass the caller's remaining time down. Every network call and subprocess has a
  timeout sized for its upstream.

**Writes and background work** ([references/durability.md](references/durability.md))
- Every write is safe to repeat. One job in flight per (tenant, resource).
- Pick the lowest durability level that is acceptable: in memory, a job queue,
  an outbox, or a workflow engine.
- A sweep backs every event path. Orphaned work resumes at startup.
- Background work is a hosted loop that catches per tick. No fire-and-forget.

**Telemetry** ([references/telemetry.md](references/telemetry.md))
- Every use case gets a span and a `usecase.duration` histogram in seconds,
  tagged `usecase.name` and `usecase.outcome`, from one decorator.
- A span is an error only when we failed, not when the caller made a mistake.
- Record an exception once, at the unit-of-work boundary.
- Metric tags are bounded. IDs go on the span.
- Values go in log fields, never in the text. An event's identity lives in code.
- Where we own both ends, the client starts the trace at the user's action, and
  one trace covers client and server.

**Health, alerts and monitors** ([references/health.md](references/health.md))
- `/alive` is the process only. `/health` checks each dependency with its own
  timeout and returns JSON naming each check. Both are always mapped, never
  public.
- Alerts query metrics or structured fields, never message text, and say what
  "no data" means.
- Alerts, dashboards and monitors are committed with the service. Prove an
  alert by making it fire.
- A scheduled job proves it ran by pushing to its monitor.

## When you add a call to an upstream

1. Name the retry owner for that call path.
2. Size the timeout for that upstream.
3. Classify its failures where the response is read.
4. Make the call visible: a span, and retries in metrics or logs.

## When you add background work

1. Choose the durability level and say why in the plan.
2. Make each step idempotent.
3. Add the sweep and the startup resume.
4. Give it a span per run, and a push monitor if it is scheduled.
