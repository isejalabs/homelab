# Monitoring sites

**Status:** current as of 2026-10-18. **Tracking:** [#1780](https://github.com/isejalabs/homelab/issues/1780), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

Authoritative inventory of the Checkmk containers and sites. Values marked *(owner)* come from the owner, everything else was read from the live hosts on 2026-10-18. Earlier point-in-time statements in [`2026-09-observability.md`](../audits/2026-09-observability.md) and its siblings are superseded where they conflict with this page; those audits stay unedited (see [`audits/README.md`](../audits/README.md)). The corrections are listed in [`2026-10-monitoring-container-oom.md`](../audits/2026-10-monitoring-container-oom.md#corrections-to-the-september-2026-audits).

## Containers

| Container | CT | Proxmox node | CPU / memory limit / swap | Sites |
| --- | --- | --- | --- | --- |
| `monitoring1.home.iseja.net` | 7002061 | pve5 (pve6 in the September audits) | 3 cores / 10 GiB / none | `core`, `dev_k8s`, `qa_k8s` |
| `monitoring2.home.iseja.net` | 7002056 | pve4 | 3 cores / 8 GiB (`memory: 8196`) / none | `free`, `prod`, `prod_k8s` |

Memory is a hard cgroup limit with no swap, so exceeding it kills processes inside the container. See [how to read the memory numbers](#reading-container-memory) below.

## Sites

All sites run Checkmk 2.5.0p15 since the upgrade on 2026-10-18 (`omd update` from 2.4.0p36; `prod_k8s` was already on 2.5.0p12).

| Site | Container | Edition | Purpose |
| --- | --- | --- | --- |
| `prod` | monitoring2 | Community | Main Community-edition site. |
| `free` | monitoring2 | Community | *(owner)* Physical hosts and general (non-Kubernetes) infrastructure: DNS, HTTP/SSL, SMTP and TCP checks. Also monitors some Kubernetes nodes and services that `*_k8s` and `prod` monitor too (duplicate monitoring). See [why `free` exists](#why-free-exists). |
| `prod_k8s` | monitoring2 | Ultimate | Production Kubernetes cluster. |
| `dev_k8s`, `qa_k8s` | monitoring1 | Ultimate | Dev and QA Kubernetes clusters. |
| `core` | monitoring1 | Ultimate | *(owner)* Meant for Smart Ping of the LAN and WAN connection (all crucial physical hosts), the original intent of `free`. Smart Ping stopped working. Kept for now; a decommissioning candidate, not decided. |

### Why `free` exists

*(owner)* Hosts were once moved out of `prod` into a new site on a commercial edition, which offered Smart Ping and other features. Checkmk used to allow integrating such a remote site into the Community site for one combined view, then dropped that. `free` was therefore downgraded to Community and the split stayed. Merging `free` back into `prod` is possible but needs a data migration, so it has not been done. It is a recorded follow-up, not a plan.

## Reading container memory

Proxmox reports a container's memory as the cgroup's `memory.current` minus its file-backed pages. The file-backed pages include `shmem`, which cannot be reclaimed without swap. The Proxmox figure therefore understates what the OOM-killer counts. Verified on CT 7002056 on 2026-10-18: `memory.current` 6.95 GB minus `file` 1.41 GB is 5.54 GB, against Proxmox's 5.1–5.5 GiB.

| CT 7002056 (monitoring2) | Value |
| --- | --- |
| Proxmox "used" (idle, 2026-10-18 evening) | about 5.1–5.5 GiB (64–69 % of 8 GiB) |
| `anon` + `shmem` (idle, same time) | about 6.3 GiB (78 %) |
| `anon` + `shmem` at the first OOM kill (20:13:48) | about 7.9 GiB (98 %) |

Neither figure is a good alarm threshold on its own: the OOMs came from a short spike on top of the idle level, shorter than the 1-minute RRD resolution.
