# Checkmk site `core`: result of stopping it — 2026-10-29

**Date:** 2026-10-29. **Status:** `core` stopped and verified within minutes; the effects over days (pve5 headroom over a week, CT 7002061 right-sizing) are not measured. **Scope:** step 6 and 7 of phase 2b in the [consolidation plan](../plans/2026-10-checkmk-consolidation.md#phase-2--make-room-in-prod_k8s-then-move-the-pings-and-retire-core). Not covered: shrinking the memory of CT 7002061, cleaning up `prod`'s services for `core`, phase 3. **Tracking:** [#1783](https://github.com/isejalabs/homelab/issues/1783). **Origin:** Claude Code session on the owner's explicit go ("stop and disable core already"), read-only `lq`/`ps`/`free` over SSH. Preceding record: [`2026-10-checkmk-prod-k8s-ping-only-result.md`](2026-10-checkmk-prod-k8s-ping-only-result.md).

## What was changed

On 2026-10-29 at 00:05:57 CET on `monitoring1`: `omd stop core` and `omd config core set AUTOSTART off` (`omd config core show AUTOSTART` reads `off`). The owner asked for it before the planned parallel run of a few days was over; the comparison so far was one controlled outage (equal) and about one day of both pings running. Before the stop all ten hosts were UP in `prod_k8s` (10 UP, 0 DOWN). The site and its data stay as a restorable archive.

## Measured

| | Before (00:05 CET) | After (00:07 to 00:10 CET) |
| --- | --- | --- |
| `monitoring1` memory (`memory.current` of the CT cgroup) | 8,518 MiB of 10,240 (anon 8,220) | 5,929 MiB (anon not re-read) |
| `monitoring1` `free -m` "used" / available | 8,347 / 1,892 MiB | 5,780 / 4,459 MiB |
| Resident memory of the site `core` | 2,699 MiB | 0 (no process left) |
| `qa_k8s`, `dev_k8s` resident memory | 3,105, 2,964 MiB | 3,018, 2,964 MiB |
| `prod_k8s` services, hosts | 599, 83 | 599, 83 |
| `prod_k8s` host checks per second | 12.9 | 10.0 (single `lq` readings, varying between 9 and 13) |
| `prod_k8s` CPU over 120 s | 0.12 cores (2026-10-28) | 13 s, 0.11 cores |
| pve5 memory | not read before | used 38.0 of 46.8 GiB (`free`: 9,196 MiB available) at 00:08 CET |

`monitoring1` freed about 2.6 GiB, as estimated (about 2.3 GiB). For pve5 there is no reading from before the stop, so the headroom change is not measured; the capacity audit had 6.7 GiB available on pve5 on 2026-10-18/19 before `dev_k8s` was stopped (it runs again since 2026-10-22). The CPU of `core` was 0.04 cores and now falls away on `monitoring1`; the load of the ten pings stays on `monitoring2` (0.11 cores for the whole of `prod_k8s`).

## Left over

- `prod` still lists the services of `core` on `monitoring1` (`OMD core ...`, `Process core ...`, `Site core statistics`), all OK from before the stop at the time of reading; they will go stale or vanish and are to be cleaned up (rediscovery or disabling) — not done.
- The service-count rule in `prod` (id `d9e78913-…`) still names `core`; delete that entry.
- Right-size CT 7002061 (10 GiB, now about 5.9 GiB used with web-interface swings in mind), measure a week first.
- Rollback: `omd start core`, `omd config core set AUTOSTART on`.
