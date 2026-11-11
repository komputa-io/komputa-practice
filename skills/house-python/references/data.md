# Data access

- **SQLAlchemy 2.0.** Use the typed ORM (`Mapped[...]`, `mapped_column`) for a
  relational domain, and Core (`select`, `insert`) for a query-shaped store.
- **The entities and value types are frozen dataclasses in a `domain` package
  that imports no I/O** (no `sqlalchemy`, `httpx`, `fastapi`). The ORM classes
  live in the data-access package and map to and from them, the same way
  pydantic stays at a wire boundary. The use cases and the data access both
  import `domain`; `domain` imports neither.
- **An import contract holds it.** Add `import-linter` to the dev group and a
  `.importlinter` with a `forbidden` contract from `<package>.domain` to the
  data-access package and the I/O libraries
  (`include_external_packages = True`). The full gate runs `lint-imports` when
  the file exists.
- **Plain `sqlite3` for a few small tables** with no relations worth mapping.
- **Not the Django ORM outside Django, and not SQLModel.**
- **Do not migrate an existing app to these choices** just to follow the rule.

## Slices and stores

- **With the ORM, the handler uses the session directly.** Without it, each
  slice has one store module (`store.py`) that holds queries, not rules.
- **A query slice selects the columns it returns.** It does not load ORM objects
  to map them.

## Tenant and user isolation

- **One global filter on the session**: a `do_orm_execute` event that adds
  `with_loader_criteria(Entity, lambda e: e.owner_id == current_owner())` to
  every select. Without the ORM, the store's functions take a required
  `owner_id` argument.
- **A bypass lifts only the filter it names**, through one named, reviewed
  function.
- **`text()` and Core statements skip the filter**, so they take `owner_id` as a
  required argument. The database holds the final boundary (`house-architecture`).
- **Test it**: user A cannot see, change or delete user B's rows.

## Writes

- **Make every write safe to repeat**: an upsert on a natural key
  (`insert ... on conflict do update`), or a guard that returns an
  `AlreadyExists` case.
- **Timestamps come from an injected clock**, not a database default, so tests
  control them.
