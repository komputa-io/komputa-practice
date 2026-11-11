# Tooling, dependencies and the gate

## Dependencies

- **Take `^` ranges, commit the lockfile, and install in CI with `npm ci`**
  (pnpm: `--frozen-lockfile`). CI then builds what was tested.
- **Hold every release seven days**: `min-release-age=7` in `.npmrc`, or
  `minimumReleaseAge: 10080` in `pnpm-workspace.yaml`. The units differ: npm
  counts days, pnpm minutes.
- **Let a security fix through, then remove the entry**:
  `min-release-age-exclude[]=<pkg>` in `.npmrc`, or `<pkg>@<version>` under
  `minimumReleaseAgeExclude`. Take a Next or React security release within days
  this way; a `^` range picks it up only when someone reinstalls.
- **Run a dependency's install script only once approved.**
  `npm install-scripts approve <pkg>` writes `allowScripts` in `package.json`,
  and `strict-allow-scripts=true` fails the install on an unreviewed one. pnpm's
  list is `allowBuilds`, written by `pnpm approve-builds`; it ignores the older
  `onlyBuiltDependencies`. An install script runs with your credentials the
  moment it lands.
- **A weekly job runs `npm update` within the ranges and opens a PR.** The
  lockfile holds the exact versions. The job never crosses a major; it opens an
  issue.
- **The React Compiler (`babel-plugin-react-compiler`) has an exact version in
  `package.json`, moved only by the weekly job.** Its output changes between
  patches, so each bump arrives as its own reviewed PR.

## Compiler and lint

- **Set `strict`, `noUncheckedIndexedAccess`, `erasableSyntaxOnly` and
  `verbatimModuleSyntax` in `tsconfig`.** The last two refuse `enum`, a runtime
  `namespace` and a constructor parameter property, and keep type-only imports
  visible to Node, which strips types.
- **Run `tsc` on the native compiler and give typed ESLint the previous API**:
  `npm install -D @typescript/native@npm:typescript typescript@npm:@typescript/typescript6`.
  The native build has no API yet; drop the aliases once typescript-eslint's peer
  range admits it.
- **Point openapi-typescript at that alias**:
  `"overrides": { "openapi-typescript": { "typescript": "$typescript" } }`. Its
  peer range lags, and npm refuses the install without it.
- **Lint with `eslint-config-next/core-web-vitals` and typescript-eslint
  `recommendedTypeChecked`, plus by name**: `no-non-null-assertion`,
  `switch-exhaustiveness-check`, `consistent-type-definitions: ["error", "type"]`,
  `no-unsafe-type-assertion`, `max-lines-per-function` (60) and eslint-comments
  `require-description`. They hold the short rules in `SKILL.md` and a reason on
  every disable.
- **Hold slice boundaries with `eslint-plugin-boundaries` or
  `dependency-cruiser`.**

## The gate

- **Gate on `tsc --noEmit`, `eslint --max-warnings 0`, `prettier --check`,
  `openapi-typescript --check` and `vitest run`**, with the generated schema in
  the ESLint and Prettier ignores. Prettier owns layout; the generator emits its
  own layout, so `--check` is that file's gate.

## Node scripts and MCP servers

- **Run a Node script's or MCP server's `.ts` directly under Node's type
  stripping**, with Node's recommended `tsconfig` plus `"types": ["node"]`. There
  is no build step to keep, and `types` now defaults to empty.
- **Build an MCP server on `@modelcontextprotocol/server`, not
  `@modelcontextprotocol/sdk`.** The older package is the previous major, and
  agents reach for it from memory.
