# Data

```csharp
// Good (illustrative): named filters, so a bypass lifts only the one it names
modelBuilder.Entity<Workout>()
    .HasQueryFilter("Tenant", w => w.TenantId == tenant.Id)   // a DbContext member, so EF sends a parameter
    .HasQueryFilter("SoftDelete", w => !w.IsDeleted);
db.Workouts.IgnoreQueryFilters(["SoftDelete"])                // the one reviewed bypass; Tenant still applies
```

- **Change the schema only with `dotnet ef migrations add`, applied by a
  migration service the AppHost waits for (`WaitForCompletion`).** A hand-edited
  migration drifts from the snapshot, and an API that migrates on start races its
  own replicas.
- **Begin a transaction only inside
  `Database.CreateExecutionStrategy().ExecuteAsync(…)`.** Aspire's Npgsql EF
  integration retries by default, and a retrying strategy throws on a
  transaction started outside it. The strategy is then that call's one retry
  owner.
- **Name every global query filter. Lift one only through
  `IgnoreQueryFilters([name])` in one reviewed type.**
- **A consumer or hosted loop creates a scope, sets the scoped tenant from the
  message, then resolves the DbContext.** The tenant accessor throws when unset,
  so a missed set fails instead of returning nothing.
- **A Blazor Server page runs each handler call in a new scope**
  (`IServiceScopeFactory`), sets the scoped tenant from
  `AuthenticationStateProvider`, then resolves the handler. A circuit's scope
  lives as long as the browser tab, and one DbContext held across it goes stale
  and is not safe for overlapping calls.
- **NoTracking and SplitQuery are the context defaults**, with snake_case names
  from EFCore.NamingConventions. A write path calls `AsTracking()`. Never call
  `Update()` on an untracked entity.
- **A query slice projects with `Select`.** It never loads entities to map them.
- **Run a set change with `ExecuteUpdateAsync` or `ExecuteDeleteAsync`. End every
  list query in `Take(n)` or a keyed filter.**
- **Compose queries with extension methods on `IQueryable<T>`.** No
  specification library.
- **Hold one run per (tenant, resource) with `pg_try_advisory_xact_lock(key)`
  around the unit of work.** A lock already held is a logged skip.
- **When a service first publishes a message, save an outbox entity in the same
  `SaveChangesAsync` and publish it from a hosted loop** (or the chosen bus's EF
  outbox).
- **Timestamps come from the injected `TimeProvider`**, not
  `HasDefaultValueSql`, so tests control them.
- **Dapper or raw SQL only where EF cannot express the query**, inside that
  slice. Query filters do not reach Dapper or `ExecuteSql`, so it takes the tenant
  as a required argument.
