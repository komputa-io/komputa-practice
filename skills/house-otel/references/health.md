# Health, alerts, monitors and the front end

## Health endpoints

- **Map `/alive` and `/health` in every environment**, restricted by network, a
  host filter or Traefik. Never only in development, and never public.
- **`/alive` checks the process only, and the container `HEALTHCHECK` points at
  it.** Restarting the app never fixes its database.
- **`/health` checks each dependency with its own timeout, caches the report for
  about 10 seconds, caps the request at about 5, and returns a JSON body naming
  each check.** A probe then cannot hammer the database.
- **`/health` or a `/version` endpoint reports the project's semver.**
- **A probe matches the body, not only the status** (an Uptime Kuma keyword or
  JSON query). Authentik answers 200 with a login page.

## Alerts and dashboards

```text
Bad (acme, garmin-sync-failure-rate.json):  body LIKE '%Data sync failed for Garmin%'
Good:  usecase.duration count where usecase.outcome = "Failure", or logrecord.event.id = 2313
```

- **Alerts and dashboards query metrics or structured fields, never message
  text.** Reword the log line and a text alert computes 0/0 and never fires
  again.
- **Every alert says what "no data" means**: fire on absence, or compute a rate
  that cannot go 0/0. Staleness rules once selected zero series for seven weeks.
- **Performance budgets come from users and become alerts.**
- **Commit alerts, dashboards and monitors with the service**
  (`deploy/observability/`), and route every monitor. When audited, 47 of 77
  Kuma monitors notified nobody. Where an alert goes is in the homelab repo's
  notification routing page.
- **Prove an alert by making it fire.**

## Scheduled jobs

- **A scheduled job proves it ran by pushing** to its Uptime Kuma push monitor on
  success, so a missed push alerts by itself. A job that reports a last-success
  metric instead gets an alert that also fires when the series is absent.

## Front end

- **Default to server-side OTel, with an `error.tsx` per route segment that
  fetches, plus `global-error.tsx`.** Show the error `digest`, and offer
  `retry`.
- **Export `onRequestError` from `instrumentation.ts`, and log the digest with
  the trace ID**, so the digest a user quotes can be found in SigNoz.
- **Where we own both the front end and the API, one trace covers both.** The
  rules are in [telemetry.md](telemetry.md), "End-to-end traces".
