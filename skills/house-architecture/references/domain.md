# Domain and style

Four principles underlie this file. Model the domain in types, so invalid
states cannot be built. Check data at the boundary, then trust it inside. Let
the type system carry rules the compiler can enforce. Separate shared state
before you add locks or queues around it.

## Functional core, imperative shell

- **Decisions and calculations are pure functions**: no clock, network or
  database. They test with no setup.
- **I/O comes in from the edge.** A check that fails holds the boundary: a
  Domain project that references nothing with I/O, `import-linter` contracts,
  `no-restricted-imports`.
- **Expected failures are results**, read with early returns (ErrorOr in C#).
  See [errors.md](errors.md).
- **Chains stay short**: two or three steps. Use LINQ or comprehensions for
  queries and transforms. Use a loop for side effects or more than about four
  operators.
- **Immutable by default**: records, frozen dataclasses, `readonly` types.
- **A state machine only where real states exist**: closed states and a pure
  `Apply`. TypeScript and Python use a `kind` discriminant. C# uses sealed
  records.

## Types and parsing

- **Parse, don't validate.** Raw input becomes a domain type once, at the edge.
  The parse reports every field that failed, not only the first.
- **Few primitives.** An ID, a quantity with a unit, an email address or a date
  range is its own type, so a `WorkoutId` passed where a `GoalId` belongs fails
  to compile. The unchecked constructor must be unreachable: Vogen in C#, a
  frozen dataclass that checks in `__post_init__` in Python, a brand that only
  the parse function may assert in TypeScript.
- **Money is whole minor units** (pennies) or an exact decimal type, never a
  float.
- **State-dependent rules live with the state.** Capacity, uniqueness and
  permission are business rules, not parsing.

## Pragmatic DDD

- **No repositories.** See [structure.md](structure.md).
- **An entity with rules has private state** and methods that return a result.
  No caller can build an invalid state. Where there are no rules, a plain record
  is right.
- **An aggregate only at a real consistency boundary.** A CRUD table needs no
  domain ceremony.
- **No base Entity class.**
- **Domain events stay in process.** An outbox only when a second service
  exists (`house-otel`, the durability ladder).
- **No specification pattern.** Compose queries with extension methods on the
  query type. Use a static expression only for a predicate needed both in SQL
  and in memory, and test it against the real database: the database compares by
  its collation, the language does not.

## Tenant and user isolation

- **One global filter on data access**: an EF named query filter, SQLAlchemy
  `with_loader_criteria`, or a required scope argument in a store module. Never a
  `Where` that each slice must remember.
- **A bypass lifts only the filter it names**, through one named, reviewed type.
- **The tenant comes from a verified identity, never from client input alone.**
  A token, session, API key or client certificate proves who calls. A tenant in
  a host, path, header or query string only selects: check it against the
  caller's membership and refuse a mismatch. A verified tenant claim passes that
  check, so keep its token short-lived. One component sets the scope; a slice
  never reads the tenant from the request. No tenant is a refusal, never an
  unscoped query.
- **A message or queued job for one tenant carries its tenant.** The producer
  takes it from its own verified scope, never from a field a client set. The
  consumer sets the same scope from it before any data access, so the one
  filter still holds. A missing or invalid tenant is a permanent failure:
  dead-letter it and do not retry.
- **A tenant field proves nothing by itself.** A shared queue is not a boundary.
  Trust the field only when just our services can publish, or the payload is
  signed; a queue per tenant gives the tenant by its route. Check permission
  again when delay can make it stale. Never read a tenant from W3C baggage: it
  has no integrity check.
- **Work across tenants runs under one named system identity**, one tenant scope
  at a time. Never a made-up tenant.
- **The filter is not the final boundary.** It does not cover raw SQL, bulk
  statements or a forgotten scope. On a shared Postgres table, row-level security
  is that boundary: `ENABLE` and `FORCE` it on every tenant-owned table, with
  `USING` and `WITH CHECK`. The app connects as a role that is neither a superuser
  nor `BYPASSRLS`, and a test reads the deployed role from `pg_roles`. Set the
  tenant with `SET LOCAL` inside the transaction; a plain `SET` survives on a pooled
  connection. A test with the filter lifted still sees only its own tenant.
- **Physical isolation** (a database per person) where it fits; it needs no policy.
  Where row-level security is not available, a database per tenant or a constrained
  role holds the boundary. Say which in an ADR.
- **A write stamps the tenant from the same scope.** A query filter does not guard
  an insert.
- **Raw SQL and bulk statements take the tenant as a required argument**, with their
  own isolation test.

## Data access in Python

- SQLAlchemy 2.0: the typed ORM (`Mapped`) for relational domains, Core for
  query-shaped stores. Plain `sqlite3` for a few small tables.
- Not the Django ORM outside Django, and not SQLModel.
- Do not migrate an existing app for this rule.

## External APIs

- **Each external API has its own anti-corruption layer**: a typed client,
  internal wire types, a pure mapper to domain types, typed error kinds and
  validated options. The domain never sees a wire type.
- **A missing required field throws**, with the upstream's name in the message.
  Never map it to a default.
- **An unofficial or scraped API runs as its own sidecar process.**
- **The vendor's name appears only in the client layer.** A drift test holds the
  seam's interface to what is really called.

## The glossary

- `CONTEXT.md` terms are the names in code, tests and messages. Its `_Avoid_`
  terms do not appear in code.
- `CONTEXT.md` is a glossary only: each term, its meaning, and the words to
  avoid. No implementation detail. Module lists and boundaries go in an ADR or
  an architecture test.
- **An ADR is required** for a decision that changes:
  - stored data or its format, including a version bump or a migration;
  - a contract other code or people rely on: a CLI, an API, a file format or
    an event;
  - a layer or module boundary;
  - the runtime dependencies or external services.
- Any other decision gets an ADR only when it is hard to reverse, surprising
  without context and a real trade-off. Nothing less.
- An ADR is short: the context, the decision, the options rejected and why,
  and the consequences. A later ADR that changes it links back to it.
- The PR that makes the decision adds the ADR and names it under Tradeoffs.
