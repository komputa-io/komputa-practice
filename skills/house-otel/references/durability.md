# Writes, background work and durability

## Writes

- **Make every write safe to repeat**: an upsert on a natural key, or a guard
  that returns "already exists". Background work can then re-run from the top.
- **Run at most one job in flight per (tenant, resource)**, and log a duplicate
  trigger as a skip. Four concurrent Garmin loops raced each other in
  production on 2026-04-25.
- **Change a stored or queued message's format in two releases, readers first.**
  Identify its type by an explicit discriminator, never a class name. A queued
  message outlives the deploy that wrote it.

## The durability ladder

Choose the lowest level whose loss you can accept, and say why in the plan.
Every step at levels 1 to 3 is idempotent.

| Level | Mechanism | Use when |
|---|---|---|
| 0 | In memory | Loss is fine: a cache warm-up, a best-effort notification. |
| 1 | A persisted job queue (Hangfire, huey), idempotent handler | Work must survive a restart, with no message to another service. |
| 2 | Transactional outbox and inbox (Wolverine, or a hand-built outbox table) | Most things that announce a state change. A second service consumes it. |
| 3 | Durable workflow engine (Temporal, DBOS, Restate under BSL 1.1; Akka Persistence with sharding; Wolverine sagas) | Many steps that need compensating, waits longer than a process lives (an approval, days of timers), audit and replay, money or legal duties. |

- **Commit a state change and the message announcing it together**: an outbox
  row in the same transaction, published after commit, to consumers that
  tolerate duplicates. Writing the message separately loses it when the process
  dies between the two.
- **Domain events stay in process** until a second service exists. Then use the
  outbox.
- **Money also needs** end-to-end idempotency keys, an append-only double-entry
  ledger, and reconciliation.
- **Under a workflow engine, keep workflow code deterministic.** The clock,
  randomness and I/O go only through the engine's APIs. The engine is the one
  retry owner for its steps, because it re-runs the code to recover.

## Background work

- **With no human in the loop, background work is a hosted loop**: a timer that
  calls a decorated handler, idempotent steps, one run per resource, and a
  catch per tick so one bad tick cannot stop the host.
- **No fire-and-forget tasks.**
- **Put a sweep behind every event path, and resume orphaned work at startup.**
  The sweep catches what the event path dropped.
- **Producer and consumer meet through a bounded queue** with an explicit
  full-mode, read by a hosted service.
- **Parallelism only when throughput is measured, always with a maximum
  degree.**
