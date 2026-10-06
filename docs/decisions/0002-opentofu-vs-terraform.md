# OpenTofu over Terraform

## Status

current

## Context

By the time this project started provisioning infrastructure (the first PoC commit, October 2024), HashiCorp had already relicensed Terraform from the open-source MPL 2.0 to the [Business Source License](https://www.hashicorp.com/en/blog/hashicorp-adopts-business-source-license) (August 2023), and the Linux Foundation-backed [OpenTofu](https://opentofu.org/) fork (MPL 2.0, a drop-in-compatible continuation of pre-BSL Terraform) had already reached a stable 1.6/1.7 release. Both tools were evaluated in the very first infrastructure commit, titled "TerraForm/ToFu PoC".

## Options considered

- **HashiCorp Terraform** — the incumbent, BSL-licensed since the above change.
- **OpenTofu (chosen)** — the open-source fork, drop-in CLI/HCL-compatible.

## Decision

OpenTofu, chosen specifically because of HashiCorp's BSL relicensing, used throughout via Terragrunt (see [ADR 0003](0003-terragrunt.md)) as the `tofu` binary.

## Consequences

- Stays on a genuinely open-source (MPL 2.0) license rather than HashiCorp's BSL — relevant for a personal project that might otherwise bump into BSL's competing-use restrictions.
- Full compatibility with the Terraform provider ecosystem and HCL syntax — nothing in this repo's modules (`terraform-proxmox-talos`, `terraform-modules`) had to be written any differently than if targeting Terraform itself.
- Tied to OpenTofu's own release cadence/compatibility tracking with upstream Terraform going forward, rather than HashiCorp's.
