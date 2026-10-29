# Checkmk site `free` merged into `prod`: result of phase 3 — 2026-10-29

**Date:** 2026-10-29. **Status:** Change applied; first-hour readings only, the CPU and memory comparison over a full day is still to be taken (see [Still to check](#still-to-check)). **Scope:** phase 3 of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md#phase-3--merge-free-into-prod): the 18 hosts of the Nagios site `free` moved to `prod`, `free` stopped, the metric history of the six Proxmox hosts kept. It does not cover `prod_k8s`, `core` or the memory of CT 7002056 (phase 4). **Origin:** Claude (Claude Code), REST API of `prod` (folders, hosts, activation), a root shell on `monitoring2` for the file copies and `omd stop free`, `lq` (livestatus) for the readings; the pillar change, the Salt run and the deletion of the site connection were done by the owner. **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783), umbrella [#71](https://github.com/isejalabs/homelab/issues/71). Current state: [`monitoring-sites.md`](../reference/monitoring-sites.md#change-of-2026-10-29-free-merged-into-prod).

## What was done

The owner gave an explicit go for the sequence below. Pending changes in `prod` were empty before the first edit; CT 7002056 got the snapshot `pre_phase3_1783` first (next to the older `before-cmk-2-5`).

| Time (CET) | Step |
| --- | --- |
| 20:32 | `pct snapshot 7002056 pre_phase3_1783` on pve4 |
| ~20:33 | Copied the 17 `autochecks/*.mk` files and the six RRD directories `free` to `prod` (first pass, 578/420/416/648/608/538 files); created the hosts `plug-trockner` and `plug-waschmaschine` in `/iot` |
| 21:11 | `omd stop npcd` in `prod`; set `site: prod` on the folders `/external_sites`, `/network-2`, `/physical`, `/iot` (REST); one activation of `prod` and `free` (id `a091f502-…`), `free` had 0 hosts afterwards |
| 21:12 | `omd stop free` (flushes `rrdcached`), `omd config free set AUTOSTART off`, final `rsync` of the six directories (0 differences), `omd start npcd` in `prod`; deleted the stale `prod` connection on pve4 |
| ~21:15 to 21:24 | Owner: pillar `monitoring_site: prod`, Salt run `apps/check-mk/cmk-agent-register` on pve1, pve4, pve5, pve6 |
| 21:20 to 21:27 | Restored the folder attributes and activated `prod` again (see [the mistake](#the-mistake)); `/iot` set to `no-agent` and `no-snmp` |
| 21:28 | Recreated the three fixed downtimes ("offline") of pve2, pve3 and pve6 through the Nagios command pipe |
| 21:38 | Owner deleted the site connection `free` in Setup and activated `prod` (audit log: `Deleted site free`) |

## The mistake

The folder update in the first activation used the REST `PUT` with `attributes: {"site": "prod"}`. `PUT` replaces the whole attribute set, so `/external_sites` lost `tag_agent: no-agent`, `tag_snmp_ds`, `tag_networking: wan` and its parent, `/physical` lost `tag_agent: all-agents` and the label `skl/server_role`, and `/iot` lost `tag_agent`. For roughly ten minutes the four ping-only hosts and the two plugs had `Check_MK` and `Check_MK Discovery` services that failed, and the WAN ping rule did not match (`gw-kdg` showed 60% loss). It was noticed from the service counts (3 services per ping-only host instead of 1), the values read before the change were put back with the full attribute set, and `prod` was activated again. Nothing notified (no notification is configured in `prod`). `/iot` is the exception: its old `tag_agent: ping` is not a valid tag in `prod` any more (the REST API refuses it as an enum value), so it is now `no-agent` plus `no-snmp`.

## Findings from the pre-checks

- "Monitored on site" is a **folder attribute** here; the four folders carried all 18 hosts. No rule, notification or other configuration in `prod` referred to the site `free`.
- The discovered services (`autochecks`) were **only on `free`**. They were copied so that the service set, and with it the RRD file names, stayed the same.
- Only pve1 to pve6 are **TLS pull agents** registered at `free`'s receiver (port 8002). `gw2`, `gw3`, `gw4` run the plain FreeBSD agent 2.1.0p27, `sw01`, `core-switch`, `ap-kueche`, `ap-wozi` use SNMP. `prod` and `free` share the container and its address, so no firewall or allow-list changed.
- The Salt model (`apps/check-mk/cmk-agent-register.sls` and its status script in the Salt repo) registers at the site named by the pillar `monitoring_site`. The status script treats a connection as healthy unless its `Remote:` block has an `Error:` line, so pve4's old `prod` connection (`Remote: Not registered`) would have been left alone; it had to be deleted by hand. pve2 and pve3 are offline and keep only their old `free` connection until they are powered on.
- **Downtimes and comments do not migrate** (`free` had three fixed downtimes, "offline").
- `terraform` (role Administrator in `prod`) can read and edit folders, create hosts and activate, but not delete a site connection ("Site management").

## Readings

Both from the Proxmox RRD of CT 7002056 (`pvesh get /nodes/pve4/lxc/7002056/rrddata`, 1-minute points; `cpu` is a fraction of the 3 vCPUs) and from inside the container.

| Value | Before (20:57 to 21:11) | After the merge, 21:14 to 21:29 | 21:30 to 21:56 |
| --- | --- | --- | --- |
| Memory "used" as Proxmox shows it (GiB) | 6.46 | 5.28 | 5.45 |
| `cpu` (fraction of 3 vCPUs) | 0.27 (0.80 cores) | 0.33 (0.98 cores) | 0.39 (1.17 cores) |
| CPU pressure (some, %) | 5.7 | 4.7 | 13.1 |

Inside the container (`free -m`): used 6,755 MiB at 20:15, 5,319 MiB at 21:35, 5,640 MiB at 21:55. The load average spiked to 39 (1 minute) at 21:55 with 19.6 and 16.0 for 5 and 15 minutes (7.9, 7.5, 6.7 before the change), and was back to 8.9, 14.0, 14.6 at 21:59.

A 120-second sample at 21:57 (CPU time of `prod`'s Nagios process including the checks it waited for, container cgroup): `prod` Nagios 0.66 cores, the container 0.88 cores, 29 new processes per second. `prod_k8s` was 0.064 cores (its own processes) and 0.003 cores of waited children. There is no earlier sample with this exact method for `prod` alone (the phase 1 audit measured `prod` at 0.25 and `free` at 0.06 cores on 2026-10-29 06:11 with a different method), so the container figure and the Proxmox RRD are the only before/after comparison.

State of the services: the moved set is 631 services (the 609 of `free`, one `PING` for each of the two plugs, and 20 `corosync_latency` services that `prod`'s periodic discovery added on pve1, pve4, pve5 and pve6). At 21:57: 460 OK, 17 WARN, 43 CRIT, 7 UNKNOWN and 104 PEND, the PEND being the 52 services each of pve2 and pve3 (both offline, never checked in `prod`). Before, in `free` (2026-10-29 06:11): 524 OK, 24 WARN, 47 CRIT, 10 UNKNOWN, 4 PEND, so no new UNKNOWN or PEND service apart from the two offline hosts. The 20 moved hosts all have a check interval of 1 minute, the moved services are at 5 minutes (614), 1 minute (7: the `PING`/`DNS` services of the external targets) or 125 minutes (10, the discovery services). `prod` has 93 hosts and 1,951 services (was 73 and 1,320 without the moved set).

## Reading the numbers

- **Memory fell by about 1.0 to 1.2 GiB** against the plan's 1.2 to 1.5 GiB, and is rising slowly again as `prod` loads the extra 631 services (page cache and the larger Nagios object cache). Treat 1.0 GiB as the lower bound until a day of data exists.
- **CPU did not fall in the first hour; it rose** by about 0.2 to 0.4 cores of the container. The plan expected a drop of about 0.03 cores on top of the phase 1 effect. The first hour is not representative: the 104-service backlog, the periodic discovery that ran on the moved hosts, four re-registered agents and the Proxmox special agent of pve4 (36 seconds per run) all happened inside it. This has not been analysed further, and the number must be re-read after a day.
- **The load spike at 21:55** had no single cause that was identified; the top process at the time was a precompiled Python host check of `deb-cache.home.iseja.net` (a `prod` host that was already there).

## Still to check

- CPU and memory of `monitoring2` after 24 hours and after a week (Proxmox RRD of CT 7002056 and pve4, the 120-second method per site), to decide whether the merge saved anything on CPU and to size phase 4 (the memory of CT 7002056 was not changed).
- Whether the 20 added `corosync_latency` services and the "vanished" services reported by `Check_MK Discovery` on the four Proxmox hosts (for example `lnx_thermal`, `pvecm_nodes`) were there in `free` too; `free` is stopped, so this needs its stored state or a decision to leave them.
- A test notification: `prod` has no notification that can reach the owner (see [`monitoring-notifications.md`](../reference/monitoring-notifications.md)), so it was not tested; it can be simulated in Setup, Test notifications.
- The RRD history of the six Proxmox hosts in the graphs of `prod` (the files and their last update were checked, the graphs were not opened).
- Deleting the stopped `free` site and the snapshot `pre_phase3_1783`; proposal: after 90 days, owner to decide.
