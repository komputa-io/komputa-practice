---
name: house-shell
description: "The house rules for Bash and PowerShell scripts. Use whenever a shell script is involved: writing, fixing or reviewing a .sh, .bash, .ps1 or bin/ script (including reviewing one before it runs on a server, or one that carried on after a command failed); install, deploy, backup, clean-up and migration scripts that delete, rename or move things across repos or hosts; Claude Code hooks; CI steps; a .sh and .ps1 pair; shellcheck, shfmt or PSScriptAnalyzer setup. Covers the strict-mode header, exit codes, dry runs by default, twins in step, temp files and traps, killing by PID, stub tests, lint and format."
metadata:
  author: "Komputa"
  version: "0.1"
---

# House shell

This skill gives the script form of `house-architecture` and `house-otel`. It
does not repeat their rules or reasons.

Where any other installed skill says otherwise, this skill wins. A repo's
`AGENTS.md` or `CLAUDE.md` or an ADR wins over this skill for that repo.

**A script a generator wrote, and marks as generated, is exempt.** Regenerate it;
do not hand-edit it to meet these rules.

## The rules in one screen

**Bash** ([references/bash.md](references/bash.md))
- Open with `set -Eeuo pipefail`, `shopt -s inherit_errexit` and an `ERR` trap
  that names the failing line. Drop `-e` only on purpose, with a comment.
- Exit 1 through `die()` on an error and 2 with usage on misuse, both to
  stderr. A Claude Code hook never exits 2 for misuse: there, 2 means block.
- Every exit path names its reason. A silent script and a missing one look the
  same.

**Hooks** ([references/hooks.md](references/hooks.md))
- Judge the folder the command names (`cd X`, `git -C X`) before payload `cwd`.
- Deny to change a call; `additionalContext` arrives after it ran.
- Set `"onFailure": "block"` on every gate: a hook that cannot start fails open.
- Under Codex, a write gate parses `apply_patch` from `tool_input.command`.

**PowerShell** ([references/powershell.md](references/powershell.md))
- `#Requires -Version 7.4`, help, `[CmdletBinding()]`, `param()`,
  `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'` and
  `$PSNativeCommandUseErrorActionPreference = $true`, in that order.
- stdout is for data. Leave through `throw`; write messages to stderr.

**Safety** ([references/safety.md](references/safety.md))
- A destructive or shared-state script defaults to a dry run that ends by
  printing the exact command to apply.
- A `.sh` and `.ps1` pair changes in the same commit and stops at the same
  points. Past about 100 lines, the logic moves into a tool both call.
- Scratch goes in `mktemp -d`, removed by `trap … EXIT` (`try/finally` in
  PowerShell).
- Stop a process by its PID or its unit, never by name or pattern.
- Every network call has a timeout: `curl -fsS --max-time N`, or `timeout`.

**The gate** ([references/gate.md](references/gate.md))
- shellcheck at its default severity, shfmt with settings in `.editorconfig`,
  PSScriptAnalyzer with layout rules on. All run through the repo, never a
  global install.
- Fake a command with a stub script on `PATH`, never Pester `Mock`.
- Prove the script harness can go red.
