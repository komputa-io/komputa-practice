# Build, analyzers and dependencies

```ini
# .editorconfig [*.cs]: every change from the default, with its reason. Under latest-all no IDE rule fails the build until raised
dotnet_diagnostic.CA2007.severity = none        # ASP.NET Core has no SynchronizationContext; a library turns it back on
dotnet_diagnostic.MA0004.severity = none        # Meziantou's ConfigureAwait rule, same reason
dotnet_diagnostic.CA1812.severity = none        # DI-activated types look unused
dotnet_diagnostic.CA1062.severity = none        # nullable reference types cover it
dotnet_diagnostic.MA0097.severity = none        # Vogen value objects implement IComparable without operators
dotnet_diagnostic.MA0191.severity = warning     # on: stops null! and default!
dotnet_diagnostic.MA0053.severity = warning     # seal public classes too; CA1852 sees only internal ones
MA0053.public_class_should_be_sealed = true
dotnet_diagnostic.CA2254.severity = warning     # log message templates, never interpolation
csharp_style_namespace_declarations = file_scoped:warning
csharp_style_var_elsewhere = true:warning       # and the _for_built_in_types and _when_type_is_apparent keys
csharp_style_prefer_primary_constructors = true:warning
dotnet_style_prefer_collection_expression = when_types_loosely_match:warning
dotnet_diagnostic.IDE1006.severity = warning    # naming rules: _camelCase private fields; PascalCase const and static readonly
# tests/.editorconfig
dotnet_diagnostic.CA1707.severity = none        # behaviour test names use underscores
```

## The build

- **Turn on `Nullable`, `ImplicitUsings`, `TreatWarningsAsErrors` (src and
  tests), `AnalysisLevel=latest-all`, `EnforceCodeStyleInBuild` and `NuGetAudit`,
  with Meziantou and Roslynator as `GlobalPackageReference`s, on a `.slnx`.**
  `AnalysisMode` is redundant beside `AnalysisLevel`. `EnforceCodeStyleInBuild`
  stays on in every build, not only CI. KomputaAgents ran without analyzers and
  drifted from every rule here.
- **Treat these as enforced, and let the build error teach them**: one type per
  file (MA0048), 60-line methods (MA0051), sealing (CA1852, MA0053; the DbContext
  or a documented base class takes a pragma with its reason), `[LoggerMessage]`
  (CA1848), message templates (CA2254), token position and forwarding (CA1068,
  CA2016), `System.Threading.Lock` (MA0158), and no `new` or `default` value
  object (VOG009, VOG010).
- **A lint-rule disable or a preview pin gives its reason in place**: the
  `.editorconfig` comment, the `#pragma` comment, or a comment in the props
  file. Not an ADR.

## Packages

- **Central package management in `Directory.Packages.props`, with
  `CentralPackageTransitivePinningEnabled`.** NuGet resolves the lowest version a
  range allows, so the props file names a version, and the weekly job moves it:
  `dotnet outdated --version-lock Major --older-than 7 --upgrade`, then a PR. No
  version is bumped by hand, except for a security fix.
- **Commit lock files**: `RestorePackagesWithLockFile` in
  `Directory.Build.props`, and `dotnet restore --locked-mode` in CI.
- **`NuGetAudit` covers transitive packages**, so a new advisory fails restore.
  Bump the package to its first fixed version at once, in its own PR named for
  the advisory. Never lower `NuGetAuditMode` or suppress the warning to get
  green.
- **Only versions at least seven days old. Security fixes skip the wait.** The
  job's `--older-than 7` enforces the wait, and its first pass takes the fix of
  each package NuGetAudit names without it. When you add a package by hand, read the
  date in the NuGet gallery's version history.
- **The job never crosses a major version; it opens an issue instead.** No
  preview without a reason recorded in place.
- **Confirm on nuget.org that a new package is the intended one**: the publisher,
  the repository link and the release history.
- **Give each package family one version property** (Aspire.*, OpenTelemetry.*).
  Mixed versions fail at run time.

## Tools and the gate

- **Every .NET tool the gate runs is a local tool in
  `.config/dotnet-tools.json`, updated by the weekly job, and the repo commits a
  `nuget.config` that clears inherited sources.** Otherwise the workstation and
  CI run different checks, and a feed on one machine satisfies a restore the
  gate never sees.
- **Run `dotnet format --verify-no-changes` in the gate.**
- **Run slopwatch in the gate, plus a check for TUnit `[Skip]` and `[Explicit]`
  and for `.editorconfig` severity downgrades, which it does not read.** It
  catches the shortcuts an agent takes to go green: a disabled test, a
  swallowed exception, a suppressed warning.
