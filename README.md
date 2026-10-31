# homelab

A personal, [IaC](https://en.wikipedia.org/wiki/Infrastructure_as_code)-driven homelab: [Proxmox](https://www.proxmox.com/) VMs → [Talos Linux](https://www.talos.dev/) → [Kubernetes](https://kubernetes.io/), provisioned with [OpenTofu](https://opentofu.org/)/ [Terragrunt](https://terragrunt.gruntwork.io/) and reconciled with [Flux CD](https://fluxcd.io/). Still in its foundation phase — the cluster itself has been stable since prod went live, and the set of deployed [workloads](docs/architecture/workloads.md) is growing from there.

![Platform overview: Terragrunt provisions Proxmox VMs and installs Talos Linux, which bootstraps Kubernetes; the bootstrap helmfile hands off to Flux CD, which reconciles this repository. Around it: 1Password Connect with External Secrets, Cilium, Longhorn and proxmox-csi storage, and kopiur backups to an S3-compatible NAS.](docs/assets/platform-overview.svg)

The diagram is hand-drawn; its source of truth is the [architecture overview](docs/architecture/overview.md), and it is updated in the same PR as any change to the architecture it shows.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/isejalabs/homelab) gives an up-to-date, browsable overview of the current implementation.

## At a glance

- **Stack**: Proxmox → Talos Linux → Kubernetes, provisioned by OpenTofu/Terragrunt, reconciled by Flux CD.
- **Environments**: `dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src` — see [`environments.md`](docs/architecture/environments.md) for what each one is for.
- **Status**: prod has been live since 9/2025; still in its foundation phase — see [history](#a-bit-of-history) below.
- **Where to go next**: the [architecture overview](docs/architecture/overview.md) for the full stack diagram, or [`docs/README.md`](docs/README.md) for the documentation index.
- **Documentation site**: the same Markdown is built into a searchable site (see [how it is built](docs/README.md#documentation-site)); it is not published yet, pending the public-disclosure decision.

## I need to…

| Task | Start here |
| --- | --- |
| Provision or bootstrap a cluster | [`terragrunt/README.md`](terragrunt/README.md) to provision VMs and install Talos, then [`k8s/bootstrap/README.md`](k8s/bootstrap/README.md) to install foundational services and hand off to Flux |
| Diagnose a live issue | [`docs/README.md`'s troubleshooting paths](docs/README.md#finding-what-you-need) |
| Upgrade Talos/Kubernetes or replace a node | [`docs/node-lifecycle.md`](docs/node-lifecycle.md) |
| Restore app data, a VM/LXC, or rebuild a cluster | [`docs/README.md`'s recovery paths](docs/README.md#finding-what-you-need) |

## Principles

- **IaC and [GitOps](https://opengitops.dev/) for the cluster, no [snowflakes](https://martinfowler.com/bliki/SnowflakeServer.html).** Cluster VMs are provisioned with OpenTofu/Terragrunt, and Flux reconciles the apps and their configuration from Git. The `rebuild` environment exercises cluster reconstruction periodically, while kopiur backs up configured app data (see [`environments.md`](docs/architecture/environments.md#what-each-environment-is-for) and the [disaster recovery guide](docs/disaster-recovery.md)). This does not yet establish recovery of the whole homelab: some out-of-cluster components and 1Password-held secrets lack complete recovery documentation or periodic backup. `git log` is the change history.
- **Multi-environment, not just prod.** [8 environments](docs/architecture/environments.md) (`dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`) exist so infrastructure-level changes — DNS, firewall rules, CNI config, anything that could take the network down — get proven out somewhere else first, before they can take out the home network (and, more importantly, the household's tolerance for it). That's a step beyond what's typical in home-ops, where a single cluster usually doubles as the test bed.
- **DRY wherever possible.** One `base/` per app/infra unit, thin per-environment overlays, and a shared `components` layer (see [`k8s/components/README.md`](k8s/components/README.md)) that every environment composes from — see [DRY](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself). The tradeoff is real: this keeps the repo consistent but adds a layer of kustomize indirection — see [`docs/architecture/kustomize.md`](docs/architecture/kustomize.md) for how it fits together.

## How it's built

See [`docs/architecture/overview.md`](docs/architecture/overview.md) for the full stack diagram; summary:

- **Provisioning** ([`terragrunt/`](terragrunt/README.md)) — OpenTofu modules provision Proxmox VMs and install Talos, orchestrated per environment with Terragrunt for DRY multi-environment IaC.
- **Bootstrap** ([`k8s/bootstrap/README.md`](k8s/bootstrap/README.md)) — `helmfile` installs foundational CRDs and infra (Cilium, sealed-secrets, cert-manager, external-secrets, 1Password Connect, the Flux operator/instance), then hands reconciliation off to Flux.
- **Workloads** ([`k8s/infra/`](k8s/infra), [`k8s/apps/`](k8s/apps)) — everything Flux reconciles from here on: cluster infra (storage, networking, observability, secrets) and applications (DNS, finances, monitoring, network management, …), each following the same `base/` + `envs/<env>/` + `flux/` shape. See [`docs/architecture/workloads.md`](docs/architecture/workloads.md) for the full catalog of what's actually deployed.

## Staying current

[Renovate](https://docs.renovatebot.com/) opens PRs for dependency/version updates, and [Mergify](https://mergify.com/) auto-merges digest, patch, and minor updates by default — major updates always wait for review, and so do the exceptions: packages/paths pinned or flagged `updateStrategy:manual`, and prod-specific version promotions (prod can pin its own version separately from `qa`/`base`, so a change gets validated in `qa` first and merged into prod deliberately, not automatically). GitHub Actions CI validates infrastructure and configuration changes, mostly through static checks plus a bootstrap test against a throwaway cluster; local `pre-commit` and Flux reconciliation provide additional feedback. See the [CI guide](docs/architecture/ci.md) for workflow coverage, required checks, and PR-label automation, and [`docs/update-handling.md`](docs/update-handling.md) for the update policy. Left to its own preferences this would rather be a boring, patch-only Debian box than chase every minor release — the environment split above is what makes that patience compatible with also wanting to catch breakage early.

## Documentation

- [`docs/README.md`](docs/README.md) — cross-cutting architecture docs vs. per-folder usage READMEs, and an index of what's written up so far.
- [`terragrunt/README.md`](terragrunt/README.md) — provisioning VMs in Proxmox, installing Talos, and deploying core cluster infrastructure.
- [`k8s/README.md`](k8s/README.md) — the `k8s` folder structure (`apps/`, `bootstrap/`, `components/`, `infra/`, `test/`) and the shared `base`/`envs`/`flux` shape every app/infra unit follows.
- [`k8s/bootstrap/README.md`](k8s/bootstrap/README.md) — the helmfile bootstrap phase and handoff to Flux.
- [`k8s/components/README.md`](k8s/components/README.md) — the shared kustomize DRY layer.
- [`scripts/README.md`](scripts/README.md) — CI validation entry points, SOPS bulk ops, Terragrunt state cleanup, and kopiur backup/restore scripts.
- `AGENTS.md` (symlinked as `CLAUDE.md`) — repo conventions and commands for AI coding agents working in this repo; also a decent map of the layout for humans.

### Folder structure

```
📁 homelab
├── 📁 terragrunt      # OpenTofu/Terragrunt IaC: provisions Proxmox VMs and installs Talos Linux (see terragrunt/README.md)
├── 📁 k8s             # cluster bootstrap + the infra/apps Flux reconciles + the shared DRY kustomize components layer (see k8s/README.md)
├── 📁 scripts         # helper shell scripts (SOPS bulk ops, terragrunt state cleanup, k8s upgrade)
├── 📁 docs            # cross-cutting architecture docs, procedural notes, and bootstrap logs (see docs/README.md)
├── 📁 .agents         # shared agent instructions/skills (YAML sorting conventions, track-branch, port-app)
├── 📁 .commons        # git submodule: AI-agent conventions shared across isejalabs repos
├── 📁 .github         # issue/PR automation config (labeler, Renovate, Mergify)
├── 📁 .claude         # Claude Code project skills
├── 📁 .ci             # CI tooling config (prettier)
└── 📁 _attic          # retired/old material, not part of the active implementation
```

Root-level config files (`.sops.yaml`, `.pre-commit-config.yaml`, `.justfile`, `.minijinja.toml`, `.gitmodules`) wire up SOPS, pre-commit hooks, the `just` command runner and templating.

## A bit of history

- **9/2024** — start of the journey: getting to know IaC, GitOps, Terraform, Kubernetes and Talos. Learning `git rebase` well enough to digest [vehagn/homelab](https://github.com/vehagn/homelab) counted as a milestone.
- **9/2025** — prod cluster go-live, after turning vehagn's (deliberately non-modular) homelab into a reusable Terraform module, and building out the multi-environment cluster with kustomize overlays and Terragrunt for DRY module handling.
- **3/2026** — started moving from ArgoCD to Flux for easier adoption of the wider home-ops ecosystem.
- **8/2026** — Flux fully replaced ArgoCD — the last big implementation done without AI guidance.
- **9/2026** — adopted AI-assisted development (Claude Code), which has meaningfully boosted productivity — documentation included, an area this developer was otherwise not great at.

**Fun fact:** the whole thing started out of sheer frustration with deploying the Unifi controller — previously stuck in a Debian/Ubuntu LXC container to satisfy its Java + MongoDB compatibility requirements. Plain Docker containers were the obvious lighter alternative, but didn't fit the networking needs either — so a Kubernetes cluster it was.

## Credits

- [**@vehagn**](https://github.com/vehagn) — where I learned my first IaC/GitOps steps, and the conceptual author of [terraform-proxmox-talos](https://github.com/isejalabs/terraform-proxmox-talos) (derived from his non-modular [vehagn/homelab](https://github.com/vehagn/homelab); see also his [write-up](https://blog.stonegarden.dev/articles/2024/08/talos-proxmox-tofu/)). Only the Terraform module in this repo traces back to his work directly — the rest (helmfile bootstrapping, backup, storage provisioning, and everything since) has grown from there.
- [**@mirceanton**](https://github.com/mirceanton) — for the excellent YouTube walkthroughs.
- [**@onedr0p**](https://github.com/onedr0p) — for the Flux implementation that inspired this repo's, even though the multi-environment approach here meant it couldn't be reused as directly. Newcomers to home-ops should start with his [cluster-template](https://github.com/onedr0p/cluster-template); his [home-ops](https://github.com/onedr0p/home-ops) repo is worth a look regardless.
