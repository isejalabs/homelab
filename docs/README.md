# Documentation

This folder holds documentation that doesn't belong to a single folder in the repo — cross-cutting explanations of how a mechanism works across the whole cluster ("architecture"), plus supporting reference material. Docs tied 1:1 to one piece of tooling or one app/component stay as a `README.md` right next to that code instead (see below) — that's what keeps them from rotting out of sync with the thing they describe.

## Finding what you need

This is the single index of the documentation, grouped by task. Each folder's own `README.md` indexes its contents (see [Architecture and reference docs](#architecture-and-reference-docs)).

### Understand the system

| I need to… | Start here |
| --- | --- |
| Get a summary of the system | The root [`README.md`](../README.md) |
| Look up a term used in the docs | [`glossary.md`](glossary.md) |
| See the stack diagram and reading order | [`architecture/overview.md`](architecture/overview.md), [`architecture/README.md`](architecture/README.md) |
| See what is deployed today | [`architecture/workloads.md`](architecture/workloads.md) and [`reference/`](reference) |
| Understand why it is designed this way | [`architecture/`](architecture) and [`decisions/`](decisions) |
| Read the project history | The root README's [history](../README.md#-a-bit-of-history) |

### Build and operate a cluster

| I need to… | Start here |
| --- | --- |
| Go from nothing to a running cluster | [`zero-to-cluster.md`](zero-to-cluster.md) |
| Provision VMs and install Talos | [`terragrunt/README.md`](../terragrunt/README.md#plan-and-apply-a-unit) |
| Bootstrap or re-sync foundational cluster services | [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md#cluster-deployment-with-just-and-flux-cd) |
| Upgrade Talos/Kubernetes or replace a node | [`node-lifecycle.md`](operations/node-lifecycle.md) |
| Upgrade Kubernetes to the next minor (compatibility, pin, rollout) | [`k8s-minor-upgrade.md`](operations/k8s-minor-upgrade.md) |
| Understand how automated dependency updates flow | [`update-handling.md`](operations/update-handling.md) |
| Look up app storage variables (`STORAGE_*`, `PUID`, `PGID`) | [`app-storage.md`](operations/app-storage.md) |
| Create the Checkmk `terraform` automation user | [`checkmk-automation-user.md`](operations/checkmk-automation-user.md) |
| Run or script Proxmox VM power and snapshot actions | [`proxmox-vm-power.md`](operations/proxmox-vm-power.md), [`proxmox-vm-snapshots.md`](operations/proxmox-vm-snapshots.md) |
| Know what a project board status means | [`project-board.md`](operations/project-board.md) |

### Back up and restore

| I need to… | Start here |
| --- | --- |
| Restore app data | [`kopiur-backup-restore.md`](backup/kopiur-backup-restore.md#daily-tasks), or [`longhorn-snapshots.md`](backup/longhorn-snapshots.md#restore-an-app-to-a-snapshot) for Longhorn local snapshots |
| Restore the Keycloak database | [`keycloak-backup-restore.md`](identity/keycloak-backup-restore.md#restore) |
| Restore a manually managed VM/LXC | [`proxmox-backup-restore.md`](backup/proxmox-backup-restore.md#restore-procedures) |
| Rebuild a whole cluster | [`disaster-recovery.md`](backup/disaster-recovery.md#full-cluster-rebuild) |

### Identity (Keycloak)

| I need to… | Start here |
| --- | --- |
| Configure realms and LDAP federation | [`keycloak-realms.md`](identity/keycloak-realms.md) |
| Sign in when UCS or the realms are down | [`keycloak-break-glass.md`](identity/keycloak-break-glass.md) |
| Check what can reach Keycloak and which headers it trusts | [`keycloak-exposure.md`](identity/keycloak-exposure.md) |

### Troubleshoot

| I need to… | Start here |
| --- | --- |
| Diagnose a stuck or failing Flux `Kustomization`/`HelmRelease` | [`troubleshooting-flux.md`](troubleshooting/troubleshooting-flux.md) |
| Diagnose a DNS resolution or record problem | [`troubleshooting-dns.md`](troubleshooting/troubleshooting-dns.md) |
| Diagnose a PVC, Longhorn or proxmox-csi storage issue | [`troubleshooting-storage.md`](troubleshooting/troubleshooting-storage.md) |
| Clear a stale Terraform/OpenTofu state lock | [`troubleshooting-terraform-state.md`](troubleshooting/troubleshooting-terraform-state.md) |

### History (not current state)

| I need to… | Start here |
| --- | --- |
| Read a point-in-time assessment | [`audits/`](audits) |
| Read a dated implementation plan that followed an audit | [`plans/`](plans) |

Current repository truth lives in the architecture, reference and procedural docs above, and in the code itself. `audits/` and `decisions/` capture reasoning and point-in-time assessments, not current configuration — don't read them as authoritative for "what exists today."

## What goes where

- **[`architecture/`](architecture)** — cross-cutting, conceptual docs for maintainers: how a mechanism that spans the whole repo actually works (e.g. how kustomize composes 8 environments from one `base`). These change rarely and don't belong to any single app/infra folder.
- **[`reference/`](reference)** — authoritative current-state factual material (specific values, tables, inventories) split out from the conceptual doc that explains it, where that split genuinely helps scanning (see [`reference/README.md`](reference/README.md)). Not every conceptual doc needs a reference sibling — only split one out where a dense lookup table would otherwise interrupt prose.
- **Procedural docs, one folder per task** — runbooks, operational recipes and incident-response guides that span multiple areas but aren't really "architecture". Which file covers what is listed once, in [Finding what you need](#finding-what-you-need); there is deliberately no second per-file list here.
  - **[`operations/`](operations)** — upgrades and node lifecycle, automated updates, app storage variables, Proxmox VM power and snapshots, the Checkmk automation user, project board statuses.
  - **[`backup/`](backup)** — backup and restore of app data, Longhorn snapshots, manually managed VMs/LXCs, and the full cluster rebuild.
  - **[`identity/`](identity)** — Keycloak: realms, break-glass login, exposure, and database backup/restore.
  - **[`troubleshooting/`](troubleshooting)** — incident-response runbooks for Flux, DNS, storage and stale Terraform state.
- **This folder, top level** — orientation pages that belong to no single task folder: [`glossary.md`](glossary.md) (one line per term, each linking to its owner doc) and [`zero-to-cluster.md`](zero-to-cluster.md) (the ordered path to a running cluster, linking the owning docs and stating each step's expected result).
- **[`decisions/`](decisions)** — lightweight Architecture Decision Records: one file per significant, non-obvious architectural choice likely to be revisited later. Not a log of every decision made in the repo, only the ones whose *why* would otherwise be lost to git-log archaeology (see [`decisions/README.md`](decisions/README.md) for the format).
- **[`audits/`](audits)** — dated, point-in-time assessments, never current-state documentation and never edited after the fact (see [`audits/README.md`](audits/README.md) for the format, cadence, and how findings turn into tracked issues).
- **[`plans/`](plans)** — dated implementation plans that follow from an audit (e.g. the observability and Checkmk consolidation plans). Each carries its own **Date**/**Status** header like an audit; unlike an audit, its status line is updated as phases land.
- **Per-folder `README.md`, elsewhere in the repo** — usage/procedural notes tied to one specific piece of tooling or code, updated in the same PR as the code they describe:
  - runbooks for a whole process, e.g. [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md), [`terragrunt/README.md`](../terragrunt/README.md),
  - the README of every app/infra unit under `k8s/apps/` and `k8s/infra/`: purpose, where it is used, how to reach it per environment, where its versions are pinned and a command cheat sheet, written from the template in [`k8s/README.md`](../k8s/README.md#readme-of-an-appinfra-unit) ([#2098](https://github.com/isejalabs/homelab/issues/2098), rollout in progress, first examples [`keycloak`](../k8s/apps/identity/keycloak/README.md) and [`cloudnative-pg`](../k8s/infra/cnpg-system/cloudnative-pg/README.md)). What a cross-cutting doc already owns (hostname scheme, update rules, runbooks) stays there and is linked, not copied.

## Conventions

### Where a new doc belongs

- A mechanism that spans the whole repo → [`architecture/`](architecture).
- Dense, factual reference tables that would interrupt an architecture doc's prose → a sibling file in [`reference/`](reference), linked both ways — only when the split genuinely helps, not by default.
- A procedure that spans multiple areas but isn't architecture → the matching task folder: [`operations/`](operations), [`backup/`](backup), [`identity/`](identity) or [`troubleshooting/`](troubleshooting) (see [What goes where](#what-goes-where) above), and add it to the index.
- A choice likely to be revisited → [`decisions/`](decisions) (see [`decisions/README.md`](decisions/README.md)).
- A point-in-time assessment → [`audits/`](audits) — written once, never edited after the fact; a later pass is a new audit file, not a rewrite of an old one.
- Everything else, tied to one piece of code → a `README.md` next to that code, not here.

When in doubt, prefer colocating with the code; use this folder only for documentation that genuinely has no single owning folder.

### Ownership

A doc is owned by whoever owns the thing it describes, and gets updated in the same PR as that thing changes (see the commons "Documentation check" convention). `architecture/*` is cross-cutting by design, so "owned by" means whoever changes the mechanism it documents, not one dedicated maintainer.

`decisions/*` and `audits/*` are the exception: once written, their body is a historical record and isn't rewritten — a decision gets superseded by a new ADR that notes the old one, and a stale audit gets a follow-up doc, rather than either being edited in place. Only an ADR's own `Status` field is expected to change over its life.

### Keeping this current

- **During a change**: covered by [Ownership](#ownership) above — update the doc in the same PR as the code it describes. The [`doc-gap-check`](../.agents/skills/doc-gap-check) skill can help spot candidates before declaring a PR's documentation check satisfied — report-only, it never edits a doc itself, and a flag is a candidate to judge, not a mandate (see the skill for its guardrails). This is the only AI-assisted documentation workflow adopted so far, deliberately narrow per [#1351](https://github.com/isejalabs/homelab/issues/1351): generated doc text is always a draft, never treated as authoritative until its factual claims are checked against the current repository, and no workflow here rewrites narrative prose or edits a doc unattended.
- **During incident follow-up**: an incident stays a GitHub issue — the investigation record, timeline, and recovery log live there, not as a permanent incident document by default. Promote only the durable learning to the right destination: operating/recovery knowledge → an operational doc (e.g. [`disaster-recovery.md`](backup/disaster-recovery.md)), authoritative current-state knowledge → [`reference/`](reference), design rationale or a material change → [`architecture/`](architecture) and/or a new [`decisions/`](decisions) ADR. The test: "would this be useful if the incident had never happened?" If yes, record it in a concise "Learnings / follow-up" section on the incident issue itself, then promote it from there into the right doc; otherwise leave it in the issue history. (First stated in [#1336](https://github.com/isejalabs/homelab/issues/1336); restated here so it's discoverable without reading that issue.)
- **Periodic review**: no separate calendar-based cadence beyond the two rules above — same-PR updates and incident-driven promotion are the mechanism, so docs stay current as a side effect of normal work rather than needing a scheduled pass. A heavier, genuinely periodic audit (re-reading everything for drift, the way the Sep 2026 documentation audit that started this whole effort did) is deliberately a separate, less frequent process — see [#1348](https://github.com/isejalabs/homelab/issues/1348).
- **Contributing**: follow [Where a new doc belongs](#where-a-new-doc-belongs) and [Status labels](#status-labels) below; a PR's own test plan should say what was actually verified, the same way it does for code — there's no separate documentation-review step beyond the PR review itself.

### Runbook skeleton

A runbook is a doc someone follows under pressure, so it leads with what to decide and keeps the caveats out of the way. Start it with an `At a glance` table that has these six rows, in this order, each pointing at the section that owns the detail:

| Row | What it holds |
| --- | --- |
| When to use | The situation the runbook is for, and a pointer to the neighbouring runbook when it is the wrong one |
| Prerequisites | Access, tools and state that must exist before step 1 |
| Steps | The ordered procedure, with the expected output of a step where the doc records one |
| Verify | How to tell that it worked |
| Rollback | How to undo it, or an explicit statement that no rollback is documented |
| Last exercised | When and where the procedure was last run, taken from the doc's own record |

Rules for filling it in:

- Use only what the doc already states. Where a row has no recorded content (no expected output, no date, no rollback), write that it is not recorded rather than leaving the row out or inventing a value.
- Put destructive or order-sensitive steps in a GitHub alert: `> [!WARNING]` for an order or precondition that breaks the procedure when ignored, `> [!CAUTION]` for a step that destroys data or can't be undone, `> [!NOTE]` for a detail that is easy to miss but harmless. The alert text is the rule, not a new rule: it must say what the surrounding procedure already says. Alerts render on github.com and map to admonitions if a docs site is added ([#2027](https://github.com/isejalabs/homelab/issues/2027)).
- Lead with the rule, then the reason.

Applied so far to [`disaster-recovery.md`](backup/disaster-recovery.md), [`node-lifecycle.md`](operations/node-lifecycle.md), [`k8s-minor-upgrade.md`](operations/k8s-minor-upgrade.md), [`kopiur-backup-restore.md`](backup/kopiur-backup-restore.md) and [`keycloak-backup-restore.md`](identity/keycloak-backup-restore.md), the highest-impact runbooks. Other runbooks adopt it when they are next edited; it is not a retrofit target.

### Status labels

Borrowed from the Sep 2026 documentation audit's own [F13 recommendation](audits/2026-09-documentation.md#f13--inferred-information-should-be-explicitly-distinguished-from-authoritative-information), and already in use in `decisions/*`'s `## Status` section:

| Status | Meaning |
| --- | --- |
| `current` | Describes the system as it actually is today. |
| `planning` | Describes an intended or not-yet-implemented design. |
| `historical` | Superseded; kept for context, not a guide to today's system. |
| `audit` | A point-in-time assessment — not itself architecture. |

Where it's signalled depends on the doc type, since each already has its own natural home for it:

- `architecture/*`, `reference/*`, and the procedural docs in `operations/`, `backup/`, `identity/` and `troubleshooting/`: a YAML frontmatter block at the very top of the file, before the title —

  ```yaml
  ---
  status: current
  ---
  ```

  — which also doubles as the place for any other per-doc metadata later, without inventing a second mechanism. `architecture/*`/`reference/*` also repeat their status in the **Status** column of their folder's `README.md` index, since those tables are the entry point for those docs.
- `decisions/*`: the ADR's own `## Status` section.
- `audits/*`: implicit from the folder — everything there is `audit`, never `current`; not retrofitted with an inline marker, since each already carries its own, more specific status prose (e.g. "partial" vs. "complete"), and these files are never rewritten after the fact (see Ownership above).
- `_attic/`, elsewhere in the repo: implicit from the folder — everything there is `historical` (see the root README's [folder structure](../README.md#-folder-structure)).

### Diagrams

Use a diagram where it shows something prose and lists show badly: a flow, a sequence or a relationship between components. Do not use one for a directory tree or a short list; those stay as text (a tree in a code block is the right format for a tree).

- **Mermaid is the default.** The source lives in the Markdown as a `mermaid` fence next to the text it illustrates, so it diffs and is reviewed like text, and GitHub renders it natively.
- **No hardcoded colours** (no `classDef`, `style` or `linkStyle` colours, no `%%{init}%%` theme variables), so GitHub's light and dark themes both work.
- **Accessibility:** every diagram starts with `accTitle:` and `accDescr:`.
- **A diagram never replaces its text.** It sits next to a prose explanation that carries the same information, and every node name must match the repository (a component, folder or environment that exists today).
- **Verify before merge.** A diagram, like any generated or drafted text, is not authoritative until it has been checked against the current repository configuration (see [Keeping this current](#keeping-this-current)). Update it in the same PR that changes what it shows.
- **Syntax is checked in CI.** GitHub renders invalid Mermaid as an error box instead of failing anything, so [`docs-mermaid-check.yml`](../.github/workflows/docs-mermaid-check.yml) parses every fence (see [`architecture/ci.md`](architecture/ci.md)). To check locally, render a fence with the Mermaid CLI pinned in [`.mise.toml`](.mise.toml).
- **One hand-authored image, stored in [`assets/`](assets).** The platform overview [`assets/platform-overview.svg`](assets/platform-overview.svg) is shown at the top of the root [`README.md`](../README.md). Its source of truth is [`architecture/overview.md`](architecture/overview.md); change both in the same PR. It follows the same rules as the Mermaid diagrams: colours as CSS variables with a dark-mode override, a transparent background, a system font stack, a `<title>` and `<desc>`, and animation only through SMIL (no scripts), switched off under `prefers-reduced-motion`.

## Architecture and reference docs

Each folder keeps its own index, with a status per doc: [`architecture/README.md`](architecture/README.md) (with a suggested reading order) and [`reference/README.md`](reference/README.md). [`decisions/README.md`](decisions/README.md) and [`audits/README.md`](audits/README.md) do the same for ADRs and audits.

## Documentation site

The Markdown in this repo is also built into a searchable, navigable site with [MkDocs](https://www.mkdocs.org/) and the Material theme (choice and trade-offs: [ADR 0017](decisions/0017-docs-site-generator.md)). The Markdown stays the single source of truth and stays readable on github.com; the site is a rendering of it, with nothing copied or moved. It is published at <https://isejalabs.github.io/homelab/> and open to search engines; the owner accepted that while the public-disclosure decision ([#1601](https://github.com/isejalabs/homelab/issues/1601)) is still pending. To hide it again, set `extra.noindex: true` in [`mkdocs.yml`](../.ci/mkdocs/mkdocs.yml), which adds a `noindex` meta tag and a `robots.txt` that disallows everything.

What the build does on top of plain MkDocs, in [`.ci/mkdocs/`](../.ci/mkdocs):

- The whole checkout is the docs directory, so the per-folder READMEs and the root `README.md` appear on the site without being moved. Everything that is not documentation (`.github/`, `.agents/`, `_attic/`, `ZZ.bak/`, `AGENTS.md`) is excluded in [`mkdocs.yml`](../.ci/mkdocs/mkdocs.yml).
- Relative links to source files and directories that are not part of the site are rewritten to their `github.com/isejalabs/homelab/blob/main` or `tree/main` URL at build time. Keep writing them as relative links, so they keep working on github.com and in `docs-link-check`.
- The [status labels](#status-labels) are shown as a banner below the page title: the `status:` front matter, an ADR's `## Status` section, and a dated-snapshot notice for everything under [`audits/`](audits) and [`plans/`](plans).
- The footer of every page names the git commit the site was built from (ID linked to github.com, plus its head line), read from the checkout at build time; a build outside a git checkout leaves it out.
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
