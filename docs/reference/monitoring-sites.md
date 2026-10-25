---
status: current
---

# Monitoring sites

**Status:** current as of 2026-10-19. Site roles and representative host assignments were checked against the live Checkmk configuration over read-only SSH on this date. **Tracking:** [#1780](https://github.com/isejalabs/homelab/issues/1780), [#1782](https://github.com/isejalabs/homelab/issues/1782), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

Authoritative inventory of the Checkmk containers and sites. Container and version details were read from the live hosts on 2026-10-18; site roles and representative host assignments were checked on 2026-10-19. Earlier point-in-time statements in [`2026-09-observability.md`](../audits/2026-09-observability.md) and its siblings are superseded where they conflict with this page; those audits stay unedited (see [`audits/README.md`](../audits/README.md)). The corrections are listed in [`2026-10-monitoring-container-oom.md`](../audits/2026-10-monitoring-container-oom.md#corrections-to-the-september-2026-audits).

## Containers

| Container | CT | Proxmox node | CPU / memory limit / swap | Sites |
| --- | --- | --- | --- | --- |
| `monitoring1.home.iseja.net` | 7002061 | pve5 (pve6 in the September audits) | 3 cores / 10 GiB / none | `core`, `qa_k8s`, `dev_k8s` |
| `monitoring2.home.iseja.net` | 7002056 | pve4 | 3 cores / 10 GiB (`memory: 10240`, raised from 8 GiB on 2026-10-19 after the [OOMs](../audits/2026-10-monitoring-container-oom.md)) / none | `free`, `prod`, `prod_k8s` |

Which sites send notifications, with what delay and period, is in [`monitoring-notifications.md`](monitoring-notifications.md).

Memory is a hard cgroup limit with no swap, so exceeding it kills processes inside the container. See [how to read the memory numbers](#reading-container-memory) below.

## Sites

All sites run Checkmk 2.5.0p15 since the upgrade on 2026-10-18 (`omd update` from 2.4.0p36; `prod_k8s` was already on 2.5.0p12).

| Site | Container | Edition | Purpose |
| --- | --- | --- | --- |
| `prod` | monitoring2 | Community (formerly RAW) | Main distributed-monitoring site. Monitors virtual hosts and general infrastructure checks such as DNS, HTTP/SSL, SMTP and TCP. Some of those checks are still assigned to `free` in the live configuration and appear in the combined view through distributed monitoring. Also monitors selected Kubernetes hosts and services, with nodes, namespaces and deployments added manually; the `*_k8s` sites provide automatic, dynamic Kubernetes monitoring. Since 2026-10-16 it also runs the Kubernetes special agent against the `dev`, `qa`, `prod` and `rebuild` clusters, see [the `prod` site also queries the clusters](environments.md#the-prod-site-also-queries-the-clusters). |
| `free` | monitoring2 | Community (formerly RAW) | Monitors physical hosts, including remote sites, and critical network infrastructure implemented as virtual OPNsense HA gateways. Live configuration confirms Proxmox nodes (for example `pve4`) and a gateway VM (`gw3`) are assigned here. It does not monitor Kubernetes hosts. Its data is included in `prod` through distributed monitoring. See [why `free` exists](#why-free-exists). |
| `prod_k8s` | monitoring2 | Ultimate | Production Kubernetes cluster. |
| `qa_k8s` | monitoring1 | Ultimate | QA Kubernetes cluster. |
| `dev_k8s` | monitoring1 | Ultimate | Dev Kubernetes cluster. Re-enabled on 2026-10-22 (autostart on, `omd config dev_k8s set AUTOSTART on`) after being stopped on 2026-10-19, to compare the dev cluster with `qa_k8s`/`prod_k8s` while investigating the collector warnings ([#1845](https://github.com/isejalabs/homelab/issues/1845)). `checkmk-kube-agent` runs in every environment, so dev is queryable again. |
| `core` | monitoring1 | Ultimate | Meant for Smart Ping of the LAN and WAN connection (all crucial physical hosts), the original intent of `free`. Smart Ping stopped working. Kept for now; a decommissioning candidate, not decided. |

### Why `free` exists

Hosts were once moved out of `prod` into a new site on a commercial edition, which offered Smart Ping and other features. Checkmk used to allow integrating such a remote site into the Community site for one combined view, then dropped that. `free` was therefore downgraded to Community and the split stayed. Merging `free` back into `prod` is possible but needs a data migration, so it has not been done. It is a recorded follow-up, not a plan.

## Reading container memory

Proxmox reports a container's memory as the cgroup's `memory.current` minus its file-backed pages. The file-backed pages include `shmem`, which cannot be reclaimed without swap. The Proxmox figure therefore understates what the OOM-killer counts. Verified on CT 7002056 on 2026-10-18: `memory.current` 6.95 GB minus `file` 1.41 GB is 5.54 GB, against Proxmox's 5.1–5.5 GiB.

| CT 7002056 (monitoring2) | Value |
| --- | --- |
| Proxmox "used" (idle, 2026-10-18 evening) | about 5.1–5.5 GiB (64–69 % of 8 GiB) |
| `anon` + `shmem` (idle, same time) | about 6.3 GiB (78 %) |
| `anon` + `shmem` at the first OOM kill (20:13:48) | about 7.9 GiB (98 %) |

Neither figure is a good alarm threshold on its own: the OOMs came from a short spike on top of the idle level, shorter than the 1-minute RRD resolution.
