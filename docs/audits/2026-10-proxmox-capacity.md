# Proxmox memory and CPU capacity — 2026-10-19

**Date:** 2026-10-19 (measurements), 2026-10-20 (write-up). **Status:** Measurements complete, including the nightly profile; nothing moved or resized yet; a power measurement per node is still outstanding. **Scope:** memory, CPU and load of the Proxmox nodes pve1, pve4, pve5 and pve6 and of every running guest on them, and the options for rebalancing. It does not cover disk, network or storage capacity. **Origin:** Claude (Claude Code), read-only access to the Proxmox API and nodes (`pvesh get`, `lscpu`, `uptime`) and to Home Assistant sensors. Nothing was changed on any host. **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783), related [#71](https://github.com/isejalabs/homelab/issues/71) and [#1780](https://github.com/isejalabs/homelab/issues/1780).

## Result

- **Memory is the constraint on pve5; CPU load is the constraint on pve4.** pve5 has about 4.6 GiB over its guests' weekly peaks, pve4 about 20 GiB but a load average twice that of the other nodes.
- **Placement of `dev-ctrl-03` (4 GiB, 0.33 cores) matters least for CPU and most for memory:** moving it to pve1 relieves pve5 without adding to pve4.
- **Raising worker memory fits pve4's free memory,** but every added gigabyte there increases the CPU and cache pressure on a host that is already the busiest. Both limits matter once the workers grow (for example for Immich, [#413](https://github.com/isejalabs/homelab/issues/413)).

## Hardware

All three main nodes (and pve6) are the same: Intel Core i5-1145G7, 4 cores with 2 threads each, shown as 8 CPUs. pve1 is on kernel 7.0.14-23, pve4 and pve5 on 7.0.14-20. RAM is 46.8 GiB (pve1, pve5), 62.5 GiB (pve4) and 31.1 GiB (pve6).

## Memory per node

"Sum of 7d guest peaks" adds up each running guest's highest 1-minute memory value of the last seven days (Proxmox RRD, maximum). The peaks occur at different times, so the sum is a conservative upper bound. A container's figure excludes `shmem` and understates what an OOM counts, see [reading container memory](../reference/monitoring-sites.md#reading-container-memory).

| Node | RAM used / total | Allocated to running guests | Sum of 7d guest peaks | Headroom over peaks |
| --- | --- | --- | --- | --- |
| pve1 | 37.8 / 46.8 GiB | 43.5 GiB | 37.5 GiB | about 9 GiB |
| pve4 | 46.2 / 62.5 GiB | 47.8 GiB | 42.1 GiB | about 20 GiB |
| pve5 | 39.2 / 46.8 GiB | 45.0 GiB | 42.2 GiB | about 4.6 GiB |
| pve6 | 22.5 / 31.1 GiB | 16.0 GiB | 16.4 GiB | about 15 GiB |

Two changes landed after the measurement window and are not in the table: `monitoring2` was raised from 8 to 10 GiB and the `dev_k8s` Checkmk site on `monitoring1` was stopped, both on 2026-10-19 ([#1784](https://github.com/isejalabs/homelab/pull/1784)). The `monitoring1` peak of 9.4 GiB therefore partly predates the stop.

## Guests, largest memory first

Allocation, 7-day peak memory and 7-day average CPU (in cores, that is utilization times vCPUs).

| Node | Guest | Allocated | 7d peak | Avg CPU |
| --- | --- | --- | --- | --- |
| pve1 | `qa-work-01` | 6.0 GiB | 5.0 GiB | 0.40 |
| pve1 | `rebuild-work-01` | 6.0 GiB | 4.9 GiB | — |
| pve1 | `prod-work-01` | 6.0 GiB | 5.5 GiB | 0.38 |
| pve1 | `polina` (PBS) | 4.0 GiB | 3.5 GiB | — |
| pve1 | `hannelore` | 4.0 GiB | 3.7 GiB | — |
| pve1 | `dev-work-01` | 4.0 GiB | 3.8 GiB | — |
| pve1 | `prod-ctrl-01` | 4.0 GiB | 4.0 GiB | 0.35 |
| pve1 | `adelheid`, `gw2`, `hassos-prod` | 2.0–2.5 GiB each | 2.0–2.3 GiB | 0.42 (`adelheid`) |
| pve1 | six small LXCs (`ns1`, `nsresolv1`, `loghost`, `smarthost`, `mqtt`, `webfront`) | 0.5 GiB each | 0.1 GiB | about 0 |
| pve4 | `monitoring2` | 10.0 GiB | 6.6 GiB | **1.09** |
| pve4 | `fiona` (NAS) | 9.0 GiB | 8.5 GiB | — |
| pve4 | `qa-work-02`, `prod-work-02` | 6.0 GiB each | 6.1 and 6.4 GiB | 0.38 and 0.41 |
| pve4 | `qa-ctrl-02`, `dev-work-02`, `prod-ctrl-02` | 4.0 GiB each | 4.1 GiB | 0.41, —, 0.38 |
| pve4 | `salt-master`, `tabea`, `baksrv`, `deb-cache` | 0.5–2.0 GiB | 0.2–1.4 GiB | about 0 |
| pve5 | `monitoring1` | 10.0 GiB | 9.4 GiB | — |
| pve5 | `qa-work-03`, `rebuild-work-02`, `prod-work-03` | 6.0 GiB each | 4.3, 6.1, 6.1 GiB | 0.33 (`qa-work-03`) |
| pve5 | `dev-ctrl-03`, `dev-work-03`, `prod-ctrl-03` | 4.0 GiB each | 4.1, 4.0, 3.8 GiB | 0.33, —, 0.31 |
| pve5 | `baerbel`, `gw3`, `ns2` | 2.5, 2.0, 0.5 GiB | 2.3, 1.9, 0.1 GiB | about 0 |
| pve6 | `rebuild-work-03`, `rebuild-ctrl-03`, `src-ctrl-03`, `src-work-03` | 6.0, 4.0, 4.0, 2.0 GiB | 6.2, 4.1, 4.0, 2.1 GiB | 0.59 in total |

A dash means the CPU value was not kept (only the twelve largest were). Several workers peak at or above their allocation (`qa-work-02`, `prod-work-02`, `prod-work-03`, `rebuild-work-02`). That can be page cache and was not checked.

## Load and CPU

| Node | Load average (30d) | Load p95 | Host CPU avg | Guest CPU sum (7d avg) | iowait avg |
| --- | --- | --- | --- | --- | --- |
| pve1 | 3.6 | 6.1 | 29% | 2.6 cores | 3.0% |
| pve4 | **7.6** | **13.8** | **48%** | **3.3 cores** | 3.2% |
| pve5 | 3.9 (466 hourly samples only) | 7.5 | 25% | 2.2 cores | 3.7% |
| pve6 | 3.9 (about 0.8 in the last week) | 7.7 | 26% | 0.6 cores | 4.4% |

By hour of day (30-day average, hourly samples) pve1 and pve5 are flat. pve4 sits at about 7 to 9.5 load all day with the highest value at 00:00. The nightly backup jobs are therefore not visible as a separate peak at this resolution: a short job inside an hourly average disappears. The 30-minute view in the next section shows them.

### Nightly profile (22:00 to 05:00 CEST)

Source: the same week of RRD data in its native 30-minute steps, averaged per time slot over seven nights. Slot labels are the RRD timestamps of each step, so a spike may belong to the half hour just before the label. Jobs in the table are the owner's schedule (all times CEST).

| Start | Duration | What |
| --- | --- | --- |
| 22:00 | | OneDrive sync to `fiona` |
| 22:10 | about 1 min | borgmatic and similar from the Proxmox hosts |
| 22:30 | | `polina` prune |
| 23:00 | 30 min | borgmatic `natascha-data` from `fiona` |
| 23:10, 23:20, 23:30 | 2, 3, 5 min | `vzdump` to `polina`: Crit, Prod, Test |
| 00:00 | 2 h | `polina` verify |
| 00:07 | 3 min | ZFS pull sync from `fiona` into `polina` |
| every 20 min from 02:00 | | ZFS replication `polina` to `book4tb` |
| 02:30 | | `polina` prune |
| 03:00 | | kopiur backups to `fiona` |
| 04:00 | | Longhorn backups to `fiona` |

| Slot | pve1 load / CPU | pve4 load / CPU | pve5 load / CPU | Likely cause |
| --- | --- | --- | --- | --- |
| 22:00 to 23:00 | 3.8 / 35% | 5.1 to 6.4 / 40 to 45% | 3.5 to 6.2 / 29% | OneDrive sync, borgmatic |
| **23:30** | **7.7 / 51%** | **11.9 / 72%** | **5.8 / 32%** | `vzdump` of all nodes to `polina` plus borgmatic of `fiona` |
| 00:00 and 00:30 | 4.4 / 35% | 8.5 and 7.4 / 49% | 3.7 / 28% | `polina` verify starts, backup tail |
| 01:00 to 03:00 | 3.6 to 5.2 / 37% | 5.6 to 6.7 / 40% | 3.5 to 4.3 / 28% | quiet, `polina` verify and replication |
| 03:30 | 4.6 / 37% | 7.9 / 48% | 4.6 / 30% | kopiur backups from the workers |
| 04:30 | 5.6 / 37% | 8.6 / 46% | 4.5 / 30% | Longhorn backups from the workers |
| 08:00 to 22:00 (for comparison, 13 Oct left out) | — | 5.7 / 42% | — | daytime baseline |

- **The night is not what makes pve4 busy.** Apart from the spike around 23:30, its load at night (5.1 to 6.7 in the table) is about the same as by day (mean 5.7, median 5.4 from 08:00 to 22:00, against 6.9 and 5.7 from 22:00 to 06:00, both with 13 October left out). pve4 is loaded around the clock; see [pve4 outside the nights](#pve4-outside-the-nights).
- **The 23:30 spike is host work.** Weekly means: `polina` 0.72 cores and `fiona` 1.16 cores, but the host CPU rises to 72% on pve4 and 51% on pve1, which is more than the guests account for. `vzdump` compression and I/O run on the Proxmox host, outside any guest. It affects all three nodes because every node backs up its own guests.
- **`fiona` is not CPU-heavy at night.** It stays at 0.2 to 0.4 cores. Its disk reads are 28 to 46 MB/s from 00:30 until at least 05:00, so the nightly cost on pve4 is mostly storage reads, not CPU.
- **`monitoring2` is flat around the clock** at about 1.0 core (0.95 to 1.1, 1.44 at 23:30), so it adds to the baseline both day and night.
- **The k8s backups (03:00 and 04:00) raise the load on all three nodes,** by about 2 to 3 on pve4 and about 1 on pve1 and pve5.

### pve4 outside the nights

The first pass over the week showed pve4 at 75 to 99% host CPU and load 20 to 85 from Tuesday 07:00 to 21:00. That is 2026-10-13, the day of the interim control-plane rollouts on `rebuild` and `dev` ([`node-lifecycle.md`](../node-lifecycle.md#5-moving-a-node-to-another-proxmox-host)). The interim `ctrl-02` VMs ran on pve4 and were retired again, so they are not in today's guest list, and image imports and VM creation run on the host as well. The attribution to that work is an inference from the dates; the per-guest data of the destroyed VMs no longer exists. Its daily mean load that day was 22.6 at 75% CPU. This one day lifted every average that included it; it is left out of the comparisons here.

Without that day pve4 is steady, not bursty:

| Node | Daily mean load (range over 14 days, 13 Oct left out) | Daily mean host CPU | Median load (30 days) |
| --- | --- | --- | --- |
| pve1 | 3.0 to 6.2 | 26 to 42% | 3.1 |
| pve4 | 5.3 to 8.3 | 36 to 49% | 6.5 |
| pve5 | 2.6 to 5.4 | 19 to 35% | 3.6 |

- **The difference is a higher baseline, not events.** pve4 carries about 3.3 cores of guest CPU against 2.6 on pve1 and 2.2 on pve5, and its load and CPU are about 50% above pve1's at all hours. Load per percent of CPU is similar on all nodes.
- **Who uses the CPU on pve4 (7-day average, in cores, day and night about the same):** `monitoring2` 1.05 to 1.09, `qa-ctrl-02` 0.41, `prod-work-02` 0.39 to 0.41, `qa-work-02` 0.38, `prod-ctrl-02` 0.38, `dev-work-02` 0.29, `fiona` 0.24 by day and 0.33 at night. The remaining guests are below 0.05. `monitoring2` is by far the largest single user. The number of Kubernetes VMs does not explain the gap: pve4 hosts five, pve1 five and pve5 six, so the difference is `monitoring2` plus `fiona`.
- **`monitoring2` is bursty inside its average.** A live sample on 2026-10-20 06:46 showed the `prod_k8s` Kubernetes special agent (`agent_kube`, one Python process) at 91% of a core, together with the host check helper of `monitoring2` itself, while `kvm` processes of the Kubernetes VMs sat at 29 to 40% of a core each. This is one sample and not a time series.
- **Kernel time is a large share.** `vmstat` over four 5-second samples showed 8 to 21% user and 5 to 15% system CPU, with 4 to 23% iowait and 22 to 34 runnable tasks in the busiest sample. The `top` snapshot read 30% user and 21% system. System time at this level is typically virtualization and network overhead of many VMs; the share was not broken down further.
- **The CPU governor is `performance`** on pve4, so the nodes already run at full clock (`/proc/cpuinfo` showed 2.5 GHz).
- **Scheduling pressure:** `/proc/pressure/cpu` showed that some task waited for a CPU for 12.3% of the last 5 minutes (`some avg300`).

### Reading load average against host CPU

The two numbers answer different questions and do not have to agree.

- **Host CPU %** is the share of time the logical CPUs were not idle, averaged over all 8. It says how much of the compute capacity is used. With 4 cores and 2 threads each, 50% busy on the logical CPUs is already closer to full than it sounds: the second thread of a core adds only a fraction of a core's throughput, so the physical cores are busier than the percentage suggests.
- **Load average** is the average number of tasks that are runnable (running or waiting for a CPU) plus tasks in uninterruptible sleep, usually waiting for disk. It says how much work is queued, not how much capacity is used. Compare it with the 8 logical CPUs: load 8 means on average one task per logical CPU, load above 8 means tasks wait.
- **A high load with moderate CPU** means many guest threads want the CPU at the same moment and wait. Here that is the case on pve4: 22 vCPUs are allocated on 8 logical CPUs, and its Checkmk and several Kubernetes VMs run at the same time. It can also mean threads blocked on disk, but iowait is the same on all nodes, so disk waiting is not the difference.
- **A low load with high CPU** means a few threads that run continuously, which is harmless.
- **Which number to watch:** use load average (and its 15-minute value) for responsiveness, host CPU % for capacity. For this homelab the load matters most when interactive work runs during the same minutes as the backups, and it does not during the night.
- **Load spikes of 30 to 92** are in the monthly maxima. They are rare and each is a single 30-minute step. By date: 2026-09-20 08:30 (pve1 33, pve4 43) follows the merge of the migration of the `dev` and `rebuild` VMs from pve5 to pve6 at 06:26 and 06:33; 2026-09-28 11:30 (pve4 46, pve6 49) and 2026-09-30 04:30 to 06:30 (pve6 59 and 92) match no commit, and pve6 hosts the on-demand clusters, so cluster rebuild runs are plausible (the owner's assumption, not confirmed); 2026-10-13 (pve4 up to 86, pve5 47) is the interim control-plane rollouts; 2026-10-18 11:00 (pve1 50) is the day of the production Kubernetes upgrade (merged 00:28), not confirmed.

## Checkmk sites in monitoring1 and monitoring2

Measured on 2026-10-20 inside the two containers (read-only). CPU is cumulative since the container started (monitoring2 32.3 h, monitoring1 33.2 h), summed over the processes of each site user including the children they waited for. Memory is PSS. Check intervals and licence state per site are in [`reference/monitoring-sites.md`](../reference/monitoring-sites.md#check-intervals-and-licence-state).

| Container | Site | Core | CPU (cores) | Memory (PSS) | Hosts / services |
| --- | --- | --- | --- | --- | --- |
| monitoring2 | `prod` | Nagios | 0.44 | 1.2 GiB | 84 / 1,411 |
| monitoring2 | `free` | Nagios | 0.31 | 1.5 GiB | 18 / 609 |
| monitoring2 | `prod_k8s` | CMC | 0.10 | 2.8 GiB | 73 / 679 |
| monitoring2 | processes of `root` | | 0.13 | 0.1 GiB | |
| monitoring1 | `qa_k8s` | CMC | 0.10 | 2.7 GiB | 68 / 616 |
| monitoring1 | `core` | CMC | 0.04 | 2.3 GiB | 22 / 636 |
| monitoring1 | processes of `root` | | 0.11 | 0.1 GiB | |

- **The `root` rows are unattributed.** Orphaned child processes are reaped by `systemd` and their CPU ends up there, so the site rows are probably somewhat too low.
- **The Nagios sites cost CPU, the Ultimate (CMC) sites cost memory.** `prod` and `free` together use 0.75 cores of the 1.0 cores of monitoring2. Each Ultimate site uses 2.3 to 2.8 GiB however few hosts it has (`core`: 22 hosts, 2.3 GiB).
- **`prod_k8s` special agents are not the problem.** `agent_kube` for `prod-homelab` ran every 70 seconds and used about 3 CPU-seconds per run (5-minute sample); the Proxmox special agent of `free` used about 2 CPU-seconds in a run of about 30 s. Together with the other agents this is well below 0.1 cores. Longer intervals on the `*_k8s` sites would save little.
- **`free` spawns five times as many processes as `prod`:** 1,659 new processes in 180 seconds (about 9 per second) against 502 for `prod` and 67 for `prod_k8s`. About 47% of those are `check_icmp` host checks (`sh -c` wrapper and plugin) of 12 hosts that `free` pings every second, 4 of them internet targets with `-n 6 -t 20`. The remaining host checks of `free`, `snmpbulkwalk` and `pnp4nagios` make up the rest.
- **The same pings cost almost nothing in CMC.** `core` runs Smart Ping on 22 hosts at 1 second or 6 seconds (13.6 host checks per second measured) with 0.04 cores in total, because CMC does it inside the core without a process per check. That is the design argument for keeping 1-second pings on a CMC site.
- **`pve2` and `pve3` are DOWN in `free`** (host state 1) and are checked every minute with a 3.8 second timeout. Their services are in a failed state. Not touched.
- **Intervals:** `free` has 12 hosts at 1 second and 153 services at 1 minute (140 passive, 13 active); `prod` has all hosts at 1 minute and 29 services at 1 minute; the `*_k8s` sites have almost all services at 1 minute; `core` has 125 passive services at 1 minute.

### Time series inside monitoring2 (2026-10-20 07:22 to 09:52)

A snapshot loop inside the container (26 snapshots, about 5 minutes apart, 24 usable intervals) summed the CPU of each site's processes per interval and their PSS memory.

| Site | CPU mean (cores) | Range | Memory (PSS) |
| --- | --- | --- | --- |
| `prod` | 0.46 | 0.41 to 0.49 (p90), one 0.66 | 1.2 GiB, then 1.7 to 1.8 GiB from 08:41 |
| `free` | 0.31 | 0.28 to 0.36 | 1.4 GiB, steady |
| `prod_k8s` | 0.10 | 0.08 to 0.14 | 2.75 GiB, then 3.1 GiB from 08:51 |
| processes of `root` | 0.09 | 0.06 to 0.12 | |
| Total | 0.96 | up to 1.17 | 5.5 GiB, then 6.4 GiB |

- **CPU is flat.** No hourly spike shows at this resolution, and the means match the 32-hour totals above (0.44, 0.31, 0.10). The window cannot show daily jobs; those are covered only by the cumulative totals and the weekly Proxmox RRD of the container (about 1.0 core at all hours, 1.4 at 23:30 when the container itself is backed up).
- **Memory is not flat.** Between 08:41 and 08:51 the `apache` processes grew by about 490 MiB in `prod` and by about 310 MiB in `prod_k8s` and stayed there. The cause was not established; the web interface was probably opened (these are the workers that serve it). Whatever the cause, the memory of the three sites can swing by about 0.8 GiB within minutes, which is as large as the saving expected from merging `free` into `prod` (1.2 to 1.5 GiB). The memory limit of the container should not be lowered by the estimates alone, and any before and after comparison has to be made under the same web-interface use.

### Estimated effect of the proposed changes

All figures are estimates from the measurements above; none has been tried.

| Change | CPU | Memory | Where |
| --- | --- | --- | --- |
| `free`: services from 1 min to 5 min (153 services) | scheduled service executions of `free` drop from about 242 to about 120 per minute (-50%) | none | monitoring2 (pve4) |
| `free`: the 12 one-second hosts moved to 1 min or to Smart Ping on a CMC site | scheduled host checks drop from about 726 to about 18 per minute; together with the line above, roughly 0.1 to 0.2 of the 0.28 cores that the `free` Nagios uses (assumes CPU scales with the share of spawned processes) | none | monitoring2 (pve4) |
| Merge `free` into `prod` (after the two lines above) | about 0.03 cores (the non-Nagios daemons of `free`) | about 1.2 to 1.5 GiB (1.5 GiB of `free` minus some growth of `prod`) | monitoring2 (pve4) |
| Merge `core` into `prod_k8s` (22 hosts as host-only, with their Smart Ping) | about 0.04 cores move from monitoring1 to monitoring2, no net saving | about 2.3 GiB freed on monitoring1 (pve5), a small increase on monitoring2 | pve5 relieved, pve4 slightly loaded |
| Services of `core` dropped | none | none | the owner states that the 636 services of `core` are covered by `free` and `prod` (not compared one by one); dropping them removes them from that site's licence count |

- **`core` duplicates `free`.** 17 of its 22 hosts (the 12 one-second hosts and `pve1` to `pve5`) are also monitored in `free`, each with its own agent services (for example `pve1`: 74 services in `core`, 77 in `free`), so the same agents are fetched by two sites (the Checkmk caching agent on the target answers the repeated query, so merging lowers the load on the Checkmk servers, not on the targets). Only `monitoring1`, `ns-quad9`, `pi4.dir` and the two plugs exist only in `core`. The 12 one-second hosts are pinged by `check_icmp` in `free` and by Smart Ping in `core` at the same time.
- **`prod_k8s` and `prod` overlap.** 191 of the 679 services of `prod_k8s` exist on the same host in `prod` (nodes 102 of 114, deployments 35 of 347, namespaces 45 of 128, cluster 9 of 10). The node services in `prod` show the same values, from the same Kubernetes piggyback source. Removing the node services from `prod_k8s` (114, 21% of its scheduled executions) raises its licence headroom from 71 to about 185.
- **History of the Proxmox hosts:** the Checkmk RRDs of `free` keep 6-hour steps for 1,460 days (and 30-minute steps for 90 days); Proxmox's own RRD keeps only weekly steps beyond a month. Together `pve1` to `pve6` are 214 MB in `free`; the RRDs of `pve2` end at 2026-01-08 and of `pve3` at 2026-06-23.
- **Licence headroom:** `prod_k8s` is at 679 of 750 services (91%). Host-only hosts add no services, but every new Kubernetes workload (Immich and others) adds some. A merge of `core` into `prod_k8s` must keep to hosts without services, or the limit is reached after about 70 more services.
- **Smart Ping in `core` is reported as not working** ([`monitoring-sites.md`](../reference/monitoring-sites.md#sites)). The measurement above shows its checks running; what exactly fails was not investigated and should be clarified before relying on it for the one-second pings.
- **No merge was done.** A merge of `free` into `prod` needs a data migration (see [why `free` exists](../reference/monitoring-sites.md#why-free-exists)).

## Options considered

1. **Move `dev-ctrl-03` from pve5 to pve1** (recommended): frees about 4 GiB on pve5, leaves about 5 GiB over peaks on pve1, adds 0.33 cores to a node with 2.6 cores of guest load. Dev has a single control plane, so it follows the interim-control-plane procedure in [`node-lifecycle.md`](../node-lifecycle.md#5-moving-a-node-to-another-proxmox-host), not an in-place `host_node` change. `dev-ctrl-02` on pve1 would be the interim node and also the final one.
2. **Move `dev-ctrl-03` to pve4:** frees the same on pve5 but adds to the node with the highest load. Not recommended.
3. **Resize workers** (more memory for the `-02` workers, less for the `-03` workers): only `qa-work-03` has real slack (about 1.5 GiB), the other `-03` workers peak at their allocation, so it frees at most 1.5 GiB on pve5. Uneven sizes inside one cluster also complicate scheduling and Longhorn replica placement. Whether a memory change reboots or recreates the VM was not checked. Growing the pve4 workers uses pve4's free memory, which is what it has plenty of.
4. **Move `monitoring1` to pve1:** does not fit (9.4 GiB peak against about 9 GiB headroom), and a monitor on the host with the gateway, directory, Home Assistant and PBS would be lost together with the monitoring of exactly those services if pve1 failed.
5. **Reduce what the monitoring VMs do:** see [Checkmk sites in monitoring1 and monitoring2](#checkmk-sites-in-monitoring1-and-monitoring2). The `*_k8s` special agents are cheap (about 3 CPU-seconds per run, see below); the load is in the two Nagios sites, mostly `free`, and the memory is in the Ultimate sites.
6. **Permanently run a fourth node (pve6):** adds about 4 cores and 31 GiB, but costs power around the clock and one more machine. See below.

## Power and the fourth-node question

Home Assistant has a Tasmota plug `Server-3er-Plug` in the cellar with these values on 2026-10-20:

| Sensor | Value |
| --- | --- |
| Power now | 81 to 84 W |
| Energy yesterday | 1.946 kWh (about 81 W average) |
| Energy total since 2022-07-30 | 1732.7 kWh |

It is not recorded which devices are on the plug, so these numbers are not a per-node figure. At a constant 81 W the plug's devices use about 710 kWh a year; the annual cost is that times the electricity price. Per-node power is still to be measured (one smart plug per node, or the same plug moved around). A fourth node's annual cost is its average draw times 8.76 times the price in €/kWh; at an assumed 10 W and 0.30 €/kWh this would be about 26 €, which is an illustration, not a measurement.

## Open

- **Whether pve4's constant load matters for the workers' responsiveness:** its CPU pressure (PSI `some`) was 12% over 5 minutes on 2026-10-20 06:46, that is some task waited for a CPU in 12% of the time. Not compared with pve1 and pve5.
- **The exact slot of the `vzdump` spike:** the 30-minute steps cannot separate the three `vzdump` jobs and the `natascha-data` borgmatic run; a finer view (day timeframe, 1-minute steps) is needed within one week of the event.
- **Power per node** and the electricity price, to compute the yearly cost of the current three nodes and of a permanent pve6.
- **Daily jobs inside the Checkmk sites:** the snapshot loop covered 2.5 hours; a daily pattern is only visible in the cumulative totals.
- **What fails in Smart Ping of `core`,** and whether `core` is needed as a separate site at all.
- **Whether four free-state Ultimate sites are within the licence terms** (the code counts per site; Checkmk's pages describe the free mode as one site).
- **Whether worker peaks at 100% of allocation are page cache or real demand,** before sizing workers up or down.
