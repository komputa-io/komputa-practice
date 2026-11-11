# Tests

- **vitest for a unit; vitest Browser Mode, or jsdom with Testing Library, for a
  component; Playwright for a journey or an async Server Component.** vitest
  cannot render an async Server Component.
- **While you work, check the UI with agent-browser.** It is faster and needs no
  test code, but it leaves nothing that runs again. A journey worth keeping
  becomes a Playwright test, because only a committed test runs in CI.
- **`vi.mock`, `vi.fn` and `vi.spyOn` are a mocking library, and the house rules
  them out.** They ship inside vitest, so they look allowed.
- **Fake our API at the HTTP level with MSW**, typed from the generated schema,
  and start it with `onUnhandledRequest: "error"`. A request nothing handles then
  fails the test instead of reaching the network.
- **Control time with `vi.useFakeTimers()` and `vi.setSystemTime()`.** The clock
  is a seam, not a collaborator.
- **One contract suite runs over the MSW fake and the real API with
  `describe.each`**, the real case only in the integration run.
- **Property-based tests with fast-check** for calculations and parsers.
- **Test names describe behaviour**: `it("records the volume of a completed
  workout")`.
