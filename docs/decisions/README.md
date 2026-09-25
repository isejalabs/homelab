# Decisions

Lightweight Architecture Decision Records (ADRs) — one file per significant, non-obvious architectural
choice that's likely to be revisited later. This directory doesn't exist to record every choice made in the
repo, only ones where the *why* would otherwise be lost to git-log archaeology.

Introduced by [#1378](https://github.com/isejalabs/homelab/issues/1378) (the in-cluster authoritative DNS
work), itself following the recommendation in [`docs/audits/2026-09-documentation.md`](../audits/2026-09-documentation.md#f12--architecture-decisions-should-be-separated-from-current-state-documentation) —
this is the first real use of that recommendation, not a separate convention invented independently.

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
