# Checkmk container OOMs — 2026-10-18

**Date:** 2026-10-18. **Status:** Mechanism established; trigger probable, not proven; fixes proposed, none applied. **Scope:** cgroup OOM kills in the two Checkmk containers (`monitoring1` on pve5, `monitoring2` on pve4) on 2026-10-18, and corrections to the September 2026 observability audits. **Origin:** Claude (Claude Code), read-only SSH to pve4 and pve5, plus the owner's `grep` of the central syslog and the shell history of `monitoring2`. Nothing was changed on any host. **Tracking:** [#1780](https://github.com/isejalabs/homelab/issues/1780).

## Result

Not a host or kernel fault. pve4 had about 16 GiB available, no panic, hung task or lockup was logged, and the pve4 reboot on 2026-10-10 (kernel 7.0.14-5 to 7.0.14-20) was a clean one. Every kill is `constraint=CONSTRAINT_MEMCG`: the container hit its own memory limit (no swap), after the Checkmk 2.5.0p15 upgrade of the same day.

## Events

| Time (CEST) | Container | Kills |
| --- | --- | --- |
| 2026-09-19 13:31 | CT 7002056 | 2 `cmk-ui-job-sche`/`apache2` (2.4.0p36, before the upgrade) |
| 2026-10-18 20:13:48–20:14:23 | CT 7002056 (limit 8 GiB) | 5 |
| 2026-10-18 20:32:50 and 20:32:56 | CT 7002061 (limit 10 GiB) | 2 |
| 2026-10-18 21:20:16–21:20:26 | CT 7002061 | 2 |

The kills hit `cmk-ui-job-sche` (the UI background-job scheduler), `apache2` and login `systemd`; the invoker is whatever allocated the next page.

## Why the dashboards showed nothing

- At the first kill the cgroup stood at 8392560 kB of 8392704 kB: `anon` 7.19 GB, `shmem` 1.29 GB.
- Proxmox excludes file-backed pages including `shmem`, so it shows about 64 %. Checkmk's own maximum of about 78 % since 18:20 is also roughly the idle level of `anon` + `shmem` (about 6.3 GiB of 8). See [reading container memory](../reference/monitoring-sites.md#reading-container-memory).
- The spike on top of that was about 1.6 GiB and short. The Proxmox RRD (1-minute maximum of 10-second samples) shows 5.9 GiB at 20:13 and 6.3 GiB at 20:14, still without `shmem`.

## Probable trigger

- Checkmk's scheduled **Auto-discovery** job in site `prod` started at 20:13:25, 23 seconds before the first kill. Its automation-helper log shows `autodiscovery` processing the hosts' autochecks at that moment. Timing is the only evidence.
- The containers carry a larger steady load than before: each site runs two `cmk-automation-helper[worker]` processes of about 170 MB, several apache workers of 250–300 MB, and a UI job scheduler (up to about 330 MB per job process).
- The 2.4 baseline was already high. `monitoring1`'s 28-day history before the upgrade was 6.79–8.29 GB used (average 7.23 GB, see [`2026-09-observability-phase0-findings-claude.md`](2026-09-observability-phase0-findings-claude.md)). On 2026-10-18 the Proxmox RRD shows a steady 9.0–9.3 GiB of 10 GiB, and `anon` is 9.6 GB.
- Not established: what part of the spike each process contributed, whether 2.5 or the new editions raised the baseline, and the trigger on `monitoring1`. The `monitoring1` jobs had no auto-discovery job record near 20:32 or 21:20.

## Corrections to the September 2026 audits

These audits remain unedited; where they conflict, [`monitoring-sites.md`](../reference/monitoring-sites.md) wins.

| Statement | Correction |
| --- | --- |
| `free` is a "historical sibling" of `prod` ([`2026-09-observability.md`](2026-09-observability.md)) | `free` is a live site that monitors the physical hosts and general infrastructure and is not redundant with `prod`. Its consolidation into `prod` is a follow-up. |
| `monitoring1` is an LXC on pve6 | It runs on pve5 (observed 2026-10-18). |
| `prod`/`free` are 2.4.0p36.cre, `dev_k8s`/`qa_k8s` are 2.4.0p36.cce | All sites are 2.5.0p15 as of 2026-10-18; `prod` and `free` are Community, the others Ultimate. |
| `core` is "Smart Ping ... explicitly outside this project" | Still outside this project, but Smart Ping stopped working; kept deliberately for now. |

## Proposals (none applied; owner decides)

1. **`monitoring2`:** raise the limit to about 10 GiB. pve4 has the room (62.5 GiB total, about 16 GiB available).
2. **`monitoring1`:** pve5 has 46.8 GiB (47903 MiB) and about 6.6 GiB available, and `monitoring1` alone sits at 9.0–9.3 of 10 GiB. Raising it there is not free; moving it to a node with room or shrinking `core` are the alternatives.
3. Remove unused Checkmk versions with `omd cleanup` after checking `omd versions`: frees disk, not memory.
4. Tuning Checkmk 2.5 memory (apache and automation-helper process counts) is unverified: no documented knob was found for 2.5, so the trade-offs are open.

## Follow-ups

- Merge `free` into `prod`, which removes duplicate monitoring and one site's memory.
- Decide whether to keep `core`.
- Observability rework, [#71](https://github.com/isejalabs/homelab/issues/71): include container memory headroom (`anon` + `shmem` against the limit) among the things to monitor.
