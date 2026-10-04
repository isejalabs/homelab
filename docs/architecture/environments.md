---
status: current
---

# Environments

Every environment shares the same overlay structure ([`kustomize.md`](kustomize.md)) — the same apps *could*
run anywhere, and every environment has identical `envs/<env>/` folders throughout the repo. What actually
differs per environment is: which subset of apps Flux deploys there, how much compute it gets, how
aggressively updates land on it, and who's allowed to change it and how. This doc ties those axes together
for all 8: `dbg`, `dev`, `head`, `poc`, `prod`, `qa`, `rebuild`, `src`.

All 8 environments normally target `main` — there's no per-environment git branch, fork, or other such split.
The differentiation is entirely declarative: kustomize overlays (`envs/<env>/`, composed via the shared
[`components/envs/<env>/`](kustomize.md#the-shared-components-layer) layer) for everything Flux reconciles,
and lean, parameterized Terragrunt units (`terragrunt/<non-prod|prod>/eu-central-1/<env>/`) for the
infrastructure underneath. The one deliberate exception is the
[`track-branch`](../../.agents/skills/track-branch/SKILL.md) skill, which *temporarily* points a single
environment's Flux instance at a feature branch to test an unmerged change live — always a throwaway,
explicitly-reverted override on top of the normal `main`-tracking setup, never a standing per-environment
branch.

For resource sizing, reconciliation intervals, domain/naming, and the ID/ASN/LB-pool reference tables, see
[`docs/reference/environments.md`](../reference/environments.md) — this doc only covers what each axis
*means* and what each environment is *for*.

## The two axes that actually vary

### 1. Which apps run there — the Flux `minimal`/full split

[`k8s/bootstrap/cluster/flux/envs/<env>/kustomization.yaml`](../../k8s/bootstrap/cluster/flux/envs/) points
each environment at one of two Flux resource sets:

| Set | Environments | Apps deployed |
| --- | --- | --- |
| `sets/minimal` | `dbg`, `dev`, `poc`, `src` | [`apps/diag/whoami`](../../k8s/apps/diag/whoami/), [`apps/dns/powerdns`](../../k8s/apps/dns/powerdns/), [`apps/monitoring/metrics-server`](../../k8s/apps/monitoring/metrics-server/) only |
| `sets` (full: minimal + optional) | `head`, `prod`, `qa`, `rebuild` | + [`adguard`](../../k8s/apps/dns/adguard/), [`unbound`](../../k8s/apps/dns/unbound/), [`actualbudget`](../../k8s/apps/finances/actualbudget/), [`checkmk-agent`](../../k8s/apps/monitoring/checkmk-agent/), [`unifi-controller`](../../k8s/apps/network/unifi-controller/), [`unifi-mongodb`](../../k8s/apps/network/unifi-mongodb/) |

Every environment still gets the **full infra set** either way —
[`sets/minimal/kustomization.yaml`](../../k8s/bootstrap/cluster/flux/sets/minimal/kustomization.yaml)
includes infra unconditionally, with the reasoning inline:

```yaml
resources:
  - ../infra  # use full set for having all CSI options for, e.g., development of new apps
  - ../apps/minimal
```

So the minimal/full split is purely about **apps**: `dbg`/`dev`/`poc`/`src` are infra-and-diagnostics-only
environments (useful for testing cluster mechanics without running the full app stack); `head`/`prod`/`qa`/
`rebuild` are the ones that actually run the homelab's real applications.

This doesn't line up with kopiur's backup-schedule grouping (see
[`docs/kopiur-backup-restore.md`](../kopiur-backup-restore.md#dormant-environments)) — a separate axis with
its own 4/4 split, `dbg`/`head`/`poc`/`src` dormant vs. `dev`/`qa`/`rebuild`/`prod` active. `dev` is
minimal-apps but kopiur-active; `head` is full-apps but kopiur-dormant — the two groupings share three
members (`dbg`/`poc`/`src`) but disagree on `dev`/`head`, so don't assume one from the other.

### 2. How updates land

Which git ref an environment's Flux instance reconciles from (normally `main` — see the intro above for
`dev`'s `track-branch` exception) and how aggressively renovate-generated dependency-update PRs targeting
that environment's overlay get automerged are both covered in full in
[`docs/update-handling.md`](../update-handling.md), not duplicated here — that doc owns the update-handling
story end to end (labels, mergify/renovate rules, per-app version pinning), this one owns what each
environment structurally *is*.

One structural fact worth stating here because it isn't about renovate automerge at all: `terragrunt apply`
against `prod` or `qa` may only ever run from a `main` checkout, no exceptions — see
[`../../CLAUDE.md`](../../CLAUDE.md)'s Terragrunt rule. Unlike Flux config (which can be reverted by pointing
back at `main`), a Terragrunt apply from a branch creates real cloud state that only matches that unmerged
branch; the only way back in sync is merging it, not reverting.

## What each environment is for

- **`prod`** — production. Only environment with a full 3-controlplane HA topology, its own separately
  pinned Talos/Kubernetes version, the real (unprefixed) domain, the full app+infra Flux set, and the `1h`
  reconciliation interval. It's the one environment excluded from the
  [`track-branch`](../../.agents/skills/track-branch/SKILL.md) skill's live-cluster testing entirely (line
  16: *"one or more of `dbg`, `dev`, `head`, `poc`, `qa`, `rebuild`, `src` (not `prod`)"*), baked into the
  manifests themselves, not just convention —
  [`k8s/infra/flux-system/flux-instance/envs/prod/helmrelease.yaml`](../../k8s/infra/flux-system/flux-instance/envs/prod/helmrelease.yaml)
  has no commented-out `ref:` override placeholder at all, unlike every other environment's copy of that
  file. See [`docs/update-handling.md`](../update-handling.md) for how prod's dependency-update policy
  differs from the others.
- **`qa`** — the validation gate immediately before prod: full app+infra Flux set, `1h` interval, and the
  same `main`-checkout-only Terragrunt restriction as prod (`../../CLAUDE.md`: *"`prod` and `qa` may only
  ever be applied from a `main` checkout — no exceptions"*). Changes get exercised here before they're
  considered safe for `prod`. Part of why a dedicated environment earns that overhead rather than testing
  directly in `prod`: Terragrunt/Tofu changes are infrastructure-level, not app-level — a bad one can take
  down the whole cluster (nodes, CNI, control plane), not just a single app's Flux `Kustomization`, so they
  need proving out at that layer too, not only via kustomize overlay testing.
- **`head`** — the bleeding-edge tracking environment: unreleased-tip Terraform module (`ref=HEAD`) and the
  newest Talos/Kubernetes versions of any environment. Runs the full app set, so it's a live,
  continuously-updated real deployment used to catch breakage from new versions early — its
  dependency-update policy (see [`docs/update-handling.md`](../update-handling.md)) is built around that
  same role. In practice this leading-edge testing isn't exercised as a regular, periodic process at the
  moment — `head` is structurally set up for that purpose, but actively watching it for breakage isn't yet a
  habitual routine.
- **`poc`** — a proof-of-concept/throwaway testbed: not intended for long-term use and can be easily
  recreated if needed, unlike `dev`. Reserved for bigger, more fundamental changes — architecture or
  tooling-level experiments such as switching the GitOps controller (e.g. ArgoCD to Flux) or trying a
  different Terraform approach — deliberately kept separate from `dev`'s smaller, everyday enhancement work.
  Minimal app set (infra + diagnostics only), and the only environment with its own extra standalone `vms`
  Terragrunt module (`terragrunt/non-prod/eu-central-1/poc/vms/`) for ad hoc VM experiments beyond the
  standard cluster module. See [`docs/update-handling.md`](../update-handling.md) for how it also gets
  special dependency-update treatment, distinct from every other environment including `head`.
- **`rebuild`** — exists purely to periodically rehearse disaster recovery: kicked off from time to time to
  verify the cluster can actually be rebuilt from scratch as `prod` evolves over time, a safety net alongside
  (data) backups rather than a running app environment in its own right. Sized almost exactly like `prod` —
  same big-tier worker sizing — with the one deliberate difference being its non-HA, single-controlplane
  topology (1 + 3 nodes vs. `prod`'s 3 + 3), since rebuild-testing doesn't need HA to prove the rebuild
  procedure itself works. Runs the full app+infra Flux set like `prod`/`qa`/`head` so the rebuild is tested
  against the same real workloads, and is excluded from the `main`-only Terragrunt restriction and carries no
  special version pinning, consistent with being deliberately torn down and recreated — see
  `terragrunt/README.md`'s ["Cluster end of lifecycle"](../../terragrunt/README.md#cluster-end-of-lifecycle)
  section and [`scripts/tg-state-rm.sh`](../../scripts/tg-state-rm.sh) for the actual destroy/rebuild
  procedure this environment exercises.
- **`dev`** — the primary environment for feature development and possibly unit testing, `on_boot=true`,
  medium sizing, standard 1-controlplane + 3-worker topology, minimal app set. Typically pointed at whatever
  feature branch is currently under development (via
  [`track-branch`](../../.agents/skills/track-branch/SKILL.md), see the intro above) rather than continuously
  tracking `main` like the always-on full-stack environments. Distinguished from `poc` by being long-lived
  rather than throwaway, and by scope — `dev` is for the everyday enhancement work, while `poc` is reserved
  for bigger, more fundamental changes (see `poc` below).
- **`dbg`** — a dedicated debugging environment, kept separate from `dev` specifically so investigating a bug
  doesn't collide with or pause `dev`'s own in-progress work — the maintenance/bugfixing track and the
  enhancement track get their own environments rather than competing for the same one. Concretely, this means
  an incident can be reproduced and investigated on its own separate cluster, while `dev` stays free for
  ongoing feature/enhancement development. Smallest topology alongside `src` (1 controlplane + 1 worker only,
  rest of the node pool commented out in Terragrunt), `on_boot=false`, minimal app set.
- **`src`** — for developing the underlying
  [`terraform-proxmox-talos`](https://github.com/isejalabs/terraform-proxmox-talos) module itself, not the
  apps running on top of it: its `vehagn-k8s` module `source` points at a local, uncommitted checkout of that
  module rather than a git tag — the clearest naming confirmation in the whole set ("src" = source, as in the
  IaC module's own source code). Minimal topology and app set, `on_boot=false`, manually-applied config.

See [`docs/reference/environments.md#summary-table`](../reference/environments.md#summary-table) for a
one-table, at-a-glance summary of every axis above plus cluster sizing, Flux interval, and domain prefixing.
