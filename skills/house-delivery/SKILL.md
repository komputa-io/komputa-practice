---
name: house-delivery
description: "The house rules for delivering software, on any forge or cloud. Use for any task that writes or changes a CI or CD pipeline or build spec (.onedev-buildspec.yml, azure-pipelines.yml, .github/workflows); pins a shared template, action or job image; runs helm upgrade or another release to Kubernetes; changes Terraform, OpenTofu or Bicep; names cloud resources; sets up build agents or runners; gives a deploy job its credentials; sets up a ZAP, Trivy, TruffleHog or Strix scan; or adds an SBOM or provenance. Covers immutable pins, a release that ends at the last good state, plan before apply, one artefact promoted by digest, short-lived deploy credentials, a fresh agent per job, scan findings as tracked work, where each security scan runs, and scheduled shutdown of non-production. Not for a shell script's own form, service health and alerts, or driving odev."
metadata:
  author: "Komputa"
  version: "0.1"
---

# House delivery

These rules hold on OneDev, Azure DevOps, GitHub, Kubernetes and Proxmox. A rule
that names one tool says so. Flags and product facts were read on 2026-11-06.

`house-architecture` holds versioning and dependency rules. `house-shell` holds
the form of a script in a pipeline step. `house-otel` holds health checks and
alerts.

Where any other installed skill says otherwise, this skill wins. A repo's
`AGENTS.md` or `CLAUDE.md` or an ADR wins over this skill for that repo. A
client's written standard goes in that repo's `AGENTS.md` or `CLAUDE.md` or an
ADR.

## What a pipeline pulls in

- **Pin what the pipeline fetches at run time to a ref that cannot move.** Use a
  full commit SHA for a third-party action or template. A protected release tag
  is enough only for a template you own. A tag elsewhere can be force-pushed.
  - GitHub: a workflow lockfile covers actions. Reference a reusable workflow by
    full commit SHA, because the lockfile does not cover it.
  - Azure Pipelines: always set `ref` on a repository resource. With no `ref`,
    the pipeline takes `refs/heads/main`.
  - OneDev: set a tag or commit as the import's revision.
- **A job moves the pins.** A pin is a lock entry, not a hand pin. The weekly
  dependency job proposes the new SHA in a PR and honours the seven-day wait
  (`house-architecture`). A pin with no job to move it goes stale.
- **Pin scanners the same way.** A security tool runs with the job's secrets. It
  is a supply chain risk like any other step.

## Build and promote

- **Build once. Promote the same artefact by digest.** Build in the first stage,
  then deploy that digest to each environment. Do not rebuild per environment.
  A tag can move. A digest cannot. Config comes from the environment.
- **A build runs in a fresh environment, and nothing survives to the next job.**
  Use the platform's per-job option: a container executor on OneDev, "Fresh agent
  every time" on Managed DevOps Pools, a just-in-time runner on GitHub. A release
  build and any job that holds a secret have no exception.
- **A mounted Docker socket is not isolation.** A job that can reach the host's
  daemon can reach the host. Do not give it to a job that holds a secret, or one
  that builds code from outside.
- **A cache must not change the output.** Key each cache on the lock file. Do not
  share a cache between trusted jobs and jobs that build outside code.
- **An artefact that leaves us carries an SBOM and signed provenance.** This means
  a package, image or installer that another party runs. The build platform signs
  the provenance, not a build step. Where the forge cannot, sign in a separate job
  that runs no project code, and do not claim SLSA Build L3. Verify it at deploy
  where the platform can. An internal service needs this only when its client's
  contract asks for it.

## Credentials

- **A deploy credential is short-lived, and only the deploy job can get it.** Use
  workload identity federation where the forge and cloud support it: OIDC on
  GitHub, a workload identity federation service connection on Azure DevOps.
  Restrict trust to the branch and environment, with no wildcard.
- **Where federation is not available, scope the secret.** Limit it to the deploy
  job on the protected branch. On OneDev, set job authorization on the production
  executor. Build code from outside with no deploy secret.

## Release to Kubernetes

- **A failed release ends at the last good state, and the pipeline goes red.**
  - Helm 4: `helm upgrade --rollback-on-failure --cleanup-on-fail --timeout <t>`.
    `--rollback-on-failure` sets `--wait=watcher`. Without it or `--wait`, Helm
    waits for hooks only. Size `--timeout` to the slowest rollout; the default
    is 5m.
  - `--atomic` is the deprecated Helm 3 name for that flag. Do not write it in a
    new pipeline. A pipeline still on Helm 3 keeps it until it moves. That move
    is due: Helm 3 security fixes end on 2026-11-11.
  - On a first install, `--rollback-on-failure` uninstalls the release.
  - Flux: use `.spec.upgrade.remediation`. Argo CD only inflates the chart with
    `helm template`, so Helm's flags do nothing there: use its own sync and health
    checks.
- **A rollback restores manifests, not data.** Every migration in a release must
  work with the previous version of the code (`house-architecture`: add, migrate,
  delete).
- **Capture the failure before the rollback removes it.** Keep the release's
  events and pod logs as job output.

## Infrastructure as code

- **Lint and scan each change on the PR**: the tool's format and validate, its
  linter, then a misconfiguration scanner. tfsec is now part of Trivy.
- **Show the plan on the PR. Apply the plan that was reviewed.** Use a saved
  `terraform plan` or `tofu plan`, or `what-if` for Bicep. What-if can report false
  changes, and cannot see template spec references, so read it as a prediction.
- **Write tests only for logic**: a module with conditions, loops or computed
  names. A test that repeats a flat config proves nothing.
- **`terraform test` and `tofu test` create real resources by default.** On the PR
  use `command = plan` or mock providers (Terraform 1.7 or later). Run real-resource
  tests on a schedule in a throwaway account.
- **Choose Terraform or OpenTofu once per estate, and record it in an ADR.**
  Terraform is under the Business Source License. OpenTofu is MPL 2.0.

## Names

- **Each estate has one naming pattern, in one place in code**: a module or
  shared locals that every resource uses. Validate it in the gate. A convention
  that lives only in a document drifts.
- **A name holds only what stays true.** Use type, workload and environment. Add
  region when the name must differ per region, and an instance number when there
  can be more than one. Most cloud names cannot change, so owner, cost centre and
  the like go in tags or labels.
- **Names carry no sensitive data**, and global names become public DNS.
- **Check the provider's limits.** Length, characters and scope differ per resource
  type. A storage account allows no hyphen.

## Non-production

- **A non-production environment billed by the hour has an owner and an off
  schedule.** Use the platform's own schedule or scale to zero first. A pipeline
  is the fallback. Skip this where the saving is less than the work.
- **Starting must be proven.** Run the wake-up on the schedule and check its
  health. Tell the alerts: an environment that is off is not an outage
  (`house-otel`).

## Dynamic scanning

- **An HTTP service with a non-production deployment gets a dynamic scan.** This
  rule does not apply to a library or a CLI. ZAP is the default. Its images are
  `zaproxy/zap-stable` and `ghcr.io/zaproxy/zaproxy:stable`.
- **The baseline scan runs on each deploy to non-production.** It is passive. Its
  spider runs for one minute by default and it reports every alert as WARN, so a
  pipeline with no rules file never fails. Commit the rules file, and give each
  IGNORE a reason.
- **The active scans run on a schedule, or before a release.** Full scan and API
  scan attack the target. Run them only on a non-production target you own, or
  have written permission to test. Give the API scan the OpenAPI file, and log in
  first where the service needs it.
- **A finding becomes one tracked issue.** A confirmed finding at the severity the
  rules file sets to FAIL opens an issue, deduplicated by rule and URL. A report
  that nobody opens is not a control.

## Security scanning

- **Each scan runs where its cost fits.**
  - On each PR, the gate runs Trivy over the lock files for known
    vulnerabilities in Python, TypeScript and .NET. Rust keeps `cargo deny`.
    The scan is cheap and gives the same result each time.
  - Each night, TruffleHog scans the whole git history with `--only-verified`.
    It is too slow for each PR, and a verified secret is a live one.
  - The `Security review` job runs Strix in source mode and the Cloudflare
    security-audit skill through `scripts/security-review.sh`. It is for a
    service or an app, and runs by hand and once a month. A run spends up to
    its `--budget` (default $40), and its results change from run to run.
- **Pin each scanner to an exact version at least seven days old.** Pin an
  image by digest. Check a downloaded binary by sha256, and by cosign where the
  project signs it. Never use a tag or `latest`. The reason: Trivy v0.69.4 to
  v0.69.6 were compromised in March 2026 (CVE-2026-33634). The `Security
  review` job keeps its pins in `scripts/security.pin`. The weekly dependency
  job does not move them: raise one by hand, in a PR, after you read what
  changed.
- **Strix runs on its own scan host.** Strix needs the Docker socket, and the
  job holds an LLM key. The Docker socket rule above forbids that pair on a
  shared agent. Use a VM, not a container: Strix runs exploit code that a model
  wrote. The host runs nothing else. Its egress reaches only the forge, the LLM
  API and the registries it pulls from. No server caps the key, so
  `--budget` is mandatory: the script passes it to Strix as `--max-budget` and
  to Claude Code as `--max-budget-usd`, and accepts only the models in
  `scripts/security.pin` that Strix can price.
- **Turn off each scanner's telemetry.** Set `STRIX_TELEMETRY=0` on every Strix
  run.
- **A finding becomes one tracked issue**, as in Dynamic scanning.
  `scripts/security-issues.sh` files each finding once, deduplicated by a
  fingerprint in the issue body.
- **The `Security review` job runs on `main` only.** Never run it on a pull
  request from outside. Its agents read the code that they scan. That code can
  carry a prompt injection, and the job holds the LLM key and the Docker socket.
  A branch can edit the job's own guard, so the guard is the secrets: limit them
  to the default branch (OneDev `odev secret set ... --branches main`; GitHub, an
  environment `security-review` that only the default branch can use). On GitHub
  the job runs on private repos only, and the `security` runner serves private
  repos only.
