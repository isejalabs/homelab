# Decisions

Lightweight Architecture Decision Records (ADRs) — one file per significant, non-obvious architectural choice that's likely to be revisited later. This directory doesn't exist to record every choice made in the repo, only ones where the *why* would otherwise be lost to git-log archaeology.

Introduced by [#1378](https://github.com/isejalabs/homelab/issues/1378) (the in-cluster authoritative DNS work), itself following the recommendation in [`docs/audits/2026-09-documentation.md`](../audits/2026-09-documentation.md#f12--architecture-decisions-should-be-separated-from-current-state-documentation) — this is the first real use of that recommendation, not a separate convention invented independently.

## When to add one, and when not to

Write an ADR when a choice is both non-obvious and likely to be revisited, and nothing else already captures the *why* durably. A decision that's already explained in a dedicated, actively-maintained architecture doc (e.g. [`storage.md`](../architecture/storage.md)'s "Choosing between them" section) doesn't need a second copy here — moving it would only risk the two drifting apart, the exact duplication problem linking (below) exists to avoid. A settled choice nobody expects to revisit (an old migration, a dropped approach) belongs in the root README's history instead, not here — this directory's own `likely to be revisited` bar specifically excludes it.

## Linking conventions

An architecture/reference doc whose content depends on a decision links to that decision's ADR instead of restating the reasoning (e.g. [`network.md`](../architecture/network.md) linking to 0001/0002, [`repositories.md`](../architecture/repositories.md) linking to 0003) — the ADR is the one place the *why* lives. The reverse link (an ADR pointing back to the architecture doc with the current-state detail) is useful too where one exists, as 0001's Context section already does for `network.md`, but isn't required when there's no single obvious doc to point to.

## Format

Each ADR is `NNNN-short-title.md`, numbered sequentially, with:

```markdown
# Title

## Status
current | planning | superseded

## Context

## Options considered

## Decision

## Consequences
```

## Index

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-powerdns-as-dns-server.md) | PowerDNS as the in-cluster authoritative DNS server | current |
| [0002](0002-tsig-over-ip-acl-for-axfr.md) | TSIG over IP-ACL for AXFR and dynamic-update authorization | current |
| [0003](0003-repository-and-tool-boundaries.md) | Repository and IaC tool boundaries | planning |
| [0014](0014-checkmk-configuration-as-code.md) | Checkmk configuration as code: Terraform provider, Ansible deferred | current |
