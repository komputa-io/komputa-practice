---
title: Versioning
description: The one-version rule, what the gate refuses, how to derive copies, and how a release tag is made.
---

Every project has one semver version. The repo holds it in one place. CI tags each release. The running program shows it.

## What the gate refuses

`scripts/version-check.sh` runs in the shell section of `scripts/gate.sh`, in every project. It reads these declarations in the tracked files:

| Language | Declaration |
|----------|-------------|
| Python | `pyproject.toml` `[project] version`, and a literal `__version__ = "…"` in a `.py` file |
| JavaScript | `package.json` `"version"` |
| Rust | `Cargo.toml` `[package]` or `[workspace.package]` `version` |
| .NET | `<Version>` in `Directory.Build.props` or a `.csproj` |
| Any | a `VERSION` file |

A derived version is not a declaration: a `dynamic` pyproject version, `version.workspace = true`, and a read of the installed package.

The check fails when:

- a literal `__version__` exists in Python source;
- two declarations disagree (it names each path and value);
- a version is not semver: `MAJOR.MINOR.PATCH`, with an optional `-pre-release`;
- the project declares no version.

Equal copies pass. The check keeps them from drifting, and each message says how to derive them instead. A repo of content only (notes, docs) answers `versioned: false` to `copier update`. It then has no check, no tag job and no seeded `VERSION` file.

## Derive a copy

- **Python.** Keep the version in `pyproject.toml`. Read it at run time: `from importlib.metadata import version; __version__ = version("<package>")`. For a version taken from git tags, use a Hatch or uv dynamic version: `dynamic = ["version"]`.
- **Rust.** Set `version` once in `[workspace.package]`, and `version.workspace = true` in each member.
- **JavaScript.** Keep `package.json` as the source. Read it where the program needs it (a JSON import or the build tool's define), not a copy.
- **.NET.** Set `<Version>` once in `Directory.Build.props`.
- **No manifest** (shell, content): a `VERSION` file. The template seeds it with `0.1.0` when the project has no Python.

## Show it at run time

A UI footer or about page, `--version`, `/version`, or a field in `/health`. The value comes from the one source.

## Tags

The job `Tag release` (OneDev) or the workflow `tag-release.yml` (GitHub) runs `scripts/tag-release.sh` on each push to the default branch. It creates the annotated tag `v<version>` at that commit when the remote has no such tag. It never moves, deletes or replaces a tag: with a tag at another commit, it prints the fact and leaves it. Bump the version to make a release.

- **OneDev** uses the job secrets `ONEDEV_USER` and `ONEDEV_TOKEN` that `Update dependencies` already uses. The account must be allowed to push a tag. No new secret.
- **GitHub** uses the workflow's `contents: write` permission.

`copier update` adds the job to an older project's build spec. The gate's CI pattern check then keeps it there.
