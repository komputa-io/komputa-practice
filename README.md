# Komputa Practice

This repo holds the practice that Komputa uses to build software with coding
agents. The default is one Claude Code session that plans, builds and merges
one pull request at a time. An agent that did not write the change verifies
each pull request that changes behaviour. The repo gives you the rules, the
hooks that refuse what must never run, the project template, and the evidence
behind each rule.

![A funnel of five layers that catch mistakes: codebase, static analysis, verification, prose and human review, with an arrow that moves each lesson up.](docs/quality-funnel.png)

## Documentation

The docs site is at [docs.komputa.io](https://docs.komputa.io). It is built
from this repo, so each page is also a file here:

| Start with | Page | File |
|---|---|---|
| What it is and why | [Introduction](https://docs.komputa.io/start) | `site/start/index.md` |
| Install it and make a first change | [Quickstart](https://docs.komputa.io/start/quickstart) | `site/start/quickstart.md` |
| Do a task with it | [Guides](https://docs.komputa.io/guides) | `site/guides/` |
| The ideas and the evidence | [Explanation](https://docs.komputa.io/explanation) | `site/explanation/`, `docs/` |
| Look something up | [Reference](https://docs.komputa.io/reference) | `site/reference/`, `rules/`, generated pages |

## Check

```sh
scripts/check.sh
```

It runs every check in this repo: the scrub check, shellcheck, shfmt, ruff and
the shell tests. CI runs the same command. To change the practice or its docs,
see [Contribute to the practice](https://docs.komputa.io/guides/contribute)
(`site/guides/contribute.md`).

## Credits

- [pstack](https://github.com/cursor/plugins/tree/main/pstack) is Lauren
  Tan's skill stack, under the MIT license. The playbooks, the model roles,
  `poteto-mode`, `swarm`, `interrogate` and `show-me-your-work` all come
  from pstack.
- The [Claude Code port of pstack](https://github.com/michael-denyer/pstack-claude)
  is by Michael Denyer.
- `hooks/block-dangerous-git.sh` starts from Matt Pocock's git-guardrails
  skill in [mattpocock/skills](https://github.com/mattpocock/skills), under
  the MIT license. We removed its block on a plain `git push` and added the
  pinned-lease rule for forced pushes.
- The quality funnel is our own drawing of a funnel by Lauren Tan (poteto).
- [herdr](https://releases.herdr.dev) provides `herdr-app` and `hc`. Our
  skill adds rules on top of herdr's own `hc --skill` and
  `herdr-app --skill` guides.

The rest of this repo is Komputa's own work, under the MIT license in
`LICENSE`.
