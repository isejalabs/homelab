# Observability phase 0 — baseline follow-up

**Date:** 2026-09-30. **Origin:** Codex read-only follow-up for [#1437](https://github.com/isejalabs/homelab/issues/1437). **Status:** Partial; elapsed-time baseline and some access/interface checks remain outstanding.

## Existing work and evidence limits

The [previous findings](2026-09-observability-phase0-findings-claude.md) and its two detailed inventories already cover much of phase 0. They were present on `main` when this pass started; this follow-up does not repeat that work or claim those measurements as newly verified. The issue still had an entirely unchecked checklist and no progress comments.

The earlier pass records five in-scope Checkmk sites, including `prod_k8s` on monitoring2, and sampled RRD tiers of one minute/two days, five minutes/ten days, 30 minutes/90 days and six hours/1460 days. Preserve that measured history rather than shortening it to the initial approximately 700-day estimate. It also distinguishes manual syslog-ng application configuration from Salt-managed base host configuration.

The prior restore test demonstrates extraction of monitoring1's PBS backup and presence of WATO files and an RRD binary header. It did not parse the restored RRD with `rrdtool` or render an old graph. This is useful recovery evidence, but it does not prove historical graph usability or verify every site's archive. No additional restore was run in this pass. A graph/parse check against an isolated restore remains desirable before a future site retirement; avoid repeating a large restore merely for this inventory.

## Fresh baseline measurements

Successful SSH connections used existing trusted host keys. Device identity was obtained from `lsblk -d -o NAME,TYPE,TRAN,MODEL`; SMART was queried only on the identified internal `/dev/nvme0n1`, using `smartctl -a -j`. No USB disk SMART commands, self-tests, log rotation or configuration changes were performed. Selected machine-readable results are in [baseline JSON](data/2026-09-30-observability-nvme-baseline.json).

| Host | SMART timestamp (UTC) | NVMe data units written | Wear used | Temperature | Critical warning | Media errors |
| --- | --- | --- | --- | --- | --- | --- |
| pve1 | 2026-09-30 16:40:40 | 449590531 | 94% | 54°C | 0 | 0 |
| pve4 | 2026-09-30 16:37:52 | 265420810 | 63% | 54°C | 0 | 0 |
| pve6 | 2026-09-30 16:38:09 | 31896142 | 4% | 81°C | 0 | 0 |

Resource snapshots taken at 16:37:36 UTC reported pve4 memory total/available as 64031/13731 MiB and pve6 as 47903/6850 MiB. Their 15-minute loads were 8.82 and 8.31 respectively. These are point samples, not CPU-utilization percentages or a sustained RAM budget. In particular, pve6's available RAM differs from the earlier investigation's approximately 2.1 GiB; do not mix timestamps into a single capacity conclusion.

pve6 also reported cumulative warning-temperature time of 1504 minutes and critical-temperature time of 176 minutes. The 81°C reading deserves follow-up, despite a zero current SMART critical-warning bit. Historical counters do not establish when those conditions occurred or whether thermal throttling is active now. No cooling or workload changes were made.

Earlier SMART values in the prior audit lack precise per-host timestamps, so this pass does not derive a daily write rate from them. These fresh samples provide exact starting points for all three hosts. Repeat the same internal-device counters after approximately seven days (2026-10-07 around 16:38 UTC), preferably with intermediate samples and a record of backup, restore, VM-rebuild or other workload changes. Counter resets and device replacements must be handled explicitly. The seven-day baseline cannot be completed from this single observation, and no recurring collection job was installed.

## Loghost measurements and access

After the owner corrected trusted-host entries, normal strict SSH verification succeeded for pve1 and loghost. No verification bypass was used. monitoring2 still failed host-key verification; its previous site inventory remains sourced from the existing audit rather than independently refreshed here.

At 16:40:15 UTC, loghost had 512 MiB RAM, 347 MiB available, and active syslog-ng and salt-minion services. Its root filesystem is 2 GiB (1,037,565,952 bytes used), but `/var/log` is a **separate 3 GiB volume** with 797,573,120 bytes used and 2,423,652,352 available. This corrects the earlier inventory's inference that logs consumed the root volume. Journald reported 8.4 MiB currently used; that observation does not establish a configured maximum. The LXC load averages matched pve1's values, so do not interpret them as independent loghost CPU utilization.

`/etc/logrotate.d/syslog-ng` configures syslog daily with 365 rotations, compression and delayed compression; mail.log weekly with 52 rotations; auth.log and other listed logs weekly with four rotations. The four-week auth.log policy alone does not meet the planned 90-day authentication requirement; verify which authentication records are also retained in syslog before changing routing/retention.

| Rotated file suffix | Lines | Uncompressed bytes | Stored bytes |
| --- | --- | --- | --- |
| 2026-09-24.gz | 303167 | 38093861 | 3129050 |
| 2026-09-25.gz | 305180 | 38308865 | 3156780 |
| 2026-09-26.gz | 311265 | 39597644 | 3260599 |
| 2026-09-27.gz | 302077 | 37954942 | 3064670 |
| 2026-09-28.gz | 317404 | 40940138 | 3356988 |
| 2026-09-29.gz | 318012 | 40588789 | 3335315 |
| 2026-09-30 | 302167 | 37792047 | 37792047 |

These filenames mark rotation dates: for example, the last file contains records from September 29 00:00:09 through September 30 00:00:07 in the log's local timestamp format. It remains uncompressed because of delayed compression. All 364 compressed syslog archives together occupy 708,637,312 bytes by file size. These are logical file sizes, not SSD write volume or ZFS allocation.

monitoring1 contributes approximately 192,655–193,572 lines per sampled day, making it the dominant source. For the September 30 rotation, its leading program tags are systemd (117502), su (37863), CRON (29630) and systemd-logind (3390). Session/scheduler-related logging is therefore a useful next investigation target, but program names alone do not prove that messages are safe to suppress. This identifies a useful source for subsequent noise analysis; no filtering or log-level changes were made. Counts were produced by streaming the archives and returning aggregates, without copying raw log contents into the repo.

pve1's resource snapshot at 16:40:13 UTC showed 47,903 MiB total / 6,640 MiB available RAM and a 15-minute load of 7.95. Its internal NVMe wear indicator is now 94%; this is an endurance estimate rather than an exact failure forecast.

## TrueNAS version review: previous documentation-access gap resolved

The official [25.10 release notes](https://www.truenas.com/docs/scale/25.10/gettingstarted/versionnotes/) were readable in this pass. They list 25.10.7, released September 2, 2026, beyond the previously observed 25.10.0 installation. This is release-note evidence, not proof that the host has remained on that version or that its update profile offers a particular release.

Relevant changes include restored SNMP HDD-temperature data and notification-email fixes in 25.10.1, plus Cloud Sync task-visibility fixes in 25.10.2. Starting with 25.10.1, deprecated REST API use produces alerts; new API integrations should consider the versioned JSON-RPC/WebSocket interface or supported `midclt` route. Review the installed Checkmk integration before any separate upgrade to avoid API compatibility surprises. No upgrade is required or performed by this follow-up, and live collection compatibility remains untested.

## Remaining phase-0 work

1. Refresh monitoring2 only where it resolves a specific remaining question, after its host identity is verified. pve1 and loghost initial measurements are now captured.
2. Complete the elapsed-time baseline and account for exceptional workloads before setting an incremental logging write/RAM budget.
3. Validate RustFS accounting/quota access for the selected version, including freshness and permissions; prior directory counts are not authoritative logical-byte measurements.
4. Verify collector access on Talos and TrueNAS/API compatibility. Preserve USB-disk daily-check behavior without actively waking disks to test it.
5. Reconcile the original assessment and plan with verified inventory corrections. Keep the existing audits' provenance and distinguish reported results from independently reproduced evidence.

Phase 0 remains open. Neither a candidate backend nor an incremental resource budget has been selected on the basis of these partial measurements.
