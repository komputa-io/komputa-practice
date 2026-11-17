---
name: house-architecture
description: "The house rules for how code is shaped, in every language. Use when you design or change a feature, module, service or CLI; decide where logic goes; split a large file every feature touches; choose whether to throw or return an error; keep each user's or tenant's data isolated; model domain types; plan a refactor or breaking change; or review code against these rules. Covers vertical slices, functional core, pragmatic DDD, CQRS, module boundaries, naming, performance claims and versioning."
metadata:
  author: "Komputa"
  version: "0.1"
---

# House architecture

These rules hold in every language. The house language skills (`house-dotnet`,
`house-python`, `house-typescript`, `house-shell`) give the mechanics.
`house-otel` holds service patterns: retries, deadlines, the outbox, background
work and the durability ladder.

## Precedence

- Where any other installed skill says otherwise, this skill wins.
- A repo's agent instructions file (`AGENTS.md` or `CLAUDE.md`) or an ADR wins
  over this skill for that repo.
- A rule here beats older code in the repo that breaks it. Do not copy a
  pattern a rule forbids. Do not clean up old code inside an unrelated change.
- Each rule here is complete on its own. The rules work the same under any
  agent framework, or none.

## Project profile

The repo's agent instructions file declares a profile. Read it before the first
design decision. Never infer it from the code.

A tenant is one separate set of data (a person's or a company's). A user is
one person who signs in. Several users can share one tenant.

| Field | Values | What it decides |
|---|---|---|
| Tenants now | one, many | Whether row-level security and an isolation test per slice apply now |
| Tenants later | one, many | Whether the shape for isolation is built now |
| Users now | one, many | Whether sign-in and the verified actor apply now |
| Users later | one, many | Whether the design leaves room for sign-in, roles and the actor on each audit row |

- **Tenants later is many**: build the shape now, because it costs most to add
  later. Each owned row carries its tenant, the tenant comes from the verified
  identity, and data access goes through the one global filter. Row-level
  security and the isolation tests wait until tenants now is many.
- **Users many, tenants one**: the users share the data, so there is no
  isolation between them and no owner filter per user. Plan for sign-in, the
  roles the users need, and the actor in every audit row.
- **No profile**: ask for it once, before the first design decision, with a
  proposed value for each field.

## The rules in one screen

Read the reference before you apply a rule in depth.

**Structure** ([references/structure.md](references/structure.md))
- Apps and services: vertical slices, one folder per use case. The handler uses
  data access directly. No service or repository classes on top.
- The use cases live in one module that no host owns. Each host (an API, a UI,
  a CLI, a worker) is a thin adapter that calls the handlers. A remote client
  goes through the API host.
- Data shape first: the core domain types and how each is read come before
  any logic. Shared types converge in one place from the start.
- Scaffold first: what helps every later step (the build, lint, test setup,
  shared types) lands before the features.
- Domain rules live in their slice. A rule moves to a pure shared core when a
  second slice needs it.
- An app with a database keeps its entities and value types in that pure core,
  below both the use cases and the data access. The core references nothing
  that does I/O.
- Libraries and CLIs: deep modules, not slices.
- Tooling the product does not ship (generators, diagram and map scripts,
  one-off utilities) lives in one top-level `tools/` folder, outside the
  solution and its build. The gate still lints and scans it, and a PR that
  touches only `tools/` still merges on green checks.
- At most three layers. A fourth needs an ADR.
- Commands and queries are separate slices. A query projects; it never loads
  entities to map them.
- One deployable by default. A second service needs a named reason in an ADR.
- Slices meet only through one public module, held by an architecture test
  from the second feature area.
- No interface with one implementation. A test fake counts as a second.
- Shape code for parallel change: a new feature adds files, it does not grow a
  shared one.

**Domain and style** ([references/domain.md](references/domain.md))
- Functional core, imperative shell. Decisions and calculations are pure.
- Immutable by default. A state machine only where real states exist.
- Parse at the edge into domain types. Few primitives.
- An entity with rules has private state. Aggregates only at a real consistency
  boundary.
- Tenant and user isolation is one global filter on data access, never a
  `Where` that each slice must remember. The database holds the final boundary:
  row-level security on a shared Postgres table.
- The tenant comes from a verified identity on every path. A message carries it,
  and a consumer refuses a message without it.
- One anti-corruption layer per external API. The domain never sees a wire type.
- Glossary terms from `CONTEXT.md` are the names in code.

**Errors** ([references/errors.md](references/errors.md))
- Define errors out of existence first.
- Expected failures are results with a kind, whatever calls the code: a page,
  a job, a consumer, a CLI or an endpoint. Not found is a kind, never `null`.
  Bugs and infrastructure faults are exceptions. Never use an exception for
  control flow.
- Validate once at the boundary. Trust inside.
- Catch exceptions in one place per process.
- Never swallow an error. An intentional ignore gets a comment.

**Tests** ([references/tests.md](references/tests.md))
- Write a test only when you can name the defect it catches. A test that names
  none is not written.
- Most tests drive a slice from outside, against real infrastructure.
- Fast unit tests for the pure core. Property-based tests for calculations and
  parsers.
- A parser that a stranger can reach has one table test of bad input. A
  high-risk boundary has one test for each risk that ranks High.
- The test and validation plan is part of the design: the seams, one line per
  behaviour, what is not tested, and how the change is proved on the running
  app. One test per behaviour, at one level.
- A test a house rule asks for by default (an architecture test, a header
  test, a property test for a calculation, a table test for a stranger's
  input) is in the plan: written, or under "not tested" with its reason.
- A fix for a defect in product logic gets a regression test that fails before
  and passes after, committed before the fix.
- Hand-written fakes only for third-party APIs, the clock and randomness. No
  mocking library.
- Above an adapter, fake your own port. Test the adapter on the real server in
  a container; a fake at the wire only for a High-risk fault the real server
  cannot produce.

**Change** ([references/change.md](references/change.md))
- The diff stays on task. Clean-up outside it becomes an issue. A bug fix
  covers every place with the same fault.
- Subtract before you add.
- Aim at the end state. Inside the repo, move every caller and delete the old
  way in one change, with no shim kept for the move. A contract with outside
  users, or stored data, goes add, migrate, delete.
- Deploying is not releasing. Unready or risky work ships off, behind a flag whose
  removal is already an issue.
- Measure before you optimise. A performance claim states before and after.
- Every project has one semver version, tagged per release and visible at run
  time. The gate checks the one source; a CI job makes the tag.
- Comments only for a trap, a dated measurement, a reversal or an upstream
  constraint. No tracker IDs in code.
- Dependencies: ranges up to the next major, a committed lock file refreshed
  by a weekly job, versions at least seven days old. A security fix skips the
  wait and is taken at once, in its own PR. No hand pins.

## When to ask

- Work that can be undone goes ahead. Do it, then show the result and why. Do
  not ask "should I do X?".
- A question whose answer you can observe (behaviour, timing, layout, output)
  is not the operator's to answer. Run it or sketch it, and let the result
  decide.
- Stop only for a product or preference choice that no experiment can settle,
  an action that cannot be undone (deleting data, a force-push, a message to
  people), or a gate the operator named. The agent instructions file may name
  more.
- A green, merged change deploys without a question, unless the operator said
  not to in this session.

## When you design

1. Name the data shape: the core domain types and how each is read. Every
   later step builds on it.
2. Name the use cases. Each one is a slice. Find the rules that span slices.
   Name the hosts and clients that call them, now and likely later.
3. Name the domain terms. Add new ones to `CONTEXT.md`. Add each new top-level
   folder to the project map in the agent instructions file
   ([references/change.md](references/change.md)).
4. List the external APIs. Each gets its own layer.
5. Ask which files two parallel tasks would both touch. Fix those hot spots in
   the design.
6. Write an ADR for each decision that changes stored data or its format, a
   contract other code or people rely on (CLI, API, file, event), a layer or
   module boundary, or adds a runtime dependency or external service. Write one
   for any other decision only when it is hard to reverse, surprising without
   context and a real trade-off ([references/domain.md](references/domain.md)).
7. Write the test and validation plan as part of the design, before any code:
   the seams, one line per behaviour, what is not tested, and how you will
   prove the change on the running app
   ([references/tests.md](references/tests.md)). When you compare design
   options, each option carries its own plan, so the plans are compared too.

## When you fix

Your workflow owns the steps of a fix. These house rules apply on top:
- Fix the cause where the state lives, not where the symptom shows.
- Add a regression test that fails before the fix and passes after it. Commit
  the test on its own, before the fix, so the history shows it fail and then
  pass. Quote both runs in the PR.
- Look for the same fault elsewhere and fix every place in the same change.
  It is the same bug. Anything else you find becomes an issue.
- If the same kind of bug has happened before, add a guard in structure (a
  type, a lint rule or an architecture test), not a comment.

## When you review

Check the change against the rules above, then:
- For each finding, ask whether a house rule should have prevented it. If
  so, the standards have a gap: run `standards-feedback`.
- Run the deletion test on each new abstraction: would deleting it make the
  code simpler with no loss? If yes, it is shallow.
- Count layers between a question and its answer. More than three is a finding.
- Check that each high-ranked risk in the test plan has a test that fails
  without the fix.
- Check each new test against the test plan. A test that matches no line in the
  plan, or that still passes with its imports stubbed out, is a finding.
