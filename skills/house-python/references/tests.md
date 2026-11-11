# Tests

```toml
[tool.pytest]
strict = true
addopts = ["-m", "not integration", "--allow-hosts=127.0.0.1,::1"]
markers = ["integration: starts Docker or calls a real upstream"]
```

## Shape

- **pytest, hand fakes and `monkeypatch`. Never `unittest.mock`.** The
  HTTP-level fake is `responses` for requests, or `httpx.MockTransport`.
- **Name each test as a sentence that states the behaviour**:
  `test_exit_zero_does_not_turn_an_unreadable_run_into_a_pass`. A failure then
  reads as the broken promise.
- **One contract suite runs over the fake and the real client**, through a
  fixture parametrised on both, with the real case marked `integration`.
- **Property-based tests with Hypothesis** for calculations and parsers.

## Markers and the network

- **Mark integration tests `integration` under pytest's `strict = true`,
  deselected by default.** A misspelt marker is then an error, not a test in the
  wrong suite.
- **Block the network with `pytest-socket`, loopback allowed**:
  `--allow-hosts=127.0.0.1,::1`. A test reaches only what it started (a local
  server, a headless browser) and nothing outside. `--disable-socket` is too
  strict: it blocks a test's own local server. Lift the block only for
  `-m integration --force-enable-socket`.
- **A database test runs on the production engine through testcontainers**,
  pinned to production's major version. Postgres: a migrated template database
  copied per test class. SQLite: a temp file.

## Async and CLIs

- **Write async tests with anyio's `@pytest.mark.anyio`, one async plugin per
  repo.** anyio already ships with FastAPI, FastMCP and httpx.
- **Test a click CLI with `CliRunner` and `tmp_path`, asserting `stdout` and
  `stderr` apart.** `isolated_filesystem()` changes directory, which is not
  thread-safe.
- **Each CLI command's `--json` output has a contract test.**
