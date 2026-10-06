---
status: current
---

# Repositories and IaC tool boundaries

How the homelab is split across repositories, which tool manages which kind of thing, and where cross-repo issues live. The reasoning and the still-open decisions are in [ADR 0013](../decisions/0013-repository-and-tool-boundaries.md); this page is the current-state reference.

## Repositories

| Repo | Role | Holds |
| --- | --- | --- |
| [`isejalabs/homelab`](https://github.com/isejalabs/homelab) | Live config, k8s platform | Kustomize/Flux manifests (`k8s/`), Terragrunt instantiation of modules (`terragrunt/`), bootstrap, docs |
| [`isejalabs/terraform-modules`](https://github.com/isejalabs/terraform-modules) | Reusable modules | Versioned, per-module-tagged Terraform/OpenTofu modules with no environment knowledge (RustFS buckets/users, 1Password items, PoC VM/Talos modules) |
| [`isejalabs/terraform-proxmox-talos`](https://github.com/isejalabs/terraform-proxmox-talos) | Reusable module | The Proxmox + Talos cluster module, a fork of an upstream project, kept separate to track upstream |
| [`sebiklamar/salt-iseja.net`](https://github.com/sebiklamar/salt-iseja.net) | Live config, Linux and physical layer | Salt states for Proxmox hosts, the monitoring/Checkmk LXCs, loghost, ns2 and the Checkmk agents. Pillar data lives on the salt-master only, not in git |
| [`isejalabs/commons`](https://github.com/isejalabs/commons) | Shared conventions | Agent conventions, branching rules and repo settings, imported as the `.commons` submodule |

This is the usual modules/live split: logic that is reusable and versioned lives in the module repos, and everything that says "this instance, in this environment" lives in a live repo. `homelab` holds Terragrunt instantiation because those files are only `include` blocks, a pinned module source and per-env inputs.

## What belongs in one repo

Colocate code that shares a change unit and a toolchain, not everything that is part of the homelab as a product.

- Terragrunt and k8s stay together: Talos and Kubernetes upgrades, state cleanup before destroy, per-env bootstrap and the 8-environment model are coupled, and they share CI and secrets handling.
- Salt stays separate: it runs from the salt-master fileserver, has its own apply cadence and secrets path, and no shared CI.
- The product "homelab" is wider than any one repo (Proxmox hosts, TrueNAS, backup, monitoring). This page, not code colocation, is what keeps that whole discoverable.

## Which tool manages what

| Kind of thing | Tool | Examples |
| --- | --- | --- |
| Objects behind an API with a create/destroy lifecycle | Terraform/OpenTofu via Terragrunt | S3 state and IAM roles, RustFS buckets, users and policies, 1Password items, VM existence, Talos |
| Configuration inside a long-lived Linux host | Salt | Packages, files, services and cron on Proxmox hosts, monitoring2, loghost, ns2; Checkmk agents and plugins |
| Anything running in Kubernetes | Flux | Everything under `k8s/infra` and `k8s/apps` |
| Application settings of appliances | Manual, documented | TrueNAS, Checkmk site configuration (hosts, rules, password store) |
| GitHub repository/branch settings | Manual, documented | `main`'s branch protection (required status checks, PR-before-merge) — see [`ci.md`](ci.md) for what's actually required and why; no Terraform GitHub provider exists in this repo, this is a deliberate exception for a low-churn setting rather than new IaC surface area |

Rules of thumb:

- A VM's existence is Terraform; what runs inside a long-lived VM or LXC is Salt.
- Bare-metal Proxmox hosts are Salt, since there is no provider lifecycle to manage.
- Manual steps are allowed but must be written down next to the feature that needs them, with rollback notes.
- Salt vs Ansible is a separate assessment and not decided here.

### Handoff between layers

Terraform writes generated credentials to 1Password (via the `onepassword-item` module), and Salt reads them through its `onepassword` `ext_pillar`. Neither side copies secrets by hand. The Salt repo's README documents the same pattern for the PowerDNS TSIG secrets.

## Where issues live

- A problem owned by one repo is filed in that repo.
- A problem spanning two or more repos gets one umbrella issue in `homelab`, with a real sub-issue in each repo that owns part of the fix (GitHub sub-issues work across repos within an org). This follows the sub-issue convention in the commons conventions.
- Steering uses the org project [isejalabs/projects/1](https://github.com/orgs/isejalabs/projects/1) as the single board across repos.

Worked examples:

- RAM overcommit on pve6 ([#1465](https://github.com/isejalabs/homelab/issues/1465)): VM sizing is in `homelab` Terragrunt inputs, host-level mitigation is Salt, so the umbrella stays in `homelab` with a Salt sub-issue for the host part.
- A SMART problem on a Proxmox host that does not change any VM: a Salt-only issue, no umbrella.

## Worked example: RustFS bucket monitoring

Tracked in [#1438](https://github.com/isejalabs/homelab/issues/1438); design in [`2026-10-rustfs-capacity.md`](../audits/2026-10-rustfs-capacity.md). RustFS runs on TrueNAS, not in Kubernetes, so Flux is not involved.

| Piece | Tool | Where |
| --- | --- | --- |
| One monitoring user per environment with a bucket-scoped `s3:GetBucketQuota` policy, credentials into 1Password | Terraform | New module tracked in [isejalabs/terraform-modules#34](https://github.com/isejalabs/terraform-modules/issues/34), instantiated per environment in `terragrunt/` here |
| Checkmk special agent and check plugin on monitoring2, secret read from 1Password | Salt | `sebiklamar/salt-iseja.net` |
| Checkmk host, password-store entry and rules | Manual, documented | Recorded with the feature |

## Known inconsistencies

Tracked as open decisions in the ADR rather than fixed here:

- `terraform-modules` still carries the PoC `talos-proxmox` and `vms` modules, which overlap with `terraform-proxmox-talos`, and `homelab` still has `poc` env units using them.
- `terragrunt/_envcommon/talos-proxmox.hcl` has an unpinned module source, unlike `rustfs-kopiur-backup.hcl`, which pins a tag.
- No cross-env singleton Terraform unit exists today (the RustFS monitoring identity is deliberately one unit per environment). If one is ever needed, it has no natural home in the per-env `terragrunt/<account>/<region>/<env>/<module>` tree.
