---
status: current
---

# Monitoring sites

**Status:** current as of 2026-10-19; the [root filesystem section](#root-filesystem-growth) as of 2026-10-22. Site roles and representative host assignments were checked against the live Checkmk configuration over read-only SSH on 2026-10-19. **Tracking:** [#1843](https://github.com/isejalabs/homelab/issues/1843), [#1780](https://github.com/isejalabs/homelab/issues/1780), [#1782](https://github.com/isejalabs/homelab/issues/1782), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

Authoritative inventory of the Checkmk containers and sites. Container and version details were read from the live hosts on 2026-10-18; site roles and representative host assignments were checked on 2026-10-19. Earlier point-in-time statements in [`2026-09-observability.md`](../audits/2026-09-observability.md) and its siblings are superseded where they conflict with this page; those audits stay unedited (see [`audits/README.md`](../audits/README.md)). The corrections are listed in [`2026-10-monitoring-container-oom.md`](../audits/2026-10-monitoring-container-oom.md#corrections-to-the-september-2026-audits).

## Containers

| Container | CT | Proxmox node | CPU / memory limit / swap | Sites |
| --- | --- | --- | --- | --- |
| `monitoring1.home.iseja.net` | 7002061 | pve5 (pve6 in the September audits) | 3 cores / 10 GiB / none | `core`, `qa_k8s`, `dev_k8s` (stopped) |
| `monitoring2.home.iseja.net` | 7002056 | pve4 | 3 cores / 10 GiB (`memory: 10240`, raised from 8 GiB on 2026-10-19 after the [OOMs](../audits/2026-10-monitoring-container-oom.md)) / none | `free`, `prod`, `prod_k8s` |

Memory is a hard cgroup limit with no swap, so exceeding it kills processes inside the container. See [how to read the memory numbers](#reading-container-memory) below.

## Sites

All sites run Checkmk 2.5.0p15 since the upgrade on 2026-10-18 (`omd update` from 2.4.0p36; `prod_k8s` was already on 2.5.0p12).

| Site | Container | Edition | Purpose |
| --- | --- | --- | --- |
| `prod` | monitoring2 | Community (formerly RAW) | Main distributed-monitoring site. Monitors virtual hosts and general infrastructure checks such as DNS, HTTP/SSL, SMTP and TCP. Some of those checks are still assigned to `free` in the live configuration and appear in the combined view through distributed monitoring. Also monitors selected Kubernetes hosts and services, with nodes, namespaces and deployments added manually; the `*_k8s` sites provide automatic, dynamic Kubernetes monitoring. |
| `free` | monitoring2 | Community (formerly RAW) | Monitors physical hosts, including remote sites, and critical network infrastructure implemented as virtual OPNsense HA gateways. Live configuration confirms Proxmox nodes (for example `pve4`) and a gateway VM (`gw3`) are assigned here. It does not monitor Kubernetes hosts. Its data is included in `prod` through distributed monitoring. See [why `free` exists](#why-free-exists). |
| `prod_k8s` | monitoring2 | Ultimate | Production Kubernetes cluster. |
| `qa_k8s` | monitoring1 | Ultimate | QA Kubernetes cluster. |
| `dev_k8s` | monitoring1 | Ultimate | *(owner)* Stopped, autostart off (`omd config dev_k8s set AUTOSTART off`) since 2026-10-19: no Checkmk agent is deployed in dev. Data is kept; whether dev needs observability is part of [#71](https://github.com/isejalabs/homelab/issues/71). |
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

## Root filesystem growth

Tracking: [#1843](https://github.com/isejalabs/homelab/issues/1843). Read-only investigation on 2026-10-22 after Checkmk reported `Filesystem /` on both containers as CRIT ("full in about 30 days"). Root is an 11 GiB ZFS subvolume on each container.

| Container | Used (2026-10-22) | Steady growth since the upgrade settled |
| --- | --- | --- |
| `monitoring1` | 3.8 GiB (34 %) | about 3 MB/day |
| `monitoring2` | 6.2 GiB (56 %) | about 35–45 MB/day, so roughly 4 months of headroom |

- **The trend alarm mostly measures one-off steps, not steady growth.** The daily `fs_used` history shows jumps on 2026-10-02 and 2026-10-11 and drops on 2026-10-12 and 2026-10-19 (the `omd update` to 2.5.0p15). The "+3.3 / +4.4 GiB per 21 days" figures come from that window and cannot be reproduced as sustained growth. The alarm should clear once the window has moved past the upgrade.
- **Where the space is.** Checkmk 2.5 itself takes 2.3 GiB on `monitoring2` and 1.3 GiB on `monitoring1`. The old 2.4 versions are already gone, so `omd cleanup` has nothing to remove. Site data takes 2.2 GiB on `monitoring2` and 1.1 GiB on `monitoring1`.
- **Historical data that does not need to stay.** The Nagios log archive (`var/nagios/archive`, daily files back to 2015) is about 388 MB in `prod` and about 355 MB of files older than a year in each of `free` and `core`. The `licensing.log` of the Ultimate sites is 33–38 MB each. `apt` caches take 62 MB and journald 111 MB on `monitoring2`. These are the cleanup candidates.
- **Not identified yet.** The remaining roughly 40 MB/day on `monitoring2`. Candidates are the large `prod_k8s` logs (`wato_audit.log` 45 MB, core history 35 MB), journald and the `rrdcached` journals.
- **RRDs are not the cause.** Their files have a fixed size once created.

Handling of the trend alarm while this is open: if the `Filesystem /` trend drops to WARN it is acknowledged to take it off the dashboard; if it stays CRIT it stays visible for active monitoring. This is specific to #1843, not a general rule; acknowledgement handling is decided in [#71](https://github.com/isejalabs/homelab/issues/71).

### Cleanup applied on 2026-10-22

Applied on both containers: `apt-get clean` and removal of the `apt` package caches; journald vacuumed to 30 MB; Nagios archive files dated before 2025-10-22 deleted (752 in `core`, 752 in `free`, 4022 in `prod`); `licensing.log` truncated in every Ultimate site.

| Container | Used before | Used after |
| --- | --- | --- |
| `monitoring1` | 3.8 GiB (34 %) | 3.6 GiB (33 %) |
| `monitoring2` | 6.2 GiB (56 %) | 5.7 GiB (52 %) |

The gain is smaller than the file sizes suggest because ZFS compresses the logs. RRDs, core history, WATO audit logs and WATO snapshots were left alone. The `licensing.log` files regrow, so this is a one-off, not a retention setting. The trend state after the cleanup is not recorded yet.
