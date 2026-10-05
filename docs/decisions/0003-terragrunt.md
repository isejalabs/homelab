# Terragrunt for multi-environment OpenTofu

## Status

current

## Context

[@vehagn](https://github.com/vehagn/homelab)'s reference repo (see [ADR 0001](0001-proxmox-and-talos.md)) was deliberately non-modular and single-environment — this project's own [Credits](../../README.md#credits) section is explicit that only the Terraform module itself traces back to his work, not the surrounding tooling. Terragrunt entered the picture on 2024-10-31, the same day a second environment was first stood up (git history: "1st terragrunt PoC using existing tofu/dev/vm module", then "implemented 2nd poc env w/ terragrunt") — the point at which copy-pasting a whole Terraform configuration per environment stopped being viable. The project now spans [8 environments](../architecture/environments.md) (see [ADR 0005](0005-eight-environments.md)).

Remote state (S3) and its encryption weren't part of the original motivation — those were added almost a year later (2025-08-01, "feat: remote state in S3"/"feat!: state encryption"). The original draw was DRY environment config plus a clean way to consume **versioned** Terraform modules (`terraform-proxmox-talos`, later `terraform-modules`) rather than inlining or duplicating module code per environment.

## Options considered

- **Plain OpenTofu with workspaces** — one state, switched per environment. Doesn't give per-environment file-level separation (sizing, secrets, module version pinning like `head`'s `ref=HEAD` or `src`'s local module checkout — see [`environments.md`](../architecture/environments.md)), and workspace-based drift between environments is easy to lose track of without separate directories.
- **Copy-pasted per-environment Terraform configs** — the naive starting point, abandoned once a second environment made the duplication cost concrete.
- **Terragrunt (chosen)** — a thin DRY layer over OpenTofu: one hierarchy of `.hcl`/`*-secrets.sops.yaml` files (global → account → region → env → local, see [`terragrunt/README.md`](../../terragrunt/README.md#folder-structure)) merged into each environment's own module invocation, plus shared `_envcommon/*.hcl` includes so a module's actual Terragrunt unit per environment stays small, while still referencing specific versioned module releases.

## Decision

Terragrunt, structured as `terragrunt/<non-prod|prod>/<account>/<region>/<env>/<module>` with the global/account/region/env/local override hierarchy — see [`terragrunt/README.md`](../../terragrunt/README.md) for the live structure. Remote state (S3, SOPS-encrypted passphrase) was added later on top of this structure, not part of the original decision.

## Consequences

- A new environment is cheap to add (a new `<env>/` directory plus env-specific `.hcl`/secrets overrides), which is what made scaling to 8 environments practical.
- An extra layer of indirection on top of plain OpenTofu — a problem has to be diagnosed as either an OpenTofu/provider issue or a Terragrunt config-merging issue, and `terragrunt/README.md`'s own documented gotchas (state cleanup before destroy, the per-env `.envrc`/`TG_IAM_ASSUME_ROLE` direnv step) are specific to this layer.
- Remote state and its encryption passphrase (via SOPS, see [`secrets.md`](../architecture/secrets.md)) now run through `root.hcl` for every unit uniformly, even though that wasn't the original reason for adopting Terragrunt.

## Open decisions

- Whether to stay on the current nested-folder-hierarchy structure or migrate to Terragrunt's newer [Stacks](https://terragrunt.gruntwork.io/docs/features/stacks/) feature — not yet decided.
