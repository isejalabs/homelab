# Checkmk site `free` merged into `prod`: result of phase 3 — 2026-10-29

**Date:** 2026-10-29. **Status:** Change applied; first-hour readings and an early-morning reading (about nine hours later) taken; one defect found afterwards, about one hour of metric history of the Proxmox hosts was missing, repaired on 2026-10-30 08:05 to 08:38 (see [24-hour reading](#24-hour-reading-early-morning-2026-10-30)), and on 2026-11-01 the 111 trend files and the history of the other 12 hosts were restored (see [second repair](#second-repair-trend-files-and-the-other-12-hosts-swapped-in-on-2026-11-01)); the one-week reading is still to be taken (see [Still to check](#still-to-check)). **Scope:** phase 3 of the [consolidation plan](../plans/2026-10-checkmk-consolidation.md#phase-3--merge-free-into-prod): the 18 hosts of the Nagios site `free` moved to `prod`, `free` stopped, the metric history of the six Proxmox hosts kept. It does not cover `prod_k8s`, `core` or the memory of CT 7002056 (phase 4). **Origin:** Claude (Claude Code), REST API of `prod` (folders, hosts, activation), a root shell on `monitoring2` for the file copies and `omd stop free`, `lq` (livestatus) for the readings; the pillar change, the Salt run and the deletion of the site connection were done by the owner. **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783), umbrella [#71](https://github.com/isejalabs/homelab/issues/71). Current state: [`monitoring-sites.md`](../reference/monitoring-sites.md#change-of-2026-10-29-free-merged-into-prod).

## What was done

The owner gave an explicit go for the sequence below. Pending changes in `prod` were empty before the first edit; CT 7002056 got the snapshot `pre_phase3_1783` first (next to the older `before-cmk-2-5`).

| Time (CET) | Step |
| --- | --- |
| 20:32 | `pct snapshot 7002056 pre_phase3_1783` on pve4 |
| ~20:33 | Copied the 17 `autochecks/*.mk` files and the six RRD directories `free` to `prod` (first pass, 578/420/416/648/608/538 files); created the hosts `plug-trockner` and `plug-waschmaschine` in `/iot` |
| 21:11 | `omd stop npcd` in `prod`; set `site: prod` on the folders `/external_sites`, `/network-2`, `/physical`, `/iot` (REST); one activation of `prod` and `free` (id `a091f502-…`), `free` had 0 hosts afterwards |
| 21:12 | `omd stop free`, `omd config free set AUTOSTART off`, final `rsync` of the six directories (the two copies on disk were identical, but `omd stop free` had not flushed `rrdcached`, see [24-hour reading](#24-hour-reading-early-morning-2026-10-30)), `omd start npcd` in `prod`; deleted the stale `prod` connection on pve4 |
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
- **CPU did not fall in the first hour; it rose** by about 0.2 to 0.4 cores of the container. The plan expected a drop of about 0.03 cores on top of the phase 1 effect. The first hour is not representative: the 104-service backlog, the periodic discovery that ran on the moved hosts, four re-registered agents and the Proxmox special agent of pve4 (36 seconds per run) all happened inside it. This has not been analysed further; the early-morning reading below shows the load settling back.
- **The load spike at 21:55** had no single cause that was identified; the top process at the time was a precompiled Python host check of `deb-cache.home.iseja.net` (a `prod` host that was already there).

## 24-hour reading (early morning, 2026-10-30)

Taken on 2026-10-30 between 06:22 and 06:27 CET, read only, about nine hours after the change. It is a night and early-morning reading, not a full day: the usual daytime use of the web interface is not in it. The container's load pattern was flat across yesterday (hourly means 0.74 to 0.83 cores from 06:00 to 20:00), so night against day is a small effect for this container.

**Container CT 7002056, Proxmox RRD** (`pvesh get /nodes/pve4/lxc/7002056/rrddata --timeframe day`, 1-minute points, `cpu` is a fraction of 3 vCPUs):

| Window (CET) | CPU (cores) | CPU pressure (some, %) | Memory "used" (GiB) |
| --- | --- | --- | --- |
| 2026-10-29 06:00 to 19:00, hourly means (before the change) | 0.74 to 0.83 (about 0.77) | 3.7 to 6.2 | 6.64 to 6.92 |
| 2026-10-29 20:57 to 21:11 (just before) | 0.81 | 5.7 | 6.46 |
| 2026-10-29 21:14 to 21:29 | 0.96 | 4.7 | 5.28 |
| 2026-10-29 22:00 to 23:00 | 0.84 | 4.3 | 5.62 |
| 2026-10-29 23:00 to 00:00 | 1.08 | 10.3 | 5.68 |
| 2026-10-30 00:00 to 02:00 | 0.76 | 3.3 | 5.34 |
| 2026-10-30 02:00 to 04:00 | 0.71 | 2.4 | 5.36 |
| 2026-10-30 04:00 to 06:00 (hourly: 0.73, 0.73) | 0.73 | 2.7 to 2.9 | 5.37 to 5.38 |

- **Memory** is 1.3 to 1.5 GiB lower than the day before and flat (5.3 to 5.4 GiB), against the 1.2 to 1.5 GiB of the plan. The creep seen in the first hour did not continue.
- **CPU** is about 0.05 cores (a few percent) lower than the day before at the same level of activity, which is inside the minute-to-minute noise (single minutes range from 0.5 to 1.4 cores). The first-hour rise (0.98 to 1.17 cores) was transient; it was not caused by a lasting extra load. The plan expected about 0.03 cores on top of phase 1, so the CPU target is met only in the sense of "not worse". The hour from 23:00 (1.08 cores, pressure 10.3%) is unexplained; there is no comparable hour from the day before in the 24-hour window to say whether it recurs.

**120-second samples** (`prod` Nagios including the checks it waited for, container cgroup; two runs, 06:22:45 and 06:24:44, while this reading's own `ssh`, `lq` and `/proc` scans were running, so they are inflated and not comparable with the Proxmox figures above):

| Value | 06:22:45 | 06:24:44 | For reference, 21:57 yesterday |
| --- | --- | --- | --- |
| `prod` Nagios incl. waited checks (cores) | 0.73 | 0.67 | 0.66 |
| `prod_k8s` cmc incl. waited checks (cores) | 0.004 | 0.004 | 0.003 |
| `prod_k8s` own processes (cores) | 0.082 | 0.082 | 0.064 |
| Container cgroup (cores) | 1.07 | 1.10 | 0.88 |
| New processes per second | 43 | 34 | 29 |

Proxmox shows 1.1 to 1.4 cores for 06:19 to 06:26 as well (hour mean 0.85 including this measurement), so the cgroup figure and the RRD agree for the window; the quiet night level is the 0.71 to 0.76 above. `free -m` at 06:23: used 5,622 MiB, 300 MiB buff/cache, 4,367 MiB free. The load average (1/5/15 minutes) was 16.7, 11.4, 9.0 at 06:23 and 9.8, 11.4, 9.6 at 06:26 (before the change: 7.9, 7.5, 6.7), under the measurement itself; a clean load figure was not taken.

**`prod` state (`lq`, 06:23):** 93 hosts, 1,954 services (1,951 yesterday), 2.49 host checks and 2.59 service checks per second. The moved set (631 services): 461 OK, 16 WARN, 43 CRIT, 7 UNKNOWN, 104 PEND (the two offline hosts), the same as at 21:57 yesterday (460, 17, 43, 7, 104). All 15 moved hosts that are online are UP; `pve2`, `pve3` and the two plugs are DOWN as before. `Check_MK` of `pve1`, `pve4`, `pve5`, `pve6` is OK (agent runs 6.3, 39.7, 4.7 and 1.7 seconds; the special agent of `pve4` is the expensive one).

### Defect: about one hour of metric history is missing

The RRD files copied to `prod` have a gap before the cutover, and `prod` filled it with a flat line. Found by comparing `CPU_load_load1.rrd` of `pve1` in `prod` and in the stopped `free`:

- `omd stop free` did **not** flush its `rrdcached` into the RRD files. The files of `free` end at 20:28 (`pve1`), 20:08 (`pve4`), 19:53 (`pve5`) and 19:58 (`pve6`) although `free` collected data until 21:11:58; the unflushed updates are only in `free`'s `rrdcached` journal (`/omd/sites/free/var/rrdcached/rrd.journal.*`, 120,000 lines, last update 21:11:58). "0 differences" of the final `rsync` compared the two copies on disk, not what `free` had collected.
- The first update that `prod` wrote after the cutover (about 21:13 to 21:24) came inside the heartbeat of the file (pnp4nagios uses 8,460 seconds), so RRDtool filled the whole gap with that one value. For `pve1` the graph in `prod` shows a flat line of 90.1 from 20:29 to about 21:24, real load values start after that; the files of the other three online hosts end at 19:53 to 20:08 in the same way (gaps of about 44 to 79 minutes); the flat fill was only looked at for this one file, and the other files of these hosts were not compared one by one.
- Not affected: everything before the gap (checked on `pve1`: the 1-minute points of 2026-10-29 06:00 to 20:28 are identical in `prod` and `free`), the older history (both files have 1-day points back to 2023-10-30), and everything collected in `prod` after 21:13.
- **Cause:** `rrdcached` runs with a journal (`-j`) and without `-F`, so it does not flush at shutdown; `omd stop` only keeps the journal. Before stopping a site that runs `rrdcached` with a journal, flush explicitly (`echo FLUSHALL | nc -U ~/tmp/run/rrdcached.sock` as the site user) and check the `last` time of a file on disk.
- It was repaired on 2026-10-30, see the plan and the result below. The journal of `free` is no longer needed for it.

### Repair plan and result (swapped in on 2026-10-30)

**Built (not live):** `/root/rrd-repair-1783/out/` on `monitoring2` (171 MB, 2,041 files of `pve1`, `pve4`, `pve5`, `pve6`; script `/root/rrd-repair-1783/rrdrepair.py`, copy in the session notes). It ran 30 minutes at `nice 19` and wrote only below that directory; no file of `prod` or `free` was touched. 32 files exist only in `prod` (new `corosync_latency` and similar services) and need nothing. The two offline hosts `pve2` and `pve3` have no gap.

**Method per file (all GAUGE, step 60 s):** copy the file of `free`, replay the journal updates newer than its last update (14,039 updates in total, 335 files had none), then take the file of `prod` and replace every row up to the end of `free`'s data by the repaired `free` row. Between that end and the first real `prod` sample (the flat line, at most until 21:30) the 5-minute and finer rows become unknown, and the coarser rows (30 minutes, 1 day) that touch that span are recomputed from the repaired 1-minute rows (20,805 rows). Constant metrics, where the flat line equals the real value, are left alone. Cost: the span from the end of `free`'s data (21:08 to 21:11) to the first agent sample after the re-registration (about 21:24) stays unknown; the values are rounded to 10 significant digits by the XML round trip.

**Validated:** 120 random files compared with the live files, 1-minute points from 2026-10-29 07:00 to 19:30 and from 21:45 to 2026-10-30 04:30: 0 differences (tolerance 1e-8). The window 19:30 to 21:45 differs in 2,051 of 16,320 points, which are the repaired ones. After 04:30 the live files differ only because `prod`'s `rrdcached` has not written the last hour to disk yet.

**Result of the swap (owner's go, 2026-10-30 08:05 to 08:38 CET):** the steps below ran as written with one change: `nc -U` does not exist on `monitoring2`, so the cache was flushed with `FLUSHALL` over the socket from Python, and the check that all 2,073 files had the same last update on disk and in the cache passed before `rrdcached` was stopped. The rebuild from the flushed state took 30 minutes with four parallel processes (it was planned at 10 to 12; the container load went to 14 to 18 meanwhile), so `npcd` stood still from 08:05:22 to 08:37:53 instead of 15 minutes; the spool (134 files) was processed within two minutes after the start. All 2,041 rebuilt files were compared with the live files before the swap: same last update, 0 differences outside the gap (1-minute, 5-minute and 30-minute averages, maxima and minima, tolerance 1e-8), 36,717 of 369,421 one-minute points in 19:00 to 22:00 changed. After the start: no `rrdcached` errors, last updates advance, `Check_MK` OK on pve1, pve4, pve5, pve6, the 5-minute points of the `pve1` load for 2026-10-29 20:20 to 21:10 read 3.7, 3.9, 5.2, 6.4, 6.9, 7.3, 5.0, 4.8, 7.1, 8.5 (before: a flat 90.1), unknown from 21:15 to 21:25 and real again from 21:30; `pve5` load15 and `pve6` ping `rta` show real values over the same window. The graphs in the web interface were not opened. Backup of the four directories before the swap: `/root/rrd-repair-1783/prod-before-swap.tar` (801 MB, remove when satisfied).

**Swap steps as planned (needed the owner's go; `npcd` stopped for about 15 minutes, the perfdata waits in the spool as at the cutover):**

1. As root on `monitoring2`: `omd stop npcd` (site `prod`, as in phase 3).
2. Flush the cache: `echo FLUSHALL | nc -U /omd/sites/prod/tmp/run/rrdcached.sock`; check that `rrdtool last` of a `pve1` file is within a few minutes of now.
3. `omd stop rrdcached`; back up the four directories: `tar -C /omd/sites/prod/var/pnp4nagios/perfdata -cf /root/rrd-repair-1783/prod-before-swap.tar pve{1,4,5,6}.home.iseja.net` (about 180 MB).
4. Rebuild from the flushed state, four hosts in parallel (3 vCPUs, about 10 to 12 minutes): `nice -n 19 python3 -I rrdrepair.py /root/rrd-repair-1783/out2 pveN.home.iseja.net`, then run the comparison again (0 differences outside the gap, `last` equal to the live file).
5. Swap the `.rrd` files from `out2` into the four directories (`chown prod:prod`, mode as the originals, `.xml` files untouched), then `omd start rrdcached` and `omd start npcd`.
6. Check: `last` of the files advances, `~/var/log/npcd.log` has no errors, `lq` unchanged, the `pve1` load graph for 2026-10-29 20:30 to 21:10 shows the real values (3.9 to 8.5) instead of the flat 90.1.
7. Rollback: stop `npcd` and `rrdcached`, unpack the tar over the directories, start both.

Side effects: graph ingestion lags by about 15 minutes and catches up from the spool; the rebuild uses about one core at lowest priority in a container that is at 0.7 to 1.1 cores on average, so a quiet time of the day is better. Afterwards keep `free` and `/root/rrd-repair-1783/` until the owner deletes them.

### Second repair: trend files and the other 12 hosts (swapped in on 2026-11-01)

Found on 2026-11-01 from two graphs, tracked in [#2116](https://github.com/isejalabs/homelab/issues/2116):

- **`pve1` `Filesystem /tank/pve` had no growth and trend from 2026-10-29 20:30 to 2026-10-30 21:41**, while the used space was continuous. Two causes. (1) The Checkmk value store of `free` (`~/tmp/check_mk/counters/<host>` on the monitoring site) was not carried over, and the filesystem check (`size_trend`) reports growth, trend and hours-left only when it has 24 hours of its own history ("Not enough data to calculate trend"); the first point in `prod` was 21:41, about 24 hours after the first check. That part cannot be recovered and has resolved itself. (2) The first repair above dropped the replayed journal data (20:28 to 21:08) of 111 `growth`, `trend` and `trend_hoursleft` files of `pve1`, `pve4`, `pve5` and `pve6`: for files that `prod` had not updated since the cutover, the script left out everything after `prod`'s last update. The "0 differences" check missed it because it compared the rebuilt files with live files that had the same gap.
- **The gateways (`gw2`, `gw3`, `gw4`) lacked ping and interface history before the cutover.** This is the phase 3 decision (history of the six Proxmox hosts only), not a fault; the files are intact in the stopped `free` (4,862 files over 18 hosts).

**Done with the owner's go on 2026-11-01** (`npcd` stopped from 14:05 to 14:47, 42 minutes, spool processed within two minutes after the start). Same method as the first repair (flush with `FLUSHALL` and check the on-disk `last`, stop `rrdcached`, tar of the affected files `/root/rrd-repair-1783/prod-before-swap2.tar` 406 MB, rebuild offline with four parallel processes, validate, swap, start), with three changes to the script: files where `prod` has nothing newer than the repaired `free` file are replaced by that file (76 of the 111 trend files; the other 35 merged as before); the RRAs of `free` and `prod` are matched by consolidation function, `pdp_per_row` and size instead of position (the RRA order of `sw01` and the gateways differs between the sites); files whose DS or RRA set differs are skipped. 1,021 files were rebuilt: the 111 trend files and 910 files of the 12 other hosts (`ap-kueche`, `ap-wozi`, `core-switch`, `google-dns`, `gw`, `gw2`, `gw3`, `gw4`, `gw-kdg`, `mailbox.rollernet.us`, `sw01`, `www.heise.de`). `prod` had no data of its own before the cutover in any of them. Not touched: files that exist only in `free` (services that do not exist in `prod`), files only in `prod`, and `gw2/TCP_Connections_FIN_WAIT_2.rrd` (the script failed on it, different DS set).

**Validated before the swap:** layout of all 1,021 files identical to the live files; 0 differences against `free` for the 5-minute and 30-minute averages and 30-minute minima from 2026-10-23 and 2026-09-01 to 2026-10-29 19:00 (1-minute points of that period no longer exist in the live files, which keep two days); 0 differences against the live files after 22:00 for the 1-minute, 5-minute and 30-minute values (all but the 76 replaced files); `last` never older than the live file; in 2026-10-29 19:00 to 22:00, 1,014 files have more 5-minute points than before, 7 the same, none fewer. After the start: no `rrdcached` errors, spool at 3 files, the `tank/pve` growth and trend of `pve1` show real values from 20:30 to 21:05 (large growth values from 20:45 to 21:05), then unknown until the value store had its history, and `gw2` ping and `sw01` uptime are continuous from 19:30. The graphs in the web interface were not opened.

**Lesson:** a metric whose check keeps state between runs (trend, rate, average over time) starts empty in a new site unless the value store is copied. Copy `~/tmp/check_mk/counters/<host>` of the old site for the moved hosts, or accept the 24 hours.

## Still to check

- CPU and memory of `monitoring2` after a week (Proxmox RRD of CT 7002056 and pve4, daytime included), to decide the memory limit of CT 7002056 in phase 4 (not changed); the 24-hour reading above is a night reading.
- The graphs of the four Proxmox hosts and of the gateways in the web interface for 2026-10-29 19:30 to 22:00; then delete `/root/rrd-repair-1783/` (the tars `prod-before-swap.tar` and `prod-before-swap2.tar`, the rebuilt files).
- Whether the 20 added `corosync_latency` services and the "vanished" services reported by `Check_MK Discovery` on the four Proxmox hosts (for example `lnx_thermal`, `pvecm_nodes`) were there in `free` too; `free` is stopped, so this needs its stored state or a decision to leave them.
- A test notification: `prod` has no notification that can reach the owner (see [`monitoring-notifications.md`](../reference/monitoring-notifications.md)), so it was not tested; it can be simulated in Setup, Test notifications.
- The RRD history of the six Proxmox hosts in the graphs of `prod` (the files were compared with `free`, the graphs were not opened).
- Deleting the stopped `free` site and the snapshot `pre_phase3_1783`; proposal: after 90 days, owner to decide.
