# Domain types

```csharp
// Good (illustrative): Domain, validated once; the analyzer rejects `new GoalId()` and `default`
[ValueObject<long>]
public readonly partial struct GoalId;
[ValueObject<decimal>]
public readonly partial struct Kilograms
{
    private static Validation Validate(decimal value) =>
        value is > 0 and < 500 ? Validation.Ok : Validation.Invalid("Weight must be between 0 and 500 kg.");
}
```

- **Every entity ID and every domain value with rules is a Vogen
  `[ValueObject<T>]` on a `readonly partial struct`.** Vogen generates the JSON
  and type converters and `IParsable`. Raw input becomes one through `TryFrom` at
  the edge, mapped to an ErrorOr validation error. VOG009 and VOG010 reject `new`
  and `default`.
- **Register Vogen's EF converters once**: `[EfCoreConverter<GoalId>]` on an
  `internal sealed partial class VogenEfCoreConverters` in Infrastructure, and
  `RegisterAllInVogenEfCoreConverters()` in `ConfigureConventions`.
- **An entity with rules has private setters, a private constructor for EF, and
  methods that return `ErrorOr<Success>`.** For example, `goal.End(on)` returns
  `Error.Validation` when `on` precedes `StartsOn`. An entity with no rules is a
  plain record.
- **A predicate needed both in SQL and in memory is a static
  `Expression<Func<T, bool>>`** in `<Entity>Predicates` (`GoalPredicates.ActiveOn(day)`).
  EF translates it, and `.Compile()` reuses it in memory. Test it against the
  real database: C# string equality is ordinal, the database uses its collation.
  Any other query rule is an `IQueryable<T>` extension method.
- **An enum that needs behaviour is a SmartEnum** (a status that knows its
  allowed transitions). Store a plain enum as a string, so reordering members
  cannot change stored data.
- **A state machine is closed states as sealed records and a pure `Apply`.**
- **The Domain project references Vogen and ErrorOr and nothing with I/O** (no
  EF Core, ASP.NET Core or HTTP client), so the compiler refuses I/O there. Pure
  calculations are static classes in Domain. An app with a database always has
  a Domain project, for its entities and value types.
