---
status: planning
---

# Immich media storage on `fiona`

The media of [Immich](../../k8s/apps/media/immich/README.md) stay on the NAS `fiona` (TrueNAS 25.10) and reach the clusters over NFS. This page is the exact TrueNAS configuration for it: datasets, permissions, NFS exports, SMB shares for the Mac, snapshots, quotas and the borgbackup. The TrueNAS side is manual, so this is the one place that states it. The cluster side (static NFS `PersistentVolume`s and claims, no CSI driver) is in the [`immich` unit](../../k8s/apps/media/immich/README.md).

Why it is built this way is decided in [ADR 0018](../decisions/0018-media-source-of-truth.md) (Immich owns phone media, Lightroom Classic owns the existing library, which Immich reads read-only). The work is tracked in [#2144](https://github.com/isejalabs/homelab/issues/2144), part of [#413](https://github.com/isejalabs/homelab/issues/413). The status is `planning` until the owner has created the datasets and the [verification](#verify) has passed; then it becomes `current`.

## At a glance

| Row | Content |
| --- | --- |
| When to use | Creating, changing or checking the storage of Immich on `fiona`: a new environment, a replaced worker node (the export clients change), a quota or snapshot change. Not for the Immich database: it never goes on NFS, it stays on Longhorn ([#2145](https://github.com/isejalabs/homelab/issues/2145)) |
| Prerequisites | Admin access to the TrueNAS UI or shell on `fiona`; the [open owner inputs](#open-owner-inputs) answered; for the checks, `kubectl` with the context of the environment |
| Steps | [Datasets](#datasets), [permissions](#users-and-permissions), [NFS](#nfs), [SMB](#smb-for-the-mac), [snapshots](#snapshots), [quotas](#quotas-and-capacity), [borgbackup](#borgbackup), [copies of the library](#copies-of-the-library-for-non-prod) |
| Verify | [Verify](#verify): a pod mounts upload and cache read-write and library and export read-only, a deleted file comes back from a snapshot, a file comes back from the off-site borg repository |
| Rollback | Disable the NFS share (nothing mounts it any more) or destroy a non-prod dataset. A prod dataset is never destroyed by this procedure; the claims use `Retain`, so deleting Kubernetes objects leaves the data. No other rollback is documented |
| State | 2026-11-18: the clones, the `upload`/`cache` datasets and the NFS shares for `dev` are created by the owner; `qa`, `rebuild` and `prod` follow. Nothing is verified from a pod yet |
| Last exercised | Not exercised yet. The values were derived from the repository, the Immich documentation and the [September 2026 TrueNAS audit](../audits/2026-09-observability-phase0-truenas-k8s-claude.md); anything marked *verify* has to be confirmed on `fiona` |

## Design in short

- Immich needs a POSIX filesystem with owners and permissions for its own data, and reads the Lightroom library and the export tree (JPEG renditions of edited RAWs) as two external libraries. All of it is on `fiona`; Longhorn disks of the workers are 30 GB at most.
- Four volumes per environment, so snapshot, quota, backup and export rules can differ:

  | Volume | Mode in Immich | Holds | Snapshots | Borgbackup |
  | --- | --- | --- | --- | --- |
  | `upload` | read-write | originals of phone uploads (`upload/`, `library/`, `profile/`), Immich's own database dumps (`backups/`) | yes | yes, `prod` only |
  | `cache` | read-write | thumbnails and encoded video (regenerable) | no | no |
  | `library` | **read-only** | the Lightroom Classic library (the folder `Pictures/orig`), `YEAR/MONTH/DAY-Title` | the owner's existing rules | already part of the `fiona` backup |
  | `export` | **read-only** | JPEG renditions of edited RAWs, same folder layout, written by Lightroom Classic from the Mac | the owner's existing rules | already part of the `fiona` backup |

- A read-only external library means Immich can neither delete nor rewrite an original: a delete in Immich comes back after the trash is emptied, and metadata edits are not possible (see [ADR 0018](../decisions/0018-media-source-of-truth.md#what-immich-does-with-a-library)). A writable mount would let Immich delete the original when the trash is emptied. So the library is read-only on three levels: the NFS share, the `ro` mount option and `nfs.readOnly` in the `PersistentVolume`.
- Non-prod environments only ever see **copies** of the library (ZFS clones, see [below](#copies-of-the-library-for-non-prod)), never the live library, and no non-prod environment can reach `prod` data: every export lists only the worker nodes of one environment.
- Two pools carry the data: the important data (`prod` upload, the live library and its export) is on `natascha1`, everything of less value (all non-prod upload and cache, and the `prod` cache) on `fiona2`. The copies of the library have to be on `natascha1`, because a ZFS clone lives in the pool of its origin.
- Read-only is enforced by the NFS share options (and, as a second and third level, the `ro` mount option and `nfs.readOnly`), **not** by filesystem permissions: the group that Immich's account belongs to has write access on the whole `natascha1/data/media` dataset, so the library and export folders are writable on the filesystem level. A path to these folders that is not the read-only share would be a path with write access.
- The database never goes on NFS ([Immich requirements](https://docs.immich.app/install/requirements)).

## Datasets

The NFS export of a dataset or folder is always its mount path `/mnt/<dataset>`: `natascha1/data/srv/immich` is shared as `/mnt/natascha1/data/srv/immich`. The `PersistentVolume`s carry exactly these paths ([`envs/<env>/kustomization.yaml`](../../k8s/apps/media/immich/envs)); change both together.

| Volume | Dataset | Environments |
| --- | --- | --- |
| `upload` | `natascha1/data/srv/immich` (`prod`), `fiona2/gamma/srv/immich/<env>/upload` (directory of the dataset `fiona2/gamma/srv/immich/<env>`) | `dev`, `qa`, `rebuild`, `prod` |
| `cache` | `fiona2/gamma/srv/immich/<env>/cache` (directory of the same dataset) | `dev`, `qa`, `rebuild`, `prod` |
| `library` (`pictures`) | `natascha1/gamma/srv/immich-copy/<env>/Pictures/orig` | `dev`, `qa`, `rebuild`: **copies** |
| non-prod `export` (renditions) | `natascha1/gamma/srv/immich-copy/<env>/Pictures/export` | `dev`, `qa`, `rebuild`: **copies** |
| `prod` `library` | the existing Lightroom library, the folder `natascha1/data/media/Pictures/orig` | `prod`: the live library, exported only |
| `prod` `export` | the folder `natascha1/data/media/Pictures/export` | `prod`: written from the Mac, exported read-only |
| videos-only library | `natascha1/data/media/Videos/` | postponed, not part of the proof of concept yet |
| renditions of the videos-only library | | postponed, not part of the proof of concept yet |

Notes on the table:

- **`upload` and `cache`** are directories of one dataset per environment, `fiona2/gamma/srv/immich/<env>`, not datasets of their own. So snapshots and a quota apply to the two together (the cache is regenerable and is snapshotted along, which only costs space). The `prod` `upload` path is `natascha1/data/srv/immich`, a child of `natascha1/data` on purpose: it is then inside the tree the existing backup already covers, see [borgbackup](#borgbackup); whether it is a dataset of its own or a folder decides whether it gets its own snapshot rule (*verify*, see [snapshots](#snapshots)).
- **`Pictures/orig` and `Pictures/export` of the copies** are *folders* of a cloned dataset (the clone mirrors `natascha1/data/media`: `Music`, `Pictures`, `Videos`, `clipart`, `fonts`), see [Copies of the library](#copies-of-the-library-for-non-prod). On the live side the `prod` library and the `prod` export are folders of the dataset `natascha1/data/media` as well, not datasets of their own, and the NFS shares are made on these folders.
- The copies sit in their own hierarchy, `immich-copy`, apart from `immich`, so that a clone can be thrown away and made again without touching the `upload` and `cache` data of the same environment.

Created for `dev` and `qa` by the owner on 2026-11-18, the same commands apply to `rebuild` and `prod` (for `prod` only the `cache` directory, the `upload` path is the one in the table):

```sh
zfs create fiona2/gamma/srv/immich/dev
zfs create fiona2/gamma/srv/immich/qa
mkdir -p /mnt/fiona2/gamma/srv/immich/dev/upload /mnt/fiona2/gamma/srv/immich/dev/cache
mkdir -p /mnt/fiona2/gamma/srv/immich/qa/upload /mnt/fiona2/gamma/srv/immich/qa/cache
chown -R immich:fs.media-rw /mnt/fiona2/gamma/srv/immich/
```

Dataset properties for the new datasets (`fiona2/gamma/srv/immich/<env>`): `compression=lz4` (photos hardly compress, but it costs nothing), `recordsize=1M` (large files), `atime=off`, `sync=standard`, `copies=1`. ACL type: see [permissions](#users-and-permissions). Do not enable deduplication.

How Immich uses its volume, for the [Immich unit](../../k8s/apps/media/immich/README.md): the upload volume is `/data` (`IMMICH_MEDIA_LOCATION`, the default), the cache volume is mounted into it with `subPath: thumbs` and `subPath: encoded-video`, so Immich sees its usual folder layout while the regenerable parts live on a dataset of their own. Immich checks each of its folders for a hidden `.immich` file and reports a missing mount ([system integrity](https://docs.immich.app/administration/system-integrity)), so a volume that fails to mount is noticed, not silently replaced by an empty folder. The mount points of the two external libraries, and the import paths set in Immich for them, must stay the same for good: Immich stores the path of every asset, and a moved path is a deleted asset plus a new one (ADR 0018, rule 3).

## Users and permissions

The account `immich` is a central one (UCS user management), with **UID `10004`**; the Immich pods run with the same user ID, see the [unit README](../../k8s/apps/media/immich/README.md#media-volumes). It has no shell. Access to the media runs through the ACL group **`fs.media-rw`**, which the account is a member of.

- `upload` and `cache`: owner `immich:fs.media-rw`, set with `chown -R` as in the [datasets](#datasets) section. With the recommended NFS option **Mapall user `immich`, group `fs.media-rw`** every client is mapped to `immich`, so it does not matter which user ID a container runs as, and files on `fiona` are always owned by `immich`. Without it, the pods have to run as that user.
- `library` and `export`: they are folders of the dataset `natascha1/data/media`, and the group `fs.media-rw` grants **write** access on that whole dataset. So `immich` can read them through the group, but there is no read-only on the filesystem level: the **NFS share option read-only** (plus the `ro` mount option and `nfs.readOnly` in the `PersistentVolume`) is what keeps Immich from changing them. The Mac keeps writing the `prod` export as its own user. TrueNAS 25.10 reports ignored group entries for Mapall users, see [this forum thread](https://forums.truenas.com/t/nfsv4-acl-group-based-permissions-not-honored-for-mapall-user-nfs-exports-on-scale/68097) (*verify*; the read check in [Verify](#verify) decides).
- ACL type: a thread on 25.10 reports ownership problems on datasets with the `SMB/NFSv4` ACL type ([forum](https://forums.truenas.com/t/permissions-for-user-group-from-nfsv4-acls-are-ignored-when-mounting-shares-via-nfsv4/64362)); the new `fiona2` datasets are plain ZFS datasets with the default ACL type. If the read-only SMB share of the `prod` upload path (see [SMB](#smb-for-the-mac)) does not work, use the `SMB/NFSv4` type and a named-user entry for `immich`, and re-run the write check. The existing datasets keep their ACL type.

## NFS

Services → NFS: enable **NFSv4** (NFSv3 is not needed). Talos mounts NFS from its kubelet image, so no system extension is required ([Talos storage guide](https://docs.siderolabs.com/kubernetes-guides/csi/storage): "The NFS client is part of the kubelet image maintained by the Talos team"); NFSv4 does not use the separate lock daemon that NFSv3 needs (*verify* on the first mount). The `PersistentVolume`s mount with `nfsvers=4.1,hard,noatime,nconnect=4`: `hard` so that a NAS outage stalls the pod instead of returning I/O errors to Immich in the middle of a write, `nconnect=4` for parallel connections (*verify* that the node kernel accepts it; drop it if the mount fails). The server name in the volumes is `fiona.home.iseja.net`, which the nodes have to resolve through their DNS (*verify*).

One share per path in the [datasets table](#datasets), Shares → NFS → Add, path `/mnt/<dataset>` (for the library and the export the folder `Pictures/orig` or `Pictures/export`, inside the cloned dataset for the copies). Settings that are the same for every share: **Security `SYS`**, **Maproot** empty, **Mapall user `immich` and group `fs.media-rw`** (recommended; the `dev` and `qa` shares as created have no mapping yet, see [open owner inputs](#open-owner-inputs)), share enabled. The clients are listed as **Hosts**, never as a whole network: an export lists exactly the worker nodes of one environment (a pod only ever runs on a worker, and the kubelet of that node does the mount).

| Environment | Hosts (worker nodes) | `upload`, `cache` | `library`, `export` |
| --- | --- | --- | --- |
| `dev` | `10.7.8.134`, `10.7.8.135`, `10.7.8.136` | read-write | **Read-only** (shares created 2026-11-18) |
| `qa` | `10.7.8.124`, `10.7.8.125`, `10.7.8.126` | read-write | **Read-only** |
| `rebuild` | `10.7.8.174`, `10.7.8.175`, `10.7.8.176` | read-write | **Read-only** |
| `prod` | `10.7.8.184`, `10.7.8.185`, `10.7.8.186` | read-write | **Read-only** |

The addresses come from the Terragrunt units (`ip` of each `machine_type = "worker"` node in `terragrunt/<tier>/eu-central-1/<env>/vehagn-k8s/terragrunt.hcl`); the scheme is described in [`reference/environments.md`](../reference/environments.md#environment-id). **When a worker is added, replaced or renumbered, change the Hosts of that environment's four shares**, otherwise the pod on the new node cannot mount. List the current addresses:

```sh
awk '/^[[:space:]]*#/ {next} /machine_type/ {t=$3} /^[[:space:]]*ip[[:space:]]*=/ && t ~ /worker/ {print $3}' terragrunt/non-prod/eu-central-1/dev/vehagn-k8s/terragrunt.hcl
```

The live `prod` library and export are exported **read-only to the `prod` workers only**. The `qa`, `dev` and `rebuild` shares point at the copies, so no non-prod cluster has any path to the live library or to `prod` upload data. If the live library already has an NFS share, check that the new share of the `orig` folder is accepted next to it (TrueNAS may warn about shares of nested paths; *verify*).

Network: TCP 2049 has to pass from the node VLAN to `fiona`. Kopiur already reaches `fiona` on port 9000 from the pods; NFS is a separate rule on the gateway if that VLAN is filtered (*verify*, the mount in the [test pod](#verify) shows it).

## SMB for the Mac

- **`prod` upload, read-only:** an SMB share `immich-upload` on `natascha1/data/srv/immich` with **Read Only** enabled and access for the Mac's own account only, for the rare edit of a phone photo in Lightroom Classic (the edited copy goes back to Immich through the plugin, never into this share). The Mac reads as "other", so mode `0755`/`0644` is enough. Check that no existing share of `natascha1/data` already covers this path with write access.
- **`prod` export, read-write for the Mac:** the Lightroom Classic publish service writes the renditions from the Mac. The protocol the Mac uses for the library today decides how this share is made, see [open owner inputs](#open-owner-inputs); SMB is assumed here. It is a share of the folder `natascha1/data/media/export` with write access for the Mac's account only. The NFS export of the same dataset stays read-only.
- The live library: no change. Whatever the Mac uses today stays; the NFS exports above do not touch it.

## Snapshots

Data Protection → Periodic Snapshot Tasks. Snapshots are the undo for an accidental or Immich-made delete of an original. A task per row, **not recursive** (every dataset has its own rule), naming schema as given so that two tasks on one dataset do not expire each other's snapshots:

| Dataset | Schedule | Keep | Naming schema |
| --- | --- | --- | --- |
| `prod` upload (`natascha1/data/srv/immich`) | hourly | 2 days | `auto-hourly-%Y%m%d-%H%M` |
| `prod` upload | daily | 30 days | `auto-daily-%Y%m%d-%H%M` |
| `prod` library and export (the dataset `natascha1/data/media`) | hourly / daily | 2 days / 30 days, unless the owner's existing tasks already cover it | same two schemas |
| `qa` (the dataset `fiona2/gamma/srv/immich/qa`, upload and cache) | daily | 7 days | `auto-daily-%Y%m%d-%H%M` |
| `dev`, `rebuild`, the clones of the library | none | | |

Before creating the `prod` tasks, look at the existing tasks of `natascha1/data` and `natascha1/data/media` (the library has its own rules today): a recursive task there may already cover `srv/immich` (*verify*), and then a second one only needs to exist if the retention is meant to differ.

The `qa` task exists so the snapshot restore can be exercised outside `prod`. The 30 days match Immich's own trash retention (30 days by default): a delete in Immich is first undone by the trash, a delete outside Immich by the snapshots. Snapshots live in the same pool, so they protect against deletion and bad upgrades, not against a pool failure; that is what the borgbackup is for.

## Quotas and capacity

A quota keeps a runaway import from filling the pool (set `quota`, which counts snapshots too, not `refquota`). Because `upload` and `cache` are directories of one dataset per environment, the quota is one value for both, set on `fiona2/gamma/srv/immich/<env>`. Proposed starting values; every one is a cap, not a reservation, and can be raised:

| Dataset | `dev` | `qa` | `rebuild` | `prod` (cache dataset) |
| --- | --- | --- | --- | --- |
| `fiona2/gamma/srv/immich/<env>` | 30 GiB | 260 GiB | 30 GiB | 10 to 20 % of library plus upload |

The `prod` upload path has its own limit (the dataset it is in, or none), sized as: expected phone uploads for the first year (4,000 to 10,000 assets a year across photos and videos, times the average size from the library inventory in [#2309](https://github.com/isejalabs/homelab/issues/2309)) plus 30 days of snapshot churn plus headroom, revisited after the [size test](https://github.com/isejalabs/homelab/issues/2147). The cache grows with library and uploads by 10 to 20 %. The clones of the library need no quota: they share their blocks with the origin. The `refquota=100G` set on the parent `natascha1/gamma/srv/immich-copy` limits only that dataset itself, not the clones below it.

> [!WARNING]
> `fiona2` has about 1.8 TB, which is ample for all non-prod data and the `prod` cache. The pool `natascha1` had **1.40 TiB free of 5.45 TiB** in the audit of 2026-09-30. It takes the `prod` upload and its snapshots, and the **origin snapshot of the clones**: while a clone exists, the snapshot `natascha1/data/media@2144_immich-clone` cannot be destroyed and pins every block of `natascha1/data/media` that is changed or deleted afterwards. Read the current free space (`zpool list natascha1 fiona2`) before creating anything, and destroy clones and the snapshot when they are not needed.

## borgbackup

The `prod` upload dataset holds originals (it is the master for phone media, not a transit copy), so it must be in the on-site and the off-site backup. The cache datasets and everything non-prod (`fiona2`, the copies on `natascha1/gamma`) are not backed up: regenerable, or copies. The live library and its export are already part of the `fiona` backup.

The audit of 2026-09-30 found `borgmatic` as a container on `fiona` with `/mnt/fiona1/data` and `/mnt/natascha1/data` mounted. `natascha1/data/srv/immich` is a child of `natascha1/data`, so it is covered if the configuration backs up that tree as a whole, and nothing has to be bind-mounted; `fiona2` and `natascha1/gamma` are not mounted, so the cache and the copies stay out. To check it, on `fiona` (*verify*, the borgmatic configuration is not in this repository):

1. The `source_directories` of the on-site **and** the off-site configuration contain a path that includes `/mnt/natascha1/data/srv/immich`, and no `exclude_patterns` entry (for example for `srv`) removes it.
2. The container sees the files of the child dataset, not an empty directory: a bind mount of a dataset path only shows its child datasets if the mount is recursive. The restore check in [Verify](#verify) proves both points.
3. Do not add `fiona2` or `natascha1/gamma` to the sources: that would pull in the cache and the copies.
4. Backup order matters for Immich: back up the database first, the files second, so that the worst case is a file the database does not know, not the reverse ([Immich backup and restore](https://docs.immich.app/administration/backup-and-restore)). Immich's own database dumps are in `upload/backups/`, so they are included; the CloudNativePG dump to RustFS ([#2145](https://github.com/isejalabs/homelab/issues/2145)) should finish before the borg run starts (*verify* the schedules once both exist).

## Copies of the library for non-prod

Non-prod environments get **ZFS clones** of the dataset `natascha1/data/media`, never the live data. A clone costs no space until it differs from its origin and is made in seconds. The cost is that a clone is the **whole dataset** (every folder in it, not only the library and its export), because the dataset is the unit of a clone, not a sub-folder. The clone has to be in the same pool as its origin, so it is on `natascha1`, not on `fiona2`. Nothing is deleted from the clones: the environments simply see the full data, read-only through the NFS share. To keep a test environment small, limit what Immich scans (the import path and the exclusion patterns of the external library in Immich, [#2146](https://github.com/isejalabs/homelab/issues/2146)), not the files on `fiona`.

Made by the owner on 2026-11-18 for `dev` and `qa`; `rebuild` gets the same, `prod` needs none:

```sh
# one origin snapshot for all clones, named so that no periodic snapshot task owns or expires it
zfs snapshot natascha1/data/media@2144_immich-clone
zfs create natascha1/gamma/srv/immich-copy
zfs set refquota=100G natascha1/gamma/srv/immich-copy
zfs clone natascha1/data/media@2144_immich-clone natascha1/gamma/srv/immich-copy/dev
zfs clone natascha1/data/media@2144_immich-clone natascha1/gamma/srv/immich-copy/qa
```

The NFS shares are folders of the clones, `/mnt/natascha1/gamma/srv/immich-copy/<env>/Pictures/orig` and `.../Pictures/export`, the same relative paths as the live ones, see [NFS](#nfs).

Re-establishing a copy: destroy the clone (`zfs destroy natascha1/gamma/srv/immich-copy/<env>`), then make a new snapshot and clone it; the old snapshot can only be destroyed when no clone uses it any more. Because the copies live apart from `fiona2/gamma/srv/immich/<env>`, this never touches the data Immich wrote in that environment. The paths in Immich stay the same, so the external libraries keep their assets.

The Lightroom catalog copy for the proof of concept stays on the Mac; it is not part of any export.

## Verify

These are the acceptance criteria of [#2144](https://github.com/isejalabs/homelab/issues/2144). Run the first on `dev` and on `qa`, the second on any environment with snapshots (`qa`), the third once for `prod`.

1. **Mounts, read-write and read-only.** With the `immich` unit applied in the environment (merged, or [`track-branch`](../../.agents/skills/track-branch/SKILL.md) on `dev`), apply the test pod and read its result:

   ```sh
   kubectl --context admin@dev-homelab apply -f k8s/test/storage/test-nfs-immich-media.yaml
   kubectl --context admin@dev-homelab -n immich logs test-nfs-immich-media
   kubectl --context admin@dev-homelab delete -f k8s/test/storage/test-nfs-immich-media.yaml
   ```

   Expected: `OK` for `upload` and `cache` writable, and for `library` and `export` both `read-only` and `readable`, and the `mount` lines show `nfs4` with `ro` on the two read-only ones. A `FAIL ... not readable` on a read-only volume means the mapped user `immich` cannot read the files: see [permissions](#users-and-permissions). A pod stuck in `ContainerCreating` is a mount problem: `kubectl describe pod` shows the NFS error (export hosts, firewall, name resolution).
2. **Restore a deleted file from a snapshot.** On `fiona`, with a `qa` snapshot task running (or a manual snapshot); the snapshot is of the dataset `fiona2/gamma/srv/immich/qa`, so the file is found below `upload/` in it:

   ```sh
   echo canary > /mnt/fiona2/gamma/srv/immich/qa/upload/snapshot-test.txt
   zfs snapshot fiona2/gamma/srv/immich/qa@manual-test
   rm /mnt/fiona2/gamma/srv/immich/qa/upload/snapshot-test.txt
   cp /mnt/fiona2/gamma/srv/immich/qa/.zfs/snapshot/manual-test/upload/snapshot-test.txt /mnt/fiona2/gamma/srv/immich/qa/upload/
   zfs destroy fiona2/gamma/srv/immich/qa@manual-test
   rm /mnt/fiona2/gamma/srv/immich/qa/upload/snapshot-test.txt
   ```

   Expected: the `cp` finds the file in the snapshot and the content is `canary`.
3. **Restore a file from the off-site borg repository.** Put a canary file in the `prod` upload dataset `natascha1/data/srv/immich` next to Immich's folders (`restore-test/<date>.txt`; Immich only uses its own folders), wait for the backup run, then extract it from the off-site repository with the installed borgmatic (`borgmatic extract --help` for the exact flags of that version) into a scratch directory, never over the live dataset:

   ```sh
   borgmatic list --repository <off-site repository> --archive latest --find restore-test
   borgmatic extract --repository <off-site repository> --archive latest --path <path of the file in the archive> --destination /tmp/borg-restore
   ```

   Expected: the extracted file equals the original. After the first real uploads, repeat it once with a real asset.

## Monitoring

`fiona` already has the Checkmk agent. Run a service discovery on the host after the datasets exist and check that the new datasets show up as filesystem services, set the usage thresholds on `prod` upload with the quota in mind, and add the quota fill level of the non-prod datasets as a warning only (*verify* what the existing ZFS dataset check on `fiona` reports, see the [RustFS capacity audit](../audits/2026-10-rustfs-capacity.md)). The RustFS quota monitoring in [`terragrunt/README.md`](../../terragrunt/README.md) is unrelated to these datasets.

## Open owner inputs

These are not guessed in the repository. The dataset layout above is the owner's decision; what is left is to confirm it against `fiona`:

1. **User mapping of the shares:** the exports of `dev` and `qa` as created (`/etc/exports`) carry `sec=sys` and `subtree_check` only, with `rw` on `upload` and `cache` and the default `ro` on the library and export, and no user mapping. The runbook recommends Mapall (user `immich`, group `fs.media-rw`); without it the user ID of the pod counts, so the pods have to run as `10004` and that user must have access through `fs.media-rw`. Decide, and the read check in [Verify](#verify) will show whether it works.
2. **Which protocols the Mac uses** for the library today (SMB or NFS) and so which one the export share and the read-only upload share should use.
3. **Pool capacity** of `natascha1` (`prod` upload growth, snapshots, the origin snapshot pinned by the clones); `fiona2` has about 1.8 TB, which is enough (see the warning under [quotas](#quotas-and-capacity)).
4. **The group ID of `fs.media-rw`**, for the Immich pods' `fsGroup` or `runAsGroup`, if they need it ([#2146](https://github.com/isejalabs/homelab/issues/2146)); the NFS shares map every client to the account and group anyway.
5. **`borgmatic` configuration** of the on-site and the off-site repository: that `natascha1/data/srv/immich` is covered, including as a child dataset (see [borgbackup](#borgbackup)).

## Related

- [ADR 0018](../decisions/0018-media-source-of-truth.md): the media model this storage implements
- [`k8s/apps/media/immich`](../../k8s/apps/media/immich/README.md): the Kubernetes side, static NFS volumes
- [`k8s/test/storage/test-nfs-immich-media.yaml`](../../k8s/test/storage/test-nfs-immich-media.yaml): the mount test
- [CSI alternatives (#455)](https://github.com/isejalabs/homelab/issues/455): why a static volume is enough here
