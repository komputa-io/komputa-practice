# The boundary

Data that crosses into the program is `unknown` until it is parsed into a named
domain type. Inside, trust the types.

```ts
// Good (illustrative): failure is decided on the status, and the API module returns a Result
const { data, error, response } = await api.GET("/goals/{id}", { params: { path: { id } }, signal });
if (!response.ok || data === undefined) return { ok: false, error: toApiError(response, error) };
return { ok: true, value: data };
// Bad (acme, lib/api.ts): the error body is discarded and the cast trusts anything
if (!response.ok) throw new Error(`API request failed: ${response.status} ${response.statusText}`);
return (await response.json()) as T;
```

## Our own API

- **Generate our API's types with `openapi-typescript`, and run the generator
  with `--check` in the gate.** A spec change the client has not picked up then
  fails the build. Leave `--immutable` off: openapi-fetch's response types turn a
  readonly array's methods into `{}`.
- **Call our API through one `openapi-fetch` client.** It returns
  `{ data, error }` typed from the spec and does not throw on a 4xx.
- **Trust our API's generated types, with no runtime schema, only when the
  client ships with the server** (same repo, same release). A separately
  deployed API is outside data: parse it with zod.
- **The API module has a server entry and a browser entry on that client.** The
  server entry starts with `import "server-only"`, uses the internal base URL,
  and forwards the caller's cookie or token, because a server-side request
  carries none by itself. The browser entry sends credentials to the public URL.

## Data we do not own

- **Parse it with zod before use**: third-party APIs, `localStorage`,
  `postMessage`, the App Router's route `params` and `searchParams`, Server Action
  arguments, and `process.env` (once, in a `server-only` module). Each can hold
  anything at run time, whatever its type claims.
- **Write zod 4**: `z.email()`, not `z.string().email()`; `error`, not
  `message`; `z.strictObject`, a two-argument `z.record`, `z.treeifyError`.
  Agents write zod 3 from memory.
- **A Server Action is a public POST endpoint.** Parse its arguments, check auth
  inside it, and return a plain `Result`. Anyone can call it with any body, and a
  class instance does not survive the trip back. Add a Server Action only where
  the Next server holds the credential.

## Branded values

- **One brand shape everywhere**: `string & { readonly __brand: "GoalId" }`.
- **Each brand is declared once, with one parse function.** Where zod parses the
  value, produce the brand in `.transform()`; do not use zod's `.brand<>()`, a
  second shape that does not assign to the first.
- **Where later code needs a map's literal types, write
  `as const satisfies Readonly<Record<Union, X>>`.** The map stays exhaustive and
  keeps its literals.
