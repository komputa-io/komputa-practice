# React and Next.js

## Server state

- **TanStack Query does all data fetching in Client Components.** Never `fetch`
  in `useEffect`: the query cancels, dedupes and caches, and the effect does none
  of it.
- **A Server Component fetches the first load through the server entry, or
  prefetches it under `HydrationBoundary`. Each piece of data has one owner.**
  Rendered from both a Server Component and a query, the copies disagree after
  the first mutation.
- **React Context holds preferences only** (theme, locale, layout choices).
  Server data never goes in Context.

## Components

- **A component is a named `export function`, one per file**, with a default
  export only where Next requires one (`page`, `layout`, `error`). A default
  export takes whatever name its importer gives it.
- **One file per screen or component. The shell only loads them.**
- **Write React 19**: `ref` is a prop, and `<Ctx value={…}>` replaces
  `<Ctx.Provider>`. New code needs no `forwardRef`.
- **With the React Compiler on, add no `useMemo` or `useCallback`** unless an
  effect needs a stable dependency. Turning the compiler on is the project's
  call, because it costs build time.
- **A state machine in a component is a `kind` union and a pure reducer.**

## Next.js

- **Set `typedRoutes: true` in `next.config.ts`.** A bad `href` then fails the
  type check.
- **A Next container maps `app/alive/route.ts` and `app/health/route.ts`.** What
  they report is in `house-otel`.
- **A Server Action, route handler or Node use case is wrapped in one
  `withUseCase(name, fn)` function** over `@opentelemetry/api`, which records
  its span and duration (`house-otel`).

## Security headers

- **An app that a browser reaches sets one header policy for every response**,
  in the request middleware: a `Content-Security-Policy` with a nonce for each
  request on `script-src`, plus `base-uri 'none'` and `frame-ancestors 'none'`;
  `X-Content-Type-Options: nosniff`; and `Referrer-Policy`. No `unsafe-inline`
  and no `unsafe-eval` for scripts in production. `house-dotnet` holds the same
  policy for an ASP.NET host.
- **A nonce makes each page render on request.** For a page that must stay
  static, allow scripts by hash, not by nonce.
- **A test reads the headers** on a 200 and on an error page.
- **Never add `X-XSS-Protection`, `Expect-CT` or `Public-Key-Pins`.** Behind a
  proxy, let the proxy write HSTS.

