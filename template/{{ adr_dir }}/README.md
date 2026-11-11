# Architecture decision records

Record a decision here only when all three hold:

1. It is hard to reverse.
2. It would be surprising without context.
3. It was a real trade-off between options.

One file per decision: `NNNN-short-title.md`, numbered in order.

```markdown
# NNNN. Short title

Date: YYYY-MM-DD

## Context
What forced a decision, and the options that were on the table.

## Decision
What we chose, in one or two sentences.

## Consequences
What becomes easier, what becomes harder, and what would make us revisit it.
```

A reversed decision gets a new ADR that names the old one. The old one stays,
with a line at the top pointing to its replacement.
