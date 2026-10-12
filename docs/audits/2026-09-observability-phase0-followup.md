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
| pve5 | new node, no baseline (sampled 2026-10-12 06:23:20) | 1,682,800 in 58 power-on hours | about 0.86 TB since first power-on | not comparable: initial fill and guest migration | 0% | 62°C |
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

## Collection-interface follow-up

### Dev Kubernetes and Talos

Read-only queries against `admin@dev-homelab` found four Ready nodes: one control plane and three workers, running Talos 1.12.11 and Kubernetes 1.34.11. The API returned 184 current Events; this confirms availability at query time, not durable history. The `checkmk-agent` namespace and its DaemonSets are absent in this environment, so the pilot must not assume an existing Checkmk collector is available to extend.

The worker `dev-work-01.test.iseja.net` kubelet `/configz` reports `podLogsDir=/var/log/pods`, `containerLogMaxSize=10Mi` and `containerLogMaxFiles=5`. A directory listing through the Kubernetes node proxy confirmed pod-log directories actually exist there. No raw application log messages were retrieved. These settings are rotation bounds, not a guaranteed historical time window.

A future node log collector needs an explicitly read-only host-path mount and suitable admission settings; the existing `longhorn-system` and `csi-proxmox` namespaces are labeled privileged, but no collector admission/mount test was performed. Use a dedicated namespace and narrowly scoped workload configuration rather than inheriting another service's namespace. The Event collector separately needs least-privilege list/watch access. Current admin access does not prove that a future collector service account is correctly authorized.

Direct Talos API access failed certificate verification against worker `10.7.8.134` using the saved `dev-homelab` context. The installed Talos client was invoked directly because the local mise shim had no selected version; no tool configuration was changed. The owner was asked to refresh the trusted Talos configuration. Verification was not bypassed. Kubernetes API inspection succeeded independently, so direct Talos access is not necessary to establish the log location, but deployed-collector access remains untested.

### Longhorn disk interface

`nodes.longhorn.io` in dev's `longhorn-system` namespace exposes `status.diskStatus` with `storageMaximum`, `storageAvailable`, `storageScheduled`, and `Ready`/`Schedulable` conditions. All three worker disks reported 21,407,727,616 bytes maximum and 20,866,662,400 available. Scheduled bytes were 134,217,728 on worker 01 and 268,435,456 on workers 02/03. All were Ready and Schedulable.

This establishes a usable Kubernetes read interface for capacity checks without a Prometheus backend. Compute consumed filesystem space separately from scheduled allocation, and include configured reserves/scheduling policies when evaluating headroom. Collection freshness and Checkmk forecasting still need explicit implementation and testing.

### RustFS beta.12 source-level interface review

The version-pinned [quota handler](https://github.com/rustfs/rustfs/blob/1.0.0-beta.12/rustfs/src/admin/handlers/quota.rs) and [quota checker](https://github.com/rustfs/rustfs/blob/1.0.0-beta.12/crates/ecstore/src/bucket/quota/checker.rs) establish the following candidate contract. This is source inspection, not a successful live API test or confirmation that the deployed binary exactly matches this tag.

- `GET /rustfs/admin/v3/quota-stats/{bucket}` returns bucket, quota limit, current usage, remaining quota and usage percentage.
- `GET /rustfs/admin/v3/quota/{bucket}` returns quota and usage; the compatibility `get-bucket-quota` route returns quota configuration only and should not be mistaken for usage accounting.
- The handlers require credentials and check the bucket-scoped `GetBucketQuotaAction`. A dedicated read-only monitoring identity and actual policy enforcement remain to validate; backup credentials must not be assumed to grant this permission.
- `get_quota_stats` reads the quota configuration and calls `get_bucket_usage_memory`; that usage path does not perform a recursive object listing. Missing authoritative usage becomes `UsageUnavailable`, mapped to `ServiceUnavailable` by the handler. Missing buckets become `NoSuchBucket`. The Checkmk integration should report collection failure/unknown rather than translating these responses into zero usage.
- The response contains no accounting timestamp. A successful recent HTTP request is not proof that usage is fresh; scanner/accounting freshness needs an additional validated signal before this interface fully meets the plan.
- Each quota-statistics request emits a warning-level request event in this version. Polling cadence therefore affects log volume as well as request overhead.

These findings support evaluating quota-stats before resorting to full listings or a telemetry stack. Do not infer its behavior from the different `datausageinfo` route: an [upstream report for beta.9](https://redirect.github.com/rustfs/rustfs/issues/4902) describes slow scans through that route, but does not establish quota-stats behavior on beta.12.

Live TrueNAS/RustFS inspection was blocked when the workstation's SSH agent failed to sign the fiona connection. No credentials were extracted, authentication settings altered or live bucket API request sent. The owner was asked to unlock/approve the agent. Live version, response values, least-privilege policy, latency and accounting freshness still need checking once access works.

## Remaining phase-0 work

1. Refresh monitoring2 only where it resolves a specific remaining question, after its host identity is verified. pve1 and loghost initial measurements are now captured.
2. Complete the elapsed-time baseline and account for exceptional workloads before setting an incremental logging write/RAM budget.
3. Validate RustFS accounting/quota access for the selected version, including freshness and permissions; prior directory counts are not authoritative logical-byte measurements.
4. Verify collector access on Talos and TrueNAS/API compatibility. Preserve USB-disk daily-check behavior without actively waking disks to test it.
5. Reconcile the original assessment and plan with verified inventory corrections. Keep the existing audits' provenance and distinguish reported results from independently reproduced evidence.

Phase 0 remains open. Neither a candidate backend nor an incremental resource budget has been selected on the basis of these partial measurements.

## Second sample — 2026-10-12

**Origin:** Claude, read-only, for [#1437](https://github.com/isejalabs/homelab/issues/1437). SSH as `root` with the agent key (the first pass above used the same access), strict host-key checking, internal NVMe only (`smartctl -a -j /dev/nvme0n1`); no USB SMART probes, self-tests or changes. Raw values in [sample JSON](data/2026-10-12-observability-nvme-sample2.json).

The planned seven-day repeat (2026-10-07) was taken 11.6 days after the baseline. The workload of the interval (backups, restores, VM rebuilds) was not recorded, so the rates are averages over an unknown mix. One NVMe data unit is 512,000 bytes; these are **host** writes, not physical NAND writes.

| Host | Interval | Data units written (Δ) | Host writes | Average rate | Wear used | Temperature |
| --- | --- | --- | --- | --- | --- | --- |
| pve1 | 2026-09-30 16:40:40 → 2026-10-12 06:11:54 UTC (11.56 d) | 449,590,531 → 456,092,277 (+6,501,746) | about 3.33 TB | about 288 GB/day | 94% → 95% | 54°C → 49°C |
| pve4 | 2026-09-30 16:37:52 → 2026-10-12 06:11:55 UTC (11.57 d) | 265,420,810 → 272,146,624 (+6,725,814) | about 3.44 TB | about 298 GB/day | 63% → 65% | 54°C → **69°C** |
| pve6 | 2026-09-30 16:38:09 → 2026-10-12 06:18:21 UTC (11.57 d, host was off for part of it) | 31,896,142 → 37,090,385 (+5,194,243) | about 2.66 TB | about 230 GB/day over the whole interval, about 10.6 GB per powered-on hour | 4% → 6% | 81°C → 34°C (idle, just booted) |

Critical warning and media errors stayed 0 on all three hosts. Power-on hours advanced by 279 h (pve1) and 278 h (pve4), consistent with the elapsed time, so both ran continuously. pve6 advanced by only 250 h of the 277.7 h elapsed, and was unreachable until the owner powered it on for this sample (it had been up for under a minute), so the average over calendar time understates its rate while it runs.

Observations, without drawing conclusions the data does not support:

- pve1 gained one percentage point of wear in under 12 days. At that pace (a rough extrapolation of a vendor estimate, not a failure forecast) the remaining 5% would be used in about two months; the endurance indicator can exceed 100%. The write rate is the budget to compare monitoring and logging overhead against.
- pve4's temperature rose by 15°C compared with the baseline sample; its 15-minute load was 7.45 at sampling. A single reading does not show whether this is sustained.
- pve6: its cumulative time above the warning temperature grew from 1,504 to 2,454 minutes (+950) and above the critical composite temperature from 176 to 312 minutes (+136) while it ran 250 hours, so the 81°C reading from the baseline was not a one-off, and the follow-up on cooling or workload stays open. Today's 34°C only reflects an idle fresh boot. Its wear indicator rose from 4% to 6% with 2.66 TB written, a steeper ratio than pve1 or pve4, which is a different drive model (Samsung PM991a rather than Intel); the indicator is coarse at low values. Its memory is now 31,823 MiB total, against 47,903 MiB at the baseline, because the owner moved a 32 GB DIMM to pve5 and put a 16 GB DIMM from pve5 in its place on 2026-10-12 (confirmed with `dmidecode`: 2 × 16 GB on pve6; 32 GB + 16 GB on pve5, which reads 47,903 MiB). The earlier available-memory figures of pve6 therefore no longer apply.

### Loghost, same day

At 2026-10-12 06:14 UTC: 512 MiB RAM (about 298 MiB free, 74 MiB cache), syslog-ng and salt-minion active; root 1,035,206,656 of 2 GiB used (49%) and `/var/log` 813,039,616 of 3 GiB used (26%), against 797,573,120 on 2026-09-30 (+15.5 MB). Daily syslog rotations stayed in the same range as before: 301,875–316,854 lines per rotated day (5–11 October), about 3.0–3.3 MB compressed each; the current day's file already has 336,990 lines and 42.6 MB. 364 compressed archives (the 365-rotation policy is full) plus the current file occupy about 790 MB by file size. As before, these are logical file sizes, not SSD write volume.

### Checkmk backup recoverability: file-level restore test

A **file-level restore from the nightly Proxmox Backup Server snapshot** of monitoring1 (CT 7002061, snapshot `ct/7002061/2026-10-11T21:23:26Z`, 11.4 GB) was done with `proxmox-file-restore` from pve6 (read-only on the backup server; the PBS password is read from the PVE storage configuration inside the SSH session and never printed). The RRD `dev_k8s/var/check_mk/rrd/dev-ctrl-01.test.iseja.net/CPU_utilization.rrd` was extracted to a temporary file on the monitoring1 host, parsed with the `rrdtool` binary there, and deleted again together with the local copy. The `core` site was not touched (its binary was only used as a tool).

- The extracted file has the exact size listed in the snapshot (1,918,040 bytes) and a valid `RRD0003` header; `rrdtool info` shows step 60 and the four-tier layout (1 min × 2880, 30 min × 4320 = 90 days, 6 h × 5840 = 1460 days, plus a 5-minute tier) for AVERAGE, MAX and MIN, five GAUGE data sources, last update 2026-04-06 (the host has been gone since then, which makes it a historical series).
- `rrdtool fetch` returned real values from the restored file: the recent rows carry CPU utilization values, and 323 non-empty six-hour rows (about 80 days) in the 1,000 days before the last update. So old graph data is demonstrably readable from the backup, not only present as a file.
- Not done: a full restore of the container (it would create a guest and is not read-only), and PBS verification state of the newer snapshots (only 2026-10-08's shows a verification result `ok` in the storage listing; the later ones show none yet).
- The snapshot size fell from 15.6 GB (2026-10-10) to 11.4 GB (2026-10-11): the owner removed packages on monitoring1, so this is expected.

**monitoring2 (CT 7002056, snapshot `ct/7002056/2026-10-11T21:22:38Z`, 16.4 GB, extracted via pve4)** after the owner trusted its host key. One RRD per site was extracted, shipped over SSH to monitoring2 and parsed with the `prod` site's `rrdtool` binary, then deleted:

| Site | File | Size = listing | Header | Tiers (AVERAGE) | History found | Last update |
| --- | --- | --- | --- | --- | --- | --- |
| `prod` (Nagios core, PNP4Nagios) | `var/pnp4nagios/perfdata/adelheid.dir.iseja.net/CPU_load_load1.rrd` | 384,952 B, yes | `RRD0003` | 1 min × 2880, 5 min × 2880, 30 min × 4320, 6 h × 5840 | about 5,560 six-hour rows, roughly 3.8 years | live (2026-10-11) |
| `free` (CMC) | `var/check_mk/rrd/gw.home.iseja.net/Check_MK.rrd` | 2,684,584 B, yes | `RRD0003` | the same four tiers | about 740 six-hour rows, roughly 6 months | 2023-09-29 (the host has been gone since) |
| `prod_k8s` (CMC, 2.5) | `var/check_mk/rrd/cmk-k8s-cluster-collector.prod.iseja.net/CPU_resources.rrd` | 2,684,584 B, yes | `RRD0003` | the same four tiers | about 1,070 six-hour rows, roughly 9 months | live (2026-10-11) |

The history spans come from counting non-empty rows of the coarsest tier (six hours per row) with `rrdtool fetch`, so they are approximate; the point is that all three layouts, including PNP4Nagios, restore into files `rrdtool` reads, with real values in the recent rows (for example the restored `prod` file ends with load values of 0.05). Together with monitoring1 this covers a file from each of the sites checked, but not every file: the other RRDs of a site are the same format and were not each verified. Old graph usability is therefore shown for the RRD data; the WATO configuration of the sites was not part of this test.

Still open in #1437: a full-container restore if wanted, USB backup-disk polling behavior, the pilot resource/write budget, and the pve6 thermal and memory follow-ups.
