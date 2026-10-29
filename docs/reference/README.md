# Reference

Authoritative current-state factual material — specific values, tables, and inventories — kept separate from the conceptual/architectural doc that explains *why* those values are what they are. This directory doesn't exist to duplicate `architecture/`'s explanations, only to hold the dense, independently-scannable lookup tables that would otherwise force a reader through prose to reach a single fact.

## Index

| Doc | Status | Covers |
| --- | --- | --- |
| [`environments.md`](environments.md) | current | per-environment sizing, Flux interval, domain/naming schemes, and the ID/ASN/LB-pool/API-VIP tables — the conceptual side is [`architecture/environments.md`](../architecture/environments.md), split per [#1350](https://github.com/isejalabs/homelab/issues/1350) |
| [`monitoring-sites.md`](monitoring-sites.md) | current | Checkmk containers and sites, their monitoring roles, and representative live host assignments |
| [`monitoring-notifications.md`](monitoring-notifications.md) | current | per-site Checkmk notification settings (delay, period), what is noise vs signal in the k8s sites, and the proposed SNR changes |
| [`monitoring-thresholds.md`](monitoring-thresholds.md) | current | Checkmk rules tuned against false positives (Proxmox VM memory, filesystem levels, K8s node root filesystem) with the evidence behind them |

## Adding a doc here

Split a table out of a conceptual doc only when it genuinely helps scanning, not by default. Link the two both ways, start the file with the `status:` frontmatter block described in [Status labels](../README.md#status-labels), and add a row to the index above in the same PR.

## Background

Introduced by [#1350](https://github.com/isejalabs/homelab/issues/1350), itself following the "target documentation model" in [#1336](https://github.com/isejalabs/homelab/issues/1336) and finding F4 of [`docs/audits/2026-09-documentation.md`](../audits/2026-09-documentation.md#f4--environment-documentation-mixes-conceptual-and-reference-information) — this is the first real use of that recommendation, not a separate convention invented independently.
