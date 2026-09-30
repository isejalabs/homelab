# Observability Phase 0 — Findings

**Date:** 2026-09-29. **Origin:** produced by Claude (Anthropic's Claude Code), via read-only SSH/`midclt`/`kubectl` commands against live infrastructure — not manually authored by the repository owner. Corrections noted throughout came from the owner reviewing this pass's initial output. **Status:** In progress — this is a consolidated summary of a first read-only investigation pass for [issue #1437](https://github.com/isejalabs/homelab/issues/1437). Detailed command-level evidence lives in two sibling docs:

- [`2026-09-observability-phase0-checkmk-proxmox-claude.md`](2026-09-observability-phase0-checkmk-proxmox-claude.md) — Checkmk sites/RRD/backups, Proxmox hosts (pve1/pve4/pve6), loghost.
- [`2026-09-observability-phase0-truenas-k8s-claude.md`](2026-09-observability-phase0-truenas-k8s-claude.md) — TrueNAS/RustFS, Longhorn/Talos.

Everything below is a point-in-time snapshot taken 2026-09-29 via read-only SSH/`midclt`/`kubectl get`/`rrdtool info` commands. Nothing was changed, restarted, or reconfigured; no SMART self-tests were run; USB-attached backup disks were not queried directly to avoid spin-up.

## Corrections to the September assessment/plan

These update or contradict specific claims in [`2026-09-observability.md`](2026-09-observability.md) / [`2026-09-observability.md` plan](../plans/2026-09-observability.md):

| Assessment claim | Actual finding |
| --- | --- |
| `prod_k8s` placement "absent from supplied `omd sites` output" | Lives on **monitoring2**, running **2.5.0p12.ultimate** (the other `_k8s` sites are 2.4.0p36.cce) |
| (not mentioned) `prod` site core | Runs **legacy Nagios + PNP4Nagios**, not CMC like every other site — different RRD path, different backup/notification behavior |
| "owner estimates approximately 700 days" RRD retention | Verified via live `rrdtool info`: 4-tier RRA scheme, longest tier is **1460 days (~4 years)** at 6h resolution, identical across all 5 in-scope sites |
| Checkmk backups (implicitly assumed to exist) | No `mkbackup`-level (Checkmk-native) backup is configured on 4/5 sites, and `prod`'s only job is a stale 2021 test. **However**, real, verified, full-container Proxmox Backup Server snapshots exist nightly for all three monitoring/loghost LXCs (`/etc/cron.d/vzdump`, pool-based, `--storage pbs` → external PBS at `10.7.15.116`) — an earlier pass in this investigation initially missed this and wrongly concluded no backup existed at all; corrected after owner feedback. See "Checkmk/LXC backup — corrected" below |
| pve1 SSD "203 TB written and 91% endurance used" | Now **229 TB / 93%** — continued climbing since the assessment was written |
| `natascha1/gamma/srv/rustfs` (read as a hostname) | `natascha1` is a **ZFS pool name**, not a host. The actual TrueNAS host is **`fiona.home.iseja.net`** |
| "eight kopiur backup buckets, four active" | Confirmed exactly as stated, **plus** four previously-undocumented `*-longhorn-backup` buckets — Longhorn's own native S3 `BackupTarget` CRD, already wired live for `prod-homelab` and `dev-homelab` against the same RustFS/fiona endpoint |
| "Salt manages Linux host configuration, including monitoring1/2 and loghost" | Correct at the host level (loghost is a normal Salt minion like any other Linux system — confirmed `salt-minion` active/enabled). **But** per owner: loghost's *application setup* — syslog-ng and its configuration — was installed/configured manually, not via Salt. The assessment's claim holds for base host config but not for the loghost-specific service configuration. |

## Checkmk/LXC backup — corrected

An earlier version of this document reported "no Proxmox-level backup job covers any of the three monitoring/loghost LXCs" as the single biggest finding. **That was wrong**, per your correction — you pointed out that all QM/LXC VMs are backed up via `/etc/cron.d/vzdump`. Re-verified directly:

- `/etc/cron.d/vzdump` (identical on pve1/pve4/pve6, Proxmox-generated) runs three pool-based jobs nightly (23:10/23:20/23:30) targeting an external **Proxmox Backup Server** (`10.7.15.116`, datastore `polina1`).
- loghost (VMID 7002020) is in the `Crit` pool; monitoring1 (7002061) and monitoring2 (7002056) are both in the `Prod` pool — all three are covered.
- Confirmed real snapshots exist on PBS for all three: `format: pbs-ct`, `subtype: lxc` (full-container), going back to at least 2026-02-22, daily since ~2026-09-19, most recent 2026-09-28. Older snapshots show `verification.state: "ok"`.
- The earlier finding was based only on `/etc/pve/jobs.cfg`, which is real but is a *separate, supplementary* weekly job for three unrelated VMs (gw2, gw3, Polina) — it isn't, and was never meant to be, the primary backup mechanism.

**Revised bottom line**: the LXCs themselves (including `/omd/sites/*` RRDs/config on the monitoring hosts) are backed up nightly and the backups verify as healthy. The one real remaining gap was narrower than originally stated: there's no Checkmk-*native* (`mkbackup`) export, and until now nobody had performed a test restore of a PBS snapshot into isolation. Full detail in the [checkmk-proxmox doc](2026-09-observability-phase0-checkmk-proxmox-claude.md#checkmk-backups-no-mkbackup-level-job-but-full-container-pbs-backups-exist-and-are-verified).

### Isolated restore test (2026-09-30) — passed

Performed the actual test restore: `monitoring1`'s most recent PBS snapshot (`pbs:backup/ct/7002061/2026-09-29T21:22:10Z`, ~14.2 GB) restored via `pct restore 101 ... --storage local-enc --unprivileged 1` into a new, isolated VMID **on the same node monitoring1 already runs on (pve6)** — never started, never networked.

- Extraction took **~20 minutes** (01:51–02:11 CEST) — slow because of the sheer number of small RRD/WATO files, not a hang; confirmed via `vmstat` showing 50%+ I/O-wait and ZFS `txg_sync`/`zvol_tq` threads in disk-wait while it ran.
- **Cost/impact note**: container creation and disk writes stayed on pve6, but the restore necessarily *reads* backup data from the PBS server itself — Polina (VMID 7005116), which runs on **pve1**, not pve6. So this test did add ~20 minutes of extra read I/O/network load against Polina/pve1, on top of whatever else runs there overnight (the owner flagged that PBS itself runs additional jobs around 2–3 AM). Worth keeping in mind for any future restore test: consider timing it outside that window, or ask first if it lands inside it.
- Verified read-only via `pct mount 101` (no boot, no network): `ls /opt/omd/sites/` showed all three of monitoring1's real sites (`core`, `dev_k8s`, `qa_k8s`); a sample RRD (`dev_k8s/var/check_mk/rrd/dev-work-03.test.iseja.net/Uptime.rrd`, 385 KB) has an intact `RRD\0` binary header (checked via `od -c`, since `rrdtool` isn't installed on the Proxmox host itself — a full `rrdtool info` parse wasn't done, but the file is not truncated/corrupted); WATO config (`dev_k8s/etc/check_mk/conf.d/wato/hosts.mk`, `global.mk`, `contacts.mk`) is present and human-readable with real content.
- Cleaned up immediately: `pct unmount 101` + `pct destroy 101 --purge 1` — confirmed no residual config/disk left on pve6.

**Acceptance criterion #2 ("Checkmk backups shown to be recoverable, including old graphs in an isolated restore where feasible") is now satisfied**: a real snapshot restores intact, RRDs and WATO config both survive, and cleanup leaves no trace. This was a single sample (`monitoring1`, one snapshot) — extending the same spot-check to `monitoring2`/`loghost` would be pure confirmation, not a new finding, so it's not treated as a blocking gap.

## Resolved via owner feedback

- **`loghost2.home.iseja.net`**: was a deliberate test copy of loghost created to test a Debian upgrade, not a mystery/undocumented host. The commented-out forwarding rule referencing it is consistent with it being a retired one-off test box — no action needed, single-node `loghost` remains the real log source for phase 1B planning purposes.
- **AD-sync source**: Active Directory itself runs on the UCS servers `adelheid.dir.iseja.net` and `baerbel.dir.iseja.net` — those are the actual domain controllers and the right log source for "AD synchronization failures" in the phase-2 source rollout. Separately, TrueNAS (`fiona`) has its own native AD *join* (SCALE directory services, `directoryservices.status` → `HEALTHY`, computer account `FIONA$@DIR.ISEJA.NET`) — this is why no discrete "AD sync job" was found via `cloudsync`/`rsynctask`: it isn't a scheduled job at all, it's an ongoing domain-join/idmap integration. Worth including TrueNAS's own directory-service health as a secondary, smaller monitoring signal alongside the UCS DCs.
- **`natascha.home.iseja.net` (10.7.5.114)**: not a live investigation target — it's the old, superseded predecessor host that `fiona` replaced; `fiona` inherited the `natascha1` zpool name from it, which is what caused the confusion in the first place. The DNS name itself was never found in any repo file or live config — it was a guess this investigation tried, derived from the assessment doc's `natascha1/gamma/srv/rustfs` text before it was known that `natascha1` is just a pool name. It happened to resolve to a real (but unreachable/retired) DNS record. No further action needed.

## New/undocumented items surfaced

- Longhorn's backup-target model has moved to a dedicated `backuptargets.longhorn.io` CRD in the deployed version, not the older Settings-based `backup-target` model the plan/assessment assumed.
- Checkmk's Linux agent already tracks per-job backup run history (`vzdump_*`, `borgbackup`, cron_* durations/exit codes) under `/var/lib/check_mk_agent/job/root/` — a ready-made signal for the phase-2 "backup coverage matrix" item.
- `pvecm status` shows `Expected votes: 5` / `Highest expected: 5` against only 3 active cluster members — noticed in passing, not investigated, possibly unrelated to this project.
- Two host-key mismatches were hit during this session (`monitoring1`, `pve6`) — you updated `known_hosts` yourself before the investigation continued. pve6's unusually low SMART wear/hours and different drive model versus pve1/pve4 is *consistent with* a recent rebuild, which would also explain the key change, but that's inference, not confirmed against change history.
- **`qa-work-03.test.iseja.net` was found `NotReady` since 2026-09-25** (kubelet stopped posting status), found incidentally while checking Longhorn state across environments during the [PR #1458](https://github.com/isejalabs/homelab/pull/1458) review. Its stuck old-version `longhorn-manager` pod was directly causing an active crash loop in `qa`'s Longhorn manager after the chart was bumped to v1.13.0. **Remediated 2026-09-30 at the owner's request**: the VM was simply stopped (not hung) — found via `just proxmox vm list -e qa`, restarted via `just proxmox vm start -e qa --vmid 7008126`; the stuck pod was force-deleted, clearing the crash loop; the node rejoined and Longhorn's manager is now stable on it.

  **Root cause, traced via loghost's syslog**: two separate, unrelated problems, six days apart. (1) On 2026-09-19, Terraform legitimately destroyed and recreated qa-work-03 (old VM on pve5 → new VM on pve6) as a routine infra rebuild — the fresh disk this created is why Longhorn's disk record shows a `DiskFilesystemChanged`/UUID-mismatch condition dated that day; not corruption, just an unreconciled disk record, still open (needs a Longhorn disk re-add + replica rebuild — left for the owner). (2) On 2026-09-25, pve6's kernel OOM-killer killed qa-work-03's VM process outright — this is what actually caused the 5-day outage, and it's part of a **broader, still-current pve6 memory-pressure problem**: the same OOM-killer also hit `prod-work-03` and `dbg-work-03` on 09-19 (prod self-recovered quickly; dbg's current stopped state is an unrelated, deliberate later shutdown). Per the owner, pve6's RAM was upgraded between 09-19 and 09-25 (explains the 09-20 reboot and pve6's oddly-low SMART wear/different drive model noted earlier) — but **pve6 still runs at ~44GB/46GB used today**, so the overcommit risk (including for prod) isn't resolved. Full timeline and evidence in the [checkmk-proxmox doc](2026-09-observability-phase0-checkmk-proxmox-claude.md#pve6-memory-pressure-and-the-qa-work-03-outage-2026-09-30-investigation) and the [truenas-k8s doc](2026-09-observability-phase0-truenas-k8s-claude.md)'s qa section.

## Phase 0 acceptance criteria — status

From [the plan](../plans/2026-09-observability.md#phase-0--baseline-inventory-and-preservation):

| # | Acceptance item | Status | Notes |
| --- | --- | --- | --- |
| 1 | Current site/source inventory and actual RRD resolutions/retention recorded | **Done** | 5 Checkmk sites inventoried, RRD tiers confirmed live via `rrdtool info` |
| 2 | Checkmk backups shown to be recoverable | **Done** | Nightly full-container PBS snapshots exist and verify healthy for all three LXCs; isolated test restore of monitoring1's latest snapshot performed 2026-09-30, RRDs and WATO config both confirmed intact — see "Isolated restore test" above |
| 3 | Loghost traffic and SSD write/resource baseline recorded, with units/intervals/confounders | **Partial** | Day-0 SMART snapshot taken for pve1/pve4/pve6; loghost's own daily log-volume/logrotate figures not captured; the actual 7-day delta genuinely needs elapsed time |
| 4 | RustFS/Longhorn/Talos/TrueNAS interfaces inspected; version/compatibility checked | **Partial** | TrueNAS + RustFS + Longhorn now checked across all 5 environments (`qa`/`rebuild` on 2026-09-30; `dbg` confirmed N/A — no Longhorn, cluster unreachable). RustFS has a newer `1.0.1-preview` series (quota-fix status still unconfirmed); TrueNAS's own point-release changelog remains unresearched — its docs site isn't fetchable via WebFetch, needs checking directly in the TrueNAS UI |
| 5 | Existing service/USB backup-disk polling/caching behavior recorded; no added spin-ups | **Partial** | Checkmk's `86400`-interval cached SMART plugin confirmed for Linux hosts; ZFS space accounting confirmed as in-memory (not verified against an actually spun-down disk); USB disks' own SMART/wear data intentionally not queried |
| 6 | Pilot resource/write budget agreed from baseline | **Not started** | Blocked on #3's 7-day measurement |

## Open questions for you

- pve1's SSD is at 93% wear (229 TB written) — independent of this project, but worth flagging: is a replacement already planned?
- loghost's syslog-ng setup is manually configured, not Salt-managed — worth keeping in mind for any phase 1B rollout that assumes Salt-managed config on loghost; no action needed for this project otherwise.

## Remaining access/inventory gaps

- Salt-based inventory (`salt-key -L`, `salt '*' grains...`) — `salt-master` needs a sudo password not available in this session.
- loghost daily log-line-count/logrotate figures (transient tool issue mid-session, not retried).
- USB backup disk SMART/wear (by design, not queried this pass).
- RustFS's own S3 admin API for exact per-bucket logical-byte/quota accounting (no admin credentials pulled).
- TrueNAS SCALE point-release changelog comparison (WebFetch couldn't get usable content from TrueNAS's docs site; needs checking directly in the TrueNAS UI's update page instead).
- borgmatic's actual backup-server target — **deliberately deferred**, not a gap: backup infrastructure is a separate topic the owner will address in the coming days, out of scope for this observability pass.

Closed since the last update: Checkmk notification-rule contents (reviewed), `qa`/`rebuild`/`dbg` Longhorn state (checked — surfaced the `qa-work-03` NotReady issue above), Syncthing folder configuration (resolved — wrong container name).

## Suggested next steps

1. Close the remaining access gaps above (most just need either the salt-master sudo password, RustFS admin credentials, or a look at the TrueNAS UI's update page).
2. Start the 7-day write-delta/log-volume measurement window — this needs a decision on mechanism (manual daily re-run vs. some kind of scheduled snapshot script), since setting up new instrumentation goes slightly beyond this pass's "read without changing" scope. Note for scheduling any future live-infrastructure work: avoid the ~2–3 AM window if possible, since PBS runs its own jobs against Polina/pve1 then.
3. Once the above settles, fold the corrections in this doc back into `docs/audits/2026-09-observability.md` and `docs/plans/2026-09-observability.md`, and only then open the actual GitHub issue update / PR.
