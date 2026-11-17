---
title: Running services
description: Every service the practice runs on a workstation runs the release export, never a working checkout.
---

Every service or timer that the practice runs on your workstation runs from
one place: the release export, `~/.sitrep-live/runner/current`. It does not run
from a working checkout, and it does not follow `main`.

The export is a copy of the build that the Sitrep Live hub runs. There is one
folder for each build, and `current` is a symlink to the live one. The runner,
the herdr agent, the codex reporter, the plugins and the [watcher](/explanation/the-watcher)
all run from it. `exportRunner` in `app/scripts/install.ts` makes it.

## How a change reaches a service

1. Deploy the release to the hub with `app/scripts/deploy-remote.sh`.
2. Run the workstation install again. It exports the build the hub now runs and
   points `current` at it.

A service follows a deploy only when the install runs. To roll back, point
`current` back at the earlier build folder.

## Add a new service

Run it from `~/.sitrep-live/runner/current`, with a path that goes through
`current`. Do not give it a clone of its own, and do not point it at a working
checkout. Its install command refuses to run when the export is missing.

## Why

A service that runs from a working checkout runs whatever that checkout holds.
On 17 Nov 2026 the watcher ran from the working checkout. The checkout sat
detached at an old commit, so merged fixes did not run. The first fix
([#392](https://github.com/komputa-io/komputa-practice/pull/392)) gave the
watcher a clone that follows `main`. That was no better: `main` is not the
release, and every other service ran the export. One rule for every service
means none of them drifts onto stale or unreleased code.
