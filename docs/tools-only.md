# Tools-only pull requests

Some folders hold tooling: diagram generators, one-off scripts, utilities. They sit outside the shipped solution. A pull request that changes only those folders needs no solution build. It still needs the cheap checks.

`archive/herdr/scripts/check-tools-only` decides whether a pull request is tools-only. It exits 0 only then. The script is in the archive since 10 November 2026 with the other herdr scripts: this repo's check no longer runs its tests.

```text
check-tools-only --base <ref> --head <sha> [--repo <dir>]
```

## Using it in another repo

Copy `archive/herdr/scripts/check-tools-only` into the repo and call it from its CI.

## The list of folders

The repo keeps the list in `.tools-paths` at its root. Write one folder on each line. Blank lines and `#` comments are allowed.

```text
# tooling outside the solution
tools/
diags/
```

The check reads the list from the base side (the merge base of `--base` and `--head`). A pull request cannot add itself to the list. A pull request that changes `.tools-paths` is not tools-only.

## What the check refuses

The check exits 1 for each of these. It prints the first path and the reason.

- A path outside every listed folder. A rename or copy counts by both its old and its new path.
- A symlink or a submodule, old or new.
- A path with a `..` part, a leading `/` or a control character.
- An empty diff.

`tools/` does not match `tools-evil/x` or `Tools/x`. The check does not fold case.

The check exits 2 when it cannot decide: no `.tools-paths` on the base, an empty or malformed list (a byte order mark counts), or a ref it cannot read. A doubt is never a yes.

## How a repo's CI uses it

Run one gate job on every pull request. The gate job runs the cheap checks for tools folders too: lint, secret scan, shellcheck. Skip only the solution build, and only when `check-tools-only` exits 0.

Never put `paths-ignore` on a required workflow. A workflow that a path filter skips leaves its required checks pending. The pull request then cannot merge.

This GitHub Actions example runs the cheap checks always and builds the solution only when the pull request is not tools-only.

```yaml
name: ci
on:
  pull_request:
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<pinned sha>
        with:
          fetch-depth: 0
      - name: Lint, secret scan, shellcheck
        run: scripts/check.sh
      - name: Is this pull request tools-only?
        id: tools
        env:
          BASE: origin/${{ github.base_ref }}
          HEAD: ${{ github.event.pull_request.head.sha }}
        run: |
                    if archive/herdr/scripts/check-tools-only --base "$BASE" --head "$HEAD"; then
            echo "only=true" >> "$GITHUB_OUTPUT"
          else
            echo "only=false" >> "$GITHUB_OUTPUT"
          fi
      - name: Build the solution
        if: steps.tools.outputs.only != 'true'
        run: dotnet build --no-restore
```

The build step is the only step that the result skips. An exit 1 or an exit 2 both build. The `gate` job always starts, so a required check always reports.

## The stall watcher

The stall watcher is archived too (`archive/herdr/scripts/`). `stall-pr-gh` and `stall-pr-onedev` do not report "no build" for a tools-only pull request. Each runs `check-tools-only` with base `origin/<the PR's base branch>` and head the PR's head commit. When the head commit or the base is not in the local repo, or the base has no `.tools-paths` yet, the watcher fetches objects once for that pull request (`refs/pull/<n>/head` on GitHub, `refs/pulls/<n>/head` on OneDev, under the call timeout). It fetches only for a pull request with no build, never for a green or failed one. When the fetch fails, or the check cannot run, or says no, the pull request is reported as before. A failed tools-only pull request, and a green one that stays unmerged, are still reported.
