---
name: house-typescript
description: "The house rules for TypeScript, React and Next.js. Use for any TypeScript or JavaScript task in our repos: writing, changing or reviewing .ts or .tsx code, React components, Next.js pages, Server Actions or route handlers, data fetching with TanStack Query, calling our API, vitest or Playwright tests, or package.json, tsconfig and ESLint changes such as adding or bumping a dependency. Covers openapi-fetch and zod at the boundary, one Result and ApiError, branded values, React 19, MSW, the 7-day release age and install-script approval. Not for language-neutral design questions."
metadata:
  author: "Komputa"
  version: "0.1"
---

# House TypeScript

This skill gives the TypeScript form of `house-architecture`, for the front end
and for Node services. It does not repeat that skill's rules or reasons.
`house-otel` holds what a service and a browser emit.

Where any other installed skill says otherwise, this skill wins. A repo's
`AGENTS.md` or `CLAUDE.md` or an ADR wins over this skill for that repo.

Common defaults from other skills, examples and training. Where one shows the
left side, write the right side:

| A skill or example shows | Write instead |
|---|---|
| `fetch` then `(await res.json()) as T` | The generated `openapi-fetch` client, or zod for outside data ([boundary.md](references/boundary.md)). |
| A runtime schema for our own API shipped with the client | Generated types only. A separately deployed API is parsed with zod. |
| `if (error)` after an openapi-fetch call | Decide failure on `response.ok`. |
| `throw new Error(...)` for an expected failure, in any module | Return a `Result` with a kind ([failures.md](references/failures.md)). Our API's failures are one `ApiError`. |
| `undefined` or `null` for a lookup that can miss | A `Result` with a `not-found` kind. |
| zod 3 (`z.string().email()`, `message`) | zod 4 (`z.email()`, `error`). |
| zod `.brand<>()` | One `readonly __brand` shape, produced by a parse function or zod `.transform()`. |
| `fetch` in `useEffect` | TanStack Query in a Client Component. |
| Business logic in a route handler, a Server Action or a component | The API's use cases, called through the generated client. A Server Action is a thin adapter over that call. |
| React Context for server data | TanStack Query. Context only for preferences such as theme or locale. |
| `forwardRef`, `<Ctx.Provider>` | React 19: `ref` as a prop, `<Ctx value={…}>`. |
| `useMemo` and `useCallback` everywhere | None with the React Compiler on, unless an effect needs a stable dependency. |
| `vi.mock`, `vi.fn`, `vi.spyOn` | MSW at the HTTP level, or a hand fake. |
| `interface`, `enum`, `namespace` | `type`, a union of string literals, a module. |
| `@modelcontextprotocol/sdk` | `@modelcontextprotocol/server`. |
| A new dependency at its latest release | One at least seven days old, with its install script approved ([tooling.md](references/tooling.md)). |

## References

- [boundary.md](references/boundary.md): our API, outside data, zod 4,
  Server Actions, branded values.
- [failures.md](references/failures.md): `Result`, `ApiError`, TanStack
  retries, timeouts and aborts.
- [react.md](references/react.md): React 19, Next.js, TanStack Query, state,
  security headers.
- [tests.md](references/tests.md): vitest, MSW, Playwright, contract suites.
- [tooling.md](references/tooling.md): dependencies, tsconfig, ESLint, the
  gate, Node scripts.

## Short rules that apply everywhere

- `type` over `interface`. No `any`; outside data is `unknown` until parsed.
- No `!` or `as T` on outside data. A brand's one parse function may cast, with
  an ESLint disable that gives its reason.
- A component is a named `export function`, one per file. A default export only
  where Next requires one (`page`, `layout`, `error`).
- Money is integer minor units or a decimal library, never a JavaScript
  `number` with fractions.
- A comment keeps only what the code cannot say.
