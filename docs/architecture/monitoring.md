---
status: current
---

# Monitoring

How the homelab is monitored today: which Checkmk sites exist and why, how data gets from the clusters and the infrastructure into them, and which tool manages which part. The live values (sites, versions, intervals, service counts, notification settings, tuned thresholds) are in the reference docs listed [at the end](#where-the-details-are); this page only explains how they fit together.

## Checkmk, outside the clusters

Monitoring runs on [Checkmk](https://checkmk.com/), in two LXC containers on Proxmox (`monitoring1`, `monitoring2`), not inside any Kubernetes cluster — so a broken cluster can still be seen. Each container runs several Checkmk sites. There is no Prometheus/Grafana stack: `k8s/infra/o11y/` only pre-installs CRDs for one (see [`workloads.md`](workloads.md)), and its future is an open question of the [observability plan](../plans/2026-09-observability.md) ([#71](https://github.com/isejalabs/homelab/issues/71)).

The sites split along two lines:

- **Community sites** (`prod`, `free`) cover the infrastructure: physical hosts, Proxmox, the OPNsense gateways, VMs and LXCs, and general checks such as DNS, HTTP/TLS and SMTP. `free` is attached to `prod` through distributed monitoring, so `prod` gives one combined view. That `free` is a separate site at all is historical (see [why `free` exists](../reference/monitoring-sites.md#why-free-exists)); merging it into `prod` is phase 3 of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md).
- **Ultimate sites in the free licence state** (`prod_k8s`, `qa_k8s`, `dev_k8s`) give dynamic Kubernetes monitoring, one site per cluster, plus Smart Ping (the fast, sub-minute host check of the commercial core) in `prod_k8s`. The free licence state limits each site to 750 services and rules out distributed monitoring, so these sites stay standalone and their service count is itself monitored. `core`, which used to hold the Smart Ping hosts, is stopped and kept as an archive.

So "is a cluster healthy" has two answers: the `*_k8s` site of that cluster for detail, and `prod`, which also runs the Kubernetes special agent against `dev`, `qa`, `prod` and `rebuild` for the combined view (see [the `prod` site also queries the clusters](../reference/environments.md#the-prod-site-also-queries-the-clusters)).

## How data gets in

```
cluster (any env)                         Checkmk sites (monitoring1/2)
──────────────────                        ─────────────────────────────
checkmk-agent (Flux, k8s/apps/monitoring) ─► <env>_k8s site, and prod  (Kubernetes special agent, piggyback hosts)
Longhorn UI route  /v1/*                  ─► prod: API-only host per env (longhorn_capacity special agent)

out of cluster
──────────────
Checkmk agents on Linux hosts (Salt)      ─► prod / free
RustFS on TrueNAS (quota API)             ─► prod: API-only host per identity (rustfs_quota special agent)
Smart Ping targets (gateways, switches)   ─► prod_k8s  (/ping-only folder)
```

- **Kubernetes**: [`checkmk-agent`](../../k8s/apps/monitoring/checkmk-agent/) runs the Checkmk cluster and node collectors in every environment. A Checkmk site queries them with the Kubernetes special agent and creates piggyback hosts for nodes, namespaces and deployments.
- **Storage capacity**: Longhorn and RustFS are watched through custom special agents (`longhorn_capacity`, `rustfs_quota`) from [`isejalabs/checkmk-modules`](https://github.com/isejalabs/checkmk-modules). Each target gets a dedicated API-only host, because a special-agent rule on a host replaces its normal agent, and Checkmk runs only the first matching special-agent rule per host.
- **Linux hosts and appliances**: the regular Checkmk agent, deployed by Salt.

## Who manages what

Following [ADR 0013](../decisions/0013-repository-and-tool-boundaries.md) (tool boundaries) and [ADR 0015](../decisions/0015-checkmk-configuration-as-code.md) (Checkmk as code):

| Part | Managed by | Where |
| --- | --- | --- |
| The in-cluster collectors | Flux | [`k8s/apps/monitoring/checkmk-agent`](../../k8s/apps/monitoring/checkmk-agent/) |
| Monitoring containers, Checkmk agents, installing plugin packages | Salt | [`sebiklamar/salt-iseja.net`](https://github.com/sebiklamar/salt-iseja.net) |
| Special agents and check plugins | Released as MKP packages | [`isejalabs/checkmk-modules`](https://github.com/isejalabs/checkmk-modules) |
| Hosts, rules and Password Store entries for the custom special agents; the RustFS read-only identities | Terraform | `checkmk-*` and `rustfs-bucket-reader` units, see [`terragrunt/README.md`](../../terragrunt/README.md#checkmk-configuration) |
| Everything else in the sites (folders, most rules, notifications, Smart Ping hosts) | Manual, in the Checkmk UI or REST API | recorded in the reference docs below |

The manual part is the larger one today. The reference docs are its only written record, and where they and a live site disagree, the site wins.

## Notifications

Notifications are configured per site and never merged across sites. They are not yet live everywhere: the signal-to-noise clean-up that has to come first is tracked in [`monitoring-notifications.md`](../reference/monitoring-notifications.md) and under [#71](https://github.com/isejalabs/homelab/issues/71). Because the same host can exist in several sites, turning notifications on in more than one site notifies once per site ([#1901](https://github.com/isejalabs/homelab/issues/1901)).

## Where the details are

- [`reference/monitoring-sites.md`](../reference/monitoring-sites.md) — containers, sites, editions, check intervals, licence state, ping-only hosts.
- [`reference/monitoring-notifications.md`](../reference/monitoring-notifications.md) — notification settings per site and what is noise vs signal.
- [`reference/monitoring-thresholds.md`](../reference/monitoring-thresholds.md) — rules tuned against false positives, with their evidence.
- [`docs/operations/checkmk-automation-user.md`](../operations/checkmk-automation-user.md) — the role of the `terraform` user the Checkmk units use.
- [`plans/2026-10-checkmk-consolidation.md`](../plans/2026-10-checkmk-consolidation.md) and [`plans/2026-09-observability.md`](../plans/2026-09-observability.md) — where this is heading.
