# Terragrunt for multi-environment OpenTofu

## Status

current

## Context

[@vehagn](https://github.com/vehagn/homelab)'s reference repo (see [ADR 0001](0001-proxmox-and-talos.md)) was deliberately non-modular and single-environment — this project's own [Credits](../../README.md#credits) section is explicit that only the Terraform module itself traces back to his work, not the surrounding tooling. Terragrunt entered the picture on 2024-10-31, the same day a second environment was first stood up (git history: "1st terragrunt PoC using existing tofu/dev/vm module", then "implemented 2nd poc env w/ terragrunt") — the point at which copy-pasting a whole Terraform configuration per environment stopped being viable. The project now spans [8 environments](../architecture/environments.md) (see [ADR 0005](0005-environments.md)).

Remote state (S3) and its encryption weren't part of the original motivation — those were added almost a year later (2025-08-01, "feat: remote state in S3"/"feat!: state encryption"). The original draw was DRY environment config plus a clean way to consume **versioned** Terraform modules (`terraform-proxmox-talos`, later `terraform-modules`) rather than inlining or duplicating module code per environment. The folder layout itself was adopted from Gruntwork's own [`terragrunt-infrastructure-live-example`](https://github.com/gruntwork-io/terragrunt-infrastructure-live-example), not invented from scratch.

## Options considered

- **Plain OpenTofu/Tofu with a hand-rolled wrapper script** — calling a Terraform module in a parameterized way is possible this way too, but Terragrunt is the tool purpose-built for exactly this problem, and [keeps the result more DRY](https://www.gruntwork.io/blog/terragrunt-how-to-keep-your-terraform-code-dry-and-maintainable) than a custom wrapper would without reimplementing a chunk of what Terragrunt already does.
- **Plain OpenTofu with workspaces** — one state, switched per environment. Doesn't give per-environment file-level separation (sizing, secrets, module version pinning like `head`'s `ref=HEAD` or `src`'s local module checkout — see [`environments.md`](../architecture/environments.md)), and workspace-based drift between environments is easy to lose track of without separate directories.
- **Copy-pasted per-environment Terraform configs** — the naive starting point, abandoned once a second environment made the duplication cost concrete.
- **Terragrunt (chosen)** — lets a Terraform module be called in a parameterized way easily and encourages separating the module's own logic from how it's called per environment, versioned independently: one hierarchy of `.hcl`/`*-secrets.sops.yaml` files (global → account → region → env → local, see [`terragrunt/README.md`](../../terragrunt/README.md#folder-structure)) merged into each environment's own module invocation, plus shared `_envcommon/*.hcl` includes so a module's actual Terragrunt unit per environment stays small, while still referencing specific versioned module releases.

The `<region>` level in that hierarchy is deliberate, not incidental, even though multi-region is unlikely to ever actually happen here: it's just one extra folder to `cd` into versus a real rearrangement of how state/config is structured later, so the room to grow costs little to keep. See [ADR 0014](0014-folder-based-environments-not-branches.md) for the broader principle this folder-per-environment structure is one instance of — folder-based separation under one branch, never a git branch/fork per environment.

## Decision

Terragrunt, structured as `terragrunt/<non-prod|prod>/<account>/<region>/<env>/<module>` with the global/account/region/env/local override hierarchy — see [`terragrunt/README.md`](../../terragrunt/README.md) for the live structure. Remote state (S3, SOPS-encrypted passphrase) was added later on top of this structure, not part of the original decision.

Staying on the current nested-folder hierarchy rather than migrating to Terragrunt's newer [Stacks](https://terragrunt.gruntwork.io/docs/features/stacks/) feature — waived for now specifically because Stacks would consolidate all environments of a module into *one* `.hcl` file, which conflicts with the per-environment file separation Renovate relies on to track and bump `base`/`head`/`prod`-style version pins independently. Revisit if that constraint changes.

## Consequences

- A new environment is cheap to add (a new `<env>/` directory plus env-specific `.hcl`/secrets overrides), which is what made scaling to 8 environments practical.
- An extra layer of indirection on top of plain OpenTofu — a problem has to be diagnosed as either an OpenTofu/provider issue or a Terragrunt config-merging issue, and `terragrunt/README.md`'s own documented gotchas (state cleanup before destroy, the per-env `.envrc`/`TG_IAM_ASSUME_ROLE` direnv step) are specific to this layer.
- Remote state and its encryption passphrase (via SOPS, see [`secrets.md`](../architecture/secrets.md)) now run through `root.hcl` for every unit uniformly, even though that wasn't the original reason for adopting Terragrunt.
