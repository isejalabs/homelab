---
status: current
---

# Environments — reference

Per-environment factual values: Terragrunt sizing, Flux reconciliation interval, domain/naming schemes, and
the numeric-ID-keyed VM/ASN/LB-pool/API-VIP block. For what each environment is *for*, and how these axes
relate conceptually, see [`docs/architecture/environments.md`](../architecture/environments.md).

## Summary table

Dependency-update/automerge policy per environment is deliberately not a column here — see
[`docs/update-handling.md`](../update-handling.md) for that axis.

| env | apps | Cluster sizing | Flux interval | domain prefix | purpose |
| --- | --- | --- | --- | --- | --- |
| `dbg` | minimal | small, 1+1 nodes, `on_boot=false` | 10m | yes | dedicated debugging: investigate an incident on its own separate cluster, apart from `dev`'s enhancement work |
| `dev` | minimal | medium, 1+3 nodes, `on_boot=true` | 10m | yes | primary feature development and unit testing; often tracks a feature branch via `track-branch` |
| `head` | full | big, newest Talos/K8s, `ref=HEAD` | 1h | yes | bleeding-edge tracking to catch breakage from new versions early (not currently exercised as a regular, periodic process) |
| `poc` | minimal | small, 1+2 nodes + extra `vms` module | 10m | yes | proof-of-concept testbed for bigger, fundamental changes (e.g. GitOps controller or Terraform approach swaps), kept separate from `dev`'s smaller enhancements |
| `prod` | full | big, 3+3 HA nodes, own pinned version | 1h | **no** | production; `main`-only apply; excluded from `track-branch` |
| `qa` | full | big/medium, 1+3 nodes | 1h | yes | validation gate immediately before `prod`; `main`-only apply |
| `rebuild` | full | big/medium (~`prod`, non-HA), 1+3 nodes | 10m | yes | periodic disaster-recovery rehearsal target |
| `src` | minimal | small, 1+1 nodes, local module source | 10m | yes | develops `terraform-proxmox-talos` itself |

See [`docs/architecture/environments.md#what-each-environment-is-for`](../architecture/environments.md#what-each-environment-is-for)
for the reasoning behind the `purpose` column above.

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
[`set-flux-defaults`](../architecture/kustomize.md#transformers-and-replacements) transformer:

| env | interval |
| --- | --- |
| `dbg`, `dev`, `poc`, `rebuild`, `src` | `10m` |
| `head`, `prod`, `qa` | `1h` |

This grouping doesn't line up with the app-deployment split in [the conceptual doc](../architecture/environments.md#1-which-apps-run-there--the-flux-minimalfull-split)
— it's its own axis, and no comment in the repo states the rationale explicitly. The most plausible reading
(flagged here as inferred, not confirmed): `head`/`prod`/`qa` carry real, steady-state application state that
doesn't need fast convergence and benefits from less reconciliation churn, while the other five are more
actively iterated on during development/testing and get faster feedback.

## Domain and naming

Every non-prod environment's domain gets an environment prefix via the
[`prefix-domain`](../architecture/kustomize.md#transformers-and-replacements) component (e.g.
`dev-adguard.dev.iseja.net`); `prod` is the sole environment that omits it, giving prod's hostnames the bare
form (`adguard.prod.iseja.net`) — confirmed uniformly across all 7 non-prod
[`k8s/components/envs/<env>/kustomization.yaml`](../../k8s/components/envs/) files, each including
`../../transformers/prefix-domain`; prod's is the only one that comments it out.

Three separate per-environment naming schemes exist — app domains, the cluster API endpoint hostname, and
PowerDNS's own nameserver identity. They're keyed differently (env name alone, env name + tier domain, or
env name via `ns1.<env>.iseja.net`), so collecting them in one place here is purely for lookup convenience,
not because they share a mechanism:

| env | app domain (`<app>` = any deployed app) | API endpoint hostname | PowerDNS nameserver identity |
| --- | --- | --- | --- |
| `dbg` | `dbg-<app>.dbg.iseja.net` | `dbg-homelab-k8s-api.test.iseja.net` | `ns1.dbg.iseja.net` |
| `dev` | `dev-<app>.dev.iseja.net` | `dev-homelab-k8s-api.test.iseja.net` | `ns1.dev.iseja.net` |
| `head` | `head-<app>.head.iseja.net` | `head-homelab-k8s-api.test.iseja.net` | `ns1.head.iseja.net` |
| `poc` | `poc-<app>.poc.iseja.net` | `poc-homelab-k8s-api.test.iseja.net` | `ns1.poc.iseja.net` |
| `prod` | `<app>.prod.iseja.net` | `prod-homelab-k8s-api.home.iseja.net` | `ns1.prod.iseja.net` |
| `qa` | `qa-<app>.qa.iseja.net` | `qa-homelab-k8s-api.test.iseja.net` | `ns1.qa.iseja.net` |
| `rebuild` | `rebuild-<app>.rebuild.iseja.net` | `rebuild-homelab-k8s-api.test.iseja.net` | `ns1.rebuild.iseja.net` |
| `src` | `src-<app>.src.iseja.net` | `src-homelab-k8s-api.test.iseja.net` | `ns1.src.iseja.net` |

App domains are keyed by env name via `prefix-domain` above. The API endpoint hostname is keyed by env name
+ tier domain via each environment's Terragrunt `certSANs` entry (see [`Environment ID`](#environment-id)
below for the VIP this hostname resolves to). `ns1.<env>.iseja.net` is each zone's own NS target and SOA
MNAME — see [`network.md`](../architecture/network.md#dns-authoritative-zones-powerdns) for the PowerDNS
mechanism this identity is part of (the one-time SOA-placeholder fix in particular).

## Environment ID

Beyond its name, each environment also has a single-digit numeric ID, used wherever a name doesn't fit into a
fixed-width identifier:

| env | ID |
| --- | --- |
| `head` | 1 |
| `qa` | 2 |
| `dev` | 3 |
| `src` | 5 |
| `poc` | 6 |
| `rebuild` | 7 |
| `prod` | 8 |
| `dbg` | 9 |

Four places this shows up, all confirmed against the current values in the repo:

- **Proxmox VM IDs** — each `vehagn-k8s` Terragrunt module
  (`terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl`) assigns its nodes' `vm_id`s in the form
  `70081<id><n>`, where `<id>` is the environment ID above and `<n>` is a single-digit per-node counter
  (`1`-`3` reserved for control-plane nodes, `4`-`9` for workers) — a full range of `70081<id>1`–`70081<id>9`
  per environment, e.g. `head`'s (`id=1`) is `7008111`–`7008119`. Most environments only populate a subset of
  that range (`prod`'s active nodes are `7008181`–`7008186`, `qa`'s are `7008121`–`7008126`); the unused
  higher slots are just headroom the scheme leaves for extra workers, not actual VMs. `just
  proxmox::snapshot::*` (see [`docs/proxmox-vm-snapshots.md`](../proxmox-vm-snapshots.md)) and `just
  proxmox::vm::*` (see [`docs/proxmox-vm-power.md`](../proxmox-vm-power.md)) lean on this exact scheme to
  discover an environment's VMs via the Proxmox API, matching the full `1`-`9` range rather than assuming
  any fixed node count.
- **BGP ASN** — each environment's
  [`CiliumBGPClusterConfig`](../../k8s/infra/kube-system/cilium/envs/prod/bgp-cluster-config.yaml) sets
  `localASN` to `6452<id>` — e.g. `prod` (`id=8`) peers as ASN `64528` (see
  [`network.md`](../architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement) for the BGP setup
  this feeds into), `poc` (`id=6`) as `64526`. The peer ASN (`64520`, the OPNsense routers) is fixed and
  unrelated to this scheme.
- **Cilium LB IPAM pool** — each environment's
  [`CiliumLoadBalancerIPPool`](../../k8s/infra/kube-system/cilium/envs/) (named `bgp-pool`) carves its block
  out of `10.8.<id>.0/24` — the same `<id>` as this table, e.g. `prod` (`id=8`) gets `10.8.8.0/24`, `poc`
  (`id=6`) gets `10.8.6.0/24`. See [`network.md`](../architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement)
  for how that address space feeds BGP and becomes reachable (the full per-environment pool table is below).
- **Kubernetes API VIP** — each environment's control-plane VIP (`vip` in its `vehagn-k8s/terragrunt.hcl`,
  e.g. [`head`'s](../../terragrunt/non-prod/eu-central-1/head/vehagn-k8s/terragrunt.hcl)) sits at
  `10.7.8.1<id>0` — e.g. `head` (`id=1`) is `10.7.8.110`, `prod` (`id=8`) is `10.7.8.180`. That VIP is also
  where the cluster's API is reachable by hostname, via the `certSANs` entry each module sets — see the
  [API endpoint hostname column](#domain-and-naming) for the full per-environment table.

All four schemes key off the same single-digit ID, so the first three are summarized once here (the API VIP/
hostname isn't a fixed-width column, see the bullet above):

| env | ID | VM ID range | BGP ASN | LB IP pool |
| --- | --- | --- | --- | --- |
| `head` | 1 | `7008111`–`7008119` | `64521` | `10.8.1.0/24` |
| `qa` | 2 | `7008121`–`7008129` | `64522` | `10.8.2.0/24` |
| `dev` | 3 | `7008131`–`7008139` | `64523` | `10.8.3.0/24` |
| `src` | 5 | `7008151`–`7008159` | `64525` | `10.8.5.0/24` |
| `poc` | 6 | `7008161`–`7008169` | `64526` | `10.8.6.0/24` |
| `rebuild` | 7 | `7008171`–`7008179` | `64527` | `10.8.7.0/24` |
| `prod` | 8 | `7008181`–`7008189` | `64528` | `10.8.8.0/24` |
| `dbg` | 9 | `7008191`–`7008199` | `64529` | `10.8.9.0/24` |

The VM ID range is the full `<n>`-digit range the scheme allows (`1`-`9`), not what's actually defined —
most environments' `vehagn-k8s/terragrunt.hcl` only goes up to `<n>=6` (`prod`'s active nodes are
`7008181`–`7008186`, `dbg`'s slots reserved-but-commented-out top out at `7008196`), and `poc`/`src` stop at
`<n>=5` (only 5 node blocks defined at all). `<n>=7`-`9` is unused headroom everywhere today.

The LB IP pool column above (each pool's actual `CiliumLoadBalancerIPPool` block only spans `.8`–`.250` of
its `/24`, leaving the low and high ends free for infrastructure/reservations) is the single source for
this data — [`network.md`](../architecture/network.md#cilium-lb-ipam-and-bgp-route-advertisement) links back
here rather than keeping its own copy.
