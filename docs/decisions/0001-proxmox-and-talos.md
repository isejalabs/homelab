# Proxmox + Talos as the virtualization and Kubernetes-node platform

## Status

current

## Context

Proxmox VE predates this project — it was already the hypervisor running other VMs (OPNsense, TrueNAS, UCS) before Kubernetes entered the picture, and stays the hypervisor for now rather than being replaced. The whole homelab's Kubernetes journey itself started in 9/2024 out of a concrete, narrow problem: self-hosting the Unifi controller, which needs a Java + MongoDB runtime that didn't fit comfortably in a plain Debian/Ubuntu LXC, and didn't fit Docker's networking model either (root [`README.md`](../../README.md#a-bit-of-history)'s "Fun fact") — so a Kubernetes cluster became the actual target, not a goal in its own right.

Before Talos, [k3s](https://k3s.io/) was evaluated and rejected: regenerating the cluster from scratch was a frequent, deliberate part of the learning process early on, and k3s didn't fit that workflow well enough at the time. Talos came onto the radar via [mirceanton's video](https://www.youtube.com/watch?v=4_U0KK-blXQ) and [@vehagn](https://github.com/vehagn/homelab)'s [write-up](https://blog.stonegarden.dev/articles/2024/08/talos-proxmox-tofu/)/repo, which this project turned into a reusable module, [`terraform-proxmox-talos`](https://github.com/isejalabs/terraform-proxmox-talos) (see root README's Credits section).

A separate, related choice was how to generate/apply Talos's own machine config: [talhelper](https://github.com/budimanjojo/talhelper) was tried and rejected — it didn't fit the need to generate config for multiple environments while keeping a shared, DRY base, the same requirement Terragrunt (see [ADR 0003](0003-terragrunt.md)) and the kustomize `base`/`envs` overlay structure (see [ADR 0004](0004-kustomize-overlays.md)) both solve elsewhere in this repo. The Terraform provider for Talos ([`siderolabs/terraform-provider-talos`](https://registry.terraform.io/providers/siderolabs/talos)) was used instead, driven through `terraform-proxmox-talos`.

## Options considered

- **k3s** — rejected; didn't fit the cluster-regeneration-heavy learning workflow of the project's early days.
- **Talos Linux (chosen)** — immutable, API-managed, no SSH/package manager/shell; found via the mirceanton/vehagn references above.
- Config generation: **talhelper** (rejected — no good multi-environment DRY story) vs. **the Terraform provider for Talos (chosen)**, driven through `terraform-proxmox-talos`/Terragrunt instead.

## Decision

Proxmox VE (already the hypervisor in use) hosts the VMs; Talos Linux is the Kubernetes-node OS inside them, configured via the Terraform provider for Talos rather than talhelper; OpenTofu/Terragrunt provisions both (see [ADR 0002](0002-opentofu-vs-terraform.md), [ADR 0003](0003-terragrunt.md)).

## Consequences

- Every node is disposable and reproducible by construction — Talos has no persistent local state to drift, and the `rebuild` environment exists specifically to periodically prove the whole stack (Proxmox VMs through Talos through the cluster) can be rebuilt from this repo alone.
- No SSH-based node debugging — `talosctl` is the only interface to a node, which shapes how [`disaster-recovery.md`](../disaster-recovery.md) and the troubleshooting runbooks are written.
- The Terraform-provider-driven upgrade flow is cumbersome in practice — see [siderolabs/terraform-provider-talos#140](https://redirect.github.com/siderolabs/terraform-provider-talos/issues/140) — motivating interest in adopting an in-cluster upgrade controller (tuppr) instead; not yet decided, see Open decisions.
- Proxmox stays the hypervisor for appliance-style VMs that don't belong in Kubernetes (OPNsense, TrueNAS, UCS) and for the stateful Debian console-access hosts (`hannelore`, `tabea`) — a plain VM fits those better than a pod. Most other LXCs, and some other VMs, are candidates to eventually move onto Kubernetes instead.

## Open decisions

- Whether to move Kubernetes/Talos onto bare metal to be less constrained by the VM layer — a future direction noted on `terraform-proxmox-talos`'s own roadmap, not yet started.
- Whether to adopt tuppr (an in-cluster Talos/Kubernetes upgrade controller) in place of the current Terraform-provider-driven upgrade flow.
