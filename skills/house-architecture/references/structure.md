# Structure

Vocabulary: a **deep module** hides a lot of behaviour behind a small
interface; a **shallow** one does not. A **seam** is a place where behaviour can
be swapped without editing the caller. An **adapter** fits an outside system to
a seam. **Locality** means code that changes together lives together.

## Apps and services: vertical slices

- **One folder per use case** (`Features/CompleteWorkout/`,
  `features/complete_workout/`, `features/complete-workout/`). The folder holds
  the handler, its request and response types, and its validator.
- **The handler uses data access directly.** With an ORM it uses the context.
  Without one, each slice has one store module that holds queries, not domain
  rules. No service, repository or "manager" class sits on top.
- **A slice may expose one public interface module** (for example `api.py`) for
  other slices. It is a door, not a layer.
- **Data shape first.** Define the core domain types, and trace how each one
  is read, before you write logic. Shared types converge in one place from the
  start. Shape the structure once; do not deduplicate every similar line.
- **Scaffold first.** What helps every later step (the build, lint, test setup,
  shared types) lands before the features.
- **Domain rules live in their slice.** A rule moves to a pure shared core when
  a second slice needs it.
- **An app with a database keeps its entities and value types in the pure
  core** (`<App>.Domain` in .NET), because the use cases and the data access
  both need them. The data access maps them; it never defines one. The core
  references nothing that does I/O, so its rules test with no setup.
- **At most three layers** between the entry point and the data: the host's
  adapter, the handler, the data access. A fourth needs
  an ADR.

## Hosts: one set of use cases, many callers

An app outlives its first front end. A Blazor app may later need an API for a
phone, a desktop app, a CLI or another service. When the use cases live inside
the first host, each new caller is a refit.

- **The use cases live in one module that no host owns** (`<App>.Features`, a
  `features` package). Every host calls the same handlers: a web API, a
  server-rendered UI, a CLI, a worker, a message consumer. A new host adds an
  adapter, not a rewrite.
- **A host is a thin adapter.** It parses the input, takes the verified
  identity, calls the handler, and maps the result kind to its own output (see
  [errors.md](errors.md), "At the edge"). No business rule lives in a host.
- **A handler takes plain inputs and the caller's identity.** Never an HTTP
  context, a page, a console or another type that belongs to one host. The
  use-case module does not reference a host framework, so the compiler holds
  the line.
- **Every caller goes through the handler and its decorators**, pages included.
  A host never reaches the data access directly, so validation, the audit, the
  log line and the span run for every caller.
- **A remote client** (a phone or desktop app, a browser front end) **reaches
  the use cases only through the API host**, with a client generated from the
  API's contract. It never holds a copy of a business rule.
- **Add a host when a caller needs it, not before.** The use-case module is
  what keeps that cheap.

## Libraries and CLIs: deep modules

- A library or CLI is not sliced. Give it a few deep modules with small
  interfaces.
- A CLI's commands, flags, JSON fields and exit codes are its public interface
  (see [change.md](change.md), "Compatibility").

## Commands and queries

- **A command and a query are separate slices**, each with its own handler.
- **A query projects** to the shape it returns (a select with no tracking, a
  Core select). It never loads entities to map them.
- **A separate read model** (a view, a summary table, a cache) only for a
  measured slow query.
- **One database by default.** Raw SQL or Dapper only where the ORM cannot
  express the query, and only inside that slice.
- **No dispatcher library** (no MediatR or similar). The host's adapter calls
  the handler. Cross-cutting concerns are decorators on a generic handler interface
  (Scrutor in .NET).

## Module boundaries

- **One deployable by default: a modular monolith.** A second service needs a
  named reason in an ADR: a different scale or failure profile, a runtime or
  process it must not share, or a team that ships on its own schedule. "Cleaner"
  is not a reason. A split costs the shared transaction, so the outbox comes
  with it (`house-otel`).
- **Slices meet only through their public module.** From the second feature
  area, an architecture test holds the rule and fails by name: NetArchTest or ArchUnitNET, `import-linter`,
  `eslint-plugin-boundaries` or `dependency-cruiser`.
- **No interface with one implementation.** A test fake counts as a second. A
  generic `IHandler<TRequest, TResponse>` exists only while decorators use it.
  Never add a per-use-case interface.
- **Run the deletion test** on every new abstraction in review.
- **Design it twice** only for an interface that is hard to change later:
  sketch two different interfaces and compare them before you build one.

## Shape code for parallel change

Several agent lanes change code at once. A file that every feature edits turns
a plan into a queue or into merge conflicts.

- **A new feature adds files. It does not grow a shared one.** A module that
  most plans touch is a split waiting to happen. Split it as its own task first.
- **Every registration point is one line per feature, or discovered.** Routers,
  navigation, DI registration and template includes are the usual hot spots.
- **One front-end file per screen or component.** The shell only loads them.
- **Keep shared vocabulary small.** Shared constants and user-facing words live
  in one small module that rarely changes. Each feature owns the rest.
- **Mirror the slices in the tests.** One test file per feature. Shared fixtures
  that a feature never has to edit.
- **Ask in design: which files would two parallel tasks both touch?** A plan
  whose longest chain equals its task count is a code-shape problem.

## Decisions each project makes

- **Actors, event sourcing and streams** are chosen per project from its needs.
  There is no default framework. Akka.NET only for many long-lived stateful
  entities or real distribution.
- **Event source only the small part of the domain that needs it.** Applying it
  to a whole domain makes the whole system carry the cost.
- **Under event sourcing**, `Apply` is pure. Projections read the durable
  journal from a stored offset, idempotent per event. A failed projection stops
  and alerts.
- **Do not restructure code that is being retired.**
