# Dry runs, twins, paths and processes

## Dry runs

```powershell
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Path, [switch]$Apply)
if (-not $Apply) { $WhatIfPreference = $true }   # each ShouldProcess now prints "What if:" and returns false
if ($PSCmdlet.ShouldProcess($Path, 'git rm')) { git rm -r --quiet -- $Path }
if (-not $Apply) { [Console]::Error.WriteLine("dry run; to apply: $PSCommandPath -Path '$Path' -Apply") }
```

- **A destructive or shared-state script defaults to a dry run that ends by
  printing the exact `--apply` command**: deletes, renames, migrations, anything
  on a server or the wiki. A mistyped run changes nothing, and what runs is what
  was reviewed.
- **An idempotent build, or a deploy to your own preview, acts by default and
  offers `-n, --dry-run`.** A wrong run there costs a re-run.

## Twins (.sh and .ps1)

- **Change both halves in the same commit**, or say in the commit message why
  the change is for one platform only.
- **Twins stop at the same points**: `set -Eeuo pipefail` pairs with `'Stop'`
  and the native-command preference, and `set -u` with `Set-StrictMode`. Bad
  arguments differ: pwsh's binder exits 1 before the script runs.
- **Keep twins thin.** Past about 100 lines, move the logic into the tool
  (`mytool install`) or into one `uv run --script` file that both call. Two copies
  of logic drift: one `install.ps1` missed ten features added only to its
  `install.sh`.

## Paths and configuration

- **The header says what the script does, how to call it, whether a re-run is
  safe, and which file is its twin.** A re-run is the first thing tried after a
  failure.
- **Find the repo from `${BASH_SOURCE[0]}` or `$PSScriptRoot`.** The caller's
  working directory can be anywhere.
- **Put scratch in `mktemp -d`, removed by `trap … EXIT`**, or in PowerShell by
  `try/finally`. Both run on Ctrl+C, and bash's trap on TERM too.
- **Read configuration at the top** as `${VAR:-default}` or
  `${VAR:?what to set}`. A missing value stops the script before any work.
- **Never put a secret on a command line or in a file.** Read it with
  `<secret-tool> <service> [field]` at the point of use.

## Network calls

- **Call HTTP with `curl -fsS --max-time N`, and run a slow command under
  `timeout`.** Without `-f`, a 500 exits 0.

## Processes

- **Stop a process by its PID or its unit, never by name or pattern.** Every
  session on the machine shares one process table, so `pkill -f`,
  `pkill <name>`, `killall` and `kill $(pgrep …)` reach other sessions'
  processes. On 2026-09-29 one killed another session's test run. A pattern can
  also match your own shell's command line and kill it.
- **Kill only a PID you have shown is yours**: from your own background task,
  or from `pstree -p` under your own shell. Stop a systemd unit you started with
  `systemctl --user stop <unit>`.
- **A wait loop never tests `pgrep -f <pattern>`.** The loop's own command line
  matches the pattern, so the wait never ends. Wait on the job's output file, a
  PID file, or `pgrep -x <name>`.
