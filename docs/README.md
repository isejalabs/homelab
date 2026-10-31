# Documentation

This folder holds documentation that doesn't belong to a single folder in the repo — cross-cutting explanations of how a mechanism works across the whole cluster ("architecture"), plus supporting reference material. Docs tied 1:1 to one piece of tooling or one app/component stay as a `README.md` right next to that code instead (see below) — that's what keeps them from rotting out of sync with the thing they describe.

## Finding what you need

| I need to… | Start here |
| --- | --- |
| Understand the system | The root [`README.md`](../README.md) for a summary; [`architecture/overview.md`](architecture/overview.md) for the stack diagram |
| Provision VMs and install Talos | [`terragrunt/README.md`](../terragrunt/README.md#plan-and-apply-a-unit) |
| Bootstrap or re-sync foundational cluster services | [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md#cluster-deployment-with-just-and-flux-cd) |
| Diagnose Flux, DNS, storage, or stale Terraform state | [`troubleshooting-flux.md`](troubleshooting-flux.md), [`troubleshooting-dns.md`](troubleshooting-dns.md), [`troubleshooting-storage.md`](troubleshooting-storage.md), or [`troubleshooting-terraform-state.md`](troubleshooting-terraform-state.md) |
| Upgrade Talos/Kubernetes or replace a node | [`node-lifecycle.md`](node-lifecycle.md) |
| Upgrade Kubernetes to the next minor (compatibility, pin, rollout) | [`k8s-minor-upgrade.md`](k8s-minor-upgrade.md) |
| Restore app data | [`kopiur-backup-restore.md`](kopiur-backup-restore.md#daily-tasks), or [`longhorn-snapshots.md`](longhorn-snapshots.md#restore-an-app-to-a-snapshot) for Longhorn local snapshots; for the Keycloak database [`keycloak-backup-restore.md`](keycloak-backup-restore.md#restore) |
| Restore a manually managed VM/LXC | [`proxmox-backup-restore.md`](proxmox-backup-restore.md#restore-procedures) |
| Rebuild a whole cluster | [`disaster-recovery.md`](disaster-recovery.md#full-cluster-rebuild) |
| Understand why it is designed this way | [`architecture/`](architecture) and [`decisions/`](decisions) |
| See what is deployed today | [`architecture/workloads.md`](architecture/workloads.md) and [`reference/`](reference) |
| Read a point-in-time assessment | [`audits/`](audits) |
| Know what a project board status means | [`project-board.md`](project-board.md) |
| Read the project history | The root README's [history](../README.md#a-bit-of-history) |

Current repository truth lives in the architecture, reference and procedural docs above, and in the code itself. `audits/` and `decisions/` capture reasoning and point-in-time assessments, not current configuration — don't read them as authoritative for "what exists today."

## What goes where

- **[`architecture/`](architecture)** — cross-cutting, conceptual docs for maintainers: how a mechanism that spans the whole repo actually works (e.g. how kustomize composes 8 environments from one `base`). These change rarely and don't belong to any single app/infra folder.
- **[`reference/`](reference)** — authoritative current-state factual material (specific values, tables, inventories) split out from the conceptual doc that explains it, where that split genuinely helps scanning (see [`reference/README.md`](reference/README.md)). Not every conceptual doc needs a reference sibling — only split one out where a dense lookup table would otherwise interrupt prose.
- **This folder, top-level** — procedural docs that span multiple areas but aren't really "architecture":
  - [`update-handling.md`](update-handling.md) — how renovate/labeler/mergify/Flux interact for automated dependency updates.
  - [`disaster-recovery.md`](disaster-recovery.md) — the full cluster-rebuild sequence, composed from the procedures below plus `AGENTS.md`'s Terragrunt section, with a validation checkpoint per step.
  - [`app-storage.md`](app-storage.md) — the app-facing `STORAGE_*`/`PUID`/`PGID` variable and storage-class reference for `apps/storage/pvc`/`pvc-no-backup`.
  - [`kopiur-backup-restore.md`](kopiur-backup-restore.md) — the kopiur backup/restore mechanism and day-to-day operational tasks (list/trigger/restore/prune backups).
  - [`checkmk-automation-user.md`](checkmk-automation-user.md) — the least-privilege Checkmk role for the `terraform` automation user that the Checkmk Terragrunt units authenticate as, and how to create it via the REST API or the UI.
  - [`keycloak-backup-restore.md`](keycloak-backup-restore.md) — the daily `pg_dump` backup of the Keycloak database to RustFS, why there is no WAL archiving, and how to restore it.
  - [`keycloak-break-glass.md`](keycloak-break-glass.md) — the local `master`-realm login (bootstrap admin) that keeps Keycloak administrable when UCS or the realms are down: where the credential lives, how to sign in, rotate it and recover it.
  - [`keycloak-realms.md`](keycloak-realms.md) — the `keycloak-realm` Terragrunt unit that fills Keycloak with its realms and LDAP federation, and its prerequisites (UCS groups and bind account, 1Password items, CA trust).
  - [`keycloak-exposure.md`](keycloak-exposure.md) — what can reach Keycloak and which forwarded headers it trusts: the admin-console exposure decision, the forged-header test and its route fix, and why there is no network policy yet.
  - [`longhorn-snapshots.md`](longhorn-snapshots.md) — the `just backup::longhorn-snapshot::*` recipes (list/create/restore) for Longhorn's local hourly/daily volume snapshots.
  - [`proxmox-vm-snapshots.md`](proxmox-vm-snapshots.md) — the `just proxmox::snapshot::*` recipes (create/list/rollback/delete) and how VM discovery/credential reuse work for them.
  - [`proxmox-vm-power.md`](proxmox-vm-power.md) — the sibling `just proxmox::vm::*` recipes (list/start/stop/shutdown/reset).
  - [`proxmox-backup-restore.md`](proxmox-backup-restore.md) — the vzdump/PBS backup tier for manually-managed "pet" VMs/LXCs (not the Terraform-managed `vehagn-k8s` environments) and how to restore one.
  - [`troubleshooting-flux.md`](troubleshooting-flux.md), [`troubleshooting-dns.md`](troubleshooting-dns.md), [`troubleshooting-storage.md`](troubleshooting-storage.md), [`troubleshooting-terraform-state.md`](troubleshooting-terraform-state.md) — incident-response runbooks for a `Kustomization`/`HelmRelease` stuck or failing, a DNS resolution/record problem, a PVC/Longhorn/proxmox-csi storage issue, and a stale Terraform/OpenTofu state lock, respectively.
  - [`project-board.md`](project-board.md) — what each `Status` value on the org project boards means and which workflow sets it.
  - [`k8s-minor-upgrade.md`](k8s-minor-upgrade.md) — runbook for a Kubernetes *minor* upgrade: compatibility checks across the infrastructure components, lifting the Renovate pin, staged rollout (non-prod, `qa`, then `prod`) and verification.
  - [`node-lifecycle.md`](node-lifecycle.md) — moving a Talos/Kubernetes version forward and replacing a single node, in an otherwise-healthy cluster.
- **[`decisions/`](decisions)** — lightweight Architecture Decision Records: one file per significant, non-obvious architectural choice likely to be revisited later. Not a log of every decision made in the repo, only the ones whose *why* would otherwise be lost to git-log archaeology (see [`decisions/README.md`](decisions/README.md) for the format).
- **[`audits/`](audits)** — dated, point-in-time assessments, never current-state documentation and never edited after the fact (see [`audits/README.md`](audits/README.md) for the format, cadence, and how findings turn into tracked issues).
- **[`plans/`](plans)** — dated implementation plans that follow from an audit (e.g. the observability and Checkmk consolidation plans). Each carries its own **Date**/**Status** header like an audit; unlike an audit, its status line is updated as phases land.
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

  — which also doubles as the place for any other per-doc metadata later, without inventing a second mechanism. `architecture/*`/`reference/*` also repeat their status in the **Status** column of their folder's `README.md` index, since those tables are the entry point for those docs.
- `decisions/*`: the ADR's own `## Status` section.
- `audits/*`: implicit from the folder — everything there is `audit`, never `current`; not retrofitted with an inline marker, since each already carries its own, more specific status prose (e.g. "partial" vs. "complete"), and these files are never rewritten after the fact (see Ownership above).
- `_attic/`, elsewhere in the repo: implicit from the folder — everything there is `historical` (see the root README's [folder structure](../README.md#folder-structure)).

## Architecture and reference docs

Each folder keeps its own index, with a status per doc: [`architecture/README.md`](architecture/README.md) (with a suggested reading order) and [`reference/README.md`](reference/README.md). [`decisions/README.md`](decisions/README.md) and [`audits/README.md`](audits/README.md) do the same for ADRs and audits.

## Documentation site

The Markdown in this repo is also built into a searchable, navigable site with [MkDocs](https://www.mkdocs.org/) and the Material theme (choice and trade-offs: [ADR 0017](decisions/0017-docs-site-generator.md)). The Markdown stays the single source of truth and stays readable on github.com; the site is a rendering of it, with nothing copied or moved. It will be published at <https://isejalabs.github.io/homelab/> once the owner has decided on public disclosure ([#1601](https://github.com/isejalabs/homelab/issues/1601)); until then the site is built and checked on every relevant pull request but not deployed, and it is marked `noindex`.

What the build does on top of plain MkDocs, in [`.ci/mkdocs/`](../.ci/mkdocs):

- The whole checkout is the docs directory, so the per-folder READMEs and the root `README.md` appear on the site without being moved. Everything that is not documentation (`.github/`, `.agents/`, `_attic/`, `ZZ.bak/`, [`logs/`](logs), `AGENTS.md`) is excluded in [`mkdocs.yml`](../.ci/mkdocs/mkdocs.yml).
- Relative links to source files and directories that are not part of the site are rewritten to their `github.com/isejalabs/homelab/blob/main` or `tree/main` URL at build time. Keep writing them as relative links, so they keep working on github.com and in `docs-link-check`.
- The [status labels](#status-labels) are shown as a banner below the page title: the `status:` front matter, an ADR's `## Status` section, and a dated-snapshot notice for everything under [`audits/`](audits) and [`plans/`](plans).
- `mermaid` code fences are rendered as diagrams.
- A new page is built and searchable without further steps, but only appears in the sidebar once it is added to the `nav:` list in [`mkdocs.yml`](../.ci/mkdocs/mkdocs.yml).

Preview locally (Python 3.11 or newer, with the virtual environment outside the checkout so MkDocs does not scan it; the versions are pinned in [`requirements.txt`](../.ci/mkdocs/requirements.txt)), from the repository root:

```sh
python3 -m venv /tmp/venv-docs && . /tmp/venv-docs/bin/activate
pip install -r .ci/mkdocs/requirements.txt
NO_MKDOCS_2_WARNING=1 mkdocs serve --config-file .ci/mkdocs/mkdocs.yml    # live preview at http://127.0.0.1:8000
NO_MKDOCS_2_WARNING=1 mkdocs build --strict --config-file .ci/mkdocs/mkdocs.yml --site-dir /tmp/homelab-site    # what CI runs
```

The [`docs-build`](../.github/workflows/docs-build.yml) workflow runs the strict build on pull requests that touch documentation, so a broken relative link or `#anchor` fails it. The deploy job runs on `main` only, and only while the repository variable `DOCS_PAGES_PUBLISH` is `true` and the repository's Pages source is set to GitHub Actions.
