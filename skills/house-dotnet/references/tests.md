# Tests

Most tests drive a slice from outside against real infrastructure. The pure
core gets fast unit tests, and calculations get property-based tests. A bug fix
gets a regression test that fails before and passes after. (The full
cross-language rules are in `house-architecture`.)

## TUnit

- **Run TUnit on Microsoft.Testing.Platform**, with
  `"test": { "runner": "Microsoft.Testing.Platform" }` in `global.json`. Without
  it `dotnet test` stops with an error. TUnit needs neither
  Microsoft.NET.Test.Sdk nor coverlet.
- **Translate xUnit examples from other skills**: `IAsyncLifetime` becomes
  `IAsyncInitializer`, a shared fixture becomes
  `[ClassDataSource<T>(Shared = SharedType.PerTestSession)]`, `[Fact]` becomes
  `[Test]`, `[Theory]` with `[InlineData]` becomes `[Test]` with `[Arguments]`.
- **Test classes are `internal sealed class <Type>Tests`. Test names describe
  behaviour**: `Completing_a_workout_records_volume`. Assert with
  `await Assert.That(x).IsEqualTo(y)`.
- **The one exception: an Avalonia headless UI test project uses xUnit with
  `Avalonia.Headless.XUnit`.** Avalonia ships integrations only for xUnit and
  NUnit. Revisit when an official TUnit one ships.
- **Property-based tests use CsCheck.**

## Infrastructure

- **Anything that touches the database runs on the production engine.**
  Postgres: `new PostgreSqlBuilder("postgres:<production major>")`, a migrated
  template database, a copy per test class. SQL Server: Respawn or a snapshot
  between tests. Never EF InMemory: it checks no constraints, transactions or
  SQL. The parameterless builder is obsolete and pins an old image.
- **Fake an HTTP upstream with an `HttpMessageHandler` that records each
  request**, passed to `ConfigurePrimaryHttpMessageHandler`. Other doubles are
  hand-written sealed fakes. No mocking library.
- **In a test host, give every client a refusing primary handler by default**
  (`ConfigureHttpClientDefaults(b => b.ConfigurePrimaryHttpMessageHandler(() => new RefuseUnfaked()))`),
  so a test reaches no upstream it did not fake. It cannot see a
  `new HttpClient()`; review catches that.
- **A contract suite is an abstract test class, run by a fake-backed and a
  real-backed subclass marked `[InheritsTests]`.** TUnit0030 fails the build
  without the attribute.
- **Set `DOTNET_HOSTBUILDER__RELOADCONFIGONCHANGE=false` in a
  `[ModuleInitializer]` in test projects that start hosts**, or Linux runs out of
  inotify watches mid-run.

## Snapshots

- **Snapshot large structured output with Verify.TUnit.** Declare the sponsorship
  in `Directory.Build.props`: `<Verify_GitHubSponsorAccount>`, plus
  `<Verify_SponsorshipStart>` when the sponsorship is newer than the package, or
  `<Verify_SponsorshipPrivateUntil>` when it is private. Verify fails the build
  (SC021) until it is declared.
- **Accept a snapshot only after reading its diff.** Accepting every received
  file deletes an assertion.
