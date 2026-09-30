# Phase 0 findings — TrueNAS/RustFS and Longhorn/Talos (read-only)

**Origin:** produced by Claude (Anthropic's Claude Code), via read-only SSH/`midclt`/`kubectl` commands against live infrastructure — not manually authored by the repository owner. Part of [issue #1437](https://github.com/isejalabs/homelab/issues/1437). Gathered via read-only SSH/`midclt`/`zfs`/`docker inspect` commands on the TrueNAS host and read-only `kubectl get` against `prod`/`dev` clusters. No configuration, workload, or state was changed. Raw command output containing credentials (an active OneDrive OAuth client secret/token from `cloudsync.query`) was deliberately excluded from this file — noted only as "present", never reproduced.

## Correcting the assessment: TrueNAS hostname

The assessment's "`natascha1/gamma/srv/rustfs`" is a **ZFS path, not a hostname** — `natascha1` is a zpool name. The actual TrueNAS host is **`fiona.home.iseja.net`** (confirmed via `ssh root@fiona.home.iseja.net` → `hostname` = `fiona`, `/etc/version` = `TrueNAS-25.10.0`), also independently confirmed as the RustFS S3 endpoint referenced by Longhorn's `backuptargets.longhorn.io` credential secrets (`https://fiona.home.iseja.net:9000`) in both `prod-homelab` and `dev-homelab` clusters.

A DNS name `natascha.home.iseja.net` (10.7.5.114) also exists but is unreachable from this workstation, `monitoring2`, and all three `pve` hosts. **Resolved via owner feedback**: this is the old, superseded predecessor host that `fiona` replaced — `fiona` inherited the `natascha1` zpool name from it, which is what caused this investigation to initially misread the assessment's `natascha1/gamma/srv/rustfs` ZFS path as a possible hostname reference in the first place. Not a live host to pursue further.

## TrueNAS (fiona.home.iseja.net)

- Version: `TrueNAS-25.10.0` (matches assessment's "25.10").
- Zpools: `boot-pool` (15G), `fiona1` (228G, 24.3G used), `natascha1` (5.45T, 3.93T used / 1.40T free, 29% frag).
- Apps (TrueNAS "apps" = Docker containers), via `midclt call app.query`:
  - `rustfs` — `rustfs/rustfs:1.0.0-beta.12` (app chart version `1.1.30`), container `ix-rustfs-rustfs-1`, up 3 weeks, healthy. Ports `9000` (S3 API, published), `9002` (console, published), `9001` (internal, not published).
  - `syncthing` — `2.1.3` (chart `1.3.12`), running; an upgrade is flagged available (`upgrade_available: true`, latest `1.3.13`) — inventory note only, not a recommendation to upgrade now.
  - `borgmatic` — `1.2.13` (chart `1.2.14`), running.
- No `rsynctask.query` entries (empty) — rsync is not used for backup here.
- One Cloud Sync task (`cloudsync.query`): OneDrive personal, path `/mnt/natascha1/data/srv/sync/onedrive/sebi`, daily at 22:00, excludes `/Persönlicher Tresor/`. Credentials/tokens present in the live config (not reproduced here — see caution above). No AD sync job was found configured in `cloudsync`/`rsynctask` — **resolved via owner feedback**: Active Directory itself runs on the UCS domain controllers `adelheid.dir.iseja.net`/`baerbel.dir.iseja.net`, not on TrueNAS. What TrueNAS has instead is its own native AD *join* (SCALE directory services) — confirmed live and healthy: `midclt call directoryservices.status` → `{"type": "ACTIVEDIRECTORY", "status": "HEALTHY"}`, `directoryservices.config` shows computer account `FIONA$@DIR.ISEJA.NET`, realm `DIR.ISEJA.NET`, idmap backend `AD`/RFC2307. This is an ongoing domain-join/idmap integration, not a scheduled sync job — which is why it never showed up in `cloudsync`/`rsynctask`. For phase 2's source rollout, "AD synchronization failures" should target the UCS DCs primarily, with TrueNAS's own directory-service health as a secondary signal.
- `borgmatic` container mounts `/mnt/fiona1/data` and `/mnt/natascha1/data` (not `gamma`, so RustFS itself is **not** in the borg backup scope) plus persistent `~/.borgmatic`, `~/.config/borg`, `~/.ssh`, `~/.cache/borg`, `/var/log` under `fiona1/data/srv/docker/borgmatic/data/`. Its SSH key (mounted, not inspected) is presumably how it reaches the borgbackup server — salt's `top.sls` assigns `roles.backup.borgbackup.server` to `pi4.dir.iseja.net`, consistent but **not independently confirmed** (didn't SSH to pi4 or inspect borgmatic's actual repository target).
- **Syncthing folder config, resolved (2026-09-30)**: the earlier empty result was the wrong container name — correct one is `ix-syncthing-syncthing-1`. Its `config.xml` has (at least) four active `sendreceive` folders, all under `/mnt/natascha1/data/media/`: `Lightroom-Data` (Lightroom catalog/DB, hourly rescan), `media-Pictures-Sync`, `media-Pictures-orig`, `media-Videos-orig` (daily rescan), syncing to one paired remote device. One additional folder entry in the config is unlabeled/empty (id and path both blank) — likely a leftover/disabled entry, not investigated further.

## RustFS buckets and quota

Dataset `natascha1/gamma/srv/rustfs`: **quota 100G, used 7.30G, 92.7G available** (`zfs get quota,refquota,used,available`). Directory listing of the RustFS data root (`/mnt/natascha1/gamma/srv/rustfs/`) shows 12 buckets, confirming and refining the assessment's "eight kopiur buckets, four active":

| Bucket | Type | Object count (raw dir entries) | Active? |
| --- | --- | --- | --- |
| `dev-kopiur-backup` | kopiur | 918 | yes |
| `prod-kopiur-backup` | kopiur | 1125 | yes |
| `qa-kopiur-backup` | kopiur | 1144 | yes |
| `rebuild-kopiur-backup` | kopiur | 483 | yes |
| `dbg-kopiur-backup` | kopiur | 0 (empty) | no |
| `head-kopiur-backup` | kopiur | 0 (empty) | no |
| `poc-kopiur-backup` | kopiur | 0 (empty) | no |
| `src-kopiur-backup` | kopiur | 0 (empty) | no |
| `dev-longhorn-backup` | Longhorn (separate!) | 2 | minimal |
| `prod-longhorn-backup` | Longhorn (separate!) | 1 | minimal |
| `qa-longhorn-backup` | Longhorn (separate!) | 1 | minimal |
| `rebuild-longhorn-backup` | Longhorn (separate!) | 1 | minimal |

The **8 kopiur buckets exactly match** the assessment (one per environment: `dbg/dev/head/poc/prod/qa/rebuild/src`), 4 active matches exactly. The 4 `*-longhorn-backup` buckets are a **separate, previously-unmentioned bucket family** — Longhorn's own native S3 backup target (`backuptargets.longhorn.io`, confirmed live in both `prod-homelab` and `dev-homelab`), distinct from kopiur's buckets, currently holding almost nothing (Longhorn `RecurringJob`s exist and run — see below — but backup content is minimal so far). Object counts above are raw directory-listing counts (include RustFS-internal per-object metadata dirs), not authoritative logical-byte accounting — the plan's own "prefer server-side accounting over listings" caveat applies; did not query RustFS's own admin/S3 API for exact accounting.

Did not attempt to reach RustFS's S3 admin API for exact per-bucket quotas/logical bytes (would need RustFS admin credentials, which weren't extracted — out of scope for this pass to avoid handling secrets unnecessarily).

## Longhorn / Talos (prod-homelab, dev-homelab contexts — kubectl already configured on this workstation)

- `prod-homelab`: 6 Talos v1.12.6 nodes (3 control-plane, 3 worker), Kubernetes v1.34.6, `containerd://2.1.6`. Only the 3 worker nodes are `nodes.longhorn.io` (control-plane nodes don't run Longhorn), each with one disk `default-disk-082000000000` at `/var/mnt/longhorn`:

  | Node | Max | Available | Scheduled |
  | --- | --- | --- | --- |
  | prod-work-01 | 32,145,145,856 (~30 GiB) | 29,360,128,000 (~27.3 GiB) | 7,713,325,056 (~7.2 GiB) |
  | prod-work-02 | 32,145,145,856 | 31,037,849,600 (~28.9 GiB) | 4,930,404,352 (~4.6 GiB) |
  | prod-work-03 | 32,145,145,856 | 29,674,700,800 (~27.6 GiB) | 2,917,138,432 (~2.7 GiB) |

  All three nodes: `AllowScheduling=true`, `Schedulable=true`, disk `storageReserved=0`.

- Longhorn `BackupTarget` (CRD `backuptargets.longhorn.io`, not the older `Setting` object — the plan/assessment's mental model of a `backup-target` *Setting* is outdated for this Longhorn version; it's now its own CRD):
  - `prod-homelab`: `s3://prod-longhorn-backup@local/default`, `available: true`, last synced 2026-09-29T08:13:48Z, poll interval 5m.
  - `dev-homelab`: `s3://dev-longhorn-backup@local/default`.
  - Both resolve (via `longhorn-minio-credentials` secret's `AWS_ENDPOINTS`) to `https://fiona.home.iseja.net:9000` — i.e., RustFS is already wired as Longhorn's backup target for at least these two environments.
- `RecurringJob`s (prod): `hourly-snapshot` (retain 24, every hour), `daily-backup` (retain 7, 04:30 daily), `weekly-backup` (retain 4, Sun 04:04), `monthly-backup` (retain 6, 1st @ 04:12), `weekly-trim` (Sat 04:07, retain 0). All target group `default`.
- **`qa-homelab`/`rebuild-homelab`/`dbg-homelab` Longhorn state, checked (2026-09-30)**:
  - `rebuild-homelab`: clean — all 4 nodes Ready, `BackupTarget` `s3://rebuild-longhorn-backup@local/default` available, all five `RecurringJob`s present (same hourly/daily/weekly/monthly/trim schedule as prod).
  - `qa-homelab`: **`qa-work-03.test.iseja.net` was found `NotReady` since 2026-09-25** ("kubelet stopped posting node status") during the same-day review of [PR #1458](https://github.com/isejalabs/homelab/pull/1458) (Longhorn 1.13.0 bump). Its stuck old-version `longhorn-manager` pod caused 1.13.0's startup safety check to crash-loop indefinitely on the *new* manager pods on the other two nodes. `qa`'s `BackupTarget` (`s3://qa-longhorn-backup@local/default`) and `RecurringJob`s were otherwise present and matched the standard schedule throughout.

    **Active remediation performed 2026-09-30, at the owner's explicit request** ("let's get qa healthy before we approach prod") — this goes beyond phase 0's original read-only scope, noted explicitly here:
    1. `just proxmox vm list -e qa` showed VMID `7008126` (qa-work-03) as **`stopped`**, not hung — it had simply been powered off since 2026-09-25, for a reason not investigated.
    2. `kubectl -n longhorn-system delete pod longhorn-manager-pkzld --grace-period=0 --force` cleared the stuck pod; the crash loop on qa-work-01/02's managers stopped immediately (restart count held steady afterward).
    3. `just proxmox vm start -e qa --vmid 7008126` (the repo's own Proxmox-API-backed `just` module, not direct SSH, per the owner's steer) brought the VM back up; Talos rejoined and the node went `Ready` within about a minute.
    4. A third `longhorn-manager` pod scheduled onto qa-work-03 automatically, took ~7 minutes to reach `2/2 Running` (cold-start image pulls after 5 days off — benign), and has been stable (0 restarts) since.

    **Remaining, separate problem — not caused by this remediation**: qa-work-03's Longhorn disk still won't come back into service. `kubectl -n longhorn-system get nodes.longhorn.io qa-work-03.test.iseja.net -o yaml` shows disk condition `DiskFilesystemChanged: "record diskUUID doesn't match the one on the disk"`, with `lastTransitionTime: 2026-09-19T11:13:19Z` — **six days before** the node even went NotReady. This predates the outage and may well be its underlying cause rather than a consequence of it. Fixing it means either removing and re-adding the disk in Longhorn (triggering a replica rebuild from qa-work-01/02) or first investigating what changed on the 19th — both bigger, more invasive steps than restarting a stopped VM, so this was left for the owner to decide rather than acted on unilaterally. **`qa` is healthy at the node/Kubernetes/Longhorn-manager level, but not yet at the Longhorn-disk level.**
  - `dbg-homelab`: **cluster entirely unreachable** (kubectl times out even listing nodes) — consistent with `dbg`'s Flux set including only `minimal` (no `optional`/Longhorn) per `k8s/bootstrap/cluster/flux/envs/dbg/kustomization.yaml`, and with `dbg` being an on-demand/rarely-powered environment. Nothing to check here; treat as N/A rather than a gap.
- Talos node/collector access for the *logging* pilot (phase 1B's log-collector permissions, not this phase's storage check) was **not tested** — out of scope for Phase 0's storage/capacity inventory but flagged since the plan bundles "Talos collector mounts/permissions" under the same validation-required list.

## Version/compatibility comparison (2026-09-30 follow-up: partial)

- TrueNAS 25.10.0 is the installed version. Attempted to fetch TrueNAS's own SCALE 25.10.x release notes via WebFetch — **inconclusive**: `truenas.com`'s release-notes pages are JS-rendered and didn't return usable static content, and `truenas/middleware` on GitHub doesn't publish point releases there. This remains an open gap requiring either checking TrueNAS's UI update page directly (Settings → Update, which lists point releases and their changelogs) or a different research approach — not resolved by WebFetch from this session.
- RustFS: confirmed a newer `1.0.1-preview.6`–`1.0.1-preview.11` series exists beyond the installed `1.0.0-beta.12` (progressed past "beta" naming), with storage/ecstore stability fixes, replication-convergence improvements, and S3 permission-enforcement hardening. **[rustfs/rustfs#5716](https://github.com/rustfs/rustfs/issues/5716)'s quota-enabled-write-failure report has no confirmed fix** in the visible preview changelogs — don't assume it's resolved; would need to check the actual issue thread or test directly against a preview build before relying on it.
- RustFS is pinned to `1.0.0-beta.12` via the TrueNAS app catalog (chart `1.1.30`); an in-place upgrade would go through TrueNAS's app-update flow, not a manual container swap — relevant if/when an upgrade is decided.

## Access gaps / things NOT verified

- RustFS S3 admin API not queried directly (no credentials pulled) — bucket quotas/logical-byte accounting above is inferred from ZFS + raw directory listing, not RustFS's own accounting interface. Phase 1A will need this properly.
- borgmatic's actual backup target (expected: `pi4.dir.iseja.net` per Salt `top.sls`) — deliberately not pursued; backup infrastructure is a separate topic the owner will address on its own in the coming days, out of scope for this observability pass.
- TrueNAS SCALE point-release changelog comparison — see above, needs a different research approach than WebFetch.
- Checkmk's own live check config for `natascha1/gamma/srv/rustfs` (thresholds, trend/forecast settings) not cross-checked against this ZFS data — that's covered by a separate, parallel Checkmk-focused investigation track.
