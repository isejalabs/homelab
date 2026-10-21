---
status: current
---

# Monitoring sites

**Status:** current as of 2026-10-20 (check intervals and licence state); earlier sections as of 2026-10-19. Site roles and representative host assignments were checked against the live Checkmk configuration over read-only SSH on this date. **Tracking:** [#1780](https://github.com/isejalabs/homelab/issues/1780), [#1782](https://github.com/isejalabs/homelab/issues/1782), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

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

## Check intervals and licence state

Read from the live sites with `lq` (livestatus) on 2026-10-20: `check_interval` and `retry_interval` per host and per service, and the scheduled executions per minute computed from them (hosts: sum of 1 / interval; services: sum of count / interval). `dev_k8s` is stopped and was not read. The measured rate is the core's own `host_checks_rate` and `service_checks_rate`.

| Site | Core | Hosts | Host check (interval, command) | Services | Service intervals | Scheduled / min (hosts, services) | Measured / s (hosts, services) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `prod` | Nagios | 84 | 47 ping at 1 min, 37 `host-ok` at 1 min | 1,411 | 1,349 at 5 min (1,220 passive, 129 active), 29 at 1 min, 33 at 125 min | 84, 299 | 0.3 to 1.0, 5.3 to 6.5 |
| `free` | Nagios | 18 | **12 ping at 1 second**, 6 ping at 1 min | 609 | 436 passive and 10 active at 5 min, **140 passive and 13 active at 1 min**, 10 at 125 min | 726, 242 | 5.8, 3.3 to 5.4 |
| `prod_k8s` | CMC | 73 | 73 `host-ok` at 1 min | 589 (679 until 2026-10-21, see below) | 443 at 1 min (370 passive, 73 active), 73 at 33 min, 73 at 1,440 min | 73, 445 | 1.7 to 3.0, 9.8 to 11.6 (measured before the change) |
| `core` | CMC | 22 | **Smart Ping**: 11 at 1 second, 10 at 6 seconds, 1 ping at 1 second | 636 | 478 passive and 7 active at 5 min, 125 passive and 15 active at 1 min, 11 at 125 min | 820, 237 | 13.6, 2.2 |
| `qa_k8s` | CMC | 68 | 68 `host-ok` at 1 min | 616 | 480 at 1 min (412 passive, 68 active), 68 at 5 min, 68 at 1,440 min | 68, 494 | 3.5, 10.8 |
| `dev_k8s` | CMC | not read (stopped) | | | | | |

Scheduled and measured rates agree for `prod`, `prod_k8s` and the `core` host checks (13.6 measured against 13.7 scheduled), and are within a factor of about 2 elsewhere, so the intervals above are roughly what the cores run. The host check commands in use are `check-mk-host-ping` (the `check_icmp` plugin, one process per check on Nagios), `check-mk-host-ok` and `check-mk-host-smart` (Smart Ping, `core` only).

### Licence state

All four Ultimate sites (`prod_k8s`, `core`, `qa_k8s`, `dev_k8s`) report **`LicenseState.FREE`** (read through the site's own licensing code). In the Checkmk 2.5.0p15 source (`cmk/utils/nonfree/pro/licensing`):

- The limit is `NUM_SERVICES_LIMIT = 750` services. It is counted per site from livestatus (`num_services` of the site), and the label `cmk/licensing:excluded` does not exclude anything in the free state.
- Above the limit, **Activate changes is blocked** (and the core may not start after a restart) until services are removed.
- **Distributed monitoring is not available** in the free state: a site with shadow hosts (including hosts added via CMCDump) has Activate changes blocked.
- Checkmk's published description of the free mode is "one site, up to 750 services" (Checkmk product pages and forum, see [the forum thread](https://forum.checkmk.com/t/question-about-free-enterprise-going-forward/59014)); the code enforces the service count per site. Whether running four separate free sites is within the licence terms was not checked.

| Site | Services | Headroom to 750 |
| --- | --- | --- |
| `prod_k8s` | 589 (679 before 2026-10-21) | 161 (79% used) |
| `core` | 636 | 114 |
| `qa_k8s` | 616 | 134 |
| `dev_k8s` | not read | |

The Community sites `prod` and `free` have no limit.

On 2026-10-21 (22:26 to 22:39 CEST) the rule "Disabled services" (rule set `ignored_services`, folder Main, rule id `e1473dd0-5026-47e0-ab74-d906e9187ad7`) was created in `prod_k8s` for the six Kubernetes node hosts (`prod-ctrl-01` to `-03`, `prod-work-01` to `-03`, all `.home.iseja.net`) and the 15 services `CPU load`, `CPU resources`, `CPU utilization`, `Condition`, `Containers`, `Disk IO SUMMARY`, `Filesystem /`, `Info`, `Kernel Performance`, `Kubelet`, `Memory`, `Memory resources`, `Number of threads`, `Pod resources` and `Uptime` (each anchored with `$`). The same services are monitored on the same hosts in `prod` from the same piggyback source. The services of `prod_k8s` went from 679 to 589; each node keeps `Check_MK`, `Check_MK Agent`, `Check_MK Discovery` and `Check_MK HW/SW Inventory`. The services show under "Disabled services" in the host's service list; to undo, delete the rule and activate.

## Reading container memory

Proxmox reports a container's memory as the cgroup's `memory.current` minus its file-backed pages. The file-backed pages include `shmem`, which cannot be reclaimed without swap. The Proxmox figure therefore understates what the OOM-killer counts. Verified on CT 7002056 on 2026-10-18: `memory.current` 6.95 GB minus `file` 1.41 GB is 5.54 GB, against Proxmox's 5.1–5.5 GiB.

| CT 7002056 (monitoring2) | Value |
| --- | --- |
| Proxmox "used" (idle, 2026-10-18 evening) | about 5.1–5.5 GiB (64–69 % of 8 GiB) |
| `anon` + `shmem` (idle, same time) | about 6.3 GiB (78 %) |
| `anon` + `shmem` at the first OOM kill (20:13:48) | about 7.9 GiB (98 %) |

Neither figure is a good alarm threshold on its own: the OOMs came from a short spike on top of the idle level, shorter than the 1-minute RRD resolution.
