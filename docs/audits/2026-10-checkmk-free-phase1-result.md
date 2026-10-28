# Checkmk site `free`: result of phase 1 (intervals) — 2026-10-28

**Date:** 2026-10-28. **Status:** Change applied and verified for the first minutes after activation; the CPU effect over hours is not yet measured. **Scope:** the three interval rules of phase 1 in the [consolidation plan](../plans/2026-10-checkmk-consolidation.md#phase-1--free-intervals-configuration-only) and the load of the Nagios site `free` before and after. It does not cover `prod`, `prod_k8s` or `core`, which were not touched. **Origin:** Claude (Claude Code), REST API of `prod` (rules and activation) and read-only `lq` (livestatus) on `monitoring2` as `free`. **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783), umbrella [#71](https://github.com/isejalabs/homelab/issues/71).

## What was changed

The owner chose no snapshot of CT 7002056 (the change is three rule values and reversible) and gave an explicit go. Pending changes in `prod` were empty before the edit, so the activation (06:24 UTC, activation id `beeac5bb-0b94-43ac-86f1-f5be13b21a9c`, sites `prod` and `free`) applied exactly these three changes. The rules are listed in [`monitoring-sites.md`](../reference/monitoring-sites.md#change-of-2026-10-28-free-intervals).

## Before and after

Both measurements on `free`, before at 07:08 CET and after at 07:27 to 07:35 CET (about one hour after the activation, so the core had settled).

| Value | Before | After |
| --- | --- | --- |
| `host_checks_rate` (per second) | 5.42 (5.66 a minute earlier) | 0.36 to 0.38 |
| `service_checks_rate` (per second) | 4.98 and 9.58 (two reads) | 1.02 and 0.73 |
| Hosts at 1 second / 1 minute | 12 / 6 | 0 / 18 |
| Services at 1 minute | 153 | 5 (4 `PING` of `external_sites` and `DNS www.iseja.net` on `google-dns`) |
| Services at 5 minutes | 446 | 594 |
| Services OK / WARN / CRIT / UNKNOWN / PEND | 519 / 25 / 51 / 10 / 4 | 520 / 25 / 50 / 10 / 4 |
| CPU of the `free` processes over 120 s (utime + stime + waited children, live processes) | 0.41 cores | 0.23 cores |
| New processes in the container in 120 s (`/proc/stat`, all sites together) | 7,217 | 4,706 |

Notes:

- No new UNKNOWN or PEND service. The 10 UNKNOWN, 4 PEND and the WARN and CRIT services were there before the change. One CRIT went to OK.
- The plan expected 4 services at 1 minute; the fifth is `DNS www.iseja.net` of `google-dns`, an active check that follows the default interval like the four `PING` services.
- The CPU value is a 120-second sample of the processes alive during the sample, not the cumulative per-site method of the [capacity audit](2026-10-proxmox-capacity.md#checkmk-sites-in-monitoring1-and-monitoring2); it is comparable between the two lines of this table only. The fork count is for the whole container and contains `prod` and `prod_k8s`, so the drop of about 2,500 per 120 s is a lower bound of what `free` saved (about 21 per second).
- `monitoring2` load average was 8.5 (1 minute) before and 12.9 after the change in these two reads; the container had 9.6 and 10.5 as 5-minute values, so this is noise from other jobs and not a result of the change.

## Still to check

- The cumulative CPU of `free` over the following hours (0.31 cores before, the plan expects a drop) and the effect on `monitoring2` and pve4. This needs a second reading later; it is not part of this note.
- Detection of a host outage on the 12 hosts is now 1 minute in `free`; `core` still pings them every second.
