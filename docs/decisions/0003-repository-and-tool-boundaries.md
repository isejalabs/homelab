# Repository and IaC tool boundaries

## Status

planning

## Context

The homelab spans a Kubernetes platform, VMs on Proxmox, the physical Proxmox hosts, a TrueNAS backup target (RustFS) and monitoring (Checkmk). The code is spread across `isejalabs/homelab`, `isejalabs/terraform-modules`, `isejalabs/terraform-proxmox-talos`, `isejalabs/commons` and `sebiklamar/salt-iseja.net`. `homelab` already combines Terragrunt and Kubernetes code, yet module logic is split off, and the Salt repo covers the host layer. Nothing recorded which piece goes where, when to choose Terraform over Salt, or where a problem touching several repos is tracked. The question surfaced when scoping IaC for RustFS bucket monitoring ([#1438](https://github.com/isejalabs/homelab/issues/1438)).

## Options considered

- **One monorepo for everything, including Salt.** Matches "the product is more than the cluster", but Salt has a different runtime (salt-master fileserver), apply cadence, secrets path and visibility, and no shared CI. Colocation would not make the whole easier to find, only the repo larger.
- **Split strictly by technology** (a Terragrunt repo, a k8s repo, a Salt repo). Clean on paper, but Talos and Kubernetes upgrades, state cleanup before destroy and per-env bootstrap change together, so it would turn single changes into coordinated multi-repo PRs.
- **Split by change unit and toolchain, with modules separate from live config (chosen).** Keeps Terragrunt and k8s together, keeps reusable versioned logic in module repos, keeps Salt separate.
- **A dedicated meta repo for issues and documentation.** Rejected for now: the gap is discoverability, which a repo map and the existing org project address, and `homelab` already acts as the product-level repo (observability audits, plan and ADRs live there).

## Decision

- Colocate code that shares a change unit and a toolchain; do not colocate merely because it belongs to the product. The repo map and tool-selection table are in [`architecture/repositories.md`](../architecture/repositories.md).
- Terraform/Terragrunt for API objects with a lifecycle, Salt for configuration inside long-lived Linux hosts, Flux for anything in Kubernetes, documented manual steps for appliance application settings (TrueNAS, Checkmk).
- 1Password is the secret handoff between Terraform (writes) and Salt (reads via `ext_pillar`).
- Cross-repo problems get an umbrella issue in `homelab` and sub-issues in the owning repos; the org project is the single steering board. No new meta repo for now.

## Consequences

- New IaC work has a default answer: RustFS monitoring splits into a Terraform module (identity and policy), a Salt state (Checkmk plugin on monitoring2) and a documented manual Checkmk step.
- `homelab` stays the product-level documentation home even for pieces implemented in other repos, so this page must be kept current when a repo is added or moved (for example when `salt-iseja.net` moves into the `isejalabs` org).
- Reconsider the no-meta-repo choice if cross-repo issues become frequent enough that the umbrella-in-`homelab` rule is hard to follow.

## Open decisions

- Where cross-env singleton Terraform units live: under the `prod` env directory, or a new shared directory. A shared directory would break the 8-environment invariant stated in AGENTS.md, so that has to be a deliberate change.
- Whether Checkmk host, password-store and rule setup stays manual or becomes code (REST API or a Terraform provider; provider maturity is unverified).
- Whether the PoC `talos-proxmox` and `vms` modules and the `poc` env units are retired, and whether `_envcommon/talos-proxmox.hcl` gets a pinned source.
- Pillar data lives only on the salt-master, outside git. Whether that stays acceptable is not decided here.
