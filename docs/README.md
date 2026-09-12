# Documentation

This folder holds documentation that doesn't belong to a single folder in the repo — cross-cutting
explanations of how a mechanism works across the whole cluster ("architecture"), plus supporting
reference material. Docs tied 1:1 to one piece of tooling or one app/component stay as a `README.md`
right next to that code instead (see below) — that's what keeps them from rotting out of sync with the
thing they describe.

## What goes where

- **[`architecture/`](architecture)** — cross-cutting, conceptual docs for maintainers: how a mechanism
  that spans the whole repo actually works (e.g. how kustomize composes 8 environments from one `base`).
  These change rarely and don't belong to any single app/infra folder.
- **This folder, top-level** — procedural docs that span multiple areas but aren't really "architecture",
  e.g. [`update handling.md`](update%20handling.md), documenting how renovate/labeler/mergify/Flux
  interact for automated dependency updates.
- **[`logs/`](logs)** — raw output logs kept as a historical/reference record of past bootstrap runs, not
  narrative documentation.
- **Per-folder `README.md`, elsewhere in the repo** — usage/procedural notes tied to one specific piece
  of tooling or code, updated in the same PR as the code they describe:
  - runbooks for a whole process, e.g. [`k8s/bootstrap/README.md`](../k8s/bootstrap/README.md),
    [`terragrunt/README.md`](../terragrunt/README.md),
  - narrow operational notes for one app/component, e.g. the `kubeseal` regen command in
    [`k8s/apps/dns/adguard/README.md`](../k8s/apps/dns/adguard/README.md).

## Architecture docs

| Doc | Status | Covers |
| --- | --- | --- |
| [`architecture/kustomize.md`](architecture/kustomize.md) | done | the `base`/`envs/<env>`/`flux` overlay triad, overlay patches, the shared `components` layer, and its `replacements`-based transformers |
| `architecture/secrets.md` | planned ([#98](https://github.com/isejalabs/homelab/issues/98), [#130](https://github.com/isejalabs/homelab/issues/130)) | SOPS (terraform + select k8s secrets) and sealed-secrets/1Password/ESO (in-cluster secrets), as one coherent story |
| `architecture/terraform-bootstrap.md` | planned ([#195](https://github.com/isejalabs/homelab/issues/195)) | the AWS/terraform remote-state chicken-and-egg bootstrapping problem |
| `architecture/environments.md` | identified, no issue yet | purpose of each of the 8 environments (`dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`) |
| `architecture/network.md` | identified, no issue yet | how Cilium (LB IPAM), Gateway API, AdGuard+Unbound (DNS), and unifi-controller fit together |
| `architecture/storage.md` | identified, no issue yet | Longhorn vs proxmox-csi, and when each is used |

Planned/tracked docs are children of [#262](https://github.com/isejalabs/homelab/issues/262) ("Document
cluster settings and procedures").
