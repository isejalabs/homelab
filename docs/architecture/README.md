# Architecture

Cross-cutting, conceptual docs: how a mechanism that spans the whole repo works, and why it is built that way. Docs tied to one piece of code live as a `README.md` next to that code instead; see [`docs/README.md`](../README.md#what-goes-where) for the split. The *why* of a significant choice lives in an ADR under [`decisions/`](../decisions), which these docs link to rather than restate. Dense lookup tables live under [`reference/`](../reference).

## Reading order

New to the repo? Read [`overview.md`](overview.md) first, then [`environments.md`](environments.md) and [`kustomize.md`](kustomize.md): together they explain the stack, the 8 environments and how one `base/` becomes 8 overlays. The rest can be read as needed.

## Index

| Doc | Status | Covers |
| --- | --- | --- |
| [`overview.md`](overview.md) | current | top-level stack diagram (Proxmox → Talos → Kubernetes → Flux) and cross-cutting components, with links out to the rest of this table — start here |
| [`environments.md`](environments.md) | current | what each of the 8 environments (`dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`) is *for*, and the two axes that vary between them — factual values live in [`reference/environments.md`](../reference/environments.md) |
| [`kustomize.md`](kustomize.md) | current | the `base`/`envs/<env>`/`flux` overlay triad, overlay patches, the shared `components` layer, and its `replacements`-based transformers |
| [`secrets.md`](secrets.md) | current | SOPS (terraform provisioning secrets) and sealed-secrets/1Password/ESO (in-cluster secrets), as one coherent story |
| [`network.md`](network.md) | current | how Cilium (LB IPAM), Gateway API, AdGuard+Unbound (DNS resolvers), PowerDNS (DNS authority, in progress), and unifi-controller fit together |
| [`storage.md`](storage.md) | current | Longhorn vs proxmox-csi, and when each is used |
| [`monitoring.md`](monitoring.md) | current | the Checkmk sites and why they are split, how cluster, storage and host data reach them, and which tool manages which part — live values in [`reference/monitoring-*.md`](../reference/README.md) |
| [`workloads.md`](workloads.md) | current | catalog of every app/infra component deployed, what it is, and how it's installed |
| [`repositories.md`](repositories.md) | current | which repo holds what, which tool (Terraform, Salt, Flux, manual) manages which kind of thing, and where cross-repo issues live |
| [`ci.md`](ci.md) | current | every CI workflow, what it checks, tool provisioning via mise, and PR labeling/Mergify |
| `terraform-bootstrap.md` | planning ([#195](https://github.com/isejalabs/homelab/issues/195); implementation in progress at [PR #1168](https://github.com/isejalabs/homelab/pull/1168)) | the AWS/terraform remote-state chicken-and-egg bootstrapping problem — not written yet |

Planned/tracked docs are children of [#262](https://github.com/isejalabs/homelab/issues/262) ("Document cluster settings and procedures").

## Adding a doc here

Only for a mechanism that spans the whole repo (see [Where a new doc belongs](../README.md#where-a-new-doc-belongs)). Start the file with the `status:` frontmatter block described in [Status labels](../README.md#status-labels), and add a row to the index above in the same PR.
