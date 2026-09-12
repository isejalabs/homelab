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

## The two axes that actually vary

### 1. Which apps run there — the Flux `minimal`/full split

[`k8s/bootstrap/cluster/flux/envs/<env>/kustomization.yaml`](../../k8s/bootstrap/cluster/flux/envs/) points
each environment at one of two Flux resource sets:

| Set | Environments | Apps deployed |
| --- | --- | --- |
| `sets/minimal` | `dbg`, `dev`, `poc`, `src` | [`apps/diag/whoami`](../../k8s/apps/diag/whoami/), [`apps/monitoring/metrics-server`](../../k8s/apps/monitoring/metrics-server/) only |
| `sets` (full: minimal + optional) | `head`, `prod`, `qa`, `rebuild` | + [`adguard`](../../k8s/apps/dns/adguard/), [`unbound`](../../k8s/apps/dns/unbound/), [`actualbudget`](../../k8s/apps/finances/actualbudget/), [`checkmk-agent`](../../k8s/apps/monitoring/checkmk-agent/), [`unifi-controller`](../../k8s/apps/network/unifi-controller/) |

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

### 2. How updates land

Which git ref an environment's Flux instance reconciles from (normally `main` — see the intro above for
`dev`'s `track-branch` exception) and how aggressively renovate-generated dependency-update PRs targeting
that environment's overlay get automerged are both covered in full in
[`docs/update handling.md`](../update%20handling.md), not duplicated here — that doc owns the update-handling
story end to end (labels, mergify/renovate rules, per-app version pinning), this one owns what each
environment structurally *is*.

One structural fact worth stating here because it isn't about renovate automerge at all: `terragrunt apply`
against `prod` or `qa` may only ever run from a `main` checkout, no exceptions — see
[`../../CLAUDE.md`](../../CLAUDE.md)'s Terragrunt rule. Unlike Flux config (which can be reverted by pointing
back at `main`), a Terragrunt apply from a branch creates real cloud state that only matches that unmerged
branch; the only way back in sync is merging it, not reverting.

## Per-environment resource sizing (Terragrunt)

Each environment's `terragrunt/<non-prod|prod>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl` overrides the
shared [`_envcommon/vehagn-k8s.hcl`](../../terragrunt/_envcommon/vehagn-k8s.hcl) include, which wraps the
[`isejalabs/terraform-proxmox-talos`](https://github.com/isejalabs/terraform-proxmox-talos) module (the
actual Proxmox VM + Talos provisioning logic — not vendored into this repo). `env.hcl` itself is trivial
(`locals { env = "<name>" }`) — the real differentiation is node topology, sizing tier, and which
Talos/Kubernetes version and module ref each environment tracks:

| env | control-plane + worker nodes | `on_boot` | sizing tier | Talos / Kubernetes | module `source` |
| --- | --- | --- | --- | --- | --- |
| `dbg` | 1 + 1 (rest commented out) | `false` | small | pinned (same as most) | git tag |
| `dev` | 1 + 3 | `true` | medium | pinned (same as most) | git tag |
| `head` | 1 + 3 | `false` | big | **newest** (ahead of everyone else) | `ref=HEAD` (module's unreleased tip) |
| `poc` | 1 + 2 (+ its own extra `vms` module) | `false` | small | pinned (same as most) | git tag |
| `prod` | **3 + 3** (only full-HA control plane) | `true` | big | own separately-pinned version | git tag; real domain hardcoded, not the envcommon placeholder |
| `qa` | 1 + 3 | `true` | big/medium | pinned (same as most) | git tag |
| `rebuild` | 1 + 3 | `false` | big/medium | pinned (same as most) | git tag |
| `src` | 1 + 1 | `false` | small | pinned (same as most) | **local filesystem path** — an uncommitted checkout of the module's own source |

Two entries are worth calling out because they're structural, not just sizing choices:

- **`head`**'s Terraform module source is pinned to the module's unreleased tip, not a tagged release —
  [`terragrunt/non-prod/eu-central-1/head/vehagn-k8s/terragrunt.hcl`](../../terragrunt/non-prod/eu-central-1/head/vehagn-k8s/terragrunt.hcl):
  ```hcl
  source = "git::https://github.com/isejalabs/terraform-proxmox-talos.git?ref=HEAD"
  ```
  paired with `kubernetes_version = "v1.37.0"` / `talos version = "v1.14.0"` — both ahead of every other
  environment's pinned versions. This is the same "track bleeding-edge" role `head` plays for app versions,
  extended to the underlying cluster module and Kubernetes/Talos itself.
- **`src`**'s module `source` is a **local path**, not a git ref at all —
  [`terragrunt/non-prod/eu-central-1/src/vehagn-k8s/terragrunt.hcl`](../../terragrunt/non-prod/eu-central-1/src/vehagn-k8s/terragrunt.hcl):
  ```hcl
  source = "${local.root_path}/../../terraform-proxmox-talos"
  ```
  i.e. an adjacent, uncommitted checkout of the Talos/Proxmox Terraform module's own source code — `src` is
  for developing and testing changes to that module itself before they're tagged and picked up by every
  other environment.

## Flux reconciliation interval

[`k8s/components/envs/<env>/cluster-param.yaml`](../../k8s/components/envs/) sets a per-environment
`FLUX_RECONCILIATION_INTERVAL`, applied to every Flux `Kustomization`/`HelmRelease` by the
[`set-flux-defaults`](kustomize.md#transformers-and-replacements) transformer:

| env | interval |
| --- | --- |
| `dbg`, `dev`, `poc`, `rebuild`, `src` | `10m` |
| `head`, `prod`, `qa` | `1h` |

This grouping doesn't line up with the app-deployment split above — it's its own axis, and no comment in the
repo states the rationale explicitly. The most plausible reading (flagged here as inferred,
not confirmed): `head`/`prod`/`qa` carry real, steady-state application state that doesn't need fast
convergence and benefits from less reconciliation churn, while the other five are more actively iterated on
during development/testing and get faster feedback.

## Domain and prefixing

Every non-prod environment's domain gets an environment prefix via the
[`prefix-domain`](kustomize.md#transformers-and-replacements) component (e.g. `dev-adguard.dev.iseja.net`);
`prod` is the sole environment that omits it, giving prod's hostnames the bare form
(`adguard.prod.iseja.net`) — confirmed uniformly across all 7 non-prod
[`k8s/components/envs/<env>/kustomization.yaml`](../../k8s/components/envs/) files, each including
`../../transformers/prefix-domain`; prod's is the only one that comments it out.

## What each environment is for

- **`prod`** — production. Only environment with a full 3-controlplane HA topology, its own separately
  pinned Talos/Kubernetes version, the real (unprefixed) domain, the full app+infra Flux set, and the `1h`
  reconciliation interval. It's the one environment excluded from the
  [`track-branch`](../../.agents/skills/track-branch/SKILL.md) skill's live-cluster testing entirely (line
  16: *"one or more of `dbg`, `dev`, `head`, `poc`, `qa`, `rebuild`, `src` (not `prod`)"*), baked into the
  manifests themselves, not just convention —
  [`k8s/infra/flux-system/flux-instance/envs/prod/helmrelease.yaml`](../../k8s/infra/flux-system/flux-instance/envs/prod/helmrelease.yaml)
  has no commented-out `ref:` override placeholder at all, unlike every other environment's copy of that
  file. See [`docs/update handling.md`](../update%20handling.md) for how prod's dependency-update policy
  differs from the others.
- **`qa`** — the validation gate immediately before prod: full app+infra Flux set, `1h` interval, and the
  same `main`-checkout-only Terragrunt restriction as prod (`../../CLAUDE.md`: *"`prod` and `qa` may only
  ever be applied from a `main` checkout — no exceptions"*). Changes get exercised here before they're
  considered safe for `prod`.
- **`head`** — the bleeding-edge tracking environment: unreleased-tip Terraform module (`ref=HEAD`) and the
  newest Talos/Kubernetes versions of any environment. Runs the full app set, so it's a live,
  continuously-updated real deployment used to catch breakage from new versions early — its
  dependency-update policy (see [`docs/update handling.md`](../update%20handling.md)) is built around that
  same role.
- **`poc`** — a proof-of-concept/throwaway testbed: not intended for long-term use and can be easily
  recreated if needed, unlike `dev`. Minimal app set (infra + diagnostics only), and the only environment
  with its own extra standalone `vms` Terragrunt module (`terragrunt/non-prod/eu-central-1/poc/vms/`) for ad
  hoc VM experiments beyond the standard cluster module. See
  [`docs/update handling.md`](../update%20handling.md) for how it also gets special dependency-update
  treatment, distinct from every other environment including `head`.
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
- **`dev`** — the primary development environment, `on_boot=true`, medium sizing, standard 1-controlplane +
  3-worker topology, minimal app set. Typically pointed at whatever feature branch is currently under
  development (via [`track-branch`](../../.agents/skills/track-branch/SKILL.md), see the intro above) or used
  for unit testing, rather than continuously tracking `main` like the always-on full-stack environments.
  Distinguished from `poc` by being long-lived rather than throwaway.
- **`dbg`** — a dedicated debugging environment, kept separate from `dev` specifically so investigating a bug
  doesn't collide with or pause `dev`'s own in-progress work — the maintenance/bugfixing track and the
  enhancement track get their own environments rather than competing for the same one. Smallest topology
  alongside `src` (1 controlplane + 1 worker only, rest of the node pool commented out in Terragrunt),
  `on_boot=false`, minimal app set.
- **`src`** — for developing the underlying
  [`terraform-proxmox-talos`](https://github.com/isejalabs/terraform-proxmox-talos) module itself, not the
  apps running on top of it: its `vehagn-k8s` module `source` points at a local, uncommitted checkout of that
  module rather than a git tag — the clearest naming confirmation in the whole set ("src" = source, as in the
  IaC module's own source code). Minimal topology and app set, `on_boot=false`, manually-applied config.

## Summary table

Dependency-update/automerge policy per environment is deliberately not a column here — see
[`docs/update handling.md`](../update%20handling.md) for that axis.

| env | apps | Terragrunt sizing | Flux interval | domain prefix | restrictions |
| --- | --- | --- | --- | --- | --- |
| `dbg` | minimal | small, 1+1 nodes, `on_boot=false` | 10m | yes | dedicated to debugging, kept separate from `dev` |
| `dev` | minimal | medium, 1+3 nodes, `on_boot=true` | 10m | yes | often tracks a feature branch via `track-branch` |
| `head` | full | big, newest Talos/K8s, `ref=HEAD` | 1h | yes | none |
| `poc` | minimal | small, 1+2 nodes + extra `vms` module | 10m | yes | none |
| `prod` | full | big, 3+3 HA nodes, own pinned version | 1h | **no** | `main`-only apply; excluded from `track-branch` |
| `qa` | full | big/medium, 1+3 nodes | 1h | yes | `main`-only apply |
| `rebuild` | full | big/medium (~`prod`, non-HA), 1+3 nodes | 10m | yes | periodic disaster-recovery rehearsal target |
| `src` | minimal | small, 1+1 nodes, local module source | 10m | yes | develops `terraform-proxmox-talos` itself |
