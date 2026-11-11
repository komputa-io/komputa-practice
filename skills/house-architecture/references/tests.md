# Tests

A test checks behaviour from the outside, never the implementation. A test that
still passes when its production code is deleted, or when every import returns
nothing, is hollow: delete it or rewrite it.

**Name the defect first.** Before you write a test, name the mistake it would
catch: a real change to the code that makes it fail. Where it is cheap, make
that change and watch the test fail. A test that names no defect is not
written, however easy it is to add.

## The test plan

Too many tests cost as much as too few: they slow the suite, pin the
implementation and bury the tests that matter. A plan decides what to test
before any test is written.

- **Write the test and validation plan with the design, before any code.** It
  goes in the design, then into the PR description (or the commit message when
  there is no PR). Never as a file in the repo. It has four parts:
  1. The seams under test. Usually one per slice: the handler, called the way
     its hosts call it (an endpoint, a page, a command).
  2. One line per behaviour each seam must show: the happy path, and one
     failure case for each risk that ranks high (likelihood times cost).
  3. What is deliberately not tested, and why. A test a house rule asks for
     by default (an architecture test, a header test, a property test for a
     calculation, a table test for a stranger's input) is either written or
     named here with its reason. It is never left out in silence.
  4. Validation: how the change is proved on the running app, the way a user
     would use it.
- **When design options are compared, each one carries its own plan.** The
  plan is part of what is compared, because it shows where the testing is
  likely to go.
- **Write the plan yourself. Do not stop to ask for approval.** The plan is
  visible in the design and the PR, where it can be challenged.
- **One test per behaviour, not per input.** Cover more inputs with a
  parametrised or property-based test, not a new test.
- **Test each behaviour at one level only**: the highest seam where the test is
  cheap. Not a unit test, an integration test and an end-to-end test of the same
  thing.
- **Do not test what something else already guarantees**: the framework or a
  library, trivial mapping, private helpers, or a rule the type checker or a
  linter enforces (for example, "rejects `None`" on a typed parameter).
- **A plan that keeps growing means the change is too big.** Split the
  change. Do not grow the plan.
- **A test that matches no line in the plan is a review finding.**

## What to test, and how

- **Most tests drive a slice from outside**: its handler, as an endpoint, a
  page or a CLI command calls it, against real infrastructure.
- **Fast unit tests for the pure core.** No setup is needed, because the core
  has no I/O.
- **Property-based tests by default for calculations and parsers**: CsCheck,
  Hypothesis, fast-check.
- **A parser that a stranger can reach has one table test of bad input**: mail,
  a file from outside, a request with no sign-in. A few rows, for the kinds the
  threat model ranks high: a malformed value, a wrong type, an encoding edge
  case, a size limit. Input from a signed-in owner needs only the test of its
  validation. A new input class joins the table only when it showed a real
  fault.
- **A high-risk boundary gets one test for each risk that the threat model
  ranks High**: a boundary that guards security, money or data that cannot be
  restored. Put each test at the lowest level that can show the risk. One table
  test or one property-based test covers a kind of input: do not test each key,
  each file-system case or each fault by itself. Write the full hostile-input
  suite (each key the code owns, the file-system cases, a property-based test
  that mutates real samples) only when it is asked for by name.
- **A few end-to-end tests for the critical user journeys** (Playwright): one
  for each main user task, on its happy path. An edge case goes to a lower
  level. While
  you work, check the UI with a browser tool; a journey worth keeping becomes a
  Playwright test.
- **When the profile says tenants now is many, every slice that adds an
  entity has an isolation test**: tenant A cannot see,
  change or delete tenant B's data, even when A names B's tenant in the request.

## Infrastructure and fakes

- **Real infrastructure where it is cheap.** The database is the same engine
  and major version as production, in a container: a template database copied
  per test class for Postgres, a reset between tests for SQL Server, a temp file
  for SQLite.
- **Hand-written fakes only for third-party APIs, the clock and randomness.**
  No mocking library. Where another skill says "mock", read it as "a
  hand-written fake".
- **Above an adapter, fake your own port**: a scripted result, not a protocol
  server.
- **Test the adapter against the real server in a container.** Write a fake at
  the wire (a small SMTP or IMAP server) only when the adapter's fault mapping
  holds a High risk that the real server cannot produce, such as a drop after
  the message body.
- **A fake at the wire holds only the faults that a test uses.** Remove a fault
  mode with its last test. A fake counts as test lines.
- **A fake that holds logic shares one contract suite with the real adapter**
  (a state machine, a protocol), so the fake cannot drift from the real thing.
  A fake that returns fixed answers needs none.
- **Tests reach only the network they start.**
- **A fake stream or response body in a test is finite.** An endless one in a
  red test fills memory until the system kills the session.

## Bug fixes

- **A fix for a defect in product logic gets a cheap regression test**: it fails before the fix and passes
  after it, and the PR quotes both runs. If no cheap test is possible, the PR
  says why. Prefer no new test over a bad one.
- **Commit the failing test on its own, before the fix.** The history then
  shows the test fail and the fix make it pass.

## Measures

- **Coverage and CRAP scores are reported, never gated.**
- **Mutation testing** (Stryker, mutmut) runs now and then on the pure core, not
  in CI.
- **No gate fails on a test-to-source line ratio.**
