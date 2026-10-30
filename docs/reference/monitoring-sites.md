---
status: current
---

# Monitoring sites

**Status:** current as of 2026-10-29 for `prod_k8s` and `core` (ping-only hosts in `prod_k8s`, `core` stopped, see [below](#ping-only-hosts-in-prod_k8s)) and for `prod` and `free` (`free` merged into `prod` and stopped, see [below](#change-of-2026-10-29-free-merged-into-prod)); check intervals and licence state as of 2026-10-20 (the `prod_k8s` rows updated 2026-10-28, the `free` row re-read after the phase 1 change on 2026-10-28); earlier sections as of 2026-10-19. Site roles and representative host assignments were checked against the live Checkmk configuration over read-only SSH on this date. **Tracking:** [#1780](https://github.com/isejalabs/homelab/issues/1780), [#1783](https://github.com/isejalabs/homelab/issues/1783), [#1782](https://github.com/isejalabs/homelab/issues/1782), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

Authoritative inventory of the Checkmk containers and sites. Container and version details were read from the live hosts on 2026-10-18; site roles and representative host assignments were checked on 2026-10-19. Earlier point-in-time statements in [`2026-09-observability.md`](../audits/2026-09-observability.md) and its siblings are superseded where they conflict with this page; those audits stay unedited (see [`audits/README.md`](../audits/README.md)). The corrections are listed in [`2026-10-monitoring-container-oom.md`](../audits/2026-10-monitoring-container-oom.md#corrections-to-the-september-2026-audits).

## Containers

| Container | CT | Proxmox node | CPU / memory limit / swap | Sites |
| --- | --- | --- | --- | --- |
| `monitoring1.home.iseja.net` | 7002061 | pve5 (pve6 in the September audits) | 3 cores / 10 GiB / none | `qa_k8s`, `dev_k8s`; `core` (stopped since 2026-10-29, archive) |
| `monitoring2.home.iseja.net` | 7002056 | pve4 | 3 cores / 10 GiB (`memory: 10240`, raised from 8 GiB on 2026-10-19 after the [OOMs](../audits/2026-10-monitoring-container-oom.md)) / none | `prod`, `prod_k8s` (`free` stopped since 2026-10-29) |

Which sites send notifications, with what delay and period, is in [`monitoring-notifications.md`](monitoring-notifications.md).

Memory is a hard cgroup limit with no swap, so exceeding it kills processes inside the container. See [how to read the memory numbers](#reading-container-memory) below.

## Sites

All sites run Checkmk 2.5.0p15 since the upgrade on 2026-10-18 (`omd update` from 2.4.0p36; `prod_k8s` was already on 2.5.0p12).

| Site | Container | Edition | Purpose |
| --- | --- | --- | --- |
| `prod` | monitoring2 | Community (formerly RAW) | Main site, and the only Community site left. Monitors virtual hosts, general infrastructure checks such as DNS, HTTP/SSL, SMTP and TCP, and, since 2026-10-29, also the physical hosts and the network gear that `free` used to monitor (the Proxmox nodes `pve1` to `pve6`, the gateways, switch and access points, the WAN targets, the two plugs). Also monitors selected Kubernetes hosts and services, with nodes, namespaces and deployments added manually; the `*_k8s` sites provide automatic, dynamic Kubernetes monitoring. Since 2026-10-16 it also runs the Kubernetes special agent against the `dev`, `qa`, `prod` and `rebuild` clusters, see [the `prod` site also queries the clusters](environments.md#the-prod-site-also-queries-the-clusters). |
| `free` | monitoring2 | Community (formerly RAW) | **Merged into `prod` and stopped on 2026-10-29** (`omd stop free`, `omd config free set AUTOSTART off`), see [the change](#change-of-2026-10-29-free-merged-into-prod). It monitored the physical hosts, including remote sites, and the critical network infrastructure implemented as virtual OPNsense HA gateways, as a remote site of `prod`. The site stays as a restorable archive (availability and event history, the RRD history of the 12 hosts that were not copied, its own discovered services); to bring it back see the rollback in that section. See [why `free` exists](#why-free-exists). |
| `prod_k8s` | monitoring2 | Ultimate | Production Kubernetes cluster. Since 2026-10-28 also the ten ping-only hosts that need a one-second or six-second Smart Ping, see [ping-only hosts](#ping-only-hosts-in-prod_k8s). |
| `qa_k8s` | monitoring1 | Ultimate | QA Kubernetes cluster. |
| `dev_k8s` | monitoring1 | Ultimate | Dev Kubernetes cluster. Re-enabled on 2026-10-22 (autostart on, `omd config dev_k8s set AUTOSTART on`) after being stopped on 2026-10-19, to compare the dev cluster with `qa_k8s`/`prod_k8s` while investigating the collector warnings ([#1845](https://github.com/isejalabs/homelab/issues/1845)). `checkmk-kube-agent` runs in every environment, so dev is queryable again. Meant to stay running (owner, 2026-10-28): its purpose is to anticipate the load of new apps for prod, to size requests and limits, until [#71](https://github.com/isejalabs/homelab/issues/71) settles or another way is found (`kubectl top pods`, or sizing in `qa`). It costs about 2.8 GiB on `monitoring1`, see [moving `monitoring1`](../audits/2026-10-monitoring1-placement.md). |
| `core` | monitoring1 | Ultimate | Smart Ping of the LAN and WAN connection (all crucial physical hosts), the original intent of `free`. Smart Ping works (checked 2026-10-28: all ten hosts UP with "Packet received via smart PING", the ICMP sender and receiver are running); the earlier "stopped working" report could not be reproduced. **Stopped on 2026-10-29** at 00:05 CET on the owner's go (`omd stop core`, `omd config core set AUTOSTART off`, phase 2b of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md)); its ten one-second and six-second hosts run in `prod_k8s` since 2026-10-28. The site and its data stay as a restorable archive; to bring it back: `omd start core`, `omd config core set AUTOSTART on`. In `prod` the `OMD core ...`/`Process core ...`/`Site core statistics` services of `monitoring1` are hidden by a Disabled-services rule (id `99854e7c-…`, 2026-10-29) and `core` is no longer in the service-count rule (below); delete that rule if `core` is started again. |

### Why `free` exists

Hosts were once moved out of `prod` into a new site on a commercial edition, which offered Smart Ping and other features. Checkmk used to allow integrating such a remote site into the Community site for one combined view, then dropped that. `free` was therefore downgraded to Community and the split stayed. Merging `free` back into `prod` needed a data migration (RRD history, discovered services, agent registrations); it was done on 2026-10-29, see [the change](#change-of-2026-10-29-free-merged-into-prod).

## Check intervals and licence state

Read from the live sites with `lq` (livestatus) on 2026-10-20: `check_interval` and `retry_interval` per host and per service, and the scheduled executions per minute computed from them (hosts: sum of 1 / interval; services: sum of count / interval). `dev_k8s` is stopped and was not read. The measured rate is the core's own `host_checks_rate` and `service_checks_rate`.

| Site | Core | Hosts | Host check (interval, command) | Services | Service intervals | Scheduled / min (hosts, services) | Measured / s (hosts, services) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `prod` (values of 2026-10-29 after the merge of `free`; 84 hosts and 1,411 services on 2026-10-20) | Nagios | 93 (73 own, 20 from `free` and the plugs) | 58 ping at 1 min (6 of them the WAN ping with 6 packets and 20 s timeout), 35 `host-ok` at 1 min | 1,951 | 1,880 at 5 min (1,794 passive, 86 active), 30 at 1 min, 41 at 125 min | 93, about 406 | 1.8 to 3.0, 4.3 to 9.6 (first hour after the merge, PEND services still filling; 0.3 to 1.0 and 5.3 to 6.5 on 2026-10-20) |
| `free` (merged into `prod` and stopped 2026-10-29, values of 2026-10-28) | Nagios | 18 | 18 ping at 1 min (12 of them at 1 second until 2026-10-28, see below) | 609 | 576 passive and 18 active at 5 min, 5 active at 1 min (the four `PING` services of `external_sites` and `DNS www.iseja.net` of `google-dns`), 10 at 125 min | 18, 124 | 0.36 to 0.38, 0.7 to 1.0 (before 2026-10-28: 5.4 to 5.8, 3.3 to 9.6) |
| `prod_k8s` | CMC | 83 (73 until 2026-10-28) | 73 `host-ok` at 1 min, 8 Smart Ping at 1 second, 2 Smart Ping at 6 seconds | 599 (679 until 2026-10-21, 589 until 2026-10-28, see below) | 443 at 1 min (370 passive, 73 active), 10 `PING` at 5 min, 73 at 33 min, 73 at 1,440 min | 73 plus 8 x 60 + 2 x 10, 445 | 9.4 to 11.8, 6.5 to 9.2 (2026-10-28 after the change; hosts were 1.7 to 3.0 and services 9.8 to 11.6 before it) |
| `core` (stopped 2026-10-29, values of 2026-10-20) | CMC | 22 | **Smart Ping**: 11 at 1 second, 10 at 6 seconds, 1 ping at 1 second | 636 | 478 passive and 7 active at 5 min, 125 passive and 15 active at 1 min, 11 at 125 min | 820, 237 | 13.6, 2.2 |
| `qa_k8s` | CMC | 68 | 68 `host-ok` at 1 min | 616 | 480 at 1 min (412 passive, 68 active), 68 at 5 min, 68 at 1,440 min | 68, 494 | 3.5, 10.8 |
| `dev_k8s` | CMC | not read (stopped) | | | | | |

Scheduled and measured rates agree for `prod`, `prod_k8s` and the `core` host checks (13.6 measured against 13.7 scheduled), and are within a factor of about 2 elsewhere, so the intervals above are roughly what the cores run. The host check commands in use are `check-mk-host-ping` (the `check_icmp` plugin, one process per check on Nagios), `check-mk-host-ok` and `check-mk-host-smart` (Smart Ping, `core` only).

### Change of 2026-10-28: `free` intervals

Phase 1 of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md) was applied in `prod` (the central site, `free` receives its configuration from there) and activated on `prod` and `free`, with REST API calls of the `terraform` user. Three rules changed, the rule properties carry a comment with the old value:

| Rule id | Rule set | Folder | Before | After |
| --- | --- | --- | --- | --- |
| `b308a945-20b6-4a98-bb01-7196024b6a38` | Normal check interval for service checks (`extra_service_conf:check_interval`, `Check_MK$`) | `/network-2` | 1 min | 5 min |
| `1e8aad76-e7b3-44d5-9329-30d1aca17202` | Normal check interval for host checks (`extra_host_conf:check_interval`) | `/external_sites` | 1 s | 1 min |
| `46616260-59d3-4b93-9bfd-e889d021dcbc` | Normal check interval for host checks (`extra_host_conf:check_interval`) | `/network-2` | 1 s | 1 min |

`core` keeps pinging the same 12 hosts every second (Smart Ping) until it is retired. Measured result: [`2026-10-checkmk-free-phase1-result.md`](../audits/2026-10-checkmk-free-phase1-result.md). To roll back, set the three rules to 1 minute, 1 second and 1 second and activate.

### Change of 2026-10-29: `free` merged into `prod`

Phase 3 of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md), [#1783](https://github.com/isejalabs/homelab/issues/1783), done on 2026-10-29 between 21:10 and 21:40 CET on the owner's go. Measured result and the order of the steps: [`2026-10-checkmk-free-merge-result.md`](../audits/2026-10-checkmk-free-merge-result.md).

What was done, all in `prod` unless stated:

- **Site attribute is a folder attribute.** The 18 hosts of `free` sat in four folders whose "Monitored on site" was `free` (`/external_sites`, `/network-2` with its subfolders `/network-2/network` and `/network-2/snmp-des` inheriting it, `/physical`, and the empty `/iot`). The four folders were set to `prod` (REST API, the `terraform` user), and `prod` and `free` activated in one run. No rule in `prod` depended on the site `free`. **Pitfall:** the REST `PUT` on a folder with `attributes` replaces the whole attribute set (tags, parents, labels), it does not merge; use `update_attributes` or send the full set. This happened once and was restored within minutes (see the result file). The old `tag_agent: ping` of `/iot` is not a valid tag in `prod` any more (the REST API refuses it), so `/iot` is now `no-agent` plus `no-snmp`, like `/external_sites`.
- **Services:** the discovered services (`var/check_mk/autochecks/*.mk`) live on the monitoring site, not on the central site, so `prod` had none of them. The 17 files were copied from `free` to `prod` before the activation (the service names, and with them the RRD file names, stay the same), plus the host-label files that `prod` did not have.
- **Metric history:** `~/var/pnp4nagios/perfdata/pve{1..6}.home.iseja.net/` (including the `.xml` files) was copied from `free` to `prod` in two passes (bulk beforehand, final pass after `omd stop free`, while `npcd` of `prod` was stopped so that the first perfdata waited in the spool). **Gap, repaired on 2026-10-30:** `omd stop free` did not flush its `rrdcached` (journal without `-F`), so the copied files ended 44 to 79 minutes before the cutover and `prod` filled that gap with a flat line; the missing updates were taken from `free`'s `rrdcached` journal and the files of the four online hosts rebuilt, see [the result](../audits/2026-10-checkmk-free-merge-result.md#defect-about-one-hour-of-metric-history-is-missing). Only 21:08 to about 21:24 (until the agents re-registered) stays unknown. Lesson: before stopping a site whose `rrdcached` has a journal, flush with `FLUSHALL` over `~/tmp/run/rrdcached.sock` and check the `last` time of a file on disk. The history of the other 12 hosts is left in the stopped `free`.
- **New hosts:** `plug-trockner.home.iseja.net` (10.7.9.137) and `plug-waschmaschine.home.iseja.net` (10.7.9.136) in `/iot`, ping only at 1 minute (both DOWN/CRITICAL, the plugs are unavailable in Home Assistant as well).
- **Agents:** only the six Proxmox hosts are TLS pull agents registered at `free`'s agent receiver (port 8002); `gw2`, `gw3`, `gw4` (FreeBSD agent 2.1.0p27) are plain and `sw01`, `core-switch`, `ap-kueche`, `ap-wozi` use SNMP. pve1, pve4, pve5 and pve6 were re-registered at `prod` (port 8001) by the Salt state `apps/check-mk/cmk-agent-register` of the Salt repo after the pillar value `monitoring_site` was switched from `free` to `prod`. pve4 had a stale `prod` connection (`Remote: Not registered`, no `Error:` line) that the status script of the state treats as healthy; it was deleted by hand (`cmk-agent-ctl delete <uuid>`) so that the state registers. `pve2` and `pve3` are offline; they register when powered on (the Salt state does it, with `monitoring_site` already `prod`).
- **Downtimes** do not migrate: the three fixed downtimes "offline" of `pve2`, `pve3` (until 2026-12-31 23:00 CET) and `pve6` (until 2027-01-01 00:00 CET) were recreated in `prod` through the Nagios command pipe (the REST API refused them with "should be monitored but it's not", which was not investigated further).
- **The `free` site** was stopped with `omd stop free`, `omd config free set AUTOSTART off`; the connection `free` was deleted in Setup, Distributed monitoring (the `terraform` role lacks the permission "Site management"); the old `sites.mk` is kept as `~/etc/check_mk/multisite.d/sites.mk.bak-1783` in `prod`. A CT snapshot `pre_phase3_1783` of CT 7002056 was taken first and is kept until the owner deletes it.
- **Service count of `prod`:** 1,951 services (no limit on the Community edition). The moved set is 631 services: the 609 of `free`, one `PING` for each plug, and 20 `corosync_latency` services that `prod`'s periodic discovery added on pve1, pve4, pve5 and pve6.

Rollback (until `free` is deleted): re-create the connection `free` from `sites.mk.bak-1783` (replication slave, `monitoring2.home.iseja.net:6602` TLS), set the four folders back to `site: free` (send the full attribute set, see above), activate, `omd config free set AUTOSTART on`, `omd start free`; re-register the four agents at `free` (pillar `monitoring_site: free`). The RRD files copied to `prod` can stay or be deleted.

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

The Community site `prod` has no limit (`free` is stopped).

On 2026-10-21 (22:26 to 22:39 CEST) the rule "Disabled services" (rule set `ignored_services`, folder Main, rule id `e1473dd0-5026-47e0-ab74-d906e9187ad7`) was created in `prod_k8s` for the six Kubernetes node hosts (`prod-ctrl-01` to `-03`, `prod-work-01` to `-03`, all `.home.iseja.net`) and the 15 services `CPU load`, `CPU resources`, `CPU utilization`, `Condition`, `Containers`, `Disk IO SUMMARY`, `Filesystem /`, `Info`, `Kernel Performance`, `Kubelet`, `Memory`, `Memory resources`, `Number of threads`, `Pod resources` and `Uptime` (each anchored with `$`). The same services are monitored on the same hosts in `prod` from the same piggyback source. The services of `prod_k8s` went from 679 to 589; each node keeps `Check_MK`, `Check_MK Agent`, `Check_MK Discovery` and `Check_MK HW/SW Inventory`. The services show under "Disabled services" in the host's service list; to undo, delete the rule and activate.

On the same day (22:44 CEST) the rule "Checkmk site performance and settings" (rule set `checkgroup_parameters:livestatus_status`, created in the central site `prod`, rule id `d9e78913-e40a-42c3-8761-667f5d67aeac`) was added with "Levels services" **warning at or above 675 and critical at or above 713** (90% and 95% of 750) for the monitoring sites `prod_k8s`, `qa_k8s` and `dev_k8s` (`core` was removed from it on 2026-10-29 when the site was stopped). It applies to the existing services `OMD <site> performance` of `monitoring1` and `monitoring2` in `prod`, which check every 5 minutes and show the service count as the metric `monitored_services`. Verified with `cmk -D`: the effective parameters of those four services (while `core` was still in the rule) contained `levels_services: (675, 713)`, `prod` and `free` have none. A real WARN has not been triggered.

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
- **Duplicate names:** the hosts also exist, since the merge of `free` (2026-10-29), in the unconnected site `prod` (and in the stopped `core` and `free`). This is no problem for the cores. Notifications are per site and never merged; `core`, `prod` and `free` have no notification rules and the rule of `prod_k8s` has no mail address (see [`monitoring-notifications.md`](monitoring-notifications.md)). It only matters when notifications are switched on in several sites ([#1901](https://github.com/isejalabs/homelab/issues/1901)): then the same outage notifies once per site.

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
