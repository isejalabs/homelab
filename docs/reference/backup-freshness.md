---
status: current
---

# Backup freshness

**Status:** current as of 2026-11-09. Read live on that date over read-only SSH (`polina`, `pve4`, `fiona` with `midclt`, `monitoring2` with `lq` against the `prod` site), read-only `kubectl` against `prod`, `qa` and `dev`, and from the Salt states in `sebiklamar/salt-iseja.net` (`apps/backup/*`). If this page and the live systems disagree, the systems win and this page is stale.

**Tracking:** [#2159](https://github.com/isejalabs/homelab/issues/2159) (stream C of the [observability plan](../plans/2026-11-observability.md#c--backup-freshness)), zrepl in [#1905](https://github.com/isejalabs/homelab/issues/1905). Restore procedures are in [`docs/backup/`](../backup); this page only answers "would anyone notice if this backup stopped?".

Every backup path, how often it runs, what tells us it last succeeded, and whether that signal reaches a person. Two facts frame the whole table:

- **Checkmk notifications are off** on `prod` and `prod_k8s` until stream B ([#2158](https://github.com/isejalabs/homelab/issues/2158)) is done, see [`monitoring-notifications.md`](monitoring-notifications.md). A CRIT service in the table below is visible in the web interface, but nobody is told.
- **healthchecks.io** is the only channel that reaches the owner today, and only for the paths that ping it. Its own notification settings are not visible from here (no API key outside 1Password); see [Open questions](#open-questions).

## Matrix

"Signal" is what records the last success. "Alerts" is whether a stale or failed run reaches a person today.

| Path | Source → target | Schedule | Signal | Alerts today | State on 2026-11-09 |
| --- | --- | --- | --- | --- | --- |
| **kopiur** | PVCs of `prod`, `qa`, `dev` → RustFS `<env>-kopiur-backup` on `fiona` | daily, `H 3 * * *` per `SnapshotSchedule` | `Snapshot` objects (phase `Succeeded`), `SnapshotSchedule.status.consecutiveFailures`, the controller metric `kopiur_policy_last_backup_success_timestamp_seconds` | **No.** Checkmk sees only bucket size (`RustFS bucket <env>-kopiur-backup`), not age | OK: every schedule in `prod` (5), `qa` (4) and `dev` (1) succeeded last night, 0 failures |
| **Longhorn `hourly-snapshot`** | Longhorn volumes → local snapshots (no offsite, see [kopiur doc](../backup/kopiur-backup-restore.md#overview)) | hourly, retain 24 | `snapshots.longhorn.io` creation times | **No** | not checked per volume; local rollback only |
| **Keycloak database dump** | CNPG `keycloak-db` → RustFS on `fiona` | daily 02:00 | healthchecks.io success and `/fail` pings | **Yes, `qa` only** (healthchecks.io, see [`keycloak-backup-restore.md`](../identity/keycloak-backup-restore.md#alerting)); `dev`/`rebuild` on purpose without | not checked here |
| **vzdump → PBS** | every Proxmox guest → PBS datastore `polina1` on `polina` | nightly ~23:20 (`vzdump_prod`, `vzdump_crit`, `vzdump_test`) | Checkmk `Proxmox VE VM Backup Status` per guest, default levels 26 h / 50 h; `Job vzdump_*` per node (exit code only) | **Signal yes, notification no** (B) | OK for every guest except `sybille` (`No backup found`, CRIT; host itself DOWN) |
| **PBS mirror to `fiona`** | `polina1` → `natascha1/gamma/mirror/polina1` on `fiona` (TrueNAS pull replication over SSH) | daily 00:07 | TrueNAS replication state and `ReplicationFailed` alert | TrueNAS mails it; **Checkmk: no** | **Broken.** Newest snapshot on the target is `zrepl_20260619_004000_000`; every run fails with "No incremental base on dataset 'polina1' and replication from scratch is not allowed" |
| **zrepl → `pi4`** | `polina1` on `polina` → `book6tb/mirror` on `pi4` (offsite) | nightly 02:00, 02:20, 02:40 | replication cursor `polina1#zrepl_CURSOR_*`; a healthchecks.io hook exists in Salt but is commented out (and is on the snapshot step, not on replication) | **No** | **Broken since 2025-11-15**: cursor from that day, client certificate expired 2025-11-15 ([#1905](https://github.com/isejalabs/homelab/issues/1905)); since 2026-11-06 also `dial tcp 10.7.19.24:12618: i/o timeout` (see `pi4` below) |
| **borgmatic, Proxmox hosts** | `/root /etc /usr/local` of `pve1`, `pve4`, `pve5`, `pve6` → `baksrv` and `pi4` | daily 22:10 + up to 30 min random delay | healthchecks.io (start, log, success or `/fail`); Checkmk `Job borgbackup` (`mk-job`, exit code only, no age levels) | **healthchecks.io yes** (if its channel is read); Checkmk CRIT without notification | **Failing** on all four since 2026-10-24/26: `baksrv` succeeds, `pi4` fails (`Permission denied` on `/mnt/book6tb/...` until 2026-10-29, then `No route to host`/timeout) |
| **borgmatic, `pi4`** | `pi4` itself → its own repository | daily 22:10 | as above | as above | Failing since 2026-10-24 (exit 1) |
| **borgmatic, `fiona`** | `/mnt/natascha1/data`, `/mnt/fiona1/data` → `baksrv` (`11_local_…`) and `pi4` (`21_remote_…`) | daily 23:00 (TrueNAS app `borgmatic`) | healthchecks.io per configuration | healthchecks.io yes; **Checkmk: no** | `pi4` configuration failing (same cause) |
| **TrueNAS snapshots** | `natascha1/data` local snapshots | hourly 05:00–23:59 (keep 2 d), daily (2 w), weekly (8 w), monthly (12 m) | TrueNAS snapshot task state | TrueNAS mail only | OK (`FINISHED`) |
| **TrueNAS Cloud Sync** | OneDrive (personal) → `/mnt/natascha1/data/srv/sync/onedrive/sebi` | daily 22:00 | TrueNAS job state and `CloudSyncTaskFailed` alert | TrueNAS mail only | OK, last success 2026-11-09 |
| **rclone OneDrive, `sybille`** | `Job rclone-onedrive-sebi` | unknown | Checkmk `Job rclone-onedrive-sebi`, exit code only | no | last run 27 days ago; `sybille` is DOWN. Likely replaced by the Cloud Sync task above, to be confirmed |

### Not backups any more

Checkmk still shows `mk-job` results that have not run for years and are OK only because the `Job` check has no age levels: `polina` `Job sync-datastore` (3 years), `pve5` `Job vzdump` (4 years), `baksrv` `Job dirvish` (6 years) and `Job trigger_backup_potter` (5 years). Their status files under `/var/lib/check_mk_agent/job/root/` can be deleted; the services then vanish at the next discovery. They must go before any age rule matches them.

## Findings

1. **`pi4`, the only offsite target, has been out of service since 2026-10-24.** It rebooted that day and came back without its `book6tb` pool: every `Filesystem /mnt/book6tb…` and `Storage Pool book6tb` service went to "Item not found", which UNKNOWN keeps quiet. Borg then failed with `Permission denied` on the empty mount point. Since about 2026-10-30 the host has also been unreachable most of the time (agent "No route to host"; host check flapping several times a day since 2026-11-04, DOWN since 2026-11-09 07:57). Everything that goes offsite (zrepl and the `pi4` half of every borgmatic run) stops there. This needs someone at the `pi4` site.
2. **zrepl to `pi4` has been broken for almost a year** for the certificate reason in [#1905](https://github.com/isejalabs/homelab/issues/1905); fixing the certificates alone will not help until finding 1 is fixed.
3. **The local PBS mirror on `fiona` has been stale since 2026-06-19** and was not on any list. Its naming schema includes `zrepl_%Y%m%d_%H%M%S_000`, so it rides on zrepl's snapshots. zrepl keeps only unreplicated snapshots plus a short grid on `polina` (and [#1906](https://github.com/isejalabs/homelab/issues/1906) destroyed the old ones), so the common base snapshot is gone, and TrueNAS refuses to start from scratch. Repairing it means either allowing a full resend (about 635 GiB already on the target, 704 GiB allocated in `polina1`) or giving the task its own snapshots on `polina` that zrepl's pruning does not touch.
4. **Checkmk has the data for host-side jobs but no freshness rule.** The `Job` check (`checkgroup_parameters:job`) takes `{"age": (warn, crit)}` and none is set, so a borgmatic or vzdump run that stops entirely stays green forever.
5. **Nothing watches TrueNAS's own backup tasks from Checkmk.** `fiona` is monitored with the plain agent over SSH (`/root/bin/check_mk_agent`, no local checks) and through Proxmox piggyback; replication, Cloud Sync and the borgmatic app are only visible in TrueNAS's alerts, which go to mail and an SNMP trap.

## Planned checks

One check per path without a signal. Thresholds follow the schedule: WARN once one run is missed, CRIT once the second one is late. Where a path already pings healthchecks.io, the Checkmk service is added anyway, because Checkmk keeps the history and becomes the notification owner (D1 of the plan).

| Path | Check | Where it lives | WARN / CRIT | Notes |
| --- | --- | --- | --- | --- |
| borgmatic (Proxmox hosts, `pi4`) | `Job borgbackup` age rule | Checkmk rule `checkgroup_parameters:job`, items `borgbackup` and `vzdump_.*` | 26 h / 50 h | Same levels as `Proxmox VE VM Backup Status`. Only after the dead job files above are removed. |
| zrepl → `pi4` | local check `zrepl backup_push`: age of the newest replication cursor on `polina1` | Salt, `apps.backup.zrepl.backup-push` ships it to `polina` | 26 h / 50 h | `zfs list -Hp -t bookmark -o name,creation polina1`, picks `zrepl_CURSOR_*_J_backup_push`. Also reports the count of unreplicated `zrepl_*` snapshots, the space problem of [#1847](https://github.com/isejalabs/homelab/issues/1847). |
| zrepl certificates | local check `zrepl certificate <cn>` on `polina` and `pi4` | Salt, same states | 30 d / 7 d before `notAfter` | The certificate that broke zrepl in 2025 would have warned a month ahead. |
| kopiur (`prod`, `qa`, `dev`) | one service per `SnapshotSchedule`: age of the newest `Succeeded` `Snapshot`, plus `consecutiveFailures` | special agent in [`isejalabs/checkmk-modules`](https://github.com/isejalabs/checkmk-modules) reading the kopiur CRDs through the Kubernetes API with a read-only ServiceAccount, same pattern as D10 for `longhorn_capacity` | 26 h / 50 h; any failure WARN, 2 CRIT | The controller metric is per policy, not per schedule, and needs a scrape path that does not exist; the CRDs are already readable. |
| TrueNAS replication, Cloud Sync, borgmatic app | one service per task: state and age of the last successful run | special agent or `fiona` local check reading `midclt` (`replication.query`, `cloudsync.query`) | 26 h / 50 h | Where it lives is an open question (TrueNAS root filesystem is read-only and rewritten on update). |
| Longhorn `hourly-snapshot` | age of the newest snapshot per volume | same special agent as kopiur, or stream E's Longhorn failure modes | 2 h / 4 h | Local rollback only, lowest priority. |

## Open questions

- Does the healthchecks.io account notify a channel the owner reads? borgmatic has sent `/fail` every night since 2026-10-24.
- Is `rclone-onedrive-sebi` on `sybille` retired in favour of the TrueNAS Cloud Sync task?
- PBS mirror on `fiona`: full resend, or own snapshots on `polina` (finding 3)?
- Where the TrueNAS check runs (finding 5).
