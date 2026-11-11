---
required: Why, Test plan, Verification
large-required: Change outline
large-production-lines: 300
large-slices: 3
slice-roots: Features, features, src/features, app
contract-paths: **/migrations/**, **/*.sql, **/openapi*.json, **/openapi*.yaml, **/*.proto
not-production: **/tests/**, **/test/**, **/*_test.go, **/*.test.ts, **/*.spec.ts, **/test_*.py, **/*_test.py, **/*.lock, **/uv.lock, **/package-lock.json, **/pnpm-lock.yaml, **/generated/**, **/*.g.cs
---
## Why

<!-- The problem and the approach, in one to three short sentences. -->

## What changed

<!-- One to three short bullets. Name a symbol or path only when it carries the change. -->

## Scope

<!-- What this covers, and what it deliberately leaves out. -->

## Test plan

<!-- The seams under test, one line per behaviour, and what is not tested and why. -->


## Change outline

<!-- Required for a big or complex change (odev pr template says when). Up to three
small views: a diff of the changed contract or data structure, pseudocode or a
call tree for the logic, a shallow file tree of changed responsibilities. -->

## Tradeoffs

<!-- Only the rejected alternatives a reviewer would ask about. Delete if none. -->

## Blast Radius

<!-- One or two sentences: who or what this touches, and why that is safe or risky. -->

## Verification

<!-- One to three bullets, each a real run and its result. -->
