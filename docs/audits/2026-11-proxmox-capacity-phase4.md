---
date: 2026-11-11
status: Readings taken 12 days after the changes (2026-10-29), proposals only; nothing was changed on any host and the owner decides the memory limits and the pve1 relief
scope: the one-week readings that phase 4 of the Checkmk consolidation plan waits for — CPU and memory of CT 7002056 (`monitoring2`, pve4) and CT 7002061 (`monitoring1`, pve5), memory and load of pve1, pve4 and pve5, and the state of the Checkmk sites. It does not cover disk, network, power or the Kubernetes content of the `*_k8s` sites
origin: Claude (Claude Code), read-only SSH to pve1, pve4, pve5, monitoring1 and monitoring2 (Proxmox RRD through `pvesh`, the containers' cgroup files and `ps`, `lq` on the sites, the kernel logs of the three nodes). The scheduled tasks that should have taken these readings on 2026-11-05 had failed with a network error
tracking: https://github.com/isejalabs/homelab/issues/1783
preceding-record: 2026-10-checkmk-free-merge-result.md
data: data/2026-11-proxmox-capacity-phase4-daily.csv
---

# Phase 4 readings: Checkmk containers and Proxmox nodes — 2026-11-11

## Result

- **CT 7002056 (`monitoring2`) keeps its 10 GiB.** CPU fell by 0.31 cores (1.04 to 0.73) and the mean memory by 1.1 GiB, but the peaks did not fall: the highest 1-minute value since the merge is 7.92 GiB (2026-11-10 06:15), above the 7.66 GiB of the week before the changes. The memory climbs in steps of 0.5 to 1.7 GiB during the day and only drops at midnight, so the web-interface swing the plan warns about is real and as large as before. Lowering the limit would free nothing on pve4 (it has 12 to 17 GiB over its peaks) and leaves under 1 GiB of margin.
- **CT 7002061 (`monitoring1`) peaked at 7.79 GiB since `core` was stopped** (9.64 GiB in the week before, with the OOM kills of 2026-10-23), baseline 5.7 to 6.3 GiB. If a smaller limit is wanted, **9 GiB** keeps 1.2 GiB over that peak; it is accounting only, because pve5 is not tight any more (see next line) and the `qa_k8s` and `dev_k8s` sites are still growing.
- **pve5 is no longer the constraint.** Lowest available memory over the 12 days is 7.4 GiB with `rebuild-work-02` up (3.4 GiB in the week before the changes), load mean 3.4 (5.5), CPU pressure 1.5% (3.9%). Over the guests' peaks it has about 12 GiB (4.6 GiB in the [capacity audit](2026-10-proxmox-capacity.md)).
- **pve1 is now the tight node while `rebuild` runs.** With `rebuild-work-01` and `dev-ctrl-01` up (2026-10-29 to 2026-11-09 06:30) its lowest available memory was 1.6 GiB (no swap), load mean 7.7 (4.7 before), CPU 57% (40%), CPU pressure 10.7% (3.5%). With `rebuild` stopped it is back to load 5.2, CPU 41% and 4.1 GiB available. The best relief candidate is `hannelore` (VM 7007108, peak 3.7 GiB, 0.09 cores) moved to pve4; the k8s nodes of `dev`, `qa` and `prod` cannot go there (the `-02` node of each is already there), `rebuild-work-01` could, through its Terragrunt entry while `rebuild` is down.
- **pve4 load fell, but less than hoped.** Median 6.3 to 5.1 (-19%), CPU pressure 11.1% to 6.2%, `monitoring2` -0.31 cores; the p95 of the load is unchanged (10.8 to 10.7), and from 2026-11-07 other guests (`qa-work-02`, `fiona`, `dev-work-02`) added about 0.5 cores in total, so pve4 is back at 7.0 average load on the last four days.
- **Checkmk:** `prod` has 15 UNKNOWN services on `monitoring2` that belong to sites that no longer exist (7 of them `free`); `prod_k8s` is at 650 of 750 services (599 two weeks ago, 25 below the WARN level of 675) and `qa_k8s` at 665 (10 below it).
- **Found on the side, not part of [#1783](https://github.com/isejalabs/homelab/issues/1783):** on 2026-10-28 `apt-get` was killed by the host's out-of-memory killer on all three nodes (10.8 to 17.8 GB of anonymous memory each), see [below](#found-on-the-side).

## Method

- **Source of the Proxmox numbers:** `pvesh get /nodes/<node>/lxc/<id>/rrddata` (and `.../qemu/<id>`, `.../nodes/<node>/rrddata`) with `--timeframe month` (30-minute steps, back to 2026-10-12) with `--cf AVERAGE` and `--cf MAX`, and `--timeframe day` (1-minute steps, last 24 hours), read on 2026-11-11 between 00:48 and 00:55 CET. A MAX point is the highest 1-minute value inside its 30 minutes, so peaks are right, spikes shorter than a minute are not. Daily values: [`data/2026-11-proxmox-capacity-phase4-daily.csv`](data/2026-11-proxmox-capacity-phase4-daily.csv). Times are CET.
- **CPU in cores** is `cpu` times the vCPUs (3 for both containers). **CPU pressure** is `pressurecpusome` (share of the time at least one task waited for a CPU). **Load** is the node's `loadavg`, averaged per 30 minutes.
- **Windows:** A = 2026-10-20 to 2026-10-27 (before every change, container limit already 10 GiB), B = 2026-10-28 to 2026-10-29 21:10 (phase 1 intervals and the ten ping-only hosts, `core` stopped at 2026-10-29 00:05), C = 2026-10-30 to 2026-11-10 (after the merge of `free` and the stop of `core`; 12 full days). 2026-11-11 is a partial day and is not in the windows. The reading was taken at night, so "day" means 08:00 to 20:00 of the earlier days.
- **Container memory** is Proxmox's "used", which leaves out file-backed pages including `shmem` (see [reading container memory](../reference/monitoring-sites.md#reading-container-memory)). That gap has shrunk: `shmem` is 0.19 GiB in `monitoring2` and 0.04 GiB in `monitoring1` now (1.29 GiB on 2026-10-18), so the Proxmox figure is within 0.2 GiB of what the OOM killer counts.
- **Nothing was changed.** My first call wrote two temporary JSON files (1.2 MB) to `/tmp` on pve4 and removed them at once; everything else was a read.

## CT 7002056 (`monitoring2`, pve4)

| | A: before | B: phase 1 only | C: after the merge |
| --- | --- | --- | --- |
| CPU, mean (day / night) | 1.04 (1.03 / 1.03) | 0.85 (0.79 / 0.95) | **0.73 (0.72 / 0.73)** |
| CPU, p95 of 30-minute means / highest 30-minute value | 1.25 / 2.87 | 1.16 / 2.71 | 0.97 / 2.94 |
| CPU pressure (some) | 13.4% | 7.7% | 3.0% |
| Memory used, mean | 6.39 GiB | 6.56 GiB | **5.25 GiB** |
| Memory used, p95 of the 30-minute maxima / highest | 7.38 / 7.66 GiB | 7.30 / 7.80 GiB | 6.99 / **7.92 GiB** |

- **CPU:** -0.31 cores (-30%) against A, -0.12 against B, and flat across the day (0.72 day, 0.73 night). The quiet-night value of the [24-hour reading](2026-10-checkmk-free-merge-result.md#24-hour-reading-early-morning-2026-10-30) (0.71 to 0.76) still holds. CPU pressure of the container fell from 13.4% to 3.0%. The highest 30-minute CPU values (2.7 to 2.9 cores) are the nightly container backup (23:30) and the midnight restart of the apache workers, and are unchanged.
- **Memory is not lower at the top.** Daily maxima before the changes were 7.06 to 7.80 GiB (2026-10-20 to 2026-10-29). After: 6.27, 6.22, 6.20, 6.19, 5.49, 4.82, 4.94, 4.98 (2026-10-30 to 2026-11-06), then 5.96, 7.28, 7.90 and 7.92 (2026-11-07 to 2026-11-10). The mean of the quiet days (4.6 to 5.3 GiB) is the 1.1 to 1.4 GiB saving of the merge; the peak is the swing on top.
- **The swing, as measured.** On 2026-11-07 to 2026-11-10 the used memory rises in steps and holds until the night: 2026-11-07 22:00 +1.0 GiB, back to 4.7 GiB at 01:00; 2026-11-08 09:00 to 11:00 +0.9 and 19:00 +0.6 (6.15 GiB at night, 6.0 at 01:00); 2026-11-09 07:00 to 08:00 +0.6 (6.9 GiB all day) and up to 7.90 GiB at 23:00, then 5.7 GiB at 01:00; 2026-11-10 05:00 to 06:15 +1.3 (7.92 GiB at 06:15, a 1-minute peak) and 6.6 GiB all day. The drops coincide with the midnight restart of the site apache workers (those in `monitoring2` started 00:00:06 to 00:01:24; the used memory fell from 6.6 to 5.0 GiB between 23:58 and 00:04 on 2026-11-11). The persistent cause per process was not recorded: the hypothesis from the [capacity audit](2026-10-proxmox-capacity.md#time-series-inside-monitoring2-2026-10-20-0722-to-0952) (the web-interface workers, 4 per site at 230 to 280 MiB each, plus the `cmk-ui-job-scheduler` at 430 to 450 MiB per site) fits and is not proven.
- **Inside the container (2026-11-11 00:53):** cgroup `memory.current` 5.30 GiB, of which anon 4.85, file 0.36 (shmem 0.19); per site RSS `prod_k8s` 3.3 GiB, `prod` 1.9 GiB, `root` 0.3 GiB. `memory.events`: `oom` 0, `oom_kill` 0 since the container started (2026-10-18 22:03). `memory.peak` is 8.85 GiB since that start; it includes page cache and was not reset, so it cannot be dated (it must have happened between 2026-10-19 and the merge: the Proxmox maxima after the merge are all below it).
- **Proposal: keep 10 GiB.** Evidence: the highest used memory since the merge is 7.92 GiB (about 8.1 GiB with `shmem`), 79% of the limit; the highest before it was 7.80; the highest `memory.current` including cache is 8.85 GiB. A limit is a ceiling and reserves nothing, so lowering it saves no memory on pve4 (its lowest available memory is 11.9 GiB over the 12 days); it would only move the OOM point closer, in a container whose limit was raised on 2026-10-19 after five kills. 9 GiB would leave 0.9 GiB over the observed peak, which is the size of one swing. Reconsider when the apache and job-scheduler memory is tuned (not documented for Checkmk 2.5) or after a month of readings.

## CT 7002061 (`monitoring1`, pve5)

| | Before `core` was stopped (2026-10-24 to 2026-10-28) | After (2026-10-29 02:00 to 2026-11-10) |
| --- | --- | --- |
| Daily maximum of memory used | 8.41, 8.83, 8.82, 8.51, 8.42 GiB (9.64 GiB on 2026-10-23) | 5.9 to 7.79 GiB |
| Idle level (night) | 7.5 to 8.0 GiB | 5.7 to 6.3 GiB |
| CPU, mean | 0.31 cores (2026-10-22 to 2026-10-28) | 0.24 cores |

- **Highest values since `core` was stopped:** 7.79 GiB (the 30-minute slot of 2026-11-01 23:30), 7.65 (2026-11-02 00:00), 7.62 to 7.64 for the five hours before. The step at 2026-11-01 17:00 (+1.7 GiB, from 5.8 to 7.5) held until 01:00 and came back to 7.2 on the next day; last seven days: 7.12 GiB (2026-11-07), last 24 hours 6.97 GiB (2026-11-10 20:07, 1-minute). The same ratchet as in `monitoring2`: the steps persist until the midnight restart of the site workers.
- **Inside the container (2026-11-11 00:54, right after the midnight restart):** `memory.current` 6.96 GiB, anon 6.19, file 0.66, shmem 0.04; per site RSS `qa_k8s` 3.56 GiB (3.02 on 2026-10-29), `dev_k8s` 3.19 GiB (2.96), `root` 0.19 GiB. The two sites grew by 0.76 GiB together in 13 days; `qa_k8s` has 665 services (616 on 2026-10-20).
- **OOM history:** `oom_kill` is 2 since the container started (2026-10-18 22:03), both on 2026-10-23 11:05 at the 10 GiB limit with `core` still running (kernel log of pve5). No kill since the stop of `core`.
- **Proposal: 9 GiB** (`pct set 7002061 --memory 9216` on pve5, takes effect live, current usage is 7 GiB including cache): the highest used memory since the stop is 7.79 GiB (7.83 GiB with `shmem`), plus 15% is 9.0 GiB, which is larger than the 0.8 GiB swing. It is optional: the effect on pve5 is accounting only (the allocated sum of the running guests falls from 41.0 to 40.0 GiB, with `rebuild-work-02` counted). No memory is returned, the node's lowest available memory stays 7.4 GiB. I would not go lower: the two sites grow, and a 10 GiB limit with `core` running already hit its OOM on 2026-10-23.

## pve5

| | A (2026-10-20 to 2026-10-26 22:30, `rebuild-work-02` up, `dev-ctrl-03` and `core` still there) | C while `rebuild` was up (2026-10-30 to 2026-11-09 06:30) | `rebuild` stopped (2026-11-09 07:00 on) |
| --- | --- | --- | --- |
| Memory used, highest (lowest available of 46.8 GiB) | 43.4 GiB (3.4) | 39.4 GiB (**7.4**) | 35.6 GiB (11.2) |
| Load, mean / median / p95 | 5.5 / 5.2 / 7.9 | 3.4 / 2.9 / 4.5 | 2.4 / 2.4 / 2.9 |
| Host CPU, mean / CPU pressure, mean | 38% / 3.9% | 30% / 1.5% | 25% / 0.7% |

- **Over the guests' peaks** pve5 has about 12 GiB: the eight running guests peak at 29.3 GiB over the 12 days (28.3 over the last seven), `rebuild-work-02` at 5.3 GiB, against 46.8 GiB. That is 8 GiB more than the 4.6 GiB of the capacity audit: `dev-ctrl-03` (4.1 GiB peak) left, `monitoring1` fell from 9.4 to 7.8 GiB.
- The pve5 node has seen no cgroup OOM kill since 2026-10-23 and one host-level one (see below).

## pve1

| | A (2026-10-20 to 2026-10-26 22:30, `rebuild-work-01` up, before `dev-ctrl-01`) | C while `rebuild` was up (2026-10-30 to 2026-11-09 06:30) | `rebuild` stopped (2026-11-09 07:00 on) |
| --- | --- | --- | --- |
| Memory used, highest (lowest available of 46.8 GiB) | 42.2 GiB (4.6) | 45.2 GiB (**1.6**, 2026-11-08 00:30) | 42.7 GiB (4.1) |
| Load, mean / median / p95 | 4.7 / 4.4 / 7.8 | **7.7 / 6.8 / 13.5** | 5.2 / 4.8 / 7.6 |
| Host CPU, mean / CPU pressure, mean / p95 | 40% / 3.5% / 7.2% | 57% / 10.7% / 24.3% | 41% / 3.8% / 8.3% |

- **Guest peaks:** the 16 running guests peak at 35.6 GiB over the 12 days (35.2 over the last seven): `qa-work-01` 5.6, `prod-work-01` 5.3, `hannelore` 3.7, `polina` 3.6, `dev-ctrl-01` 3.7, `prod-ctrl-01` 3.4, `dev-work-01` 3.2, `adelheid` 2.3, `gw2` 2.1, `hassos-prod` 1.9, six small LXCs 0.8 together. `rebuild-work-01` (stopped since 2026-11-09 06:30) adds 4.9 GiB (6.0 allocated). Together 40.5 GiB, which fits the 40.7 GiB of the [#1783](https://github.com/isejalabs/homelab/issues/1783) body. The node itself used up to 45.2 GiB of its 46.8 (ZFS ARC 2.5 GiB on average, qemu and host overhead on top of the guests' own figures), so the node-level figure, not the sum, is the one to watch. No swap exists and no OOM kill is logged on pve1 since 2026-10-28.
- **Why the load went up:** `dev-ctrl-01` adds 0.55 cores, and the workers on pve1 rose from about 0.4 to about 0.6 cores each on 2026-10-29 (`prod-work-01` 0.46 to 0.65, `dev-work-01` 0.36 to 0.6, `qa-work-01` 0.39 to 0.71, back to 0.37 on 2026-11-08), the `rebuild` guest is on top. The cause of the worker rise was not examined. With `rebuild` stopped the node is back at the level of window A, so pve1's pressure is a `rebuild`-up problem, and the owner's rule is that room for `rebuild` is always reserved.
- **Relief candidates.** Anti-affinity (one control-plane and one worker of a cluster per node): pve4 already holds the `-02` node of `dev`, `qa` and `prod`, so none of their pve1 nodes can go there. The other guests of pve1 are pinned or hard to move: `hassos-prod` has three USB passthrough devices, `gw2` is half of the gateway pair (the other half, `gw3`, is on pve5), `adelheid` is the directory master, `polina` is the backup target of all nodes. Two candidates remain:
  - **`hannelore`** (VM 7007108, the console host): 4.5 GiB allocated, peak 3.7 GiB, 0.09 cores, one disk of 10 GiB on `local-enc`, no passthrough, `onboot`. pve4 has `local-enc` (292 GiB free) and VLAN 107 in its bridge table. Effect: pve1's lowest available memory from 1.6 to about 5.3 GiB, pve4 from 11.9 to about 8.2 GiB (over its peaks 16 GiB), pve4 CPU +0.09 cores. pve5 would also take it but leaves 3.7 GiB with `rebuild` up; pve5 was not checked for `local-enc` and the VLAN.
  - **`rebuild-work-01`** (in [`terragrunt/non-prod/eu-central-1/rebuild/vehagn-k8s/terragrunt.hcl`](../../terragrunt/non-prod/eu-central-1/rebuild/vehagn-k8s/terragrunt.hcl), `host_node = "pve1"`): `rebuild` has no node on pve4 (`ctrl-03` and `work-03` on pve6, `work-02` on pve5), so `host_node = "pve4"` respects the anti-affinity. Peak 4.9 GiB (6.0 allocated), 0.41 cores while `rebuild` was up. Effect: pve1's lowest available memory from 1.6 to about 6.5 GiB and its CPU by about 0.4 cores, pve4 from 11.9 to about 7.0 GiB and +0.4 cores while `rebuild` is up, nothing while it is down. A `host_node` change of a worker is a destroy and recreate of its Talos VM and data VM ([`node-lifecycle.md`](../operations/node-lifecycle.md#5-moving-a-node-to-another-proxmox-host)), which is cheap only while `rebuild` is down, as it is now (stopped since 2026-11-09 06:30); it follows the repository's apply rules, not a `qm migrate`.
  - Not recommended: `qa-work-01` (the biggest, but a k8s node of a cluster that has its `-02` on pve4), reducing worker memory.
- **Proposal:** move `hannelore` to pve4 if `rebuild` is meant to run alongside everything else on pve1 (`qm migrate 7007108 pve4 --online --with-local-disks`, to be tested; if online migration with local disks does not work, an offline migration costs a few minutes of the console host). It adds the least to pve4 (0.09 cores) and gives 3.7 GiB. If more room is wanted, `rebuild-work-01` to pve4 adds 4.9 GiB for 0.4 cores on pve4 while `rebuild` runs; take it only together with a look at pve4's load, which went up again on 2026-11-07. Nothing else on pve1 needs to change.

## pve4 load

| | A (2026-10-20 to 2026-10-27) | C1 (2026-10-30 to 2026-11-06) | C2 (2026-11-07 to 2026-11-10) | C (all) |
| --- | --- | --- | --- | --- |
| Load, mean / median / p95 | 6.7 / 6.3 / 10.8 | **5.2 / 4.9 / 7.9** | 7.0 / 5.7 / 13.7 | 5.8 / 5.1 / 10.7 |
| Host CPU, mean | 46% | 41% | 49% | 44% |
| CPU pressure, mean / p95 | 11.1% / 18.5% | 4.9% / 9.9% | 8.8% / 29.6% | 6.2% / 17.2% |
| Day (08:00 to 20:00) load mean / p95, C against A | 6.5 / 9.0 | | | 5.5 / 9.8 |
| Night (22:00 to 06:00) load mean / p95, C against A | 7.2 / 12.6 | | | 6.3 / 11.1 |

- **It fell after the changes and rose again on 2026-11-07.** For the first eight days (C1) the load is 5.2 on average, 22% below A, CPU pressure less than half. Then `qa-work-02` (0.36 to 0.58 cores), `fiona` (0.24 to 0.62 on 2026-11-07, 0.41 to 0.45 since), `dev-work-02` (0.39 to 0.43) and `monitoring2` itself (0.69 to 0.77, the busier web interface) rose, and the load went back to 6.5 to 7.9 per day. Not related to the Checkmk changes; the cause of the rise was not examined.
- **What the changes are worth on pve4:** `monitoring2` lost 0.31 cores (1.04 to 0.73) of the 3.3 cores of guest CPU, and the Nagios host-check processes of `free` are gone. The node's median load fell by about 1.2, its p95 did not move overall (night 12.6 to 11.1, day 9.0 to 9.8).
- **The audit's baseline** (median 6.5, p95 13.8 over 30 days of hourly samples, 2026-10-13 left out) is on a different sampling and is not used for the comparison; window A is the like-for-like baseline (median 6.3, p95 10.8).

## State of the Checkmk side (2026-11-11 00:53 to 00:56)

| Site | Hosts | Services | State | Checks per second (host, service) |
| --- | --- | --- | --- | --- |
| `prod` | 93 (85 UP, 8 DOWN) | 1,969 (1,954 on 2026-10-30) | 1,651 OK, 33 WARN, 92 CRIT, 46 UNKNOWN, 147 PEND | 1.3, 4.3 (2.5 and 2.6 on 2026-10-30) |
| `prod_k8s` | 91 UP (83 on 2026-10-29) | **650** of 750 (599) | 647 OK, 3 WARN, 0 CRIT, 0 UNKNOWN, 0 PEND | 11.7, 11.4 |
| `qa_k8s` | 74 | **665** (616 on 2026-10-20) | not read | 0.6, 6.5 |
| `dev_k8s` | 64 | 581 | not read | 0.8, 5.0 |

- **UNKNOWN in `prod` (46):** 15 on `monitoring2` are services of sites that no longer exist, "Item not found in monitoring data": `OMD free` apache, disk usage, message broker, performance, piggyback-hub, status and `Site free statistics` (7, from the merge and the deletion of `free` on 2026-11-01), `OMD spikeprod` and `Site spikeprod statistics` (5) and `OMD restoretest` (3), both older test sites. `omd sites` lists only `prod` and `prod_k8s`. The other 31: `pi4.dir` 16 (host DOWN, no downtime), `pve4` 4 (temperature zones and cores, interface `enp2s0`), `tabea` 3 (mounts), `sybille` 2, `pve6` 2, `adelheid` 2 (plug-in status 127), `pve1` 1, `gw4` 1 (interface `wg1`); the usual "item not found" noise, not examined.
- **PEND (147):** `pve2` and `pve3` 52 each (offline, as before), `pi3.home.iseja.net` 43 (host DOWN, in downtime; it was not among the 104 PEND services of 2026-10-29). DOWN hosts: `pve2`, `pve3`, `pve6`, `pi3`, `sybille` (all in downtime), the two plugs and `pi4.dir` (no downtime).
- **Service-count alert:** `OMD prod_k8s performance`, `OMD qa_k8s performance` and `OMD dev_k8s performance` are OK; no WARN has fired. `prod_k8s` grew by 51 services and 8 hosts in 13 days: 374 services on 41 deployments, 142 on 20 namespaces, 80 on 10 daemonsets, 24 on the 6 nodes, 10 ping-only, 10 of the cluster collector, 8 on the one statefulset, 2 of `srv3`. `qa_k8s` at 665 is 10 below the WARN level of 675 (headroom 85 to 750); `prod_k8s` has 25 below WARN, 100 to the limit.
- **From the merge:** no new UNKNOWN or stale services on the moved hosts (the rebuild-cluster stale services are the stopped `rebuild`); the open question about `corosync_latency` and "vanished" services stays unanswerable (`free` is deleted).

## Found on the side

- **Host-level OOM kills of `apt-get` on 2026-10-28:** pve1 04:13 (10.8 GB anon), pve5 04:41 (11.0 GB), pve4 05:29 (17.8 GB), each a global kill (`CONSTRAINT_NONE`) of an `apt-get` of `cron.service` (the task dump of pve5 lists `apticron`). pve4's memory used reached 61.6 of 62.5 GiB at that time and pve5's 45.1 of 46.8. No later event in the kernel logs since 2026-10-18 21:00, apt is 3.0.3 to 3.0.4. What the `apt-get` did and why it grew was not examined. It is a risk to every capacity figure here: a single cron job can use more than the 12 GiB left on pve4.

## Fourth node: yearly power cost at 0.36 €/kWh

The owner gave the electricity price (0.36 €/kWh, 2026-11-11). Power figures are from the [36-hour reading of 2026-10-22](https://github.com/isejalabs/homelab/issues/1783#issuecomment-6334220945) in the issue, not re-measured here; the arithmetic is rechecked.

| Setup | Draw | Energy per year | Cost per year |
| --- | --- | --- | --- |
| `pve6` permanently on | 25.1 W | 220 kWh (25.1 W x 8.76) | about 79 € |
| pve1, pve4, pve5 and the NAS | about 110 W | about 960 kWh | about 346 € |
| the same with `pve6` | about 135 W | about 1,180 kWh | about 425 € |

The earlier threshold "within 50 € a year below about 0.23 €/kWh" no longer applies: at 0.36 €/kWh a permanent `pve6` is about 79 € a year, about 23% on top of the current four devices. This is a power cost only; it does not change the memory findings above.

## Not measured

- Per-process memory history: only a snapshot of 2026-11-11 00:53 exists, so the steps in `monitoring1` and `monitoring2` are not attributed.
- Daytime of 2026-11-11: the reading was at night, "day" figures are from earlier days. Weekday against weekend was not separated.
- Memory of VMs is the figure the guest reports to Proxmox, not the host's resident size of the qemu process.
- The migration of `hannelore`, its time, and `local-enc` and VLAN 107 on pve5.
- Why the workers on pve1 and `qa-work-02`, `fiona`, `dev-work-02` on pve4 rose.
- `qa_k8s` and `dev_k8s` service states, why `pi4.dir` and `pi3` are DOWN.

## Proposals (for the owner's go; nothing was applied)

| Item | Proposal | Effect | Command |
| --- | --- | --- | --- |
| CT 7002056 memory limit | keep 10 GiB | none | none |
| CT 7002061 memory limit | 9 GiB, optional | allocation of pve5's running guests 41.0 to 40.0 GiB, no memory returned | `pct set 7002061 --memory 9216` on pve5; roll back with `--memory 10240` |
| pve1 relief | `hannelore` to pve4 (alternative or addition: `rebuild-work-01` to pve4 through its Terragrunt entry) | pve1 lowest available memory 1.6 to about 5.3 GiB (6.5 with `rebuild-work-01`) with `rebuild` up; pve4 11.9 to about 8.2 GiB, +0.09 cores | `qm migrate 7007108 pve4 --online --with-local-disks` (not tested) |
| Stale services in `prod` | remove the 15 services of `free`, `spikeprod` and `restoretest` on `monitoring2` (service discovery, remove vanished, or a Disabled-services rule like the one for `core`) | 15 UNKNOWN fewer | Checkmk web interface |
| Service-count levels | decide before `qa_k8s` reaches 675 whether the levels stay or services are removed | avoids a WARN that is expected within weeks | none |
