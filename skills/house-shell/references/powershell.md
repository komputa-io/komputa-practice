# PowerShell

```powershell
#Requires -Version 7.4

<#
.SYNOPSIS
  Build odev from main and install it on PATH. Twin of install.sh; keep the two in step.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true   # a non-zero exit throws, like set -e
if (& { $PSNativeCommandUseErrorActionPreference = $false; git diff --quiet; $LASTEXITCODE -ne 0 }) { throw 'uncommitted changes' }
```

- **Give every script that header, in that order**, with `param()` even when
  empty, and help that mirrors the `.sh` usage and names the twin. Below 7.4 the
  native-command line is inert. Without the blank line, `Get-Help` finds no
  help. `Latest` in place of `3.0` changes meaning between releases.
- **Read `$LASTEXITCODE` only where a non-zero exit is an answer**
  (`git diff --quiet`, `grep`), inside `& { }` with the preference off, as on the
  last line. Everywhere else the preference throws, in captures, conditions and
  pipelines too.
- **Keep stdout for data.** Leave through `throw`, and write messages with
  `[Console]::Error.WriteLine()`. `throw` goes to stderr and exits 1, like
  `die()`. `Write-Host` goes to stdout.
- **Under StrictMode, count with `@(…).Count`, and read an optional key as
  `$h['key']`.** `.Count` on a lone result throws, and so does `$h.key` for a
  missing key.
