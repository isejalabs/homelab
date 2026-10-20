# Proxmox memory and CPU capacity — 2026-10-19

**Date:** 2026-10-19 (measurements), 2026-10-20 (write-up). **Status:** Measurements complete; nothing moved or resized yet; the nightly job list and a power measurement per node are still outstanding. **Scope:** memory, CPU and load of the Proxmox nodes pve1, pve4, pve5 and pve6 and of every running guest on them, and the options for rebalancing. It does not cover disk, network or storage capacity. **Origin:** Claude (Claude Code), read-only access to the Proxmox API and nodes (`pvesh get`, `lscpu`, `uptime`) and to Home Assistant sensors. Nothing was changed on any host. **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783), related [#71](https://github.com/isejalabs/homelab/issues/71) and [#1780](https://github.com/isejalabs/homelab/issues/1780).

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

By hour of day (30-day average, hourly samples) pve1 and pve5 are flat. pve4 sits at about 7 to 9.5 load all day with the highest value at 00:00. The nightly backup jobs are therefore not visible as a separate peak at this resolution: a short job inside an hourly average disappears. The finer week data would show them.

### Reading load average against host CPU

The two numbers answer different questions and do not have to agree.

- **Host CPU %** is the share of time the logical CPUs were not idle, averaged over all 8. It says how much of the compute capacity is used. With 4 cores and 2 threads each, 50% busy on the logical CPUs is already closer to full than it sounds: the second thread of a core adds only a fraction of a core's throughput, so the physical cores are busier than the percentage suggests.
- **Load average** is the average number of tasks that are runnable (running or waiting for a CPU) plus tasks in uninterruptible sleep, usually waiting for disk. It says how much work is queued, not how much capacity is used. Compare it with the 8 logical CPUs: load 8 means on average one task per logical CPU, load above 8 means tasks wait.
- **A high load with moderate CPU** means many guest threads want the CPU at the same moment and wait. Here that is the case on pve4: 22 vCPUs are allocated on 8 logical CPUs, and its Checkmk and several Kubernetes VMs run at the same time. It can also mean threads blocked on disk, but iowait is the same on all nodes, so disk waiting is not the difference.
- **A low load with high CPU** means a few threads that run continuously, which is harmless.
- **Which number to watch:** use load average (and its 15-minute value) for responsiveness, host CPU % for capacity. For this homelab the load matters most when interactive work runs during the same minutes as the backups, and it does not during the night.
- **Spikes of 50 to 90 on every node** are in the monthly maxima. They are rare and short; the cause was not established.

## Options considered

1. **Move `dev-ctrl-03` from pve5 to pve1** (recommended): frees about 4 GiB on pve5, leaves about 5 GiB over peaks on pve1, adds 0.33 cores to a node with 2.6 cores of guest load. Dev has a single control plane, so it follows the interim-control-plane procedure in [`node-lifecycle.md`](../node-lifecycle.md#5-moving-a-node-to-another-proxmox-host), not an in-place `host_node` change. `dev-ctrl-02` on pve1 would be the interim node and also the final one.
2. **Move `dev-ctrl-03` to pve4:** frees the same on pve5 but adds to the node with the highest load. Not recommended.
3. **Resize workers** (more memory for the `-02` workers, less for the `-03` workers): only `qa-work-03` has real slack (about 1.5 GiB), the other `-03` workers peak at their allocation, so it frees at most 1.5 GiB on pve5. Uneven sizes inside one cluster also complicate scheduling and Longhorn replica placement. Whether a memory change reboots or recreates the VM was not checked. Growing the pve4 workers uses pve4's free memory, which is what it has plenty of.
4. **Move `monitoring1` to pve1:** does not fit (9.4 GiB peak against about 9 GiB headroom), and a monitor on the host with the gateway, directory, Home Assistant and PBS would be lost together with the monitoring of exactly those services if pve1 failed.
5. **Reduce what the monitoring VMs do:** `monitoring2` is the largest CPU consumer on pve4 (1.1 cores, a third of pve4's guest CPU). Raising the check intervals of the `*_k8s` sites lowers CPU and load. It should not be expected to lower the memory footprint much: the resident memory is dominated by the monitoring core, the web UI and RRD caches, which depend on the number of hosts and services, not on how often they are checked. This is a reasoning, not a measurement; measure before and after. [#71](https://github.com/isejalabs/homelab/issues/71) records a constraint to keep five-minute service polling, so any interval change needs that constraint revisited first.
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

- **Nightly job list:** the owner will supply it; it will show which jobs run when and decides whether the night load matters.
- **Finer load data** around 01:00 to 05:00 to see the backup peaks (week timeframe, 30-minute steps).
- **Power per node** and the electricity price, to compute the yearly cost of the current three nodes and of a permanent pve6.
- **Whether worker peaks at 100% of allocation are page cache or real demand,** before sizing workers up or down.
