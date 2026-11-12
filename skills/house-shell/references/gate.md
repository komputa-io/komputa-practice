# The gate: tests, lint and layout

## Tests

- **Prove a repo's script harness can go red.** bats and Pester are not
  required, but a harness that has never failed has not shown it checks
  anything.
- **Fake a command with a stub script first on `PATH` that records its
  arguments.** Never Pester `Mock` or `Should -Invoke`: those are a mocking
  library. The stub is a fake at the boundary.

## shellcheck

- **Run shellcheck at its default severity, never with `-S warning`.** SC2086,
  the unquoted-expansion check, is severity info.
- **A repo with scripts has a `.shellcheckrc`**: `external-sources=true`,
  `source-path=SCRIPTDIR`, `enable=check-set-e-suppressed`, and in a new repo
  `enable=require-double-brackets`. shellcheck then follows `source`. The last
  line is for new repos only: it would put hundreds of findings on old ones.
- **A library whose variables its callers read gets one file-level
  `disable=SC2034`, with that reason.** Every SC2034 in it is false, and one line
  says so once.
- **Every other suppression gives its reason on the line**:
  `# shellcheck disable=SC2016 # reason`.

## shfmt

- **Format with a bare `shfmt -d .`, with its settings in an `.editorconfig`
  `[[shell]]` section**: `indent_style = space`, `indent_size = 2`,
  `switch_case_indent = true`, `binary_next_line = true`. A flag on the command
  line makes shfmt ignore the file, and `[*.sh]` misses `bin/` scripts.

## PowerShell

- **Lint with `Invoke-ScriptAnalyzer -Path . -Recurse -EnableExit`** and a root
  `PSScriptAnalyzerSettings.psd1` that enables PSPlaceOpenBrace,
  PSPlaceCloseBrace, PSUseConsistentIndentation and PSUseConsistentWhitespace.
  The default rules skip layout, and `Invoke-Formatter` rewrites but cannot
  check.
- **Decide `PSAvoidUsingWriteHost` once, in that settings file.** Any other
  suppression gives its reason in `SuppressMessageAttribute`'s `Justification`.

## Tool versions

- **shellcheck and shfmt come through the repo**: dev dependencies in a lock
  file (a repo's `scripts/gate.local.sh` can run them from `uv.lock`), refreshed by the
  weekly job, or `uvx --exclude-newer "7 days"`. The workstation and CI then run
  the same versions, and nobody bumps them by hand.
