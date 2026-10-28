---
status: current
---

# Monitoring sites

**Status:** current as of 2026-10-29 for `prod_k8s` and `core` (ping-only hosts in `prod_k8s`, `core` stopped, see [below](#ping-only-hosts-in-prod_k8s)); check intervals and licence state as of 2026-10-20 (the `prod_k8s` rows updated); earlier sections as of 2026-10-19. Site roles and representative host assignments were checked against the live Checkmk configuration over read-only SSH on this date. **Tracking:** [#1780](https://github.com/isejalabs/homelab/issues/1780), [#1782](https://github.com/isejalabs/homelab/issues/1782), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

Authoritative inventory of the Checkmk containers and sites. Container and version details were read from the live hosts on 2026-10-18; site roles and representative host assignments were checked on 2026-10-19. Earlier point-in-time statements in [`2026-09-observability.md`](../audits/2026-09-observability.md) and its siblings are superseded where they conflict with this page; those audits stay unedited (see [`audits/README.md`](../audits/README.md)). The corrections are listed in [`2026-10-monitoring-container-oom.md`](../audits/2026-10-monitoring-container-oom.md#corrections-to-the-september-2026-audits).

## Containers

| Container | CT | Proxmox node | CPU / memory limit / swap | Sites |
| --- | --- | --- | --- | --- |
| `monitoring1.home.iseja.net` | 7002061 | pve5 (pve6 in the September audits) | 3 cores / 10 GiB / none | `qa_k8s`, `dev_k8s`; `core` (stopped since 2026-10-29, archive) |
| `monitoring2.home.iseja.net` | 7002056 | pve4 | 3 cores / 10 GiB (`memory: 10240`, raised from 8 GiB on 2026-10-19 after the [OOMs](../audits/2026-10-monitoring-container-oom.md)) / none | `free`, `prod`, `prod_k8s` |

Which sites send notifications, with what delay and period, is in [`monitoring-notifications.md`](monitoring-notifications.md).

Memory is a hard cgroup limit with no swap, so exceeding it kills processes inside the container. See [how to read the memory numbers](#reading-container-memory) below.

## Sites

All sites run Checkmk 2.5.0p15 since the upgrade on 2026-10-18 (`omd update` from 2.4.0p36; `prod_k8s` was already on 2.5.0p12).

| Site | Container | Edition | Purpose |
| --- | --- | --- | --- |
| `prod` | monitoring2 | Community (formerly RAW) | Main distributed-monitoring site. Monitors virtual hosts and general infrastructure checks such as DNS, HTTP/SSL, SMTP and TCP. Some of those checks are still assigned to `free` in the live configuration and appear in the combined view through distributed monitoring. Also monitors selected Kubernetes hosts and services, with nodes, namespaces and deployments added manually; the `*_k8s` sites provide automatic, dynamic Kubernetes monitoring. Since 2026-10-16 it also runs the Kubernetes special agent against the `dev`, `qa`, `prod` and `rebuild` clusters, see [the `prod` site also queries the clusters](environments.md#the-prod-site-also-queries-the-clusters). |
| `free` | monitoring2 | Community (formerly RAW) | Monitors physical hosts, including remote sites, and critical network infrastructure implemented as virtual OPNsense HA gateways. Live configuration confirms Proxmox nodes (for example `pve4`) and a gateway VM (`gw3`) are assigned here. It does not monitor Kubernetes hosts. Its data is included in `prod` through distributed monitoring. See [why `free` exists](#why-free-exists). |
| `prod_k8s` | monitoring2 | Ultimate | Production Kubernetes cluster. Since 2026-10-28 also the ten ping-only hosts that need a one-second or six-second Smart Ping, see [ping-only hosts](#ping-only-hosts-in-prod_k8s). |
| `qa_k8s` | monitoring1 | Ultimate | QA Kubernetes cluster. |
| `dev_k8s` | monitoring1 | Ultimate | Dev Kubernetes cluster. Re-enabled on 2026-10-22 (autostart on, `omd config dev_k8s set AUTOSTART on`) after being stopped on 2026-10-19, to compare the dev cluster with `qa_k8s`/`prod_k8s` while investigating the collector warnings ([#1845](https://github.com/isejalabs/homelab/issues/1845)). `checkmk-kube-agent` runs in every environment, so dev is queryable again. Meant to stay running (owner, 2026-10-28): its purpose is to anticipate the load of new apps for prod, to size requests and limits, until [#71](https://github.com/isejalabs/homelab/issues/71) settles or another way is found (`kubectl top pods`, or sizing in `qa`). It costs about 2.8 GiB on `monitoring1`, see [moving `monitoring1`](../audits/2026-10-monitoring1-placement.md). |
| `core` | monitoring1 | Ultimate | Smart Ping of the LAN and WAN connection (all crucial physical hosts), the original intent of `free`. Smart Ping works (checked 2026-10-28: all ten hosts UP with "Packet received via smart PING", the ICMP sender and receiver are running); the earlier "stopped working" report could not be reproduced. **Stopped on 2026-10-29** at 00:05 CET on the owner's go (`omd stop core`, `omd config core set AUTOSTART off`, phase 2b of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md)); its ten one-second and six-second hosts run in `prod_k8s` since 2026-10-28. The site and its data stay as a restorable archive; to bring it back: `omd start core`, `omd config core set AUTOSTART on`. `prod` still has its `OMD core ...`/`Process core ...` services on `monitoring1` and the entry of `core` in the service-count rule (below), which show stale or vanished values until they are cleaned up. |

### Why `free` exists

Hosts were once moved out of `prod` into a new site on a commercial edition, which offered Smart Ping and other features. Checkmk used to allow integrating such a remote site into the Community site for one combined view, then dropped that. `free` was therefore downgraded to Community and the split stayed. Merging `free` back into `prod` is possible but needs a data migration, so it has not been done. It is a recorded follow-up, not a plan.

## Check intervals and licence state

Read from the live sites with `lq` (livestatus) on 2026-10-20: `check_interval` and `retry_interval` per host and per service, and the scheduled executions per minute computed from them (hosts: sum of 1 / interval; services: sum of count / interval). `dev_k8s` is stopped and was not read. The measured rate is the core's own `host_checks_rate` and `service_checks_rate`.

| Site | Core | Hosts | Host check (interval, command) | Services | Service intervals | Scheduled / min (hosts, services) | Measured / s (hosts, services) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `prod` | Nagios | 84 | 47 ping at 1 min, 37 `host-ok` at 1 min | 1,411 | 1,349 at 5 min (1,220 passive, 129 active), 29 at 1 min, 33 at 125 min | 84, 299 | 0.3 to 1.0, 5.3 to 6.5 |
| `free` | Nagios | 18 | **12 ping at 1 second**, 6 ping at 1 min | 609 | 436 passive and 10 active at 5 min, **140 passive and 13 active at 1 min**, 10 at 125 min | 726, 242 | 5.8, 3.3 to 5.4 |
| `prod_k8s` | CMC | 83 (73 until 2026-10-28) | 73 `host-ok` at 1 min, 8 Smart Ping at 1 second, 2 Smart Ping at 6 seconds | 599 (679 until 2026-10-21, 589 until 2026-10-28, see below) | 443 at 1 min (370 passive, 73 active), 10 `PING` at 5 min, 73 at 33 min, 73 at 1,440 min | 73 plus 8 x 60 + 2 x 10, 445 | 9.4 to 11.8, 6.5 to 9.2 (2026-10-28 after the change; hosts were 1.7 to 3.0 and services 9.8 to 11.6 before it) |
| `core` (stopped 2026-10-29, values of 2026-10-20) | CMC | 22 | **Smart Ping**: 11 at 1 second, 10 at 6 seconds, 1 ping at 1 second | 636 | 478 passive and 7 active at 5 min, 125 passive and 15 active at 1 min, 11 at 125 min | 820, 237 | 13.6, 2.2 |
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
| `prod_k8s` | 599 (679 before 2026-10-21, 589 before 2026-10-28) | 151 (80% used) |
| `core` (stopped 2026-10-29) | 636 | 114 |
| `qa_k8s` | 616 | 134 |
| `dev_k8s` | not read | |

The Community sites `prod` and `free` have no limit.

On 2026-10-21 (22:26 to 22:39 CEST) the rule "Disabled services" (rule set `ignored_services`, folder Main, rule id `e1473dd0-5026-47e0-ab74-d906e9187ad7`) was created in `prod_k8s` for the six Kubernetes node hosts (`prod-ctrl-01` to `-03`, `prod-work-01` to `-03`, all `.home.iseja.net`) and the 15 services `CPU load`, `CPU resources`, `CPU utilization`, `Condition`, `Containers`, `Disk IO SUMMARY`, `Filesystem /`, `Info`, `Kernel Performance`, `Kubelet`, `Memory`, `Memory resources`, `Number of threads`, `Pod resources` and `Uptime` (each anchored with `$`). The same services are monitored on the same hosts in `prod` from the same piggyback source. The services of `prod_k8s` went from 679 to 589; each node keeps `Check_MK`, `Check_MK Agent`, `Check_MK Discovery` and `Check_MK HW/SW Inventory`. The services show under "Disabled services" in the host's service list; to undo, delete the rule and activate.

On the same day (22:44 CEST) the rule "Checkmk site performance and settings" (rule set `checkgroup_parameters:livestatus_status`, created in the central site `prod`, rule id `d9e78913-e40a-42c3-8761-667f5d67aeac`) was added with "Levels services" **warning at or above 675 and critical at or above 713** (90% and 95% of 750) for the monitoring sites `prod_k8s`, `qa_k8s`, `core` and `dev_k8s`. It applies to the existing services `OMD <site> performance` of `monitoring1` and `monitoring2` in `prod`, which check every 5 minutes and show the service count as the metric `monitored_services`. Verified with `cmk -D`: the effective parameters of those four services contain `levels_services: (675, 713)`, `prod` and `free` have none. A real WARN has not been triggered. If `core` is retired, delete its entry from the rule.

## Ping-only hosts in `prod_k8s`

Since 2026-10-28 (phase 2b of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md), [#1783](https://github.com/isejalabs/homelab/issues/1783)) `prod_k8s` monitors ten hosts that only need a fast ping, so that `core` can be retired. They sit in the folder `/ping-only` (host attributes `no-agent`, `no-snmp`, IPv4 only), have no agent and no SNMP, and their host check is **Smart Ping** (`check-mk-host-smart`). Same names as in `core` and `free`, no suffix (the FQDNs of `core`, and `google-dns` without domain).

| Host | Address | Host check interval | Note |
| --- | --- | --- | --- |
| `gw.home.iseja.net` | 10.7.0.1 | 1 s | cluster of `gw2` and `gw3` in `core`; a plain host here, virtual address |
| `gw2.home.iseja.net` | 10.7.0.2 | 1 s | |
| `gw3.home.iseja.net` | 10.7.0.3 | 1 s | |
| `gw4.home.iseja.net` | 192.168.8.4 | 1 s | test host of 2026-10-28 |
| `gw-kdg.home.iseja.net` | 188.195.100.252 | 1 s | tag `networking: wan` |
| `google-dns` | 8.8.8.8 | 1 s | tag `networking: wan` |
| `sw01.home.iseja.net` | 10.7.10.50 | 1 s | alias `switch-kueche.home.iseja.net` |
| `core-switch.home.iseja.net` | 10.7.20.150 | 1 s | |
| `ap-wozi.home.iseja.net` | 10.7.20.151 | 6 s (default) | |
| `ap-kueche.home.iseja.net` | 10.7.20.152 | 6 s (default) | |

How it is configured, all in `prod_k8s` (Setup, click-ops or the REST API; nothing of it is in this repository):

- **Interval:** one rule in "Normal check interval for host checks" (rule id `34109bf2-0ce1-4d5e-b4e4-2e4f5ce853a3`, folder Main) sets 1 second (0.0166667 minutes) for the eight hosts by name. The two access points have no rule and use the Smart Ping default of 6 seconds (`SMARTPING_CHECK_INTERVAL` is 0.1 minutes in the Checkmk code).
- **Timeout:** no rule. The rule set "Settings for host checks via Smart Ping" (`cmc_smartping_settings`, one parameter, "Expected packet rate") defaults to 2.5 times the host check interval, so a 1-second host is DOWN after about 2.5 seconds without a packet and a 6-second host after 15 seconds (the 15 seconds in Checkmk's description is this 2.5 times 6 seconds). It is measured from the last packet seen, not from the last packet sent. A fixed rate in seconds is the alternative.
- **One `PING` service per host.** A ping-only host does **not** have zero services: when a host has no services at all, the CMC configuration generation adds an active `PING` service (`check_icmp`; Checkmk source `cmk/base/nonfree/cmc/_services.py`, comment "Nagios requires at least one service"). "Disabled services" does not remove it. Each of the ten hosts therefore counts one service towards the 750-service limit: `prod_k8s` went from 589 to 599 (headroom 151). A rule in "Normal check interval for service checks" (folder `/ping-only`, service `PING$`) sets the 10 services to 5 minutes instead of 1 minute, so they cost 2 `check_icmp` runs per minute in total. The `PING` service of the two WAN hosts uses the existing "Ping and host check parameters" rule for `networking: wan` (6 packets, 20 second timeout).
- **No parents.** `core` and `free` have parents for some of these hosts (`gw2` on `pve5`, `gw3` on `pve2`, `gw4` on `core-switch`); the parents do not exist in `prod_k8s`, so none are set and an outage shows as DOWN, not UNREACHABLE.
- **REST API:** `prod_k8s` has its own automation user `terraform` (role Administrator, secret stored in cleartext in the site, created on 2026-10-28 in the web interface). The URL is `https://monitoring2.home.iseja.net/prod_k8s/check_mk/api/1.0`. Activate changes through the API returns 403 when pending changes come from other users, unless foreign changes are allowed explicitly. The dynamic configuration daemon (`dcd`) of `prod_k8s` only manages the folder `k8s/prod`, the folder `/ping-only` is not touched by it.
- **Duplicate names:** the hosts also exist, or will after the merge of `free` (phase 3), in the unconnected sites `prod`/`free`. This is no problem for the cores. Notifications are per site and never merged; `core`, `prod` and `free` have no notification rules and the rule of `prod_k8s` has no mail address (see [`monitoring-notifications.md`](monitoring-notifications.md)). It only matters when notifications are switched on in several sites ([#1901](https://github.com/isejalabs/homelab/issues/1901)): then the same outage notifies once per site.

Measured on 2026-10-28 after the change (`lq "GET status"` and the CPU seconds of all processes of the site over 120 seconds, record in the audit linked below): `prod_k8s` 83 hosts, 599 services, 9.4 host checks per second (1.7 before), 0.12 cores (0.10 before); `core` 0.04 cores. The ten `PING` services are OK at 5 minutes and the ten hosts are UP.

`core` was stopped on 2026-10-29 at 00:05 CET (see the [site table](#sites)); [`2026-10-checkmk-core-stopped-result.md`](../audits/2026-10-checkmk-core-stopped-result.md) has the memory and CPU figures.

Time to DOWN, measured on 2026-10-28 with a controlled outage of `8.8.8.8` on `monitoring1` and `monitoring2` at the same second: `core` and `prod_k8s` logged DOWN in the same second, 6 seconds after the block, and UP within 1 second after it ended, so the new ping detects an outage as fast as the old one. Method, log lines and caveats: [`2026-10-checkmk-prod-k8s-ping-only-result.md`](../audits/2026-10-checkmk-prod-k8s-ping-only-result.md).

## Reading container memory

Proxmox reports a container's memory as the cgroup's `memory.current` minus its file-backed pages. The file-backed pages include `shmem`, which cannot be reclaimed without swap. The Proxmox figure therefore understates what the OOM-killer counts. Verified on CT 7002056 on 2026-10-18: `memory.current` 6.95 GB minus `file` 1.41 GB is 5.54 GB, against Proxmox's 5.1–5.5 GiB.

| CT 7002056 (monitoring2) | Value |
| --- | --- |
| Proxmox "used" (idle, 2026-10-18 evening) | about 5.1–5.5 GiB (64–69 % of 8 GiB) |
| `anon` + `shmem` (idle, same time) | about 6.3 GiB (78 %) |
| `anon` + `shmem` at the first OOM kill (20:13:48) | about 7.9 GiB (98 %) |

Neither figure is a good alarm threshold on its own: the OOMs came from a short spike on top of the idle level, shorter than the 1-minute RRD resolution.
