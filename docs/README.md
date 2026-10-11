# Documentation

This folder holds documentation that doesn't belong to a single folder in the repo — cross-cutting explanations of how a mechanism works across the whole cluster ("architecture"), plus supporting reference material. Docs tied 1:1 to one piece of tooling or one app/component stay as a `README.md` right next to that code instead (see below) — that's what keeps them from rotting out of sync with the thing they describe.

## Finding what you need

| You're asking…                                  | Where to look                                                                                                                                      |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| What is this system?                             | the root [`README.md`](../README.md)                                                                                                              |
| Why is it designed this way?                     | [`architecture/`](architecture), [`decisions/`](decisions)                                                                                        |
| What currently exists / is deployed?             | [`architecture/workloads.md`](architecture/workloads.md), [`reference/`](reference), and per-folder `README.md`s |
| How do I change, operate, or recover something?  | this folder's top-level procedural docs (e.g. [`disaster-recovery.md`](disaster-recovery.md), [`kopiur-backup-restore.md`](kopiur-backup-restore.md), [`proxmox-vm-power.md`](proxmox-vm-power.md)) and per-folder `README.md`s |
| Something's broken right now, how do I diagnose it? | [`troubleshooting-flux.md`](troubleshooting-flux.md), [`troubleshooting-dns.md`](troubleshooting-dns.md), [`troubleshooting-storage.md`](troubleshooting-storage.md) |
| Why did it become this way?                      | [`decisions/`](decisions) (ADRs), [`audits/`](audits) (point-in-time assessments), the root README's [history](../README.md#a-bit-of-history)     |

Current repository truth lives in the architecture, reference and procedural docs above, and in the code itself. `audits/` and `decisions/` capture reasoning and point-in-time assessments, not current configuration — don't read them as authoritative for "what exists today."

## What goes where

- **[`architecture/`](architecture)** — cross-cutting, conceptual docs for maintainers: how a mechanism that spans the whole repo actually works (e.g. how kustomize composes 8 environments from one `base`). These change rarely and don't belong to any single app/infra folder.
- **[`reference/`](reference)** — authoritative current-state factual material (specific values, tables, inventories) split out from the conceptual doc that explains it, where that split genuinely helps scanning (see [`reference/README.md`](reference/README.md)). Not every conceptual doc needs a reference sibling — only split one out where a dense lookup table would otherwise interrupt prose.
- **This folder, top-level** — procedural docs that span multiple areas but aren't really "architecture":
  - [`update-handling.md`](update-handling.md) — how renovate/labeler/mergify/Flux interact for automated dependency updates.
  - [`disaster-recovery.md`](disaster-recovery.md) — the full cluster-rebuild sequence, composed from the procedures below plus `AGENTS.md`'s Terragrunt section, with a validation checkpoint per step.
  - [`app-storage.md`](app-storage.md) — the app-facing `STORAGE_*`/`PUID`/`PGID` variable and storage-class reference for `apps/storage/pvc`/`pvc-no-backup`.
  - [`kopiur-backup-restore.md`](kopiur-backup-restore.md) — the kopiur backup/restore mechanism and day-to-day operational tasks (list/trigger/restore/prune backups).
  - [`proxmox-vm-snapshots.md`](proxmox-vm-snapshots.md) — the `just proxmox::snapshot::*` recipes (create/list/rollback/delete) and how VM discovery/credential reuse work for them.
  - [`proxmox-vm-power.md`](proxmox-vm-power.md) — the sibling `just proxmox::vm::*` recipes (list/start/stop/shutdown/reset).
  - [`troubleshooting-flux.md`](troubleshooting-flux.md), [`troubleshooting-dns.md`](troubleshooting-dns.md), [`troubleshooting-storage.md`](troubleshooting-storage.md) — incident-response runbooks for a `Kustomization`/`HelmRelease` stuck or failing, a DNS resolution/record problem, and a PVC/Longhorn/proxmox-csi storage issue, respectively.
  - [`node-lifecycle.md`](node-lifecycle.md) — moving a Talos/Kubernetes version forward and replacing a single node, in an otherwise-healthy cluster.
- **[`decisions/`](decisions)** — lightweight Architecture Decision Records: one file per significant, non-obvious architectural choice likely to be revisited later. Not a log of every decision made in the repo, only the ones whose *why* would otherwise be lost to git-log archaeology (see [`decisions/README.md`](decisions/README.md) for the format).
- **[`audits/`](audits)** — dated, point-in-time assessments, never current-state documentation and never edited after the fact (see [`audits/README.md`](audits/README.md) for the format, cadence, and how findings turn into tracked issues).
- **[`logs/`](logs)** — raw output logs kept as a historical/reference record of past bootstrap runs, not narrative documentation.
- **Per-folder `README.md`, elsewhere in the repo** — usage/procedural notes tied to one specific piece of tooling or code, updated in the same PR as the code they describe:
  - runbooks for a whole process, e.g. [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md), [`terragrunt/README.md`](../terragrunt/README.md),
  - narrow operational notes for one app/component, e.g. the `kubeseal` regen command in [`k8s/apps/dns/adguard/README.md`](../k8s/apps/dns/adguard/README.md).

## Conventions

### Where a new doc belongs

- A mechanism that spans the whole repo → [`architecture/`](architecture).
- Dense, factual reference tables that would interrupt an architecture doc's prose → a sibling file in [`reference/`](reference), linked both ways — only when the split genuinely helps, not by default.
- A procedure that spans multiple areas but isn't architecture → this folder's top level (see [What goes where](#what-goes-where) above).
- A choice likely to be revisited → [`decisions/`](decisions) (see [`decisions/README.md`](decisions/README.md)).
- A point-in-time assessment → [`audits/`](audits) — written once, never edited after the fact; a later pass is a new audit file, not a rewrite of an old one.
- Everything else, tied to one piece of code → a `README.md` next to that code, not here.

When in doubt, prefer colocating with the code; use this folder only for documentation that genuinely has no single owning folder.

### Ownership

A doc is owned by whoever owns the thing it describes, and gets updated in the same PR as that thing changes (see the commons "Documentation check" convention). `architecture/*` is cross-cutting by design, so "owned by" means whoever changes the mechanism it documents, not one dedicated maintainer.

`decisions/*` and `audits/*` are the exception: once written, their body is a historical record and isn't rewritten — a decision gets superseded by a new ADR that notes the old one, and a stale audit gets a follow-up doc, rather than either being edited in place. Only an ADR's own `Status` field is expected to change over its life.

### Keeping this current

- **During a change**: covered by [Ownership](#ownership) above — update the doc in the same PR as the code it describes. The [`doc-gap-check`](../.agents/skills/doc-gap-check) skill can help spot candidates before declaring a PR's documentation check satisfied — report-only, it never edits a doc itself, and a flag is a candidate to judge, not a mandate (see the skill for its guardrails). This is the only AI-assisted documentation workflow adopted so far, deliberately narrow per [#1351](https://github.com/isejalabs/homelab/issues/1351): generated doc text is always a draft, never treated as authoritative until its factual claims are checked against the current repository, and no workflow here rewrites narrative prose or edits a doc unattended.
- **During incident follow-up**: an incident stays a GitHub issue — the investigation record, timeline, and recovery log live there, not as a permanent incident document by default. Promote only the durable learning to the right destination: operating/recovery knowledge → an operational doc (e.g. [`disaster-recovery.md`](disaster-recovery.md)), authoritative current-state knowledge → [`reference/`](reference), design rationale or a material change → [`architecture/`](architecture) and/or a new [`decisions/`](decisions) ADR. The test: "would this be useful if the incident had never happened?" If yes, record it in a concise "Learnings / follow-up" section on the incident issue itself, then promote it from there into the right doc; otherwise leave it in the issue history. (First stated in [#1336](https://github.com/isejalabs/homelab/issues/1336); restated here so it's discoverable without reading that issue.)
- **Periodic review**: no separate calendar-based cadence beyond the two rules above — same-PR updates and incident-driven promotion are the mechanism, so docs stay current as a side effect of normal work rather than needing a scheduled pass. A heavier, genuinely periodic audit (re-reading everything for drift, the way the Sep 2026 documentation audit that started this whole effort did) is deliberately a separate, less frequent process — see [#1348](https://github.com/isejalabs/homelab/issues/1348).
- **Contributing**: follow [Where a new doc belongs](#where-a-new-doc-belongs) and [Status labels](#status-labels) below; a PR's own test plan should say what was actually verified, the same way it does for code — there's no separate documentation-review step beyond the PR review itself.

### Status labels

Borrowed from the Sep 2026 documentation audit's own [F13 recommendation](audits/2026-09-documentation.md#f13--inferred-information-should-be-explicitly-distinguished-from-authoritative-information), and already in use in `decisions/*`'s `## Status` section:

| Status | Meaning |
| --- | --- |
| `current` | Describes the system as it actually is today. |
| `planning` | Describes an intended or not-yet-implemented design. |
| `historical` | Superseded; kept for context, not a guide to today's system. |
| `audit` | A point-in-time assessment — not itself architecture. |

Where it's signalled depends on the doc type, since each already has its own natural home for it:

- `architecture/*`, `reference/*`, and this folder's top-level procedural docs: a YAML frontmatter block at the very top of the file, before the title —

  ```yaml
  ---
  status: current
  ---
  ```

  — which also doubles as the place for any other per-doc metadata later, without inventing a second mechanism. `architecture/*`/`reference/*` also repeat their status in the **Status** column below, since those tables are the entry point for those docs.
- `decisions/*`: the ADR's own `## Status` section.
- `audits/*`: implicit from the folder — everything there is `audit`, never `current`; not retrofitted with an inline marker, since each already carries its own, more specific status prose (e.g. "partial" vs. "complete"), and these files are never rewritten after the fact (see Ownership above).
- `_attic/`, elsewhere in the repo: implicit from the folder — everything there is `historical` (see the root README's [folder structure](../README.md#folder-structure)).

## Architecture docs

| Doc | Status | Covers |
| --- | --- | --- |
| [`architecture/overview.md`](architecture/overview.md) | current | top-level stack diagram (Proxmox → Talos → Kubernetes → Flux) and cross-cutting components, with links out to the rest of this table — start here |
| [`architecture/kustomize.md`](architecture/kustomize.md) | current | the `base`/`envs/<env>`/`flux` overlay triad, overlay patches, the shared `components` layer, and its `replacements`-based transformers |
| [`architecture/secrets.md`](architecture/secrets.md) | current | SOPS (terraform provisioning secrets) and sealed-secrets/1Password/ESO (in-cluster secrets), as one coherent story |
| `architecture/terraform-bootstrap.md` | planning ([#195](https://github.com/isejalabs/homelab/issues/195); implementation in progress at [PR #1168](https://github.com/isejalabs/homelab/pull/1168)) | the AWS/terraform remote-state chicken-and-egg bootstrapping problem |
| [`architecture/environments.md`](architecture/environments.md) | current | what each of the 8 environments (`dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`) is *for*, and the two axes that vary between them — factual values live in [`reference/environments.md`](reference/environments.md) |
| [`architecture/network.md`](architecture/network.md) | current | how Cilium (LB IPAM), Gateway API, AdGuard+Unbound (DNS resolvers), PowerDNS (DNS authority, in progress), and unifi-controller fit together |
| [`architecture/storage.md`](architecture/storage.md) | current | Longhorn vs proxmox-csi, and when each is used |
| [`architecture/workloads.md`](architecture/workloads.md) | current | catalog of every app/infra component deployed, what it is, and how it's installed |
| [`architecture/repositories.md`](architecture/repositories.md) | current | which repo holds what, which tool (Terraform, Salt, Flux, manual) manages which kind of thing, and where cross-repo issues live |
| [`architecture/ci.md`](architecture/ci.md) | current | every CI workflow, what it checks, tool provisioning via mise, and PR labeling/Mergify |

Planned/tracked docs are children of [#262](https://github.com/isejalabs/homelab/issues/262) ("Document cluster settings and procedures").

## Reference docs

| Doc | Status | Covers |
| --- | --- | --- |
| [`reference/environments.md`](reference/environments.md) | current | per-environment sizing, Flux interval, domain/naming schemes, and the ID/ASN/LB-pool/API-VIP tables — split out of `architecture/environments.md` per [#1350](https://github.com/isejalabs/homelab/issues/1350) |

See [`reference/README.md`](reference/README.md) for what belongs in this folder.
