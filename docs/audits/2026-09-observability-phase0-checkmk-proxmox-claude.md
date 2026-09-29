# Phase 0 inventory — Checkmk, Proxmox, loghost

**Date:** 2026-09-29. **Origin:** produced by Claude (Anthropic's Claude Code), via read-only SSH commands against live infrastructure — not manually authored by the repository owner. **Scope:** Read-only SSH inventory for [issue #1437](https://github.com/isejalabs/homelab/issues/1437) (Observability phase 0). Covers Checkmk site/RRD/backup inventory, Proxmox host capacity/SMART/backup-job inventory, and loghost syslog-ng/journald config. Does not cover RustFS/Longhorn/TrueNAS (separate pass) or the 7-day write-delta measurement (needs real elapsed time, not done here). No configuration was changed; no SMART self-tests were run; no USB backup disk was queried directly to avoid spin-up.

Access used: root SSH (agent key) to `monitoring1/2`, `loghost`, `pve1/4/6`. `salt-master.home.iseja.net` was reachable as `localsebi` but `sudo` needs a password we didn't have, so `salt-key`/`salt '*' grains...`-based inventory was not available — anywhere below marked "via Salt" was NOT obtained and is a gap.

## Checkmk site inventory

| Host (LXC) | Site | Version | Core | Hosts monitored | RRD/graph storage |
| --- | --- | --- | --- | --- | --- |
| monitoring1 (pve6) | `core` | 2.5.0p12.ultimate | — | — | Out of scope, not inventoried further |
| monitoring1 (pve6) | `dev_k8s` | 2.4.0p36.cce | cmc | 5 | `var/check_mk/rrd/` |
| monitoring1 (pve6) | `qa_k8s` | 2.4.0p36.cce | cmc | 66 | `var/check_mk/rrd/` |
| monitoring2 (pve4) | `free` | 2.4.0p36.cre | cmc | 18 | `var/check_mk/rrd/` |
| monitoring2 (pve4) | `prod` | 2.4.0p36.cre | **nagios** | 78 | `var/pnp4nagios/perfdata/` (PNP4Nagios, not the CMC `var/check_mk/rrd` layout) |
| monitoring2 (pve4) | `prod_k8s` | **2.5.0p12.ultimate** | cmc | 69 | `var/check_mk/rrd/` |

**`prod_k8s` placement resolved**: it lives on `monitoring2`, not `monitoring1`, and unlike every other `_k8s` site it runs the newer **2.5.0p12.ultimate** edition (the other `_k8s` sites are 2.4.0p36.cce). This was an open question in the assessment doc ("absent from supplied `omd sites` output; placement/current status remains to verify") — now confirmed present and reachable. Worth calling out: `prod_k8s` and `core` are the only 2.5.0p12.ultimate sites, so any edition-specific behavior (OpenTelemetry, licensing) applies to those two only, not the 2.4-era `cce`/`cre` sites.

**`prod` uses the legacy Nagios core + PNP4Nagios**, not CMC like every other site here. This wasn't previously documented and matters for phase 1+ work: notification rule syntax, RRD path conventions, and backup/`mkbackup` behavior all differ between `nagios`/PNP4Nagios and `cmc`. Any tooling built against the CMC sites' `var/check_mk/rrd/<host>/<service>.rrd` layout will not find `prod`'s graphs there — they're under `var/pnp4nagios/perfdata/`.

### RRD retention (verified via `rrdtool info` on live files, both storage layouts)

Every site sampled (dev_k8s, qa_k8s, free, prod via PNP4Nagios, prod_k8s) uses the same 4-tier RRA scheme, `step = 60`s:

| Tier | Resolution | Rows | Retention |
| --- | --- | --- | --- |
| 1 | 1 min (pdp_per_row=1) | 2880 | 2 days |
| 2 | 5 min (pdp_per_row=5) | 2880 | 10 days |
| 3 | 30 min (pdp_per_row=30) | 4320 | 90 days |
| 4 | 6 hours (pdp_per_row=360) | 5840 | **1460 days (~4 years)** |

Each tier stores AVERAGE, MAX, and MIN consolidation functions.

**This contradicts the assessment's "owner estimates approximately 700 days"** — the actual longest-retained tier is ~1460 days (~4 years) at 6-hour resolution, roughly double the estimate. Acceptance item "actual RRD resolutions/retention recorded" is satisfied by this table; the "~700 days" figure in the assessment/plan docs should be corrected to ~1460 days once this is folded back in.

### Checkmk backups: no `mkbackup`-level job, but full-container PBS backups exist and are verified

**Correction (2026-09-29, after owner feedback):** an earlier version of this section claimed no Proxmox-level backup covered the monitoring/loghost LXCs at all. That was wrong — it was based only on `/etc/pve/jobs.cfg`, which turns out to be a *separate, supplementary* weekly job for three other VMs, not the primary backup mechanism. The actual cluster-wide backup schedule lives in `/etc/cron.d/vzdump` (identical on pve1/pve4/pve6, Proxmox-generated, do-not-edit), and it does cover all three LXCs:

```
10 23 * * *  root mk-job vzdump_crit vzdump --pool Crit --storage pbs --mode snapshot ...
20 23 * * *  root mk-job vzdump_prod vzdump --pool Prod --storage pbs --mode snapshot ...
30 23 * * *  root mk-job vzdump_test vzdump --pool Test --storage pbs --mode snapshot ...
```

(`mk-job` is Checkmk's job-tracking wrapper — this is also the source of the `vzdump_*` entries noted in the "Backup job tracking" bonus finding below.)

Pool membership (`pvesh get /pools/<name>`): **loghost (VMID 7002020) is in the `Crit` pool**; **monitoring1 (7002061) and monitoring2 (7002056) are both in the `Prod` pool**. All three therefore run through the nightly `--storage pbs` job.

`pbs` (`/etc/pve/storage.cfg`) is a real external **Proxmox Backup Server** at `10.7.15.116`, datastore `polina1`, namespace `home.iseja.net`. Checked actual stored snapshots via `pvesh get /nodes/<node>/storage/pbs/content --vmid <id>`:

- loghost: snapshots present back to 2026-02-22, monthly cadence historically, **daily since ~2026-09-19**, most recent **2026-09-28T21:10:02Z**. Older snapshots show `verification.state: "ok"`; the last ~4 days haven't had a verification pass run over them yet (normal — verification runs on its own schedule).
- monitoring1 and monitoring2: same pattern, same dates, verified "ok" on older snapshots.
- Format is `pbs-ct` / `subtype: lxc` — a **full-container snapshot**, not a partial file-level backup, so it does include `/omd/sites/*` (RRDs, WATO config, host/service definitions) inside monitoring1/monitoring2, and loghost's full filesystem including `/etc/syslog-ng`, logcheck config, and archived logs.

Separately, `/etc/pve/jobs.cfg` (still real, just not the primary mechanism) adds a **weekly** (Sun 01:00) backup for VMIDs `7000002` (gw2), `7000003` (gw3), `7005116` (Polina) to `vm-backup` (NFS) and `local-backup` (local dir) — redundant, extra protection for those three specific VMs on top of the nightly PBS job all pooled VMs already get. This does not add coverage for the monitoring/loghost LXCs, but it isn't a gap for them either, since the PBS job already covers them.

The `borgmatic` backup (host's `/root /etc /usr/local` to `baksrv.home.iseja.net`/`pi4.dir.iseja.net`) is real but separate and narrower, as originally noted — it backs up Proxmox host config, not LXC content; the PBS vzdump job is what actually protects the LXC/container data.

**Still open** (this is where a real gap may remain): no `mkbackup`-level (Checkmk-native) backup/export is configured on 4 of 5 sites, and `prod`'s only `mkbackup` job is a stale, unscheduled 2021 test pointed at a nonexistent `/tmp` path. This means there's no Checkmk-specific *application-level* export (e.g. for migrating a site to a different host/edition independent of the underlying LXC), and the phase-0 acceptance item "Checkmk backups shown to be recoverable, **including old graphs in an isolated restore where feasible**" hasn't actually been exercised — the PBS snapshots exist and are verified, but nobody has performed a test restore-into-isolation of one to confirm the RRDs/WATO config actually come back usable. That's the concrete next step, not "no backup exists."

### Notifications, host list

Not fully inventoried this pass — `etc/check_mk/conf.d/wato/rules.mk` exists on every site (confirmed present, not read in detail) and is presumably where notification rules live; contents weren't reviewed. **Gap: notification rule content still needs review** in a follow-up pass.

## Proxmox host inventory (pve1, pve4, pve6)

Confirmed placement matches the assessment: `monitoring1` on **pve6**, `monitoring2` on **pve4**, `loghost` on **pve1** (via `pct list` on each node).

Cluster: 3-node `ISEJA-Lab` cluster (pve1/pve4/pve6), quorate, `corosync`/`knet`. (`pvecm status` also shows `Expected votes: 5`/`Highest expected: 5` with only 3 nodes contributing votes — there may be two more configured-but-absent members; not investigated further, out of scope for this pass.)

### `tank` ZFS pool free space (matches assessment)

| Host | `tank` size | Free | Assessment claimed |
| --- | --- | --- | --- |
| pve1 | 398G | 280G | 281 GB ✓ (within rounding) |
| pve4 | 398G | 288G | 288 GB ✓ |
| pve6 | 398G | 322G | 322 GB ✓ |

All three confirmed clean (`zpool status`: ONLINE, 0 errors, most recent scrub 2026-09-13 on all three, no repairs needed).

### SSD/NVMe write endurance (SMART, read-only `-a`, no self-tests run)

| Host | Model | Data units written | % used (wear) | Power-on hours |
| --- | --- | --- | --- | --- |
| pve1 | Intel SSDPEKNW512G8 | 448,791,517 → **229 TB** | **93%** | 28,350 (~3.2 yr) |
| pve4 | Intel SSDPEKNW512G8 | 264,559,390 → **135 TB** | 63% | 14,635 (~1.7 yr) |
| pve6 | Samsung PM991a 512GB | 31,070,255 → **15.9 TB** | 4% | 2,202 (~92 days) |

**pve1's boot NVMe is now at 93% wear (up from the assessment's 91%/203TB)** — it's continued climbing and has very little headroom left before the "one 512GB SSD wore out after ~3 years / 138TB" failure story the assessment cites repeats itself; pve1 is already past that point (229TB) and at 93% used. This host runs `loghost`, `ns1`, `nsresolv1`, `smarthost`, `mqtt`, `webfront` — worth flagging as a near-term hardware risk independent of the observability project, and a strong argument for keeping any new logging backend's write footprint on pve1 (loghost) as small as possible.

pve6's very low wear/hours and different drive model (Samsung PM991a vs. the Intel drives on pve1/pve4) is consistent with the host-key mismatch flagged earlier in this session (pve6 was likely rebuilt/reinstalled recently) — noting this as probable explanation, not confirmed against change history.

### USB-attached backup disks

| Host | Devices (via `lsblk`, `tran=usb`) |
| --- | --- |
| pve1 | 1× SanDisk Extreme Portable SSD, 931.5G |
| pve4 | WD80EFZZ 7.3T, WD80EZAZ 7.3T, WD60EFZX 5.5T, 2× Samsung MZ7TE256HMHP 238.5G SSD; plus a separate always-mounted `book8tb` ZFS pool (My Book 8TB, 3.79T free) |
| pve6 | none currently attached |

**Not queried directly** (per the "no additional spin-ups" instruction) — instead found the existing mechanism:

- Checkmk's Linux agent plugin `/usr/lib/check_mk_agent/plugins/86400/smart_posix` runs `smartctl --scan` + `smartctl --all --json=c` on every detected device. The `86400` in its path is Checkmk's plugin-cache-interval convention — **this plugin is cached and only actually executed once per 86400s (daily)**, confirmed via the cache file timestamp on pve4 (`plugins_smart_posix.cache` mtime 2026-09-28 23:59, ~10h before this check — i.e., due to run again around the same time tonight). A now-unused legacy `smart.cache` file is stale since 2025-12-12, suggesting an older SMART plugin was superseded by `smart_posix` around that date.
- Disk-space/usage checks for ZFS pools are handled by Checkmk's built-in `zfsget` agent section (not a separate cached plugin) — `zfs get`-style pool/dataset accounting is served from ZFS's own in-memory space accounting and does not require reading data off a spun-down disk, which is consistent with the owner's report that usage checks don't wake the USB disks. This wasn't independently verified against a spun-down disk in this pass (would require watching disk state during a real check) — **flagged as plausible-but-unconfirmed**, not a directly observed fact.
- **Did not query SMART directly on any USB disk in this pass** to avoid an out-of-band spin-up; the daily plugin cadence above is the extent of what was confirmed without touching the disks ourselves.

### Backup job tracking (bonus finding, adjacent to scope)

Checkmk's agent also tracks recent job runs under `/var/lib/check_mk_agent/job/root/` on pve4, including `vzdump_prod`, `vzdump_test`, `vzdump_crit`, `borgbackup`, `cron_daily/weekly/monthly/hourly` — each with start time, duration, and exit code (`vzdump_prod` sampled: ~10m runtime, `exit_code 0`). This is presumably surfaced as a Checkmk service (job-duration/success check) and is a useful existing signal for the later backup-coverage-matrix acceptance item in phase 2 — not investigated further here.

## loghost

- syslog-ng: stock Debian `syslog-ng.conf` plus one custom file, `/etc/syslog-ng/conf.d/local-iseja.conf`. That file adds a `s_network` source accepting **both TCP and UDP** ("UDP needed for FreeNAS" — comment in the config, confirms TrueNAS/RustFS box forwards via UDP syslog), and files everything into the same `d_syslog`/`d_mail` destinations as local logs.
- `local-iseja.conf` defines (commented-out, currently inactive) `destination d_net { tcp("loghost2.home.iseja.net" ...) }`. **Resolved via owner feedback**: `loghost2` was a deliberate one-off test copy of loghost created to test a Debian upgrade, not an undocumented second production host. Single-node `loghost` remains the only real historical log source for phase 1B planning.
- **Salt management correction (owner feedback)**: loghost the *host* is Salt-managed like any other Linux system (confirmed: `salt-minion` 3008.2 installed, systemd service active/enabled since 2026-09-20, populated `/etc/salt/minion`) — base config, packages, etc. all go through Salt normally. What's **not** Salt-managed is loghost's actual *application setup*: syslog-ng and its configuration (`/etc/syslog-ng/conf.d/local-iseja.conf`) were installed and configured manually, not via a Salt state. Treat that config as manually administered for any phase 1B Salt-based rollout planning — it won't be picked up or reconciled by a highstate.
- `journald.conf` has **no explicit overrides** — the `[Journal]` section is empty, meaning any size cap is journald's dynamic runtime default (typically a fraction of free space on the volume holding `/var/log/journal`), not a fixed "10MB" setting anywhere in config. The assessment's "reported 10 MB cap" should be treated as an observed behavior, not a configured value — worth re-verifying against actual `journalctl --disk-usage` output in a follow-up (not captured in this pass; command was blocked mid-session by a transient tool-availability error and not retried before this write-up).
- `logcheck` 1.4.2+deb12u1 installed, `REPORTLEVEL=server`, mail digest to `logcheck@sebastian.klamar.name`, `SYSLOGSUMMARY=1`.
- Root filesystem is a **2.0G** LXC volume (`tank/pve/subvol-7002020-disk-2`), already 49% used (990M), with `/var/log` alone at 755M. This is a tight constraint: any phase-1B logging backend (VictoriaLogs/Loki pilot) sized against loghost's disk will need either a larger volume or very aggressive retention — worth flagging explicitly in the phase-1B pilot sizing rather than assuming headroom.
- **Not captured this pass** (tool access briefly unavailable, not retried): exact daily/rotated log line counts (`wc -l` on live vs. rotated `syslog.*.gz`) to cross-check the assessment's 320,000/133,000-lines-per-day figures, and `logrotate.d` retention/compression settings. Should be quick to pick up in a follow-up.

## Access gaps / things not verified this pass

- **No Salt-based inventory** (`salt-key -L`, `salt '*' grains.item ...`) — `salt-master` needs a sudo password we don't have. Anything meant to come "via Salt" (e.g. a full minion list cross-checked against Checkmk's host list) is still open.
- **Checkmk notification rules** (`etc/check_mk/conf.d/wato/rules.mk`) — confirmed to exist on each site, contents not reviewed.
- **loghost**: exact daily line-count/volume figures and logrotate retention settings not captured (see above).
- **USB backup disks**: not queried directly (by design, to avoid spin-up outside the existing daily cadence); their SMART/wear data is therefore still unknown, only the polling mechanism was confirmed.
- **RustFS, Longhorn, TrueNAS** (versions, bucket/quota config, Longhorn per-node disk settings) — entirely out of scope for this pass, needs a separate sweep.
- **7-day host-write-delta / log-volume baseline** — inherently needs real elapsed time; not attempted here. Everything above is a point-in-time snapshot (2026-09-29).
- **pvecm's "Expected votes: 5" vs. 3 active nodes** — noticed in passing, not investigated; may indicate two additional configured-but-currently-absent cluster members, or may be unrelated to this project.
