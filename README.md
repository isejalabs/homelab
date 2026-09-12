# homelab

A personal, IaC-driven homelab: Proxmox VMs → [Talos Linux](https://www.talos.dev/) → Kubernetes,
provisioned with OpenTofu/Terragrunt and reconciled with [Flux CD](https://fluxcd.io/). Still in its
foundation phase — the cluster itself has been stable since prod went live, and the set of deployed
workloads is growing from there.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/isejalabs/homelab) gives an
up-to-date, browsable overview of the current implementation.

## Principles

- **IaC and GitOps end to end.** Nothing is clicked into existence — VMs come from OpenTofu/Terragrunt,
  cluster state comes from Flux reconciling this repo. `git log` is the change history.
- **Multi-environment, not just prod.** 8 environments (`dbg`, `dev`, `head`, `poc`, `prod`, `qa`,
  `rebuild`, `src`) exist so infrastructure-level changes — DNS, firewall rules, CNI config, anything that
  could take the network down — can be proven out somewhere that isn't "mission-critical" first. That's
  a step beyond what's typical in home-ops, where a single cluster usually doubles as the test bed.
- **DRY wherever possible.** One `base/` per app/infra unit, thin per-environment overlays, and a shared
  `components` layer (see [`k8s/components/README.md`](k8s/components/README.md)) that every environment
  composes from. The tradeoff is real: this keeps the repo consistent but adds a layer of kustomize
  indirection — see [`docs/architecture/kustomize.md`](docs/architecture/kustomize.md) for how it fits
  together.

## How it's built

- **Provisioning** ([`terragrunt/`](terragrunt/README.md)) — OpenTofu modules provision Proxmox VMs and
  install Talos, orchestrated per environment with Terragrunt for DRY multi-environment IaC.
- **Bootstrap** ([`k8s/bootstrap/README.md`](k8s/bootstrap/README.md)) — `helmfile` installs foundational
  CRDs and infra (Cilium, sealed-secrets, cert-manager, external-secrets, 1Password Connect, the Flux
  operator/instance), then hands reconciliation off to Flux.
- **Workloads** ([`k8s/infra/`](k8s/infra), [`k8s/apps/`](k8s/apps)) — everything Flux reconciles from
  here on: cluster infra (storage, networking, observability, secrets) and applications (DNS, finances,
  monitoring, network management, …), each following the same `base/` + `envs/<env>/` + `flux/` shape.

## Documentation

- [`docs/README.md`](docs/README.md) — cross-cutting architecture docs vs. per-folder usage READMEs, and
  an index of what's written up so far.
- [`terragrunt/README.md`](terragrunt/README.md) — provisioning VMs in Proxmox, installing Talos, and
  deploying core cluster infrastructure.
- [`k8s/bootstrap/README.md`](k8s/bootstrap/README.md) — the helmfile bootstrap phase and handoff to Flux.
- [`k8s/components/README.md`](k8s/components/README.md) — the shared kustomize DRY layer.
- `AGENTS.md` (symlinked as `CLAUDE.md`) — repo conventions and commands for AI coding agents working in
  this repo; also a decent map of the layout for humans.

## A bit of history

- **9/2024** — start of the journey: getting to know IaC, GitOps, Terraform, Kubernetes and Talos.
  Learning `git rebase` well enough to digest [vehagn/homelab](https://github.com/vehagn/homelab) counted
  as a milestone.
- **9/2025** — prod cluster go-live, after turning vehagn's (deliberately non-modular) homelab into a
  reusable Terraform module, and building out the multi-environment cluster with kustomize overlays and
  Terragrunt for DRY module handling.
- **3/2026** — started moving from ArgoCD to Flux for easier adoption of the wider home-ops ecosystem.
- **8/2026** — Flux fully replaced ArgoCD — the last big implementation done without AI guidance.
- **9/2026** — adopted AI-assisted development (Claude Code), which has meaningfully boosted
  productivity — documentation included, an area this developer was otherwise not great at.

## Credits

- [**@vehagn**](https://github.com/vehagn) — where I learned my first IaC/GitOps steps, and the
  conceptual author of [terraform-proxmox-talos](https://github.com/isejalabs/terraform-proxmox-talos)
  (derived from his non-modular [vehagn/homelab](https://github.com/vehagn/homelab); see also his
  [write-up](https://blog.stonegarden.dev/articles/2024/08/talos-proxmox-tofu/)). Only the Terraform
  module in this repo traces back to his work directly — the rest (helmfile bootstrapping, backup,
  storage provisioning, and everything since) has grown from there.
- [**@mirceanton**](https://github.com/mirceanton) — for the excellent YouTube walkthroughs.
- [**@onedr0p**](https://github.com/onedr0p) — for the Flux implementation that inspired this repo's,
  even though the multi-environment approach here meant it couldn't be reused as directly. Newcomers to
  home-ops should start with his [cluster-template](https://github.com/onedr0p/cluster-template); his
  [home-ops](https://github.com/onedr0p/home-ops) repo is worth a look regardless.
