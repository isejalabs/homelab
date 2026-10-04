# Documentation

This folder holds documentation that doesn't belong to a single folder in the repo — cross-cutting
explanations of how a mechanism works across the whole cluster ("architecture"), plus supporting
reference material. Docs tied 1:1 to one piece of tooling or one app/component stay as a `README.md`
right next to that code instead (see below) — that's what keeps them from rotting out of sync with the
thing they describe.

## Finding what you need

| You're asking…                                  | Where to look                                                                                                                                      |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| What is this system?                             | the root [`README.md`](../README.md)                                                                                                              |
| Why is it designed this way?                     | [`architecture/`](architecture), [`decisions/`](decisions)                                                                                        |
| What currently exists / is deployed?             | [`architecture/workloads.md`](architecture/workloads.md), [`architecture/environments.md`](architecture/environments.md), and per-folder `README.md`s |
| How do I change, operate, or recover something?  | this folder's top-level procedural docs (e.g. [`kopiur-backup-restore.md`](kopiur-backup-restore.md), [`proxmox-vm-power.md`](proxmox-vm-power.md)) and per-folder `README.md`s |
| Why did it become this way?                      | [`decisions/`](decisions) (ADRs), [`audits/`](audits) (point-in-time assessments), the root README's [history](../README.md#a-bit-of-history)     |

Current repository truth lives in the architecture, reference and procedural docs above, and in the
code itself. `audits/` and `decisions/` capture reasoning and point-in-time assessments, not current
configuration — don't read them as authoritative for "what exists today."

## What goes where

- **[`architecture/`](architecture)** — cross-cutting, conceptual docs for maintainers: how a mechanism
  that spans the whole repo actually works (e.g. how kustomize composes 8 environments from one `base`).
  These change rarely and don't belong to any single app/infra folder.
- **This folder, top-level** — procedural docs that span multiple areas but aren't really "architecture":
  - [`update-handling.md`](update-handling.md) — how renovate/labeler/mergify/Flux interact for automated
    dependency updates.
  - [`app-storage.md`](app-storage.md) — the app-facing `STORAGE_*`/`PUID`/`PGID` variable and storage-class
    reference for `apps/storage/pvc`/`pvc-no-backup`.
  - [`kopiur-backup-restore.md`](kopiur-backup-restore.md) — the kopiur backup/restore mechanism and
    day-to-day operational tasks (list/trigger/restore/prune backups).
  - [`proxmox-vm-snapshots.md`](proxmox-vm-snapshots.md) — the `just proxmox::snapshot::*` recipes
    (create/list/rollback/delete) and how VM discovery/credential reuse work for them.
  - [`proxmox-vm-power.md`](proxmox-vm-power.md) — the sibling `just proxmox::vm::*` recipes
    (list/start/stop/shutdown/reset).
- **[`decisions/`](decisions)** — lightweight Architecture Decision Records: one file per significant,
  non-obvious architectural choice likely to be revisited later. Not a log of every decision made in the
  repo, only the ones whose *why* would otherwise be lost to git-log archaeology.
- **[`logs/`](logs)** — raw output logs kept as a historical/reference record of past bootstrap runs, not
  narrative documentation.
- **Per-folder `README.md`, elsewhere in the repo** — usage/procedural notes tied to one specific piece
  of tooling or code, updated in the same PR as the code they describe:
  - runbooks for a whole process, e.g. [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md),
    [`terragrunt/README.md`](../terragrunt/README.md),
  - narrow operational notes for one app/component, e.g. the `kubeseal` regen command in
    [`k8s/apps/dns/adguard/README.md`](../k8s/apps/dns/adguard/README.md).

## Conventions

### Where a new doc belongs

- A mechanism that spans the whole repo → [`architecture/`](architecture).
- A procedure that spans multiple areas but isn't architecture → this folder's top level (see
  [What goes where](#what-goes-where) above).
- A choice likely to be revisited → [`decisions/`](decisions) (see [`decisions/README.md`](decisions/README.md)).
- A point-in-time assessment → [`audits/`](audits) — written once, never edited after the fact; a later
  pass is a new audit file, not a rewrite of an old one.
- Everything else, tied to one piece of code → a `README.md` next to that code, not here.

When in doubt, prefer colocating with the code; use this folder only for documentation that genuinely has
no single owning folder.

### Ownership

A doc is owned by whoever owns the thing it describes, and gets updated in the same PR as that thing
changes (see the commons "Documentation check" convention). `architecture/*` is cross-cutting by design, so
"owned by" means whoever changes the mechanism it documents, not one dedicated maintainer.

`decisions/*` and `audits/*` are the exception: once written, their body is a historical record and isn't
rewritten — a decision gets superseded by a new ADR that notes the old one, and a stale audit gets a
follow-up doc, rather than either being edited in place. Only an ADR's own `Status` field is expected to
change over its life.

### Status labels

Borrowed from the Sep 2026 documentation audit's own
[F13 recommendation](audits/2026-09-documentation.md#f13--inferred-information-should-be-explicitly-distinguished-from-authoritative-information),
and already in use in `decisions/*`'s `## Status` section:

| Status | Meaning |
| --- | --- |
| `current` | Describes the system as it actually is today. |
| `planning` | Describes an intended or not-yet-implemented design. |
| `historical` | Superseded; kept for context, not a guide to today's system. |
| `audit` | A point-in-time assessment — not itself architecture. |

Where it's signalled depends on the doc type, since each already has its own natural home for it:

- `architecture/*`: the **Status** column in the table below.
- this folder's top-level procedural docs: assumed `current` (each describes a shipped mechanism); called
  out inline if that's ever not the case.
- `decisions/*`: the ADR's own `## Status` section.
- `audits/*`: implicit from the folder — everything there is `audit`, never `current`.
- `_attic/`, elsewhere in the repo: implicit from the folder — everything there is `historical` (see the
  root README's [folder structure](../README.md#folder-structure)).

## Architecture docs

| Doc | Status | Covers |
| --- | --- | --- |
| [`architecture/overview.md`](architecture/overview.md) | current | top-level stack diagram (Proxmox → Talos → Kubernetes → Flux) and cross-cutting components, with links out to the rest of this table — start here |
| [`architecture/kustomize.md`](architecture/kustomize.md) | current | the `base`/`envs/<env>`/`flux` overlay triad, overlay patches, the shared `components` layer, and its `replacements`-based transformers |
| [`architecture/secrets.md`](architecture/secrets.md) | current | SOPS (terraform provisioning secrets) and sealed-secrets/1Password/ESO (in-cluster secrets), as one coherent story |
| `architecture/terraform-bootstrap.md` | planning ([#195](https://github.com/isejalabs/homelab/issues/195)) | the AWS/terraform remote-state chicken-and-egg bootstrapping problem |
| [`architecture/environments.md`](architecture/environments.md) | current | purpose of each of the 8 environments (`dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`) |
| [`architecture/network.md`](architecture/network.md) | current | how Cilium (LB IPAM), Gateway API, AdGuard+Unbound (DNS resolvers), PowerDNS (DNS authority, in progress), and unifi-controller fit together |
| [`architecture/storage.md`](architecture/storage.md) | current | Longhorn vs proxmox-csi, and when each is used |
| [`architecture/workloads.md`](architecture/workloads.md) | current | catalog of every app/infra component deployed, what it is, and how it's installed |
| [`architecture/repositories.md`](architecture/repositories.md) | current | which repo holds what, which tool (Terraform, Salt, Flux, manual) manages which kind of thing, and where cross-repo issues live |

Planned/tracked docs are children of [#262](https://github.com/isejalabs/homelab/issues/262) ("Document
cluster settings and procedures").
