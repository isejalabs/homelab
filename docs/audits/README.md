# Audits

Dated, point-in-time assessments — not current-state documentation, not a task tracker. Per [`docs/README.md`](../README.md#where-a-new-doc-belongs)'s conventions: written once, never edited after the fact; a later pass is a new audit file, not a rewrite of an old one. The label is implicit from this folder — everything here is `audit`, never `current` (see [`docs/README.md`](../README.md#status-labels)).

## Format

No rigid template — but every audit starts with the same YAML front matter, at the very top of the file before the title, e.g.

```markdown
---
date: 2026-09-22
status: Assessment complete for planning; live validation pending
scope: what this audit covers, and explicitly what it doesn't
origin: who or what produced the pass
tracking: "[#1336](https://github.com/isejalabs/homelab/issues/1336)"
---

# Title
```

Keys are lowercase, one per line, each value on a single line (quote it when it contains `: ` or starts with a backtick, `[` or a quote; the front matter is parsed as YAML). Values are Markdown: links and code spans work on the [documentation site](../README.md#documentation-site), which shows the front matter as a block below the page title. github.com shows it as a plain key/value table, where a link is likely to appear as its Markdown source, so keep long prose and anything a reader must be able to click in the body.

- `date` — always include; the whole point of an audit is that it's a snapshot in time. A plain `YYYY-MM-DD`; write extra context after it as text, e.g. `2026-10-19 (measurements), 2026-10-20 (write-up)`.
- `status` — free text here, not the `current`/`planning`/`historical`/`audit` vocabulary from [`docs/README.md`](../README.md#status-labels) — that vocabulary classifies which category of truth a *doc* belongs to, and an audit is always `audit` by definition, which the site takes from this folder. This field instead says how complete the assessment itself is (e.g. "partial," "in progress," "superseded by \<later audit\>").
- `scope` — what's covered, and what explicitly isn't, so a reader doesn't assume completeness that wasn't claimed.
- `origin`, `tracking`, `reviewed` — used where relevant: who/what produced the pass (e.g. a specific AI agent, read-only SSH access), which issue it's for, or a later re-confirmation date. Any other key (`repository`, `current-state`, `preceding-record`, ...) is shown the same way; the site prints it in file order with the key as its label.

Filename: `YYYY-MM-<short-topic>.md`, with an `-claude`/`-codex`-style suffix when more than one independent pass exists for the same topic (e.g. the two `2026-09-observability*.md` audits, produced independently for comparison) — see the existing files for worked examples rather than inventing a new scheme.

[`data/`](data) holds raw measurement files (e.g. NVMe write-delta baselines, bucket-policy dumps) that back a specific audit's numbers — same never-edited-after-the-fact rule applies.

## Cadence

No fixed calendar schedule — scheduling audits for their own sake tends to produce audits nobody reads, and cuts against the "no bureaucratic overhead" goal `docs/README.md`'s "Keeping this current" convention already settled on. Trigger a new audit instead when:

- a phase of related work is about to substantially change an area, the way the Sep 2026 documentation audit kicked off the whole documentation-improvement journey, or
- something feels like it's drifted and a full re-read is genuinely the only way to find out, rather than another targeted fix.

## From findings to issues

Every audit here fed the same pattern: one umbrella tracking issue referencing the audit, broken into phased/area sub-issues, each closed by a real PR — see [#1336](https://github.com/isejalabs/homelab/issues/1336) and its phase sub-issues ([#1352](https://github.com/isejalabs/homelab/issues/1352), [#1355](https://github.com/isejalabs/homelab/issues/1355), [#1356](https://github.com/isejalabs/homelab/issues/1356), [#1354](https://github.com/isejalabs/homelab/issues/1354)) for the worked example this doc is drawn from. A finding that's small and self-contained can skip the umbrella and go straight to one focused issue; reserve the full phased structure for a genuinely multi-phase effort.
